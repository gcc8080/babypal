import 'package:flutter/material.dart';

import '../core/design/tokens.dart';

/// 家长区所有页面的外壳。
///
/// **这是整个 App 里唯一有文字、唯一按成人尺度排版的地方。** 儿童端的每一条
/// 红线（90dp 抓取阈值、零文字、无对错提示）在这里都不适用，甚至应该反着来：
/// 家长区长得越像一个普通的设置界面越好——它不该吸引孩子多看一眼。
class ParentShell extends StatelessWidget {
  const ParentShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlockColors.skyBackground,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: BlockColors.skyBackground,
        foregroundColor: BlockColors.ink,
        elevation: 0,
        actions: actions,
      ),
      body: SafeArea(child: child),
    );
  }
}

/// 家长区的一行条目。
class ParentTile extends StatelessWidget {
  const ParentTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: BlockColors.ink.withValues(alpha: 0.7)),
      title: Text(title, style: const TextStyle(color: BlockColors.ink)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: BlockColors.ink.withValues(alpha: 0.6)),
            ),
      trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
      onTap: onTap,
    );
  }
}

/// 一段说明文字。家长区靠它交代「这个开关到底会怎样」。
class ParentNote extends StatelessWidget {
  const ParentNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BlockMetrics.gap,
        BlockMetrics.gap / 2,
        BlockMetrics.gap,
        BlockMetrics.gap / 2,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: BlockColors.ink.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}
