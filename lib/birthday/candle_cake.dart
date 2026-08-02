import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design/tokens.dart';

/// 蛋糕与蜡烛。
///
/// 程序化绘制，零素材——与全 App 一致（design.md D6）。蛋糕本身用的就是
/// 积木的语汇：一层层方块堆起来、圆角、同一套调色板。他看到的不是一张
/// 蛋糕图片，是**用他的积木搭出来的蛋糕**。
class CandleCake extends StatefulWidget {
  const CandleCake({
    super.key,
    required this.total,
    required this.remaining,
    required this.lit,
    required this.blowing,
    required this.showTapHint,
  });

  final int total;

  /// 还亮着几根。
  final int remaining;

  /// 点着了没有。没点着时蜡烛是灰的，画面在说「还差一步」。
  final bool lit;

  /// 正在吹——火苗歪向一边。
  final bool blowing;

  /// 演示「点一下也行」。
  final bool showTapHint;

  @override
  State<CandleCake> createState() => _CandleCakeState();
}

class _CandleCakeState extends State<CandleCake>
    with SingleTickerProviderStateMixin {
  /// 火苗的摇曳。**一直在动**——静止的火苗看着就是假的，而这一段的全部
  /// 说服力就在于「那是真的在烧」。
  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flicker,
      builder: (context, _) => CustomPaint(
        painter: _CakePainter(
          total: widget.total,
          remaining: widget.remaining,
          lit: widget.lit,
          blowing: widget.blowing,
          showTapHint: widget.showTapHint,
          phase: _flicker.value,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _CakePainter extends CustomPainter {
  const _CakePainter({
    required this.total,
    required this.remaining,
    required this.lit,
    required this.blowing,
    required this.showTapHint,
    required this.phase,
  });

  final int total;
  final int remaining;
  final bool lit;
  final bool blowing;
  final bool showTapHint;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // 蛋糕按可用空间定尺寸，短边说了算——横屏手机上高度才是稀缺的那一维。
    final cake = math.min(size.width * 0.52, size.height * 0.62);
    final left = (size.width - cake) / 2;
    final bottom = size.height * 0.94;
    final tierHeight = cake * 0.26;
    final radius = Radius.circular(cake * 0.06);

    // 两层，下宽上窄，像两块摞起来的积木。
    _tier(
      canvas,
      Rect.fromLTWH(left, bottom - tierHeight, cake, tierHeight),
      BlockColors.forIndex(9),
      radius,
    );
    final topWidth = cake * 0.78;
    _tier(
      canvas,
      Rect.fromLTWH(
        left + (cake - topWidth) / 2,
        bottom - tierHeight * 2,
        topWidth,
        tierHeight,
      ),
      BlockColors.forIndex(5),
      radius,
    );

    // 奶油：上层顶面一条浅色。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + (cake - topWidth) / 2,
          bottom - tierHeight * 2,
          topWidth,
          tierHeight * 0.22,
        ),
        radius,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    final candleTop = bottom - tierHeight * 2;
    final spacing = topWidth / (total + 1);
    for (var i = 0; i < total; i++) {
      final x = left + (cake - topWidth) / 2 + spacing * (i + 1);
      // 从右往左灭：他吹的时候火苗是一根根消失的，顺序固定才看得出
      // 「少了一根」而不是「换了一张图」。
      final isLit = lit && i < remaining;
      _candle(canvas, x, candleTop, cake, isLit: isLit, index: i);
    }

    if (showTapHint) _tapHint(canvas, size, left + cake / 2, candleTop, cake);
  }

  void _tier(Canvas canvas, Rect rect, Color color, Radius radius) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = color,
    );
  }

  void _candle(
    Canvas canvas,
    double x,
    double top,
    double cake, {
    required bool isLit,
    required int index,
  }) {
    final width = cake * 0.055;
    final height = cake * 0.30;
    final body = Rect.fromLTWH(x - width / 2, top - height, width, height);

    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(width * 0.4)),
      Paint()..color = BlockColors.forIndex(index * 2),
    );

    final wickTop = body.top - height * 0.12;
    canvas.drawLine(
      Offset(x, body.top),
      Offset(x, wickTop),
      Paint()
        ..color = BlockColors.ink.withValues(alpha: 0.7)
        ..strokeWidth = width * 0.16
        ..strokeCap = StrokeCap.round,
    );

    if (!isLit) {
      // 灭掉的那根冒一缕烟——**灭了要看得出是「刚刚灭的」**，
      // 而不是一开始就没点。
      if (lit) _smoke(canvas, x, wickTop, cake, index);
      return;
    }
    _flame(canvas, x, wickTop, cake, index);
  }

  void _flame(Canvas canvas, double x, double top, double cake, int index) {
    // 每根火苗相位错开，免得三根像同一只手在晃。
    final t = (phase + index * 0.31) * math.pi * 2;
    // 吹的时候歪得厉害、缩得小——这是「气吹到了」唯一的视觉证据。
    final lean = (blowing ? 0.42 : 0.08) * math.sin(t) * cake * 0.09;
    final scale = blowing ? 0.62 : 1.0;
    final h = cake * 0.11 * scale * (0.9 + 0.1 * math.sin(t * 1.7));
    final w = cake * 0.045 * scale;

    final path = Path()
      ..moveTo(x, top)
      ..quadraticBezierTo(x - w, top - h * 0.45, x + lean * 0.5, top - h)
      ..quadraticBezierTo(x + w, top - h * 0.45, x, top);

    canvas.drawPath(path, Paint()..color = const Color(0xFFF2B441));
    canvas.drawPath(
      Path()
        ..moveTo(x, top)
        ..quadraticBezierTo(
          x - w * 0.45,
          top - h * 0.42,
          x + lean * 0.4,
          top - h * 0.62,
        )
        ..quadraticBezierTo(x + w * 0.45, top - h * 0.42, x, top),
      Paint()..color = const Color(0xFFFFF3C4),
    );
  }

  void _smoke(Canvas canvas, double x, double top, double cake, int index) {
    final t = (phase + index * 0.2) % 1.0;
    final paint = Paint()
      ..color = BlockColors.ink.withValues(alpha: 0.22 * (1 - t))
      ..style = PaintingStyle.stroke
      ..strokeWidth = cake * 0.012
      ..strokeCap = StrokeCap.round;
    final h = cake * 0.16;
    final path = Path()..moveTo(x, top);
    for (var i = 1; i <= 6; i++) {
      final f = i / 6;
      path.lineTo(
        x + math.sin((f * 3 + t * 2) * math.pi) * cake * 0.02,
        top - h * f - t * cake * 0.06,
      );
    }
    canvas.drawPath(path, paint);
  }

  /// 「点一下也行」：一个手指印在蜡烛上方一起一落。
  ///
  /// 零文字（儿童端红线），而且**只演不拦**——它不挡住任何东西，
  /// 他想继续吹就继续吹。
  void _tapHint(
    Canvas canvas,
    Size size,
    double x,
    double candleTop,
    double cake,
  ) {
    final bob = math.sin(phase * math.pi * 2) * cake * 0.03;
    final y = candleTop - cake * 0.46 + bob;
    final r = cake * 0.05;

    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()..color = BlockColors.ink.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      Offset(x, y),
      r * (1.0 + phase * 1.4),
      Paint()
        ..color = BlockColors.ink.withValues(alpha: 0.22 * (1 - phase))
        ..style = PaintingStyle.stroke
        ..strokeWidth = cake * 0.008,
    );
  }

  @override
  bool shouldRepaint(_CakePainter old) =>
      old.total != total ||
      old.remaining != remaining ||
      old.lit != lit ||
      old.blowing != blowing ||
      old.showTapHint != showTapHint ||
      old.phase != phase;
}
