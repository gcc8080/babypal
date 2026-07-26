import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'module_id.dart';

/// 模块徽记——纯程序化绘制，零素材。
///
/// **零文字界面**（child-safety-ux 规格）：模块入口不得带文字标签。
/// 字母与汉字例外，因为它们本身就是**学习内容**而非界面指令——
/// 孩子看到 `A` 和 `木` 时认出的是内容，不是在读说明。
class ModuleEmblem extends StatelessWidget {
  const ModuleEmblem({super.key, required this.module, required this.size});

  final ModuleId module;
  final double size;

  @override
  Widget build(BuildContext context) {
    return switch (module) {
      // 三块方块堆成塔 → 数量。
      ModuleId.numbers => CustomPaint(
        size: Size.square(size),
        painter: _StackPainter(count: 3),
      ),
      // 两块方块 + 一个加号 → 合体。
      ModuleId.addition => CustomPaint(
        size: Size.square(size),
        painter: _PlusPainter(),
      ),
      // 字母本身即内容。
      ModuleId.letters => _Glyph(text: 'A', size: size),
      // 汉字本身即内容。取「木」——他已经认识，且是部件加法的起点。
      ModuleId.hanzi => _Glyph(text: '木', size: size),
      // 散落的方块 → 想怎么摆就怎么摆。
      ModuleId.sandbox => CustomPaint(
        size: Size.square(size),
        painter: _ScatterPainter(),
      ),
    };
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.text, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: size * 0.78,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

Paint get _chipPaint => Paint()
  ..color = Colors.white
  ..style = PaintingStyle.fill;

void _drawChip(Canvas canvas, Rect rect, double radius) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(radius)),
    _chipPaint,
  );
}

/// 竖向堆叠的方块，表示数量。
class _StackPainter extends CustomPainter {
  _StackPainter({required this.count});

  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final chip = size.width * 0.30;
    final gap = size.width * 0.07;
    final totalHeight = count * chip + (count - 1) * gap;
    var top = (size.height - totalHeight) / 2;
    final left = (size.width - chip) / 2;

    for (var i = 0; i < count; i++) {
      _drawChip(canvas, Rect.fromLTWH(left, top, chip, chip), chip * 0.24);
      top += chip + gap;
    }
  }

  @override
  bool shouldRepaint(_StackPainter old) => old.count != count;
}

/// 两块方块与一个加号。
class _PlusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final chip = size.width * 0.26;
    final radius = chip * 0.24;
    final cy = size.height / 2;

    _drawChip(
      canvas,
      Rect.fromLTWH(size.width * 0.06, cy - chip / 2, chip, chip),
      radius,
    );
    _drawChip(
      canvas,
      Rect.fromLTWH(size.width * 0.68, cy - chip / 2, chip, chip),
      radius,
    );

    // 中间的加号。
    final bar = size.width * 0.055;
    final arm = size.width * 0.20;
    final cx = size.width / 2;
    _drawChip(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy), width: arm, height: bar),
      bar / 2,
    );
    _drawChip(
      canvas,
      Rect.fromCenter(center: Offset(cx, cy), width: bar, height: arm),
      bar / 2,
    );
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => false;
}

/// 随意散落的方块——自由拼搭，没有对错。
class _ScatterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final chip = size.width * 0.27;
    final radius = chip * 0.24;

    // 固定的几个位置与角度，不用随机——每次进首页看到的应当是同一个图形。
    const layout = <(double, double, double)>[
      (0.08, 0.16, -0.18),
      (0.52, 0.06, 0.22),
      (0.30, 0.50, 0.06),
      (0.66, 0.56, -0.26),
    ];

    for (final (fx, fy, angle) in layout) {
      canvas.save();
      final center = Offset(
        size.width * fx + chip / 2,
        size.height * fy + chip / 2,
      );
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle * math.pi);
      _drawChip(
        canvas,
        Rect.fromCenter(center: Offset.zero, width: chip, height: chip),
        radius,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ScatterPainter oldDelegate) => false;
}

/// 星球弧线背景。
class PlanetArcPainter extends CustomPainter {
  const PlanetArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 一个远大于屏幕的圆，只露出顶部一段弧，读起来像站在星球表面。
    final radius = size.width * 0.9;
    final center = Offset(size.width / 2, size.height + radius * 0.82);
    canvas.drawCircle(center, radius, Paint()..color = color);
  }

  @override
  bool shouldRepaint(PlanetArcPainter old) => old.color != color;
}
