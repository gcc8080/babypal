import 'package:flutter/material.dart';

import '../core/design/tokens.dart';
import 'parent_shell.dart';

/// 关于：素材署名 · 隐私 · 防误退出引导。
///
/// 三件事放一页，因为它们回答的是同一类问题——「这个 App 会不会做我不知道的事」。
///
/// **全部是纯文本，没有一个外链按钮。** child-safety-ux 规格要求儿童端零外链；
/// 家长区虽然不受这条约束，但一个能跳出 App 的按钮放在这里，收益是省了家长
/// 手动输一次网址，代价是 App 里多了一条出口。协议原文照抄进来即可。
class ParentAboutPage extends StatelessWidget {
  const ParentAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ParentShell(
      title: '关于',
      child: ListView(
        padding: const EdgeInsets.all(BlockMetrics.gap),
        children: const [
          _Section(
            title: '隐私',
            body: '本应用不收集、不上传、不存储任何数据到设备之外。\n\n'
                '没有网络权限，没有第三方 SDK，没有广告，没有内购，没有任何'
                '统计或埋点。学习记录、时长、家长录音全部只存在这台设备上，'
                '卸载即消失。\n\n'
                '麦克风权限只在家长区录音时使用（以及生日彩蛋里的吹蜡烛）。'
                '录音写入应用私有目录，不会离开本机；不授权也不影响其余功能。',
          ),
          _Section(
            title: '图标素材署名',
            body: 'All emojis designed by OpenMoji – the open-source emoji and '
                'icon project.\n'
                'License: CC BY-SA 4.0\n'
                'https://creativecommons.org/licenses/by-sa/4.0/\n'
                'https://openmoji.org/\n\n'
                '名词卡片上的图标来自 OpenMoji 15.1.0，按 CC BY-SA 4.0 使用，'
                '未作修改。完整署名同时保存在仓库的 assets/icons/LICENSE.txt。',
          ),
          _Section(
            title: '积木与角色',
            body: '积木造型、表情与配色为原创，程序化绘制，不使用任何第三方'
                '角色形象。教学法（用立方体表示数量、位值、部件组字）属于'
                '公共领域。',
          ),
          _Section(
            title: '防止他退出应用',
            body: 'Android：设置 → 安全 → 「应用固定 / 屏幕固定」打开后，'
                '从最近任务里长按本应用选择固定。此后返回键与主页键需要'
                '同时长按才能退出。\n\n'
                'iOS：设置 → 辅助功能 → 引导式访问，打开后在本应用内'
                '连按三次侧边键启动。\n\n'
                '这两个是系统功能，比任何应用内的锁都可靠——'
                '应用内的锁总有办法绕过，系统级的没有。',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BlockMetrics.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: BlockColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.6,
              color: BlockColors.ink.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}
