import 'package:flutter/material.dart';

import 'hanzi.dart';
import 'hanzi_shapes.dart';

/// 象形字的「图 → 字」渐变。
///
/// 两段：
///
/// 1. `0 → kGlyphHandoff`：按 [Pictograph] 逐点插值，山峰收拢成三竖、树冠压平
///    成一横。这一段是这个玩法的全部内容。
/// 2. `kGlyphHandoff → 1`：骨架淡出，**真正的字形**淡入。
///
/// 第二段看着多余，其实是这个组件里最要紧的一处：手画的骨架再准也只是近似，
/// 而他要认的是书上、路牌上那个字。让最后停在屏幕上的是真字形，等于只用骨架
/// 讲「怎么变过来的」，不用它冒充结论。
///
/// [Pictograph] 查不到（内容包新加了字但还没配图形）时，直接静态显示字形——
/// 少一段动画，不会空白也不会报错。
class PictographView extends StatelessWidget {
  const PictographView({
    super.key,
    required this.char,
    required this.imageKey,
    required this.progress,
    required this.color,
  });

  final String char;
  final String? imageKey;

  /// 0 = 实物图，1 = 字形。
  final double progress;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final shape = pictographOf(imageKey);
    // 没有图形数据就没有「渐变」可言，直接把字摆在那里。
    final t = shape == null ? 1.0 : progress.clamp(0.0, 1.0);

    // 交叉淡入：骨架退场与真字形入场共用同一段时间轴，中间不留空档。
    final handoff = ((t - kGlyphHandoff) / (1 - kGlyphHandoff)).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (shape != null && handoff < 1)
              Opacity(
                opacity: 1 - handoff,
                child: SizedBox(
                  width: side,
                  height: side,
                  child: CustomPaint(
                    painter: _StrokePainter(
                      strokes: shape.at(t),
                      color: color,
                      strokeWidth: side * 0.075,
                    ),
                  ),
                ),
              ),
            if (handoff > 0)
              Opacity(
                opacity: handoff,
                child: SizedBox(
                  width: side,
                  height: side,
                  child: Center(
                    child: Text(
                      char,
                      style: TextStyle(
                        // 与骨架同一个尺度落位，交接才不会「跳」一下。
                        fontSize: side * 0.86,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 把归一化的笔画描出来。
///
/// 圆头圆角：一是像蜡笔，二是「山」的三竖由三角形退化而来，尖角收拢时若用
/// 平头会在末帧留下一截毛刺。
class _StrokePainter extends CustomPainter {
  const _StrokePainter({
    required this.strokes,
    required this.color,
    required this.strokeWidth,
  });

  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx * size.width, point.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) =>
      old.strokes != strokes ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
