import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'home_page.dart';
import 'server_page.dart';

/// 极连远程 - 远程连接页（ToDesk 风格）
class ConnectionPage extends StatefulWidget implements PageShape {
  ConnectionPage({Key? key, required this.appBarActions}) : super(key: key);

  @override
  final icon = const Icon(Icons.compare_arrows);

  @override
  final title = '远程连接';

  @override
  final List<Widget> appBarActions;

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _idController = IDTextEditingController();
  final RxBool _idEmpty = true.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();
  final AllPeersLoader _allPeersLoader = AllPeersLoader();
  StreamSubscription? _uniLinksSubscription;
  Iterable<Peer> _autocompleteOpts = [];

  // 0=远程控制, 1=文件传输, 2=协作会议
  int _connectMode = 0;

  _ConnectionPageState() {
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
    _idController.addListener(() {
      _idEmpty.value = _idController.text.isEmpty;
    });
    Get.put<IDTextEditingController>(_idController);
  }

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLogoHeader(),
                const SizedBox(height: 16),
                _buildRemoteIDTextField(),
                const SizedBox(height: 12),
                _buildModeSelector(),
                const SizedBox(height: 16),
                _buildConnectButtons(),
                const SizedBox(height: 20),
                _buildLocalDeviceCard(),
                const SizedBox(height: 20),
                _buildRecentConnectionsHeader(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: true,
          child: PeerTabPage(),
        )
      ],
    );
  }

  Widget _buildLogoHeader() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: MyTheme.accent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.compare_arrows,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        const Text(
          '极连远程',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: MyTheme.accent,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.qr_code_scanner, color: Colors.grey),
          onPressed: () => showToast('扫码功能即将上线'),
        ),
      ],
    );
  }

  Widget _buildRemoteIDTextField() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(Icons.search, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Expanded(
            child: RawAutocomplete<Peer>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text == '') {
                  _autocompleteOpts = const Iterable<Peer>.empty();
                } else if (_allPeersLoader.peers.isEmpty &&
                    !_allPeersLoader.isPeersLoaded) {
                  Peer emptyPeer = Peer(
                    id: '',
                    username: '',
                    hostname: '',
                    alias: '',
                    platform: '',
                    tags: [],
                    hash: '',
                    password: '',
                    forceAlwaysRelay: false,
                    rdpPort: '',
                    rdpUsername: '',
                    loginName: '',
                    device_group_name: '',
                  );
                  _autocompleteOpts = [emptyPeer];
                } else {
                  String textWithoutSpaces =
                      textEditingValue.text.replaceAll(" ", "");
                  if (int.tryParse(textWithoutSpaces) != null) {
                    textEditingValue = TextEditingValue(
                      text: textWithoutSpaces,
                      selection: textEditingValue.selection,
                    );
                  }
                  String textToFind = textEditingValue.text.toLowerCase();
                  _autocompleteOpts = _allPeersLoader.peers
                      .where((peer) =>
                          peer.id.toLowerCase().contains(textToFind) ||
                          peer.username.toLowerCase().contains(textToFind) ||
                          peer.hostname.toLowerCase().contains(textToFind) ||
                          peer.alias.toLowerCase().contains(textToFind))
                      .toList();
                }
                return _autocompleteOpts;
              },
              focusNode: _idFocusNode,
              textEditingController: _idEditingController,
              fieldViewBuilder: (BuildContext context,
                  TextEditingController fieldTextEditingController,
                  FocusNode fieldFocusNode,
                  VoidCallback onFieldSubmitted) {
                updateTextAndPreserveSelection(
                    fieldTextEditingController, _idController.text);
                return TextField(
                  controller: fieldTextEditingController,
                  focusNode: fieldFocusNode,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  onChanged: (String text) {
                    _idController.id = text;
                  },
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: '请输入远程设备代码或别名',
                    hintStyle: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[400],
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  inputFormatters: [IDTextInputFormatter()],
                  onSubmitted: (_) => _connectWithoutPassword(),
                );
              },
              onSelected: (option) {
                setState(() {
                  _idController.id = option.id;
                  FocusScope.of(context).unfocus();
                });
              },
              optionsViewBuilder: (BuildContext context,
                  AutocompleteOnSelected<Peer> onSelected,
                  Iterable<Peer> options) {
                options = _autocompleteOpts;
                double maxHeight = options.length * 50;
                if (options.length == 1) {
                  maxHeight = 52;
                } else if (options.length == 3) {
                  maxHeight = 146;
                } else if (options.length == 4) {
                  maxHeight = 193;
                }
                maxHeight = maxHeight.clamp(0, 200);
                return Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: maxHeight,
                            maxWidth: 320,
                          ),
                          child: _allPeersLoader.peers.isEmpty &&
                                  !_allPeersLoader.isPeersLoaded
                              ? Container(
                                  height: 80,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.only(top: 5),
                                  children: options
                                      .map((peer) => AutocompletePeerTile(
                                          onSelect: () => onSelected(peer),
                                          peer: peer))
                                      .toList(),
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Obx(() => Offstage(
                offstage: _idEmpty.value,
                child: IconButton(
                  onPressed: () {
                    setState(() {
                      _idController.clear();
                    });
                  },
                  icon: Icon(Icons.clear, color: Colors.grey[500]),
                ),
              )),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    final modes = ['远程控制', '文件传输', '协作会议'];
    return Row(
      children: List.generate(modes.length, (index) {
        final selected = _connectMode == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _connectMode = index),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Radio<int>(
                  value: index,
                  groupValue: _connectMode,
                  activeColor: MyTheme.accent,
                  onChanged: (v) => setState(() => _connectMode = v ?? 0),
                ),
                Text(
                  modes[index],
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? MyTheme.accent : Colors.grey[700],
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildConnectButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _connectWithoutPassword,
            style: OutlinedButton.styleFrom(
              foregroundColor: MyTheme.accent,
              side: const BorderSide(color: MyTheme.accent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('免密连接',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _connectWithPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            child: const Text('密码连接',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalDeviceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '连接本设备',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[500]),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildLocalAction(Icons.screen_share_outlined, '手机投屏'),
              _buildLocalAction(Icons.videocam_outlined, '远程摄像头'),
              _buildLocalAction(Icons.phonelink_setup, '远程控制'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocalAction(IconData icon, String label) {
    return Expanded(
      child: InkWell(
        onTap: () {
          if (label == '远程控制') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ServerPage()),
            );
          } else {
            showToast('$label 即将上线');
          }
        },
        child: Column(
          children: [
            Icon(icon, color: MyTheme.accent, size: 28),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentConnectionsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '最近连接',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        TextButton(
          onPressed: () {},
          child: const Text('...', style: TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }

  void onConnect({String? password}) {
    var id = _idController.id;
    if (id.isEmpty) {
      showToast('请输入远程设备代码');
      return;
    }
    switch (_connectMode) {
      case 0:
        connect(context, id, password: password);
        break;
      case 1:
        connect(context, id, isFileTransfer: true, password: password);
        break;
      case 2:
        showToast('协作会议即将上线');
        break;
    }
  }

  void _connectWithoutPassword() => onConnect();

  void _connectWithPassword() async {
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('输入密码'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: '远程设备密码'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('连接')),
          ],
        );
      },
    );
    if (password != null && password.isNotEmpty) {
      onConnect(password: password);
    }
  }

  void onFocusChanged() {
    _idEmpty.value = _idEditingController.text.isEmpty;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }
      final textLength = _idEditingController.value.text.length;
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _idController.dispose();
    _idFocusNode.removeListener(onFocusChanged);
    _allPeersLoader.clear();
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }
}
