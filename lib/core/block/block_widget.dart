import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'block_face.dart';
import 'block_model.dart';

/// 单块积木的渲染与触摸反馈。
///
/// **触摸反馈不变量**（block-engine 规格）：每一次作用于积木的触摸都必须产生
/// 可感知的反馈——挤压回弹、表情变化、音效，无一例外。绝不允许出现
/// 「点了没反应」的状态：对 3 岁孩子而言，没反应等同于坏掉了。
class BlockWidget extends StatefulWidget {
  const BlockWidget({
    super.key,
    required this.body,
    required this.cellSize,
    this.selected = false,
    this.onTap,
    this.onSquash,
  });

  final BlockBody body;

  /// 单位格边长（**已含缩放因子**的像素值）。
  final double cellSize;

  /// 点选通道的选中态。见 block-engine 规格「拖拽与点选双通道操作」。
  final bool selected;

  final VoidCallback? onTap;

  /// 挤压动画开始时触发——音频总线接上后由此播放音效（2.9）。
  ///
  /// 刻意与 [onTap] 分开：音效必须在**按下的瞬间**响，而不是等抬手判定完
  /// 才响，否则手感会「慢半拍」。
  final VoidCallback? onSquash;

  @override
  State<BlockWidget> createState() => _BlockWidgetState();
}

class _BlockWidgetState extends State<BlockWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _squashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 320),
  );

  late final Animation<double> _squash =
      Tween<double>(begin: 1.0, end: BlockMetrics.squashScale).animate(
        CurvedAnimation(
          parent: _squashController,
          curve: Curves.easeOut,
          // 回弹用 elasticOut，让方块像橡胶一样"弹"回来而不是平滑滑回。
          // 这一下弹性是整个手感的核心。
          reverseCurve: Curves.elasticOut.flipped,
        ),
      );

  /// 按下期间的瞬时表情覆盖，松手后回到 [BlockBody.expression]。
  bool _pressed = false;

  @override
  void dispose() {
    _squashController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    setState(() => _pressed = true);
    _squashController.forward();
    widget.onSquash?.call();
  }

  void _handleTapUp(TapUpDetails _) {
    _release();
    widget.onTap?.call();
  }

  void _handleTapCancel() => _release();

  void _release() {
    if (!mounted) return;
    setState(() => _pressed = false);
    _squashController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.body.widthUnits * widget.cellSize;
    final height = widget.body.heightUnits * widget.cellSize;
    final radius =
        BlockMetrics.blockRadius * (widget.cellSize / BlockMetrics.unit);
    final color = BlockColors.forIndex(widget.body.colorIndex);

    final expression = _pressed
        ? BlockExpression.surprised
        : widget.body.expression;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _squash,
        builder: (context, child) {
          // 纵向压扁、横向略撑开——真实橡胶块被按压时的体积守恒感。
          final s = _squash.value;
          return Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..scaleByDouble(1.0 + (1.0 - s) * 0.5, s, 1.0, 1.0),
            child: child,
          );
        },
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(radius),
                  border: widget.selected
                      ? Border.all(
                          color: BlockColors.ink,
                          width: widget.cellSize * 0.06,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: widget.cellSize * 0.08,
                      offset: Offset(0, widget.cellSize * 0.05),
                    ),
                  ],
                ),
              ),
              // 脸按单位格居中，多格积木的脸不会被拉长。
              Align(
                child: SizedBox(
                  width: widget.cellSize,
                  height: widget.cellSize,
                  child: BlockFace(expression: expression),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
