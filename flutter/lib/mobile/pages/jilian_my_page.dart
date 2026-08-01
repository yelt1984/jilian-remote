import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/jilian_api.dart';
import 'package:get/get.dart';

import '../../common.dart';
import 'home_page.dart';
import 'jilian_login_page.dart';

/// 极连远程 - 我的页（ToDesk 风格）
class JilianMyPage extends StatefulWidget implements PageShape {
  JilianMyPage({Key? key}) : super(key: key);

  @override
  final icon = const Icon(Icons.person_outline);

  @override
  final title = '我的';

  @override
  final List<Widget> appBarActions = [];

  @override
  State<JilianMyPage> createState() => _JilianMyPageState();
}

class _JilianMyPageState extends State<JilianMyPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        final isLogin = jilianApi.isLoggedIn;
        final user = jilianApi.currentUser;
        final avatarSrc = jilianApi.avatarSource;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: MyTheme.accent.withOpacity(0.15),
                      backgroundImage: avatarSrc != null
                          ? (avatarSrc.startsWith('http')
                              ? NetworkImage(avatarSrc)
                              : MemoryImage(base64Decode(avatarSrc))
                                  as ImageProvider)
                          : null,
                      child: avatarSrc == null
                          ? const Icon(Icons.person,
                              size: 32, color: MyTheme.accent)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isLogin
                                ? (user?.nickname.isNotEmpty == true
                                    ? user!.nickname
                                    : user?.phone ?? '极连用户')
                                : '未登录',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isLogin
                                ? (user?.phone ?? '')
                                : '登录后享受完整功能',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    if (!isLogin)
                      ElevatedButton(
                        onPressed: _goLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MyTheme.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('登录'),
                      )
                    else
                      OutlinedButton(
                        onPressed: _logout,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('退出'),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildSection(
                children: [
                  _buildMenuItem(Icons.workspace_premium_outlined, '会员中心',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: MyTheme.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('升级',
                            style: TextStyle(
                                color: Colors.white, fontSize: 11)),
                      )),
                  _buildMenuItem(Icons.devices_outlined, '我的设备'),
                  _buildMenuItem(Icons.history, '连接记录'),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: _buildSection(
                children: [
                  _buildMenuItem(Icons.settings_outlined, '设置'),
                  _buildMenuItem(Icons.help_outline, '帮助与反馈'),
                  _buildMenuItem(Icons.info_outline, '关于极连远程'),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildSection({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: MyTheme.accent, size: 22),
      title: Text(title),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        showToast('$title 即将上线');
      },
    );
  }

  void _goLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JilianLoginPage()),
    ).then((_) => setState(() {}));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await jilianApi.logout();
      setState(() {});
      showToast('已退出登录');
    }
  }
}
