import 'package:flutter/material.dart';

import 'tokens.dart';

/// 托盘里所有可按的东西的共同外壳。
///
/// 两条不变量：
///
/// 1. **按下即触发**，不等抬手判定。用原始 [Listener] 而非 `GestureDetector`
///    ——手势竞技场要等到抬手甚至等到与父级滚动视图竞争完才出结果，而
///    「触摸必有回应」这条红线要求按下的那一瞬间就有动静。首页的大陆瓦片
///    也是同样的原因（见 2.11 的实现说明）。
/// 2. **高度锁死在 90dp**，不随 [BlockScale] 缩放。缩放会在小屏上把它压到
///    76dp，正好抵消这条红线的意义（见 2.11 的同名修复）。
class PressableTile extends StatefulWidget {
  const PressableTile({
    super.key,
    required this.child,
    required this.onPressed,
    required this.color,
    this.width,
    this.expand = false,
  });

  final Widget child;
  final VoidCallback onPressed;
  final Color color;

  /// 为 null 时由父级约束决定宽度（如放进 `Expanded`）。
  final double? width;

  /// 撑满父级高度，而不是锁死 90dp。
  ///
  /// 只在**父级已经保证了不低于 90dp** 的场合用——比如字母页里占满上半屏的
  /// 名词卡。父级必须给紧约束（`Expanded` / `stretch`），否则没有子节点的
  /// 装饰盒会取 `constraints.smallest` 塌成 0，正是托盘缩略图那个真机 bug。
  final bool expand;

  @override
  State<PressableTile> createState() => _PressableTileState();
}

class _PressableTileState extends State<PressableTile> {
  bool _pressed = false;

  void _down(PointerDownEvent _) {
    setState(() => _pressed = true);
    widget.onPressed();
  }

  void _release() {
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        scale: _pressed ? BlockMetrics.squashScale : 1.0,
        duration: Duration(milliseconds: _pressed ? 90 : 320),
        curve: _pressed ? Curves.easeOut : Curves.elasticOut,
        child: SizedBox(
          width: widget.width,
          height: widget.expand ? null : BlockMetrics.minGrabTarget,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(BlockMetrics.blockRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 托盘右侧的动作按钮（重来 / 下一题）。
///
/// 用图标而非文字——儿童端零文字。[highlighted] 只是「该走了」的提示，
/// **按钮任何时候都能按**：他想跳过就跳过，不做门禁。
class RoundActionButton extends StatelessWidget {
  const RoundActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool highlighted;

  /// 「完成了」的统一提示色。五个模块共用，让「绿 = 成了」成为一条
  /// 不用教的约定。
  static Color get doneColor => BlockColors.forIndex(4);

  @override
  Widget build(BuildContext context) {
    return PressableTile(
      width: BlockMetrics.minGrabTarget,
      onPressed: onPressed,
      color: highlighted ? doneColor : Colors.white,
      child: Icon(
        icon,
        size: BlockMetrics.minGrabTarget * 0.42,
        color: highlighted ? Colors.white : BlockColors.ink,
      ),
    );
  }
}
