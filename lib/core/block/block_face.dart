import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'block_model.dart';

/// 积木的脸——全部由 [CustomPainter] 程序化绘制，不依赖任何位图或矢量素材。
///
/// 见 design.md D6：几何积木风格与程序化绘制天然一致，零素材、零依赖、零许可
/// 问题。这也是让积木「活起来」的关键：吸引 3 岁孩子的从来不是数学，而是
/// **方块有脸、会眨眼、会做表情**。
class BlockFacePainter extends CustomPainter {
  const BlockFacePainter({
    required this.expression,
    this.blink = 0.0,
    this.color = BlockColors.eye,
  });

  final BlockExpression expression;

  /// 眨眼进度：0 = 完全睁开，1 = 完全闭合。
  final double blink;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.07
      ..strokeCap = StrokeCap.round;

    final eyeY = size.height * 0.38;
    final leftEye = Offset(size.width * 0.32, eyeY);
    final rightEye = Offset(size.width * 0.68, eyeY);
    final eyeRadius = unit * (expression == BlockExpression.surprised ? 0.12 : 0.09);

    switch (expression) {
      case BlockExpression.happy:
        // 开心时眼睛是上弯的弧（^ ^），不受眨眼影响。
        _drawArcEye(canvas, stroke, leftEye, eyeRadius);
        _drawArcEye(canvas, stroke, rightEye, eyeRadius);
      case BlockExpression.idle:
      case BlockExpression.surprised:
        _drawRoundEye(canvas, paint, leftEye, eyeRadius);
        _drawRoundEye(canvas, paint, rightEye, eyeRadius);
    }

    _drawMouth(canvas, stroke, size, unit);
  }

  /// 圆眼睛。眨眼时纵向压扁成一条线。
  void _drawRoundEye(Canvas canvas, Paint paint, Offset center, double radius) {
    final openness = (1.0 - blink).clamp(0.06, 1.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: radius * 2,
        height: radius * 2 * openness,
      ),
      paint,
    );
  }

  /// 上弯弧形眼睛（开心）。
  void _drawArcEye(Canvas canvas, Paint stroke, Offset center, double radius) {
    canvas.drawArc(
      Rect.fromCenter(
        center: center.translate(0, radius * 0.4),
        width: radius * 2.4,
        height: radius * 2.0,
      ),
      math.pi, // 从左侧起，画上半弧
      math.pi,
      false,
      stroke,
    );
  }

  void _drawMouth(Canvas canvas, Paint stroke, Size size, double unit) {
    final center = Offset(size.width * 0.5, size.height * 0.64);

    switch (expression) {
      case BlockExpression.surprised:
        // 惊讶：小圆嘴。
        canvas.drawCircle(
          center,
          unit * 0.09,
          Paint()
            ..color = stroke.color
            ..style = PaintingStyle.fill,
        );
      case BlockExpression.happy:
        // 开心：大弧笑口。
        canvas.drawArc(
          Rect.fromCenter(
            center: center,
            width: unit * 0.46,
            height: unit * 0.34,
          ),
          0,
          math.pi,
          false,
          stroke,
        );
      case BlockExpression.idle:
        // 待机：浅浅的微笑。
        canvas.drawArc(
          Rect.fromCenter(
            center: center,
            width: unit * 0.30,
            height: unit * 0.18,
          ),
          0,
          math.pi,
          false,
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(BlockFacePainter oldDelegate) =>
      oldDelegate.expression != expression ||
      oldDelegate.blink != blink ||
      oldDelegate.color != color;
}

/// 带自发眨眼的积木脸。
///
/// 待机状态下按随机间隔眨眼——固定间隔会让一屏积木整齐划一地眨，
/// 像机器而不像一群小伙伴。
class BlockFace extends StatefulWidget {
  const BlockFace({
    super.key,
    required this.expression,
    this.color = BlockColors.eye,
  });

  final BlockExpression expression;
  final Color color;

  @override
  State<BlockFace> createState() => _BlockFaceState();
}

class _BlockFaceState extends State<BlockFace>
    with SingleTickerProviderStateMixin {
  static const Duration _blinkDuration = Duration(milliseconds: 150);
  static const Duration _minIdleGap = Duration(milliseconds: 2200);
  static const Duration _maxIdleGap = Duration(milliseconds: 6000);

  late final AnimationController _blinkController = AnimationController(
    vsync: this,
    duration: _blinkDuration,
  );
  final math.Random _random = math.Random();

  /// 必须持有并可取消。用 `Future.delayed` 的话组件销毁后定时器仍会挂着
  /// 最多 6 秒——单块积木无所谓，但拼搭台上积木频繁增删时会攒下一堆悬空
  /// 定时器，测试里也会直接报 "A Timer is still pending"。
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    final span = _maxIdleGap.inMilliseconds - _minIdleGap.inMilliseconds;
    final delay = Duration(
      milliseconds: _minIdleGap.inMilliseconds + _random.nextInt(span),
    );
    _blinkTimer = Timer(delay, () async {
      if (!mounted) return;
      try {
        // 只在待机时眨眼——开心/惊讶有各自的表情，不该被眨眼打断。
        if (widget.expression == BlockExpression.idle) {
          await _blinkController.forward();
          if (!mounted) return;
          await _blinkController.reverse();
        }
      } on TickerCanceled {
        return; // 动画期间被销毁，正常结束
      }
      if (!mounted) return;
      _scheduleBlink();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _blinkController,
      builder: (context, _) => CustomPaint(
        painter: BlockFacePainter(
          expression: widget.expression,
          blink: _blinkController.value,
          color: widget.color,
        ),
      ),
    );
  }
}
