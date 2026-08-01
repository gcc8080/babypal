import 'package:flutter/material.dart';

import 'about_page.dart';
import 'dashboard_page.dart';
import 'parent_shell.dart';
import 'recorder_page.dart';
import 'settings_page.dart';

/// 家长区首页。
///
/// 四件事，一件也不多：录音、设置、看板、关于。见 [ParentShell] 的说明——
/// 这里长得越像一个普通的设置界面越好。
class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    void go(Widget page) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
    }

    return ParentShell(
      title: '家长区',
      child: ListView(
        children: [
          ParentTile(
            key: const ValueKey('to-recorder'),
            icon: Icons.mic_rounded,
            title: '录我的声音',
            subtitle: '用真人语音替换任意一条，录完立刻生效',
            onTap: () => go(const ParentRecorderPage()),
          ),
          const Divider(height: 1),
          ParentTile(
            key: const ValueKey('to-settings'),
            icon: Icons.tune_rounded,
            title: '设置',
            subtitle: '中英双声道 · 每日时长 · 哪些大陆开着',
            onTap: () => go(const ParentSettingsPage()),
          ),
          const Divider(height: 1),
          ParentTile(
            key: const ValueKey('to-dashboard'),
            icon: Icons.insights_rounded,
            title: '今天玩了什么',
            subtitle: '玩了多久 · 哪些还生疏',
            onTap: () => go(const ParentDashboardPage()),
          ),
          const Divider(height: 1),
          ParentTile(
            key: const ValueKey('to-about'),
            icon: Icons.info_outline_rounded,
            title: '关于',
            subtitle: '隐私 · 素材署名 · 防止他退出应用',
            onTap: () => go(const ParentAboutPage()),
          ),
        ],
      ),
    );
  }
}
