import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 象形字的「图」与「字」两套笔画。
///
/// 规格要求的是「图片渐变为字形」。做成两张图交叉淡入是最省事的读法，但那只
/// 是把两样东西换了一下——**看不出这个字就是那样东西的样子**，而那恰恰是象形
/// 字唯一要教的事。所以这里两套笔画一一对应、每一笔的点数也相同，逐点插值即
/// 可让山峰收拢成三竖、树冠压平成一横、树根抬起成撇捺。
///
/// 坐标一律归一化到 0..1（y 向下），绘制时按边长缩放，因此手机和平板共用同
/// 一份数据。
///
/// **不用素材、也不用字体轮廓。** OpenMoji 里根本没有「田」和「土」；而 Flutter
/// 没有公开 API 能把字体里的字形取成 `Path`。两条路都断了，何况画成一样粗细的
/// 圆头线条，本来就更接近他将来在纸上写出来的样子。
///
/// 内容包里 `imageKey` 查不到时（明年新增的象形字还没配图形），
/// [pictographOf] 返回 null，玩法降级为直接显示字形——不会报错，也不会空白。
class Pictograph {
  const Pictograph({required this.picture, required this.glyph});

  /// 实物形态的笔画。
  final List<List<Offset>> picture;

  /// 字形骨架的笔画。与 [picture] 一一对应，且每一笔点数相同。
  final List<List<Offset>> glyph;

  /// 两套笔画是否真的能逐点插值。由测试逐个字校验——**点数对不上时不该在
  /// 屏幕上表现为一次奇怪的动画，而该在测试里就红**。
  bool get isInterpolatable {
    if (picture.length != glyph.length) return false;
    for (var i = 0; i < picture.length; i++) {
      if (picture[i].length != glyph[i].length) return false;
      if (picture[i].length < 2) return false;
    }
    return true;
  }

  /// 取 [t]（0 = 图，1 = 字）时刻的笔画。
  List<List<Offset>> at(double t) {
    final k = t.clamp(0.0, 1.0);
    return [
      for (var i = 0; i < picture.length; i++)
        [
          for (var j = 0; j < picture[i].length; j++)
            Offset.lerp(picture[i][j], glyph[i][j], k)!,
        ],
    ];
  }
}

/// 按内容包里的 `imageKey` 取图形。查不到返回 null。
Pictograph? pictographOf(String? imageKey) =>
    imageKey == null ? null : kPictographs[imageKey];

/// 沿闭合多边形取 [n] 个点（首尾同点，便于描成闭合环）。
///
/// 日与田的外框要用它：圆和方、正方和斜着看的方，只要**用同一种方式取点**，
/// 对应关系就自然成立，不需要手写几十个坐标。
///
/// **每条边分同样多的点，而不是沿周长等距取。** 等距取点在梯形上会漏掉角——
/// 四条边不一样长，采样点落不到拐角上，于是「斜着看的那块田」四个角是被削平
/// 的。真机上一眼就看出来那不是块地，是块搓圆了的糖。
List<Offset> _ring(List<Offset> corners, int n) {
  final perEdge = n ~/ corners.length;
  final points = <Offset>[];
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % corners.length];
    for (var k = 0; k < perEdge; k++) {
      points.add(Offset.lerp(a, b, k / perEdge)!);
    }
  }
  points.add(points.first);
  return points;
}

/// 圆环，从左上（135°）起**顺时针**取点。
///
/// 顺时针这件事必须与 [_ring] 一致（那边的角点是按左上→右上→右下→左下写的，
/// 屏幕坐标下就是顺时针）。方向相反的话，圆变成方的过程中整圈点会各自往
/// 相反方向跑，看起来像被拧了一圈——那不是「太阳变成日字」，那是一团乱麻。
/// 由 `hanzi_shapes_test.dart` 用有向面积的符号盯着。
List<Offset> _circleRing(Offset center, double r, int n) {
  final points = <Offset>[];
  for (var k = 0; k < n; k++) {
    final angle = math.pi * 0.75 - 2 * math.pi * k / n;
    points.add(
      Offset(center.dx + r * math.cos(angle), center.dy - r * math.sin(angle)),
    );
  }
  points.add(points.first);
  return points;
}

/// 外框取点数。12 段足够让圆看起来是圆的，再多只是白费笔。
const int _ringSteps = 12;

/// 九个象形字。键即内容包里的 `imageKey`。
final Map<String, Pictograph> kPictographs = {
  // 三座山峰收拢成三竖。每一峰是「底—顶—底」三个点，竖是同一个三点退化成
  // 一条竖线——这一下收拢正是「山」这个字的来历。
  'mountain': const Pictograph(
    picture: [
      [Offset(0.06, 0.86), Offset(0.50, 0.86), Offset(0.94, 0.86)],
      [Offset(0.06, 0.86), Offset(0.22, 0.50), Offset(0.38, 0.86)],
      [Offset(0.26, 0.86), Offset(0.50, 0.20), Offset(0.74, 0.86)],
      [Offset(0.62, 0.86), Offset(0.78, 0.50), Offset(0.94, 0.86)],
    ],
    glyph: [
      [Offset(0.16, 0.88), Offset(0.50, 0.88), Offset(0.84, 0.88)],
      [Offset(0.16, 0.88), Offset(0.16, 0.46), Offset(0.16, 0.88)],
      [Offset(0.50, 0.88), Offset(0.50, 0.12), Offset(0.50, 0.88)],
      [Offset(0.84, 0.88), Offset(0.84, 0.46), Offset(0.84, 0.88)],
    ],
  ),

  // 斜着看的一块田地，正过来就是「田」。
  'field': Pictograph(
    picture: [
      _ring(const [
        Offset(0.30, 0.22),
        Offset(0.70, 0.22),
        Offset(0.92, 0.86),
        Offset(0.08, 0.86),
      ], _ringSteps),
      const [Offset(0.50, 0.22), Offset(0.50, 0.54), Offset(0.50, 0.86)],
      const [Offset(0.19, 0.54), Offset(0.50, 0.54), Offset(0.81, 0.54)],
    ],
    glyph: [
      _ring(const [
        Offset(0.16, 0.14),
        Offset(0.84, 0.14),
        Offset(0.84, 0.86),
        Offset(0.16, 0.86),
      ], _ringSteps),
      const [Offset(0.50, 0.14), Offset(0.50, 0.50), Offset(0.50, 0.86)],
      const [Offset(0.16, 0.50), Offset(0.50, 0.50), Offset(0.84, 0.50)],
    ],
  ),

  // 地面上的一堆土：土堆压平成上面那一横，地面就是下面那一长横。
  'soil': const Pictograph(
    picture: [
      [Offset(0.30, 0.44), Offset(0.50, 0.28), Offset(0.70, 0.44)],
      [Offset(0.50, 0.36), Offset(0.50, 0.60), Offset(0.50, 0.82)],
      [Offset(0.10, 0.82), Offset(0.50, 0.82), Offset(0.90, 0.82)],
    ],
    glyph: [
      [Offset(0.28, 0.30), Offset(0.50, 0.30), Offset(0.72, 0.30)],
      [Offset(0.50, 0.30), Offset(0.50, 0.56), Offset(0.50, 0.82)],
      [Offset(0.16, 0.82), Offset(0.50, 0.82), Offset(0.84, 0.82)],
    ],
  ),

  // 一棵树：树冠压平成一横，树根抬起成撇捺，树干原地不动。
  'tree': const Pictograph(
    picture: [
      [Offset(0.12, 0.34), Offset(0.50, 0.16), Offset(0.88, 0.34)],
      [Offset(0.50, 0.22), Offset(0.50, 0.57), Offset(0.50, 0.92)],
      [Offset(0.50, 0.74), Offset(0.30, 0.84), Offset(0.12, 0.90)],
      [Offset(0.50, 0.74), Offset(0.70, 0.84), Offset(0.88, 0.90)],
    ],
    glyph: [
      [Offset(0.10, 0.35), Offset(0.50, 0.35), Offset(0.90, 0.35)],
      [Offset(0.50, 0.10), Offset(0.50, 0.51), Offset(0.50, 0.92)],
      [Offset(0.50, 0.45), Offset(0.30, 0.70), Offset(0.12, 0.90)],
      [Offset(0.50, 0.45), Offset(0.70, 0.70), Offset(0.88, 0.90)],
    ],
  ),

  // 太阳：圆变成方，中间那一点撑开成中间那一横。
  'sun': Pictograph(
    picture: [
      _circleRing(const Offset(0.50, 0.50), 0.34, _ringSteps),
      const [Offset(0.46, 0.50), Offset(0.50, 0.50), Offset(0.54, 0.50)],
    ],
    glyph: [
      _ring(const [
        Offset(0.27, 0.10),
        Offset(0.73, 0.10),
        Offset(0.73, 0.90),
        Offset(0.27, 0.90),
      ], _ringSteps),
      const [Offset(0.27, 0.50), Offset(0.50, 0.50), Offset(0.73, 0.50)],
    ],
  ),

  // 月牙：外弧立成横折钩，内弧立成撇，弯里那两道阴影长成中间两横。
  'moon': const Pictograph(
    picture: [
      [
        Offset(0.40, 0.10),
        Offset(0.30, 0.30),
        Offset(0.28, 0.52),
        Offset(0.34, 0.74),
        Offset(0.48, 0.90),
      ],
      [Offset(0.40, 0.10), Offset(0.56, 0.34), Offset(0.48, 0.90)],
      [Offset(0.40, 0.36), Offset(0.44, 0.36)],
      [Offset(0.40, 0.62), Offset(0.44, 0.62)],
    ],
    glyph: [
      [
        Offset(0.30, 0.14),
        Offset(0.72, 0.14),
        Offset(0.72, 0.50),
        Offset(0.72, 0.86),
        Offset(0.54, 0.92),
      ],
      [Offset(0.32, 0.12), Offset(0.26, 0.52), Offset(0.18, 0.90)],
      [Offset(0.30, 0.38), Offset(0.70, 0.38)],
      [Offset(0.30, 0.62), Offset(0.70, 0.62)],
    ],
  ),

  // 流水：中间那道水流立成竖钩，两边的浪花收成横撇、撇、捺。
  'water': const Pictograph(
    picture: [
      [
        Offset(0.50, 0.08),
        Offset(0.42, 0.40),
        Offset(0.58, 0.70),
        Offset(0.46, 0.92),
      ],
      [Offset(0.36, 0.26), Offset(0.24, 0.34), Offset(0.14, 0.26)],
      [Offset(0.34, 0.56), Offset(0.22, 0.70), Offset(0.10, 0.84)],
      [Offset(0.66, 0.48), Offset(0.78, 0.64), Offset(0.90, 0.82)],
    ],
    glyph: [
      [
        Offset(0.50, 0.08),
        Offset(0.50, 0.52),
        Offset(0.50, 0.80),
        Offset(0.38, 0.90),
      ],
      [Offset(0.48, 0.32), Offset(0.30, 0.42), Offset(0.18, 0.32)],
      [Offset(0.46, 0.50), Offset(0.28, 0.68), Offset(0.12, 0.86)],
      [Offset(0.54, 0.42), Offset(0.74, 0.62), Offset(0.90, 0.84)],
    ],
  ),

  // 火苗：两侧火星落成上面两点，火焰的两道边收成下面的撇和捺。
  'fire': const Pictograph(
    picture: [
      [Offset(0.18, 0.30), Offset(0.26, 0.40)],
      [Offset(0.82, 0.28), Offset(0.74, 0.38)],
      [Offset(0.50, 0.12), Offset(0.30, 0.50), Offset(0.24, 0.86)],
      [Offset(0.50, 0.12), Offset(0.72, 0.52), Offset(0.76, 0.86)],
    ],
    glyph: [
      [Offset(0.24, 0.24), Offset(0.30, 0.34)],
      [Offset(0.76, 0.22), Offset(0.70, 0.34)],
      [Offset(0.52, 0.20), Offset(0.36, 0.55), Offset(0.16, 0.88)],
      [Offset(0.48, 0.44), Offset(0.66, 0.66), Offset(0.86, 0.88)],
    ],
  ),

  // 一个人：脑袋缩成撇的起笔，两条腿张开成撇和捺。
  'person': Pictograph(
    picture: [
      _circleRing(const Offset(0.50, 0.20), 0.11, _ringSteps),
      const [Offset(0.50, 0.34), Offset(0.36, 0.60), Offset(0.24, 0.88)],
      const [Offset(0.50, 0.34), Offset(0.64, 0.60), Offset(0.76, 0.88)],
    ],
    glyph: [
      [for (var i = 0; i <= _ringSteps; i++) const Offset(0.52, 0.14)],
      const [Offset(0.52, 0.14), Offset(0.36, 0.50), Offset(0.16, 0.88)],
      const [Offset(0.52, 0.32), Offset(0.70, 0.60), Offset(0.88, 0.88)],
    ],
  ),
};
