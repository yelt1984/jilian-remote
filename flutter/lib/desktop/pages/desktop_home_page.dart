import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/jilian_api.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/peer_model.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;
  final RxInt _selectedIndex = 0.obs; // 0=主页(连接页),1=设备列表,2=屏幕墙,3=高级设置

  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToDeskSidebar(context),
        if (!isIncomingOnly) const VerticalDivider(width: 1),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  /// 侧边栏头像：优先用本地内存图（不依赖网络），加载失败回退默认图标
  Widget _buildSidebarAvatar() {
    final provider = _avatarProvider();
    if (provider == null) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: Colors.blueGrey.shade100,
        child: const Icon(Icons.person, color: Colors.white, size: 26),
      );
    }
    return ClipOval(
      child: Image(
        image: provider,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => CircleAvatar(
          radius: 22,
          backgroundColor: Colors.blueGrey.shade100,
          child: const Icon(Icons.person, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  /// 头像 ImageProvider：优先本地内存图，其次远程 URL
  ImageProvider? _avatarProvider() {
    final src = jilianApi.avatarSource;
    if (src == null || src.isEmpty) return null;
    if (jilianApi.hasLocalAvatar) {
      try {
        return MemoryImage(base64Decode(src));
      } catch (_) {}
    }
    return NetworkImage(src);
  }

  /// ToDesk 风格左侧边栏：头像用户区 + 导航 + 底部 logo/广告占位
  Widget _buildToDeskSidebar(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return Container(
      width: 200,
      color: const Color(0xFFF7F8FA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 用户信息区（登录状态联动）
          Obx(() {
            jilianApi.loginState.value; // 触发 Obx 重建
            final isLoggedIn = jilianApi.isLoggedIn;
            final user = jilianApi.currentUser;
            return InkWell(
              onTap: () {
                if (isLoggedIn) {
                  _showProfileDialog(context);
                } else {
                  _showLoginDialog(context);
                }
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(
                  children: [
                    _buildSidebarAvatar(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isLoggedIn ? (user?.nickname ?? '用户') : '未登录',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: textColor)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: MyTheme.accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(isLoggedIn ? '个人版' : '点击登录',
                                style: TextStyle(
                                    fontSize: 11, color: MyTheme.accent)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // 团队/个人中心按钮占位
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('切换团队...',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (jilianApi.isLoggedIn) {
                        _showProfileDialog(context);
                      } else {
                        _showLoginDialog(context);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('个人中心',
                        style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 导航
          Obx(() => Column(
                children: [
                  _buildNavTile(Icons.home_outlined, '主页',
                      _selectedIndex.value == 0, textColor,
                      () => _selectedIndex.value = 0),
                  _buildNavTile(Icons.devices_outlined, '设备列表',
                      _selectedIndex.value == 1, textColor,
                      () => _selectedIndex.value = 1),
                  _buildNavTile(Icons.grid_view_outlined, '屏幕墙',
                      _selectedIndex.value == 2, textColor,
                      () => _selectedIndex.value = 2),
                  _buildNavTile(Icons.settings_outlined, '高级设置',
                      _selectedIndex.value == 3, textColor, () {
                    _selectedIndex.value = 3;
                  }),
                ],
              )),
          const Spacer(),
          // 底部广告/Logo 占位
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MyTheme.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.computer,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('极连远程',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                      Text('安全稳定的远程控制',
                          style: TextStyle(
                              color: Colors.grey.shade400, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 版本号，方便用户确认当前运行的是哪个版本
          Center(
            child: Text(
              'v29',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildNavTile(IconData icon, String label, bool selected,
      Color? textColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? MyTheme.accent.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: selected
                    ? MyTheme.accent
                    : (textColor ?? Colors.grey).withOpacity(0.7)),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    color: selected ? MyTheme.accent : textColor,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalInfoCard(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, child) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Theme.of(context).dividerColor.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本机',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: MyTheme.accent)),
                const SizedBox(height: 6),
                Text('设备代码',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                GestureDetector(
                  onDoubleTap: () {
                    Clipboard.setData(
                        ClipboardData(text: model.serverId.text));
                    showToast(translate('Copied'));
                  },
                  child: Text(model.serverId.text,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Text('临时密码',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                GestureDetector(
                  onDoubleTap: () {
                    Clipboard.setData(
                        ClipboardData(text: model.serverPasswd.text));
                    showToast(translate('Copied'));
                  },
                  child: Text(model.serverPasswd.text,
                      style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Obx(() {
        switch (_selectedIndex.value) {
          case 0:
            return ConnectionPage();
          case 1:
            return _buildDeviceListPage(context);
          case 2:
            return _buildScreenWallPage(context);
          case 3:
            return DesktopSettingPage(
                key: const ValueKey('jilian-settings'),
                initialTabkey: SettingsTabKey.general);
          default:
            return ConnectionPage();
        }
      }),
    );
  }

  Widget _buildDeviceListPage(BuildContext context) {
    return const _JilianDeviceListPage();
  }

  Widget _buildScreenWallPage(BuildContext context) {
    return const _JilianScreenWallPage();
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 57,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            decoration: const BoxDecoration(color: MyTheme.accent),
          ).marginOnly(top: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 25,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate("ID"),
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.color
                                  ?.withOpacity(0.5)),
                        ).marginOnly(top: 5),
                        buildPopupMenu(context)
                      ],
                    ),
                  ),
                  Flexible(
                    child: GestureDetector(
                      onDoubleTap: () {
                        Clipboard.setData(
                            ClipboardData(text: model.serverId.text));
                        showToast(translate("Copied"));
                      },
                      child: TextFormField(
                        controller: model.serverId,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.only(top: 10, bottom: 10),
                        ),
                        style: TextStyle(
                          fontSize: 22,
                        ),
                      ).workaroundFreezeLinuxMint(),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            height: 52,
            decoration: BoxDecoration(color: MyTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 14, color: textColor?.withOpacity(0.5)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              Clipboard.setData(
                                  ClipboardData(text: model.serverPasswd.text));
                              showToast(translate("Copied"));
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.only(top: 14, bottom: 10),
                            ),
                            style: TextStyle(fontSize: 15),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(() => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ))),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      if (!bind.isDisableSettings())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              if (!isOutgoingOnly)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    // 极连自定义客户端：默认开启「被控需输入访问密码」，类 ToDesk 安全策略
    if (isCustomClient) {
      final cur = bind.mainGetOptionSync(key: 'approve-mode');
      if (cur.isEmpty) {
        bind.mainSetOption(key: 'approve-mode', value: 'password');
      }
    }
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}

/// 极连账号登录/注册弹窗（ToDesk 风格）
void _showLoginDialog(BuildContext context) {
  showJilianLoginDialog(context);
}

void showJilianLoginDialog(BuildContext context) {
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: null,
      contentPadding: 0,
      contentBoxConstraints: const BoxConstraints(maxWidth: 760, maxHeight: 540),
      content: SizedBox(
        width: 720,
        height: 520,
        child: _JilianLoginContent(onClose: close),
      ),
      actions: const [],
    );
  });
}

/// 个人中心弹窗（ToDesk 风格）
void _showProfileDialog(BuildContext context) {
  gFFI.dialogManager.show((setState, close, context) {
    return CustomAlertDialog(
      title: null,
      contentPadding: 0,
      contentBoxConstraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
      content: SizedBox(
        width: 440,
        height: 540,
        child: _JilianProfileContent(onClose: close),
      ),
      actions: const [],
    );
  });
}

class _JilianProfileContent extends StatefulWidget {
  final VoidCallback onClose;
  const _JilianProfileContent({Key? key, required this.onClose})
      : super(key: key);

  @override
  State<_JilianProfileContent> createState() => _JilianProfileContentState();
}

class _JilianProfileContentState extends State<_JilianProfileContent> {
  final _nicknameController = TextEditingController();
  final _signatureController = TextEditingController();
  final _emailController = TextEditingController();
  int _deviceCount = 0;
  bool _editing = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final u = jilianApi.currentUser;
    _nicknameController.text = u?.nickname ?? '';
    _signatureController.text = u?.signature ?? '';
    _emailController.text = u?.email ?? '';
    _loadDeviceCount();
  }

  Future<void> _loadDeviceCount() async {
    if (!jilianApi.isLoggedIn) {
      if (mounted) setState(() => _deviceCount = 0);
      return;
    }
    try {
      final list = await jilianApi.getDeviceList();
      if (mounted) setState(() => _deviceCount = list.length);
    } catch (e) {
      debugPrint('load device count error: $e');
      if (mounted) setState(() => _deviceCount = -1);
    }
  }

  ImageProvider? _avatarProvider() {
    final src = jilianApi.avatarSource;
    if (src == null || src.isEmpty) return null;
    if (jilianApi.hasLocalAvatar) {
      try {
        return MemoryImage(base64Decode(src));
      } catch (_) {}
    }
    return NetworkImage(src);
  }

  ImageProvider? _avatarImage() => _avatarProvider();

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
        allowCompression: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        // 兜底：用 path 读取
        final path = file.path;
        if (path == null || path.isEmpty) {
          showToast('无法读取头像文件');
          return;
        }
        final fileBytes = await File(path).readAsBytes();
        if (fileBytes.isEmpty) {
          showToast('无法读取头像文件');
          return;
        }
        await _uploadAvatarBytes(fileBytes, file.extension ?? 'png');
        return;
      }
      if (bytes.length > 3 * 1024 * 1024) {
        showToast('头像过大(最大3MB)');
        return;
      }
      await _uploadAvatarBytes(bytes, file.extension ?? 'png');
    } catch (e) {
      debugPrint('pick avatar error: $e');
      if (mounted) setState(() => _uploading = false);
      showToast('选择头像失败: $e');
    }
  }

  Future<void> _uploadAvatarBytes(List<int> bytes, String ext) async {
    // 压缩头像：最长边 256px，JPEG 85% 质量，控制 base64 < 100KB
    List<int> uploadBytes = bytes;
    String uploadExt = ext.toLowerCase();
    try {
      final decoded = img.decodeImage(Uint8List.fromList(bytes));
      if (decoded != null) {
        const targetSize = 256;
        final resized = decoded.width > decoded.height
            ? img.copyResize(decoded,
                width: targetSize,
                interpolation: img.Interpolation.cubic)
            : img.copyResize(decoded,
                height: targetSize,
                interpolation: img.Interpolation.cubic);
        uploadBytes = img.encodeJpg(resized, quality: 85);
        uploadExt = 'jpg';
      }
    } catch (e) {
      debugPrint('avatar compress skipped: $e');
    }
    if (uploadBytes.length > 3 * 1024 * 1024) {
      showToast('头像过大(最大3MB)');
      return;
    }
    final b64 = base64Encode(Uint8List.fromList(uploadBytes));
    setState(() => _uploading = true);
    final res = await jilianApi.uploadAvatar(b64, uploadExt);
    if (mounted) setState(() => _uploading = false);
    // 本地已乐观更新，头像一定会变；这里只根据服务器结果给出提示
    if (res['code'] == 0) {
      showToast('头像已更新');
    } else if (res['code'] == -1) {
      showToast('头像已更新(本地)');
    } else {
      showToast(res['msg'] ?? '头像已更新(本地)');
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final u = jilianApi.currentUser;
    if (u == null) return;
    u.nickname = _nicknameController.text.trim();
    u.signature = _signatureController.text.trim();
    u.email = _emailController.text.trim();
    final res = await jilianApi.updateProfile(u);
    if (res['code'] == 0) {
      showToast('保存成功');
      setState(() => _editing = false);
      _loadDeviceCount();
    } else {
      showToast(res['msg'] ?? '保存失败');
    }
  }

  void _showChangePasswordDialog() {
    final u = jilianApi.currentUser;
    if (u == null) return;
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: const Text('修改密码'),
        content: SizedBox(
          width: 360,
          child: _JilianChangePasswordContent(
            phone: u.phone,
            email: u.email,
            onClose: close,
          ),
        ),
        actions: const [],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = jilianApi.currentUser;
    if (u == null) return const SizedBox();
    final phone = u.phone;
    final email = u.email;
    final displayName = _nicknameController.text.isNotEmpty
        ? _nicknameController.text
        : (phone.isNotEmpty ? phone : email);
    return Column(
      children: [
        // 头部
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [MyTheme.accent, MyTheme.accent.withOpacity(0.8)]),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 22),
                  tooltip: '关闭',
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
              Column(
            children: [
              GestureDetector(
                onTap: _uploading ? null : _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundImage: _avatarImage(),
                      backgroundColor: Colors.white,
                      child: _avatarImage() == null
                          ? const Icon(Icons.person, size: 48, color: Colors.grey)
                          : null,
                    ),
                    if (_uploading)
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                              color: Colors.black38, shape: BoxShape.circle),
                          child: const CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 3),
                        ),
                      )
                    else
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                          child: Icon(Icons.camera_alt,
                              size: 16, color: MyTheme.accent),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('个人版',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
            ],
          ),
        ),
        // 信息区
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _infoRow(Icons.computer, '主设备',
                  gFFI.serverModel.serverId.text.isEmpty ? '本机' : formatID(gFFI.serverModel.serverId.text)),
              _infoRow(Icons.devices, '设备数量',
                  _deviceCount < 0 ? '加载失败' : '$_deviceCount 台'),
              _infoRow(Icons.phone_android, '手机号',
                  phone.isNotEmpty ? phone : '未绑定'),
              _infoRow(Icons.email, '邮箱',
                  email.isNotEmpty ? email : '未绑定'),
              const SizedBox(height: 16),
              if (_editing) ...[
                TextField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(labelText: '昵称')),
                const SizedBox(height: 10),
                TextField(
                    controller: _signatureController,
                    decoration: const InputDecoration(labelText: '个性签名')),
                const SizedBox(height: 10),
                TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: '邮箱')),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: dialogButton('取消',
                            onPressed: () => setState(() => _editing = false),
                            isOutline: true)),
                    const SizedBox(width: 10),
                    Expanded(child: dialogButton('保存', onPressed: _save)),
                  ],
                ),
              ] else ...[
                SizedBox(
                    width: double.infinity,
                    child: dialogButton('编辑资料',
                        onPressed: () => setState(() => _editing = true))),
                const SizedBox(height: 10),
                SizedBox(
                    width: double.infinity,
                    child: dialogButton('修改密码',
                        onPressed: _showChangePasswordDialog,
                        isOutline: true)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: dialogButton('退出登录',
                      onPressed: () async {
                        await jilianApi.logout();
                        widget.onClose();
                        showToast('已退出登录');
                      },
                      isOutline: true),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const Spacer(),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _signatureController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}

/// 修改密码弹窗内容
class _JilianChangePasswordContent extends StatefulWidget {
  final String phone;
  final String email;
  final VoidCallback onClose;

  const _JilianChangePasswordContent({
    Key? key,
    required this.phone,
    required this.email,
    required this.onClose,
  }) : super(key: key);

  @override
  State<_JilianChangePasswordContent> createState() =>
      _JilianChangePasswordContentState();
}

class _JilianChangePasswordContentState
    extends State<_JilianChangePasswordContent> {
  final _oldPwdController = TextEditingController();
  final _smsController = TextEditingController();
  final _newPwdController = TextEditingController();
  final _confirmPwdController = TextEditingController();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _sending = false;
  bool _submitting = false;
  int _countdown = 0;
  Timer? _timer;

  bool get _isEmailAccount =>
      widget.email.isNotEmpty && widget.phone.startsWith('em_');

  @override
  void dispose() {
    _oldPwdController.dispose();
    _smsController.dispose();
    _newPwdController.dispose();
    _confirmPwdController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _countdown--;
        if (_countdown <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendSms() async {
    if (_countdown > 0 || _sending) return;
    final account = widget.phone.startsWith('em_') ? '' : widget.phone;
    if (account.isEmpty || account.length != 11) {
      showToast('手机号异常，无法发送验证码');
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await jilianApi.sendSms(account);
      if (res['code'] == 0) {
        _startCountdown();
        showToast('验证码已发送');
      } else {
        showToast(res['msg'] ?? '发送失败');
      }
    } catch (e) {
      showToast('发送失败: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submit() async {
    final newPwd = _newPwdController.text.trim();
    final confirmPwd = _confirmPwdController.text.trim();
    if (newPwd.length < 6) {
      showToast('新密码至少6位');
      return;
    }
    if (newPwd != confirmPwd) {
      showToast('两次输入的新密码不一致');
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await jilianApi.changePassword(
        oldPassword: _isEmailAccount ? _oldPwdController.text.trim() : null,
        smsCode: _isEmailAccount ? null : _smsController.text.trim(),
        newPassword: newPwd,
      );
      if (res['code'] == 0) {
        showToast('密码修改成功');
        widget.onClose();
      } else {
        showToast(res['msg'] ?? '修改失败');
      }
    } catch (e) {
      showToast('修改失败: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isEmailAccount) ...[
          TextField(
            controller: _oldPwdController,
            obscureText: _obscureOld,
            decoration: InputDecoration(
              labelText: '旧密码',
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureOld ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureOld = !_obscureOld),
              ),
            ),
          ),
        ] else ...[
          TextField(
            controller: _smsController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '短信验证码'),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _countdown > 0 || _sending ? null : _sendSms,
              child: Text(_countdown > 0
                  ? '$_countdown 秒后重发'
                  : (_sending ? '发送中...' : '获取验证码')),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _newPwdController,
          obscureText: _obscureNew,
          decoration: InputDecoration(
            labelText: '新密码',
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPwdController,
          obscureText: _obscureConfirm,
          decoration: InputDecoration(
            labelText: '确认新密码',
            suffixIcon: IconButton(
              icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: dialogButton('取消',
                  onPressed: widget.onClose, isOutline: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: dialogButton('确定',
                  onPressed: _submitting ? null : _submit),
            ),
          ],
        ),
      ],
    );
  }
}

/// 极连远程：左侧「设备列表」页面（ToDesk 风格列表）
class _JilianDeviceListPage extends StatefulWidget {
  const _JilianDeviceListPage({Key? key}) : super(key: key);

  @override
  State<_JilianDeviceListPage> createState() => _JilianDeviceListPageState();
}

class _JilianDeviceListPageState extends State<_JilianDeviceListPage> {
  List<JilianDevice> _devices = [];
  bool _loading = false;
  String? _error;
  final AllPeersLoader _allPeersLoader = AllPeersLoader();
  List<Peer> _recentPeers = [];
  JilianDevice? _selectedDevice;
  Peer? _selectedPeer;

  // 在线状态：云端设备 + 最近连接共用
  final Map<String, bool> _onlineStates = {};
  Timer? _onlineTimer;
  static const _onlineEvent = 'callback_query_onlines';
  static const _onlineHandlerKey = 'jilian_device_list';

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init((fn) {
      if (mounted) {
        setState(() {
          fn();
          _recentPeers = _filterRecentPeers(_allPeersLoader.peers);
        });
      }
    });
    platformFFI.registerEventHandler(_onlineEvent, _onlineHandlerKey, (evt) async {
      _onOnlineEvent(evt);
    });
    _loadAll();
    jilianApi.loginState.listen((_) {
      if (mounted) _loadAll();
    });
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    platformFFI.unregisterEventHandler(_onlineEvent, _onlineHandlerKey);
    _allPeersLoader.clear();
    super.dispose();
  }

  void _onOnlineEvent(Map<String, dynamic> evt) {
    final onlines = (evt['onlines'] as String? ?? '').split(',').where((s) => s.isNotEmpty);
    final offlines = (evt['offlines'] as String? ?? '').split(',').where((s) => s.isNotEmpty);
    if (mounted) {
      setState(() {
        for (final id in onlines) {
          _onlineStates[id] = true;
        }
        for (final id in offlines) {
          _onlineStates[id] = false;
        }
      });
    }
  }

  void _startOnlineQuery() {
    _onlineTimer?.cancel();
    _onlineTimer = Timer.periodic(const Duration(seconds: 8), (_) => _queryOnlineStates());
  }

  Future<void> _queryOnlineStates() async {
    final localId = trimID(gFFI.serverModel.serverId.text);
    final ids = <String>{};
    for (final d in _devices) {
      final id = trimID(d.deviceId);
      if (id.isNotEmpty && id != localId) ids.add(id);
    }
    for (final p in _recentPeers) {
      final id = trimID(p.id);
      if (id.isNotEmpty && id != localId) ids.add(id);
    }
    if (ids.isNotEmpty) {
      try {
        await bind.queryOnlines(ids: ids.toList(growable: false));
      } catch (e) {
        debugPrint('queryOnlines error: $e');
      }
    }
  }

  List<Peer> _filterRecentPeers(List<Peer> peers) {
    final localId = trimID(gFFI.serverModel.serverId.text);
    return peers.where((p) {
      final id = trimID(p.id);
      return id.isNotEmpty && id != localId;
    }).toList();
  }

  Future<void> _loadAll() async {
    await _loadDevices();
    if (_allPeersLoader.needLoad) {
      await _allPeersLoader.getAllPeers();
    }
    if (mounted) {
      setState(() {
        _recentPeers = _filterRecentPeers(_allPeersLoader.peers);
      });
    }
    _syncRecentPeersToCloud();
    _startOnlineQuery();
    _queryOnlineStates();
  }

  Future<void> _syncRecentPeersToCloud() async {
    if (!jilianApi.isLoggedIn || _recentPeers.isEmpty) return;
    final localId = trimID(gFFI.serverModel.serverId.text);
    for (final p in _recentPeers) {
      final id = trimID(p.id);
      if (id.isEmpty || id == localId) continue;
      final name = p.alias.isNotEmpty
          ? p.alias
          : (p.username.isNotEmpty && p.hostname.isNotEmpty
              ? '${p.username}@${p.hostname}'
              : (p.hostname.isNotEmpty ? p.hostname : '远程设备'));
      try {
        await jilianApi.bindPeerDevice(id, name, platform: p.platform, alias: p.alias);
      } catch (e) {
        debugPrint('sync peer $id failed: $e');
      }
    }
    // 同步完刷新云端设备列表
    if (mounted) await _loadDevices();
  }

  Future<void> _loadDevices() async {
    if (!jilianApi.isLoggedIn) {
      setState(() {
        _devices = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await jilianApi.getDeviceList();
      if (mounted) {
        setState(() {
          _devices = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败：$e';
          _loading = false;
        });
      }
    }
  }

  void _showLogin() {
    // 复用桌面首页的登录弹窗
    _showLoginDialog(context);
  }

  Widget _buildEmpty(BuildContext context) {
    if (!jilianApi.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.devices_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('登录账号后可同步你的所有设备',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: MyTheme.accent),
              onPressed: _showLogin,
              child: const Text('去登录', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无设备，在其他设备登录同一账号后会自动同步',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final recentCount = _recentPeers.length;
    final cloudCount = _devices.length;
    final subtitle = StringBuffer();
    if (jilianApi.isLoggedIn) {
      subtitle.write('我的设备 (${cloudCount}台)');
      if (recentCount > 0) {
        subtitle.write(' · 最近连接 (${recentCount}台)');
      }
    } else {
      subtitle.write('最近连接 (${recentCount}台)');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部标题栏
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Row(
            children: [
              Text('设备列表',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: textColor)),
              const SizedBox(width: 12),
              Text(subtitle.toString(),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const Spacer(),
              if (_loading)
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: MyTheme.accent)),
              if (!_loading)
                IconButton(
                  icon: Icon(Icons.refresh, color: Colors.grey.shade600),
                  tooltip: '刷新',
                  onPressed: _loadAll,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 搜索栏（占位，后续可接过滤）
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '搜索设备名称/设备代码',
                      hintStyle:
                          TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 错误提示
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
        // 设备列表 + 详情面板
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: cloudCount == 0 && recentCount == 0 && !_loading
                    ? _buildEmpty(context)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        children: [
                          if (recentCount > 0) ...[
                            _buildSectionTitle('最近连接', recentCount),
                            const SizedBox(height: 10),
                            ..._recentPeers.map((p) => _buildRecentPeerRow(context, p)),
                            const SizedBox(height: 20),
                          ],
                          if (cloudCount > 0) ...[
                            _buildSectionTitle(jilianApi.isLoggedIn ? '我的设备' : '本机设备', cloudCount),
                            const SizedBox(height: 10),
                            ..._devices.map((d) => _buildDeviceRow(context, d)),
                          ],
                        ],
                      ),
              ),
              if (_selectedDevice != null || _selectedPeer != null)
                _buildDetailPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Row(
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800)),
        const SizedBox(width: 6),
        Text('($count)',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      ],
    );
  }

  void _selectDevice(JilianDevice d) {
    setState(() {
      _selectedDevice = d;
      _selectedPeer = null;
    });
  }

  void _selectPeer(Peer p) {
    setState(() {
      _selectedPeer = p;
      _selectedDevice = null;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedDevice = null;
      _selectedPeer = null;
    });
  }

  Widget _buildDetailPanel() {
    final device = _selectedDevice;
    final peer = _selectedPeer;
    final String name;
    final String id;
    final bool online;
    final bool isLocal;
    if (device != null) {
      name = device.deviceAlias.isNotEmpty
          ? device.deviceAlias
          : (device.deviceName.isNotEmpty ? device.deviceName : '我的设备');
      id = device.deviceId;
      final localId = trimID(gFFI.serverModel.serverId.text);
      isLocal = device.deviceId == localId || formatID(id) == formatID(localId);
      online = isLocal || (_onlineStates[trimID(device.deviceId)] ?? (device.isOnline == 1));
    } else {
      final p = peer!;
      name = p.alias.isNotEmpty
          ? p.alias
          : (p.username.isNotEmpty && p.hostname.isNotEmpty
              ? '${p.username}@${p.hostname}'
              : (p.hostname.isNotEmpty ? p.hostname : '远程设备'));
      id = p.id;
      online = p.online;
      isLocal = false;
    }
    return Container(
      width: 300,
      margin: const EdgeInsets.fromLTRB(0, 12, 24, 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.computer,
                    size: 40, color: online ? MyTheme.accent : Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: online ? Colors.green : Colors.grey,
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(online ? '在线' : '离线',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                        if (isLocal) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: MyTheme.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('本机',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.close), onPressed: _clearSelection),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 4),
          Text('设备代码',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SelectableText(formatID(id),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2)),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制设备码',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: formatID(id)));
                  showToast('设备码已复制');
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (isLocal)
            _buildLocalDetailPanel(id)
          else
            _buildRemoteDetailPanel(context, id, name),
          ],
        ),
      ),
    );
  }

  /// 远程设备详情面板：按 ToDesk 风格分块排列（4 列紧凑网格）
  Widget _buildRemoteDetailPanel(BuildContext context, String id, String name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('基础连接'),
        const SizedBox(height: 12),
        _buildActionGrid([
          _buildBigAction(Icons.desktop_windows, '远程控制',
              MyTheme.accent, () => connect(context, id)),
          _buildBigAction(Icons.folder_copy, '文件传输', Colors.blueGrey,
              () => connect(context, id, isFileTransfer: true)),
          _buildBigAction(Icons.terminal, '终端', Colors.blueGrey,
              () => _showTerminalNotice(context)),
          _buildBigAction(Icons.visibility, '观看模式', Colors.blueGrey,
              () => connect(context, id)),
          _buildBigAction(Icons.people_alt, '协作模式', Colors.blueGrey,
              () => connect(context, id)),
          _buildBigAction(Icons.videocam, '摄像头', Colors.blueGrey,
              () {
            showToast('正在连接远程摄像头...');
            connect(context, id, isViewCamera: true);
          }),
          _buildBigAction(Icons.fit_screen, '镜像屏', Colors.blueGrey,
              () => _showMirrorScreenNotice(context)),
          _buildBigAction(Icons.open_in_full, '扩展屏', Colors.blueGrey,
              () => _showExtendScreenNotice(context)),
        ]),
        const SizedBox(height: 24),
        _buildSectionHeader('辅助工具'),
        const SizedBox(height: 12),
        _buildActionGrid([
          _buildBigAction(Icons.folder_copy, '文件中心', Colors.orange,
              () => _openFileCenter(context, id)),
          _buildBigAction(Icons.sports_esports, '游戏与应用中心',
              Colors.deepOrange,
              () => _showGameCenterNotice(context)),
        ]),
        const SizedBox(height: 24),
        _buildSectionHeader('电源操作'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildPowerButton(
                label: '锁屏',
                icon: Icons.lock,
                color: Colors.grey.shade700,
                onPressed: () => _doRemotePowerOp(context, id, name, 'lock'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPowerButton(
                label: '重启',
                icon: Icons.restart_alt,
                color: Colors.grey.shade700,
                onPressed: () => _doRemotePowerOp(context, id, name, 'restart'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildPowerButton(
                label: '关机',
                icon: Icons.power_settings_new,
                color: Colors.red.shade500,
                onPressed: () => _doRemotePowerOp(context, id, name, 'shutdown'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 4 列操作按钮网格（按 ToDesk 风格紧凑排列）
  Widget _buildActionGrid(List<Widget> children) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.9,
      children: children,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: MyTheme.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800)),
      ],
    );
  }

  Widget _buildPowerButton(
      {required String label,
      required IconData icon,
      required Color color,
      required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// 远程电源操作：RustDesk 开源核心没有「无会话一键电源」接口，
  /// 这里先打开远程桌面，并提示用户在工具栏中使用对应功能。
  void _doRemotePowerOp(BuildContext context, String id, String name, String type) {
    String action;
    switch (type) {
      case 'lock':
        action = '锁屏';
        break;
      case 'restart':
        action = '重启';
        break;
      case 'shutdown':
        action = '关机';
        break;
      default:
        return;
    }
    gFFI.dialogManager.show((setState, close, ctx) {
      return CustomAlertDialog(
        title: Row(children: [
          Icon(Icons.warning_rounded, color: Colors.orange, size: 24),
          Text(' 确认$action远程设备').paddingOnly(left: 8),
        ]),
        content: Text(
          type == 'shutdown'
              ? '即将对 "$name" 执行关机。\n\n连接成功后会自动执行，无需再点任何工具栏按钮。'
              : '即将对 "$name" 执行$action。\n\n连接成功后会自动执行，无需再点任何工具栏按钮。',
        ),
        actions: [
          dialogButton('取消', onPressed: close, isOutline: true),
          dialogButton('确认$action', onPressed: () {
            close();
            showToast('正在连接 $name 并执行$action...');
            connect(context, id, autoPowerAction: type);
          }),
        ],
      );
    });
  }

  Widget _buildLocalDetailPanel(String id) {
    return FutureBuilder<String>(
      future: bind.mainGetTemporaryPassword(),
      builder: (context, snapshot) {
        final password = snapshot.data ?? '******';
        final invite = '${formatID(id)} ${password == '-' ? '' : password}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('本机连接信息'),
            const SizedBox(height: 12),
            Text('临时密码',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: SelectableText(password,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2)),
                ),
                if (password != '-' && password != '******')
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: '刷新密码',
                    onPressed: () async {
                      await bind.mainUpdateTemporaryPassword();
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: MyTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制邀请信息',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: invite.trim()));
                  showToast('邀请信息已复制');
                },
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('辅助工具'),
            const SizedBox(height: 12),
            _buildActionGrid([
              _buildBigAction(Icons.folder_copy, '文件中心', Colors.orange,
                  () => _showFileCenterNotice(context)),
              _buildBigAction(Icons.sports_esports, '游戏与应用中心',
                  Colors.deepOrange,
                  () => _showGameCenterNotice(context)),
            ]),
            const SizedBox(height: 24),
            _buildSectionHeader('电源操作'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPowerButton(
                    label: '锁屏',
                    icon: Icons.lock,
                    color: Colors.grey.shade700,
                    onPressed: () => _doLocalPowerOp('lock'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildPowerButton(
                    label: '重启',
                    icon: Icons.restart_alt,
                    color: Colors.grey.shade700,
                    onPressed: () => _confirmLocalPowerOp('restart'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildPowerButton(
                    label: '关机',
                    icon: Icons.power_settings_new,
                    color: Colors.red.shade500,
                    onPressed: () => _confirmLocalPowerOp('shutdown'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 本机电源操作：直接调用 Windows 系统命令
  Future<void> _doLocalPowerOp(String type) async {
    try {
      switch (type) {
        case 'lock':
          await Process.run('rundll32.exe', ['user32.dll,LockWorkStation']);
          showToast('本机已锁屏');
          break;
        case 'restart':
          await Process.run('shutdown', ['/r', '/t', '0']);
          break;
        case 'shutdown':
          await Process.run('shutdown', ['/s', '/t', '0']);
          break;
      }
    } catch (e) {
      showToast('操作失败: $e');
    }
  }

  void _confirmLocalPowerOp(String type) {
    final label = type == 'restart' ? '重启' : '关机';
    gFFI.dialogManager.show((setState, close, ctx) {
      return CustomAlertDialog(
        title: Text('确认$label本机？'),
        content: Text('点击「确定」后将立即对本机执行$label，未保存的工作可能会丢失。'),
        actions: [
          dialogButton('取消', onPressed: close, isOutline: true),
          dialogButton('确定', onPressed: () {
            close();
            _doLocalPowerOp(type);
          }),
        ],
      );
    });
  }

  Widget _buildBigAction(
      IconData icon, String label, Color? color, VoidCallback? onTap) {
    final enabled = onTap != null;
    final fg = color ?? Colors.grey.shade400;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 78,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? fg.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 26, color: enabled ? fg : Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: enabled
                        ? Colors.grey.shade800
                        : Colors.grey.shade400)),
          ],
        ),
      ),
    );
  }

  void _showTerminalNotice(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('终端功能'),
        content: const Text(
            'RustDesk 开源核心未内置 SSH/命令行终端。\n\n如需终端，请先点击「远程控制」连接设备，然后在远程桌面中打开 PowerShell/CMD 使用。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  void _showMirrorScreenNotice(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('镜像屏'),
        content: const Text(
            '「镜像屏」是 ToDesk 商业版功能，RustDesk 开源核心暂未提供远程屏幕镜像扩展能力。\n\n如需查看远程屏幕，请使用「远程控制」或「观看模式」。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  void _showExtendScreenNotice(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('扩展屏'),
        content: const Text(
            '「扩展屏」是 ToDesk 商业版功能，RustDesk 开源核心暂未提供远程显示器扩展能力。\n\n如需多屏操作，请在「远程控制」连接后切换远程显示器的屏幕。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  /// 打开指定设备的文件中心（独立双栏文件管理器窗口）
  void _openFileCenter(BuildContext context, String id) {
    final cleanId = trimID(id);
    if (cleanId.isEmpty) return;
    showToast('正在打开文件中心...');
    connect(context, cleanId, isFileTransfer: true);
  }

  void _showFileCenterNotice(BuildContext context) {
    final localId = trimID(gFFI.serverModel.serverId.text);
    final remoteDevices = _devices.where((d) {
      return d.deviceId.isNotEmpty && trimID(d.deviceId) != localId;
    }).toList();
    if (remoteDevices.isEmpty) {
      showToast('暂无其他设备，请先在其他设备登录同一账号');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('文件中心'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择要管理文件的设备（将打开独立文件管理器窗口）：',
                  style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              ...remoteDevices.map((d) {
                final name = d.deviceAlias.isNotEmpty
                    ? d.deviceAlias
                    : (d.deviceName.isNotEmpty ? d.deviceName : '远程设备');
                return InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _openFileCenter(context, d.deviceId);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.computer,
                            color: Colors.grey.shade500, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800)),
                              Text(formatID(d.deviceId),
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
        ],
      ),
    );
  }

  void _showGameCenterNotice(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('游戏与应用中心'),
        content: const Text(
            '「游戏与应用中心」是 ToDesk 商业版的功能（远程游戏手柄/应用快捷启动），RustDesk 开源核心未提供该能力。\n\n如需远程运行程序，请先「远程控制」连接设备后手动操作。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  Widget _buildDeviceRow(BuildContext context, JilianDevice d) {
    final name = d.deviceAlias.isNotEmpty
        ? d.deviceAlias
        : (d.deviceName.isNotEmpty ? d.deviceName : '我的设备');
    final formattedId = formatID(d.deviceId);
    final localId = trimID(gFFI.serverModel.serverId.text);
    final isLocalDevice =
        d.deviceId == localId || formattedId == formatID(localId);
    final online = isLocalDevice || (_onlineStates[trimID(d.deviceId)] ?? (d.isOnline == 1));
    final selected = _selectedDevice != null && _selectedDevice!.deviceId == d.deviceId;
    return GestureDetector(
      onTap: () => _selectDevice(d),
      onSecondaryTapUp: (details) => _showDeviceContextMenu(context, d, details.globalPosition),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isLocalDevice ? Colors.orange.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected
                  ? MyTheme.accent
                  : (isLocalDevice
                      ? MyTheme.accent.withOpacity(0.4)
                      : Colors.grey.shade200),
              width: selected ? 2 : 1),
        ),
        child: Row(
        children: [
          // 在线状态点
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: online ? Colors.green : Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // 平台图标
          Icon(Icons.computer,
              size: 28, color: online ? MyTheme.accent : Colors.grey),
          const SizedBox(width: 14),
          // 名称与设备码
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isLocalDevice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: MyTheme.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('本机',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(formattedId,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 操作按钮：本机不展示控制按钮
          if (!isLocalDevice)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildActionButton('连接', MyTheme.accent, Colors.white,
                    () => connect(context, d.deviceId)),
                _buildActionButton('文件传输', Colors.grey.shade100,
                    Colors.grey.shade800,
                    () => connect(context, d.deviceId, isFileTransfer: true)),
                _buildActionButton('观看', Colors.grey.shade100,
                    Colors.grey.shade800,
                    () => connect(context, d.deviceId)),
                _buildActionButton('协作', Colors.grey.shade100,
                    Colors.grey.shade800,
                    () => connect(context, d.deviceId)),
              ],
            ),
        ],
      ),
      ),
    );
  }

  // 从云端设备列表查找对应 peer 的备注名
  String _cloudAliasForPeer(Peer p) {
    for (final d in _devices) {
      if (trimID(d.deviceId) == trimID(p.id) && d.deviceAlias.isNotEmpty) {
        return d.deviceAlias;
      }
    }
    return '';
  }

  Widget _buildRecentPeerRow(BuildContext context, Peer p) {
    final cloudAlias = _cloudAliasForPeer(p);
    final name = cloudAlias.isNotEmpty
        ? cloudAlias
        : (p.alias.isNotEmpty
            ? p.alias
            : (p.username.isNotEmpty && p.hostname.isNotEmpty
                ? '${p.username}@${p.hostname}'
                : (p.hostname.isNotEmpty ? p.hostname : '远程设备')));
    final online = p.online;
    final id = p.id;
    final selected = _selectedPeer != null && _selectedPeer!.id == p.id;
    return GestureDetector(
      onTap: () => _selectPeer(p),
      onSecondaryTapUp: (details) => _showPeerContextMenu(context, p, details.globalPosition),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? MyTheme.accent : Colors.grey.shade200,
              width: selected ? 2 : 1),
        ),
        child: Row(
        children: [
          // 在线状态点
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: online ? Colors.green : Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          // 平台图标
          Icon(Icons.computer,
              size: 28, color: online ? MyTheme.accent : Colors.grey),
          const SizedBox(width: 14),
          // 名称与设备码
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(formatID(id),
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 操作按钮
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildActionButton('连接', MyTheme.accent, Colors.white,
                  () => _connectAndSyncToCloud(context, p)),
              _buildActionButton('文件传输', Colors.grey.shade100,
                  Colors.grey.shade800,
                  () => _connectAndSyncToCloud(context, p, isFileTransfer: true)),
              _buildActionButton('观看', Colors.grey.shade100,
                  Colors.grey.shade800,
                  () => _connectAndSyncToCloud(context, p)),
              _buildActionButton('协作', Colors.grey.shade100,
                  Colors.grey.shade800,
                  () => _connectAndSyncToCloud(context, p)),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _connectAndSyncToCloud(BuildContext context, Peer p,
      {bool isFileTransfer = false}) async {
    final localId = trimID(gFFI.serverModel.serverId.text);
    final id = trimID(p.id);
    if (jilianApi.isLoggedIn && id.isNotEmpty && id != localId) {
      final name = p.alias.isNotEmpty
          ? p.alias
          : (p.username.isNotEmpty && p.hostname.isNotEmpty
              ? '${p.username}@${p.hostname}'
              : (p.hostname.isNotEmpty ? p.hostname : '远程设备'));
      try {
        // 连接/心跳时只绑定设备，不覆盖云端已有备注名
        await jilianApi.bindDevice(id, name, platform: p.platform);
      } catch (e) {
        debugPrint('sync peer on connect failed: $e');
      }
    }
    connect(context, p.id, isFileTransfer: isFileTransfer);
  }

  Widget _buildDisabledActionButton(String label, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildActionButton(
      String label, Color bg, Color fg, VoidCallback onTap) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, color: fg, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  void _showDeviceContextMenu(
      BuildContext context, JilianDevice d, Offset position) {
    final localId = trimID(gFFI.serverModel.serverId.text);
    final isLocal = d.deviceId == localId || formatID(d.deviceId) == formatID(localId);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          child: const Row(children: [
            Icon(Icons.edit_note, size: 18),
            SizedBox(width: 8),
            Text('设置备注')
          ]),
          onTap: () => Future.delayed(
              const Duration(milliseconds: 100), () => _showRenameDialog(d)),
        ),
        PopupMenuItem(
          child: const Row(children: [
            Icon(Icons.copy, size: 18),
            SizedBox(width: 8),
            Text('复制设备码')
          ]),
          onTap: () {
            Clipboard.setData(ClipboardData(text: formatID(d.deviceId)));
            showToast('设备码已复制');
          },
        ),
        if (!isLocal)
          PopupMenuItem(
            child: const Row(children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red))
            ]),
            onTap: () => Future.delayed(const Duration(milliseconds: 100),
                () => _confirmDeleteDevice(d)),
          ),
      ],
    );
  }

  void _showPeerContextMenu(
      BuildContext context, Peer p, Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          child: const Row(children: [
            Icon(Icons.copy, size: 18),
            SizedBox(width: 8),
            Text('复制设备码')
          ]),
          onTap: () {
            Clipboard.setData(ClipboardData(text: formatID(p.id)));
            showToast('设备码已复制');
          },
        ),
        if (jilianApi.isLoggedIn)
          PopupMenuItem(
            child: const Row(children: [
              Icon(Icons.cloud_upload_outlined, size: 18),
              SizedBox(width: 8),
              Text('添加到我的设备')
            ]),
            onTap: () async {
              final name = p.alias.isNotEmpty
                  ? p.alias
                  : (p.username.isNotEmpty && p.hostname.isNotEmpty
                      ? '${p.username}@${p.hostname}'
                      : (p.hostname.isNotEmpty ? p.hostname : '远程设备'));
              final res = await jilianApi.bindPeerDevice(
                  p.id, name, platform: p.platform, alias: p.alias);
              if (res['code'] == 0) {
                showToast('已添加到我的设备');
                if (mounted) await _loadDevices();
              } else {
                showToast(res['msg'] ?? '添加失败');
              }
            },
          ),
      ],
    );
  }

  void _showRenameDialog(JilianDevice d) {
    final controller = TextEditingController(text: d.deviceAlias);
    gFFI.dialogManager.show((setState, close, ctx) {
      return CustomAlertDialog(
        title: const Text('设置备注'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '输入设备备注名称'),
          autofocus: true,
        ),
        onCancel: close,
        onSubmit: () async {
          final alias = controller.text.trim();
          final res = await jilianApi.setDeviceAlias(d.deviceId, alias);
          if (res['code'] == 0) {
            showToast('备注已保存');
            close();
            await _loadDevices();
          } else {
            showToast(res['msg'] ?? '保存失败');
          }
        },
      );
    });
  }

  void _confirmDeleteDevice(JilianDevice d) {
    gFFI.dialogManager.show((setState, close, ctx) {
      return CustomAlertDialog(
        title: const Text('删除设备'),
        content: Text('确定从「我的设备」中删除 ${d.deviceAlias.isNotEmpty ? d.deviceAlias : formatID(d.deviceId)} 吗？'),
        onCancel: close,
        onSubmit: () async {
          final res = await jilianApi.unbindDevice(d.deviceId);
          if (res['code'] == 0) {
            showToast('已删除');
            close();
            await _loadDevices();
          } else {
            showToast(res['msg'] ?? '删除失败');
          }
        },
      );
    });
  }
}

/// ToDesk 风格登录弹窗内容（左右分栏）
class _JilianLoginContent extends StatefulWidget {
  final VoidCallback onClose;
  const _JilianLoginContent({Key? key, required this.onClose})
      : super(key: key);

  @override
  State<_JilianLoginContent> createState() => _JilianLoginContentState();
}

class _JilianLoginContentState extends State<_JilianLoginContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _accountPwdTab = 0.obs; // 0=手机登录, 1=邮箱登录

  // 控制器
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _pwdController = TextEditingController();
  final _emailController = TextEditingController();
  final _emailPwdController = TextEditingController();

  final _isSending = false.obs;
  final _countdown = 0.obs;
  final _agree = true.obs;
  final _autoLogin = true.obs;

  // 注册
  final _regTab = 0.obs; // 0=手机注册, 1=邮箱注册
  final _regPhoneController = TextEditingController();
  final _regCodeController = TextEditingController();
  final _regPwdController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regSending = false.obs;
  final _regCountdown = 0.obs;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _pwdController.dispose();
    _emailController.dispose();
    _emailPwdController.dispose();
    _regPhoneController.dispose();
    _regCodeController.dispose();
    _regPwdController.dispose();
    _regEmailController.dispose();
    super.dispose();
  }

  void _sendCode() async {
    if (_isSending.value || _countdown.value > 0) return;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length != 11) {
      showToast('请输入正确手机号');
      return;
    }
    _isSending.value = true;
    try {
      final res = await jilianApi.sendSms(phone);
      showToast(res['msg'] ?? '发送成功');
      if (res['code'] == 0) {
        _countdown.value = 60;
        Timer.periodic(const Duration(seconds: 1), (t) {
          if (_countdown.value <= 0) {
            t.cancel();
          } else {
            _countdown.value--;
          }
        });
      }
    } finally {
      _isSending.value = false;
    }
  }

  void _submitSms() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (phone.isEmpty || phone.length != 11) {
      showToast('请输入正确手机号');
      return;
    }
    if (code.isEmpty) {
      showToast('请输入验证码');
      return;
    }
    final res = await jilianApi.loginBySms(phone, code);
    _handleResult(res);
  }

  void _submitAccountPassword() async {
    final account = _accountPwdTab.value == 0
        ? _phoneController.text.trim()
        : _emailController.text.trim();
    final pwd = _accountPwdTab.value == 0
        ? _pwdController.text
        : _emailPwdController.text;
    if (account.isEmpty) {
      showToast(_accountPwdTab.value == 0 ? '请输入手机号' : '请输入邮箱');
      return;
    }
    if (pwd.isEmpty) {
      showToast('请输入密码');
      return;
    }
    final res = await jilianApi.loginByAccount(account, pwd);
    _handleResult(res);
  }

  void _handleResult(Map<String, dynamic> res) {
    if (res['code'] == 0) {
      showToast('登录成功');
      widget.onClose();
      bindCurrentDeviceAndHeartbeat();
    } else {
      showToast(res['msg'] ?? '登录失败');
    }
  }

  Widget _buildQrPane(String title, String subTitle, IconData icon) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          width: 180,
          height: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: MyTheme.accent),
              const SizedBox(height: 12),
              Text('扫码登录',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(subTitle,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildSmsLogin() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('未注册的手机号将自动创建账号',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 12),
        _buildPhoneInput(_phoneController),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '请输入验证码',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Obx(() => SizedBox(
                  width: 110,
                  child: ElevatedButton(
                    onPressed: (_isSending.value || _countdown.value > 0)
                        ? null
                        : _sendCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                        _countdown.value > 0 ? '${_countdown.value}s' : '获取验证码',
                        style: const TextStyle(fontSize: 13)),
                  ),
                )),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitSms,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('登录', style: TextStyle(fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountPasswordLogin() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Obx(() => InkWell(
                      onTap: () => _accountPwdTab.value = 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _accountPwdTab.value == 0
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: _accountPwdTab.value == 0
                              ? [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4)
                                ]
                              : null,
                        ),
                        child: Text('手机登录',
                            style: TextStyle(
                                color: _accountPwdTab.value == 0
                                    ? MyTheme.accent
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.w600)),
                      ),
                    )),
              ),
              Expanded(
                child: Obx(() => InkWell(
                      onTap: () => _accountPwdTab.value = 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _accountPwdTab.value == 1
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: _accountPwdTab.value == 1
                              ? [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4)
                                ]
                              : null,
                        ),
                        child: Text('邮箱登录',
                            style: TextStyle(
                                color: _accountPwdTab.value == 1
                                    ? MyTheme.accent
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.w600)),
                      ),
                    )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Obx(() => _accountPwdTab.value == 0
            ? _buildPhoneInput(_phoneController)
            : TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email_outlined),
                  hintText: '请输入邮箱',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              )),
        const SizedBox(height: 12),
        TextField(
          controller: _accountPwdTab.value == 0
              ? _pwdController
              : _emailPwdController,
          obscureText: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.lock_outline),
            hintText: '请输入密码',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: Colors.grey.shade300)),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => showToast('请联系客服重置密码'),
            child: Text('忘记密码？',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitAccountPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('登录', style: TextStyle(fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneInput(TextEditingController controller) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              const Icon(Icons.phone_iphone_outlined, size: 18),
              const SizedBox(width: 4),
              Text('+86', style: TextStyle(color: Colors.grey.shade800)),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              hintText: '请输入手机号',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordInput(
      TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      obscureText: true,
      decoration: InputDecoration(
        hintText: hint,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade300)),
      ),
    );
  }

  void _regSendCode() async {
    if (_regSending.value || _regCountdown.value > 0) return;
    final phone = _regPhoneController.text.trim();
    if (phone.isEmpty || phone.length != 11) {
      showToast('请输入正确手机号');
      return;
    }
    if (!_agree.value) {
      showToast('请先同意用户协议');
      return;
    }
    _regSending.value = true;
    try {
      final res = await jilianApi.sendSms(phone);
      showToast(res['msg'] ?? '发送成功');
      if (res['code'] == 0) {
        _regCountdown.value = 60;
        Timer.periodic(const Duration(seconds: 1), (t) {
          if (_regCountdown.value <= 0) {
            t.cancel();
          } else {
            _regCountdown.value--;
          }
        });
      }
    } finally {
      _regSending.value = false;
    }
  }

  void _submitRegPhone() async {
    final phone = _regPhoneController.text.trim();
    final code = _regCodeController.text.trim();
    final pwd = _regPwdController.text;
    if (phone.isEmpty || phone.length != 11) {
      showToast('请输入正确手机号');
      return;
    }
    if (code.isEmpty) {
      showToast('请输入验证码');
      return;
    }
    if (pwd.length < 6) {
      showToast('密码至少6位');
      return;
    }
    if (!_agree.value) {
      showToast('请先同意用户协议');
      return;
    }
    final res = await jilianApi.register(phone, code, pwd);
    _handleResult(res);
  }

  void _submitRegEmail() async {
    final email = _regEmailController.text.trim();
    final pwd = _regPwdController.text;
    if (email.isEmpty || !email.contains('@')) {
      showToast('请输入正确邮箱');
      return;
    }
    if (pwd.length < 6) {
      showToast('密码至少6位');
      return;
    }
    if (!_agree.value) {
      showToast('请先同意用户协议');
      return;
    }
    final res = await jilianApi.registerEmail(email, pwd);
    _handleResult(res);
  }

  Widget _buildRegisterPane() {
    return Obx(() => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _regTab.value = 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _regTab.value == 0
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('手机注册',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: _regTab.value == 0
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _regTab.value = 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _regTab.value == 1
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('邮箱注册',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: _regTab.value == 1
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_regTab.value == 0) ...[
              _buildPhoneInput(_regPhoneController),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _regCodeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '验证码',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Obx(() => SizedBox(
                        width: 110,
                        child: ElevatedButton(
                          onPressed: (_regSending.value ||
                                  _regCountdown.value > 0)
                              ? null
                              : _regSendCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MyTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                              _regCountdown.value > 0
                                  ? '${_regCountdown.value}s'
                                  : '获取验证码',
                              style: const TextStyle(fontSize: 13)),
                        ),
                      )),
                ],
              ),
              const SizedBox(height: 12),
              _buildPasswordInput(_regPwdController, '设置密码(至少6位)'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitRegPhone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('注册并登录',
                      style: TextStyle(fontSize: 15)),
                ),
              ),
            ] else ...[
              TextField(
                controller: _regEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: '邮箱',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              ),
              const SizedBox(height: 12),
              _buildPasswordInput(_regPwdController, '设置密码(至少6位)'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitRegEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('注册并登录',
                      style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ],
        ));
  }

  Widget _buildBrandPanel() {
    return Container(
      width: 280,
      color: const Color(0xFF2196F3),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.computer, color: Color(0xFF2196F3), size: 26),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('极连远程',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  Text('更快 更稳定 更安全',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ],
          ),
          const Spacer(),
          _buildFeatureItem(Icons.flash_on_outlined, '极速连接 稳定流畅'),
          _buildFeatureItem(Icons.verified_user_outlined, '二次验证 安全加倍'),
          _buildFeatureItem(Icons.people_outline, '多人同控 高效协作'),
          _buildFeatureItem(Icons.folder_open_outlined, '超大文件 稳定快传'),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          // 左侧登录区
          Expanded(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部关闭按钮
                  Align(
                    alignment: Alignment.topRight,
                    child: InkWell(
                      onTap: widget.onClose,
                      child: Icon(Icons.close, color: Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Tab 标题
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: MyTheme.accent,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: MyTheme.accent,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelStyle:
                        const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    tabs: const [
                      Tab(text: '手机验证登录'),
                      Tab(text: '账号密码登录'),
                      Tab(text: '注册账号'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Tab 内容
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSmsLogin(),
                        _buildAccountPasswordLogin(),
                        _buildRegisterPane(),
                      ],
                    ),
                  ),
                  // 底部协议 + 自动登录
                  Row(
                    children: [
                      Obx(() => Checkbox(
                            value: _agree.value,
                            onChanged: (v) => _agree.value = v ?? true,
                            activeColor: MyTheme.accent,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          )),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: '登录即表示同意',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                            children: [
                              TextSpan(
                                text: '《用户隐私政策》',
                                style: TextStyle(color: MyTheme.accent),
                              ),
                              const TextSpan(text: '和'),
                              TextSpan(
                                text: '《软件许可协议》',
                                style: TextStyle(color: MyTheme.accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Obx(() => Checkbox(
                            value: _autoLogin.value,
                            onChanged: (v) => _autoLogin.value = v ?? true,
                            activeColor: MyTheme.accent,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          )),
                      Text('下次自动登录',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 右侧品牌面板
          _buildBrandPanel(),
        ],
      ),
    );
  }
}

/// 极连远程：屏幕墙（监控墙）——在一个界面展示多台电脑的实时画面入口。
/// 仅展示电脑设备（排除手机端），点击「实时查看」打开该设备的实时画面。
class _JilianScreenWallPage extends StatefulWidget {
  const _JilianScreenWallPage({Key? key}) : super(key: key);

  @override
  State<_JilianScreenWallPage> createState() => _JilianScreenWallPageState();
}

class _JilianScreenWallPageState extends State<_JilianScreenWallPage> {
  List<JilianDevice> _devices = [];
  bool _loading = false;
  String? _error;
  final Map<String, bool> _onlineStates = {};
  Timer? _onlineTimer;
  static const _onlineEvent = 'callback_query_onlines';
  static const _onlineHandlerKey = 'jilian_screen_wall';

  @override
  void initState() {
    super.initState();
    platformFFI.registerEventHandler(_onlineEvent, _onlineHandlerKey, (evt) async {
      _onOnlineEvent(evt);
    });
    _loadDevices();
    jilianApi.loginState.listen((_) {
      if (mounted) _loadDevices();
    });
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    platformFFI.unregisterEventHandler(_onlineEvent, _onlineHandlerKey);
    super.dispose();
  }

  void _onOnlineEvent(Map<String, dynamic> evt) {
    final onlines = (evt['onlines'] as String? ?? '')
        .split(',')
        .where((s) => s.isNotEmpty);
    final offlines = (evt['offlines'] as String? ?? '')
        .split(',')
        .where((s) => s.isNotEmpty);
    if (mounted) {
      setState(() {
        for (final id in onlines) _onlineStates[id] = true;
        for (final id in offlines) _onlineStates[id] = false;
      });
    }
  }

  Future<void> _queryOnlineStates() async {
    final localId = trimID(gFFI.serverModel.serverId.text);
    final ids = <String>{};
    for (final d in _devices) {
      final id = trimID(d.deviceId);
      if (id.isNotEmpty && id != localId) ids.add(id);
    }
    if (ids.isNotEmpty) {
      try {
        await bind.queryOnlines(ids: ids.toList(growable: false));
      } catch (e) {
        debugPrint('screen wall queryOnlines error: $e');
      }
    }
  }

  Future<void> _loadDevices() async {
    if (!jilianApi.isLoggedIn) {
      if (mounted) {
        setState(() {
          _devices = [];
          _loading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final list = await jilianApi.getDeviceList();
      if (mounted) {
        setState(() {
          _devices = list;
          _loading = false;
          _error = null;
        });
      }
      _queryOnlineStates();
      _onlineTimer?.cancel();
      _onlineTimer =
          Timer.periodic(const Duration(seconds: 8), (_) => _queryOnlineStates());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败：$e';
          _loading = false;
        });
      }
    }
  }

  IconData _platformIcon(String? platform) {
    switch ((platform ?? '').toLowerCase()) {
      case 'windows':
        return Icons.desktop_windows;
      case 'macos':
      case 'mac':
        return Icons.laptop_mac;
      case 'linux':
        return Icons.computer;
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      default:
        return Icons.device_unknown;
    }
  }

  bool _isMobile(String? platform) {
    final p = (platform ?? '').toLowerCase();
    return p == 'android' || p == 'ios';
  }

  @override
  Widget build(BuildContext context) {
    if (!jilianApi.isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grid_view_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('请先登录极连账号以使用屏幕墙',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          ],
        ),
      );
    }

    final localId = trimID(gFFI.serverModel.serverId.text);
    // 仅展示电脑设备（排除手机端），本机也排除
    final computers = _devices.where((d) {
      final id = trimID(d.deviceId);
      return id != localId && !_isMobile(d.platform);
    }).toList();

    if (_loading && computers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (computers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grid_view_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('暂无可监控的电脑设备',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 8),
            Text('在「设备列表」中添加电脑后，这里会显示其实时画面入口',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('屏幕墙 · 监控 ${computers.length} 台电脑',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.5,
              ),
              itemCount: computers.length,
              itemBuilder: (context, index) {
                final d = computers[index];
                final id = trimID(d.deviceId);
                final online = _onlineStates[id] ?? (d.isOnline == 1);
                final name = d.deviceName.isNotEmpty
                    ? d.deviceName
                    : (d.deviceAlias.isNotEmpty ? d.deviceAlias : id);
                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Theme.of(context)
                            .dividerColor
                            .withOpacity(0.5)),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_platformIcon(d.platform),
                              size: 22, color: MyTheme.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: online ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(id,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12)),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: online ? () => connect(context, id) : null,
                          icon: const Icon(Icons.visibility, size: 16),
                          label: Text(online ? '实时查看' : '离线'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
