import 'package:flutter/material.dart';

import '../../common.dart';
import 'home_page.dart';

/// 极连远程 - 应用中心页（ToDesk 风格占位，后续可扩展游戏/工具）
class JilianAppCenterPage extends StatefulWidget implements PageShape {
  JilianAppCenterPage({Key? key}) : super(key: key);

  @override
  final icon = const Icon(Icons.gamepad_outlined);

  @override
  final title = '应用中心';

  @override
  final List<Widget> appBarActions = [];

  @override
  State<JilianAppCenterPage> createState() => _JilianAppCenterPageState();
}

class _JilianAppCenterPageState extends State<JilianAppCenterPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '应用中心',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '扩展你的远程控制体验',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              delegate: SliverChildListDelegate([
                _buildToolItem(Icons.mouse_outlined, '远程键鼠', '键鼠映射'),
                _buildToolItem(Icons.keyboard_outlined, '游戏键盘', '自定义按键'),
                _buildToolItem(Icons.videogame_asset_outlined, '游戏手柄', '手柄映射'),
                _buildToolItem(Icons.folder_open_outlined, '文件传输', '跨设备互传'),
                _buildToolItem(Icons.camera_alt_outlined, '远程摄像头', '查看远端画面'),
                _buildToolItem(Icons.screen_share_outlined, '手机投屏', '投到电脑'),
                _buildToolItem(Icons.power_settings_new, '电源操作', '锁屏/重启/关机'),
                _buildToolItem(Icons.more_horiz, '更多', '敬请期待'),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                elevation: 0,
                color: MyTheme.accent.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: MyTheme.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.rocket_launch,
                            color: MyTheme.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '升级为专业版',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '解锁更多高级功能与商业授权',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolItem(IconData icon, String title, String subtitle) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: MyTheme.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: MyTheme.accent, size: 26),
        ),
        const SizedBox(height: 8),
        Text(title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(subtitle,
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
