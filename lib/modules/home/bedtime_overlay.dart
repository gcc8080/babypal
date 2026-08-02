import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/block/block_face.dart';
import '../../core/block/block_model.dart';
import '../../core/design/tokens.dart';

/// 到点了：积木困了。
///
/// 见 parent-zone 规格「达到上限」：**MUST NOT 硬锁屏或弹出强制对话框**。
/// 所以这里不是一个 dialog，也不是把 App 关掉——是一层盖在上面的谢幕画面，
/// 积木一块块躺下、闭上眼睛、慢慢呼吸。
///
/// 为什么是「积木睡了」而不是「时间到了」：三岁的他读不懂时间，但完全读得懂
/// 「它们睡着了，我不能吵醒它们」。前者是被规则中断，后者是一件他能理解、
/// 甚至愿意配合的事——这是 15 分钟上限能不能被接受的全部差别。
///
/// 触摸仍然有回应（积木会动一下），但**不会醒**。「触摸必有回应」是红线，
/// 「按一下就能继续玩」不是。
class BedtimeOverlay extends StatefulWidget {
  const BedtimeOverlay({super.key, this.corner});

  /// 左上角挂的东西。家长门放在这里——**谢幕画面盖住了整个 App，
  /// 若连它也盖掉，家长就没有任何办法把上限调高了**。
  ///
  /// **左上而不是右下**：右下那一块被系统吃掉了，见 [ParentGateEntry]
  /// 的类文档。两处必须一致，否则家长要记两个位置。
  final Widget? corner;

  /// 躺下的时长。慢，因为这一段本身就是「该结束了」的信号，
  /// 快了就成了一次闪烁。
  static const Duration settleDuration = Duration(milliseconds: 2200);

  @override
  State<BedtimeOverlay> createState() => _BedtimeOverlayState();
}

class _BedtimeOverlayState extends State<BedtimeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: BedtimeOverlay.settleDuration,
  )..forward();

  /// 呼吸。躺下之后一直循环——静止的画面像卡住了，起伏才是「睡着了」。
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  /// 被戳一下时的晃动。醒不过来，但会动——「触摸必有回应」。
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void dispose() {
    _settle.dispose();
    _breathe.dispose();
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _nudge.forward(from: 0),
      child: AnimatedBuilder(
        animation: Listenable.merge([_settle, _breathe, _nudge]),
        builder: (context, _) {
          final settled = Curves.easeInOutCubic.transform(_settle.value);
          return Stack(
            fit: StackFit.expand,
            children: [
              // 天色暗下来，但**不是黑屏**：他得能看见积木还在那儿。
              ColoredBox(
                color: BlockColors.ink.withValues(alpha: 0.55 * settled),
              ),
              CustomPaint(
                painter: _SleepingBlocksPainter(
                  settled: settled,
                  breath: _breathe.value,
                  nudge: Curves.elasticOut.transform(_nudge.value),
                ),
              ),
              if (widget.corner != null)
                Positioned(
                  left: BlockMetrics.gap / 2,
                  top: BlockMetrics.gap / 2,
                  child: SafeArea(child: widget.corner!),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 五块积木躺成一排，闭着眼睛起伏。
///
/// 程序化绘制，零素材——与全 App 一致（design.md D6）。
class _SleepingBlocksPainter extends CustomPainter {
  const _SleepingBlocksPainter({
    required this.settled,
    required this.breath,
    required this.nudge,
  });

  final double settled;
  final double breath;
  final double nudge;

  /// 五块，对应五块大陆。他每天见的就是这五块。
  static const int _count = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width / (_count + 3), size.height * 0.26);
    final gap = side * 0.28;
    final totalWidth = _count * side + (_count - 1) * gap;
    final left = (size.width - totalWidth) / 2;
    final restY = size.height * 0.62;

    for (var i = 0; i < _count; i++) {
      // 一块块先后躺下，不是齐刷刷同时倒。
      final delay = i / (_count * 2.2);
      final progress = ((settled - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (progress <= 0) continue;

      final x = left + i * (side + gap);
      // 从上方飘下来，落到 restY。
      final y = restY - (1 - progress) * size.height * 0.45;
      // 呼吸：躺稳之后才开始起伏，相位错开一点，免得像同一只手在推。
      final breathOffset =
          progress * math.sin((breath + i * 0.17) * math.pi * 2) * side * 0.035;
      final wobble = nudge * side * 0.06 * (i.isEven ? 1 : -1);

      final rect = Rect.fromLTWH(
        x + wobble,
        y + breathOffset,
        side,
        side * 0.72, // 躺下的积木是扁的
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(side * 0.2),
      );

      canvas.drawRRect(
        rrect,
        Paint()..color = BlockColors.forIndex(i * 2).withValues(alpha: 0.92),
      );

      // 闭着的眼睛：blink = 1 就是眯到最细的那一条缝。
      canvas.save();
      canvas.translate(rect.left + side * 0.2, rect.top + rect.height * 0.18);
      BlockFacePainter(
        expression: BlockExpression.idle,
        blink: 1.0,
        color: Colors.white,
      ).paint(canvas, Size(side * 0.6, rect.height * 0.62));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SleepingBlocksPainter old) =>
      old.settled != settled || old.breath != breath || old.nudge != nudge;
}
