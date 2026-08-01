import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/jilian_api.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../models/peer_model.dart';
import '../../common/widgets/peer_tab_page.dart';
import 'home_page.dart';
import 'jilian_login_page.dart';

/// 极连远程 - 设备列表页（ToDesk 风格）
class JilianDeviceListPage extends StatefulWidget implements PageShape {
  JilianDeviceListPage({Key? key}) : super(key: key);

  @override
  final icon = const Icon(Icons.devices_outlined);

  @override
  final title = '设备列表';

  @override
  final List<Widget> appBarActions = [];

  @override
  State<JilianDeviceListPage> createState() => _JilianDeviceListPageState();
}

class _JilianDeviceListPageState extends State<JilianDeviceListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final RxList<JilianDevice> _cloudDevices = <JilianDevice>[].obs;
  final RxBool _loading = false.obs;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    if (!jilianApi.isLoggedIn) return;
    _loading.value = true;
    try {
      final list = await jilianApi.getDeviceList();
      _cloudDevices.value = list;
    } catch (e) {
      debugPrint('拉取设备列表失败: $e');
    } finally {
      _loading.value = false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMyDevicesTab(),
                PeerTabPage(), // 复用 RustDesk 的最近连接
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Obx(() {
      final user = jilianApi.currentUser;
      final avatarSrc = jilianApi.avatarSource;
      final isLogin = jilianApi.isLoggedIn;
      return Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                // 头像
                GestureDetector(
                  onTap: isLogin ? null : () => _goLogin(),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: MyTheme.accent.withOpacity(0.15),
                    backgroundImage: avatarSrc != null
                        ? (avatarSrc.startsWith('http')
                            ? NetworkImage(avatarSrc)
                            : MemoryImage(base64Decode(avatarSrc))
                                as ImageProvider)
                        : null,
                    child: avatarSrc == null
                        ? const Icon(Icons.person, color: MyTheme.accent)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                            Text(
                            isLogin
                                ? (user?.nickname.isNotEmpty == true
                                    ? user!.nickname
                                    : user?.phone ?? '极连用户')
                                : '未登录',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isLogin) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '个人版',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: MyTheme.accent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '升级',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLogin
                            ? '个人设备：${_cloudDevices.length}'
                            : '登录后可同步电脑端设备',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLogin)
                  TextButton(
                    onPressed: _goLogin,
                    child: const Text('登录/注册',
                        style: TextStyle(color: MyTheme.accent)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 搜索栏
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.qr_code_scanner,
                      size: 20, color: Colors.grey[600]),
                  const VerticalDivider(width: 16, indent: 8, endIndent: 8),
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: '搜索设备代码或别名',
                        hintStyle: TextStyle(
                            fontSize: 13, color: Colors.grey[500]),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  Icon(Icons.search, size: 20, color: Colors.grey[600]),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: MyTheme.accent,
        unselectedLabelColor: Colors.grey[600],
        indicatorColor: MyTheme.accent,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: '我的设备'),
          Tab(text: '最近连接'),
        ],
      ),
    );
  }

  Widget _buildMyDevicesTab() {
    return Obx(() {
      if (!jilianApi.isLoggedIn) {
        return _buildLoginPrompt();
      }
      if (_loading.value && _cloudDevices.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_cloudDevices.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.devices_outlined, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 12),
              Text('暂无绑定设备',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              const SizedBox(height: 8),
              Text('在电脑端登录同一账号即可同步',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _loadDevices,
        color: MyTheme.accent,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _cloudDevices.length,
          itemBuilder: (context, index) {
            final d = _cloudDevices[index];
            return _buildDeviceCard(d);
          },
        ),
      );
    });
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_circle_outlined,
              size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text('登录后与电脑端设备同步',
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _goLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
            ),
            child: const Text('立即登录'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(JilianDevice d) {
    final isOnline = d.isOnline == 1;
    final displayName = d.deviceAlias.isNotEmpty ? d.deviceAlias : d.deviceName;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _connectToDevice(d.deviceId, displayName),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 设备缩略图（占位用 Windows 壁纸风格）
            Container(
              height: 130,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.blue[300]!,
                    Colors.blue[500]!,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? Colors.green.withOpacity(0.9)
                            : Colors.grey.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOnline ? Icons.desktop_windows : Icons.desktop_windows,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? '未锁屏' : '离线',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(Icons.desktop_windows,
                        size: 56, color: Colors.white.withOpacity(0.4)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isOnline ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _goLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JilianLoginPage()),
    ).then((_) {
      _loadDevices();
      setState(() {});
    });
  }

  void _connectToDevice(String deviceId, String name) {
    final id = trimID(deviceId);
    if (id.isEmpty) {
      showToast('设备代码无效');
      return;
    }
    showToast('正在连接 $name...');
    connect(context, id);
  }
}
