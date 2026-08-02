import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:baby_pal/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 生成应用图标。
///
///     fvm flutter test tool/gen_icon.dart
///
/// **图标和积木是同一套画法。** 它不是一张外面画好的图，是用 `Canvas` 按
/// 与 `BlockFace` / `PlanetArcPainter` 相同的语汇当场画出来的——颜色取自
/// [BlockColors.palette]，脸的比例抄的是积木的脸。这样图标永远不会和 App
/// 里的样子跑偏：改调色板，重跑一次这个脚本就同步了。
///
/// 借道 `flutter test` 是因为 `Picture.toImage` 要真的 `dart:ui`，
/// 纯 `dart run` 里没有。这个文件里没有断言，它就是个渲染器。
///
/// 三条硬约束，都写进画法里了：
///
/// - **Android 自适应图标的安全区**：前景只有中间 66% 一定可见，外面会被
///   各家启动器的形状（圆、方、水滴）裁掉。所以积木全部画在安全区内，
///   地平线画在背景层、可以铺满。
/// - **iOS 图标不许有 alpha**，圆角由系统裁。所以 iOS 那份是背景与前景
///   合成后的实心方图。
/// - **要在 48px 下还认得出**。所以只有三块积木、一条地平线，没有细节。
void main() {
  test('画图标', () async {
    // ─── Android 自适应图标 ───────────────────────────────────────
    // 108dp 画布，前景与背景分两层，由系统按启动器的形状合成。
    const adaptive = {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    for (final entry in adaptive.entries) {
      final dir = 'android/app/src/main/res/mipmap-${entry.key}';
      await _write(
        '$dir/ic_launcher_background.png',
        entry.value,
        const _IconPainter(layer: _Layer.background),
      );
      await _write(
        '$dir/ic_launcher_foreground.png',
        entry.value,
        const _IconPainter(layer: _Layer.foreground),
      );
    }

    // ─── Android 旧版图标（Android 7 及以下，以及部分启动器仍在用）──
    const legacy = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    for (final entry in legacy.entries) {
      await _write(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        entry.value,
        // 旧版图标没有系统裁切，自己画成圆角方块。
        const _IconPainter(layer: _Layer.combined, cornerRadiusFactor: 0.22),
      );
    }

    // ─── iOS ────────────────────────────────────────────────────────
    const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    const iosSizes = {
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    for (final entry in iosSizes.entries) {
      await _write(
        '$iosDir/${entry.key}',
        entry.value,
        // 直角实心：iOS 自己裁圆角，图里带圆角会露出一圈底色。
        const _IconPainter(layer: _Layer.combined),
        // App Store 拒收带 alpha 通道的图标，见 [_encodeOpaquePng]。
        opaque: true,
      );
    }

    // 预览图，方便肉眼检查（不进包）。
    await _write(
      'build/icon-preview-1024.png',
      1024,
      const _IconPainter(layer: _Layer.combined),
    );
  });
}

Future<void> _write(
  String path,
  int size,
  CustomPainter painter, {
  bool opaque = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Size(size.toDouble(), size.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);

  final Uint8List bytes;
  if (opaque) {
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = _encodeOpaquePng(raw!.buffer.asUint8List(), size, size);
  } else {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = png!.buffer.asUint8List();
  }

  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  picture.dispose();
  image.dispose();
}

/// 把 RGBA 像素编码成**不带 alpha 通道**的 PNG（colorType 2，真彩色）。
///
/// **App Store 会直接拒掉带 alpha 通道的应用图标**（"Invalid Image - The
/// image contains an alpha channel"），而 `Picture.toImage` 出来的 PNG 永远
/// 是 RGBA——哪怕每个像素都是不透明的，通道还在。第一版就是这样，15 张
/// iOS 图标全带着 alpha。
///
/// 自己写这十几行，是因为这台机器上 ImageMagick / PIL / rsvg 一个都没有，
/// 而为了删一个通道去加一个图像库依赖，代价比这段代码大得多。
/// 反正像素是现成的，PNG 的无过滤真彩色格式也就是「zlib 压一下扫描线」。
Uint8List _encodeOpaquePng(Uint8List rgba, int width, int height) {
  // 扫描线：每行前面一个过滤器字节 0（不过滤），后面是 RGB 三元组。
  final raw = Uint8List(height * (1 + width * 3));
  var o = 0;
  for (var y = 0; y < height; y++) {
    raw[o++] = 0;
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      raw[o++] = rgba[i];
      raw[o++] = rgba[i + 1];
      raw[o++] = rgba[i + 2];
    }
  }

  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', [
    ..._be32(width),
    ..._be32(height),
    8, // 位深
    2, // colorType 2 = 真彩色，无 alpha
    0, 0, 0, // 压缩 / 过滤 / 隔行，都是标准值
  ]);
  _chunk(out, 'IDAT', ZLibCodec(level: 9).encode(raw));
  _chunk(out, 'IEND', const []);
  return out.toBytes();
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final body = <int>[...type.codeUnits, ...data];
  out
    ..add(_be32(data.length))
    ..add(body)
    ..add(_be32(_crc32(body)));
}

List<int> _be32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

enum _Layer {
  /// 自适应图标的背景层：天色 + 星球弧。可以铺满，会被系统裁形状。
  background,

  /// 自适应图标的前景层：三块积木。**只有中间 66% 保证可见。**
  foreground,

  /// 两层合在一张图里（iOS 与旧版 Android）。
  combined,
}

/// 方块星球的图标。
///
/// 画的就是首页那一屏的浓缩版：一条星球地平线，三块积木站在上面，中间那块
/// 抬头看着你。**没有文字**——这个 App 的儿童端一个字都没有，图标也不该有。
///
/// 为什么是三块而不是五块（五块大陆）：48px 下五块会糊成一条彩色带子。
/// 三块还能看出「那是三个方的东西，有脸」。
class _IconPainter extends CustomPainter {
  const _IconPainter({required this.layer, this.cornerRadiusFactor = 0});

  final _Layer layer;

  /// 圆角占边长的比例。只有旧版 Android 图标用得上。
  final double cornerRadiusFactor;

  /// 星球弧顶在画面的哪个高度（设计坐标，画布边长为 1）。
  static const double _horizon = 0.605;

  /// 星球半径。远大于画布——要的是「地平线是弯的」，
  /// 而不是「画面下方摆了个球」。首页用的是同一个手法。
  static const double _planetRadius = 0.85;

  /// 这一层要把设计缩到多大。
  ///
  /// **自适应图标只有中间那个直径 66% 的圆保证可见**，外面各家启动器会按
  /// 自己的形状（圆、方、水滴、squircle）裁掉。所以两层都把同一套设计缩着
  /// 画在中间——这样系统裁完之后，看到的和 iOS 那张实心方图是**同一个
  /// 构图**，而不是放大版。
  ///
  /// 第一版没做这件事，前景照着满画布画，结果是：iOS 图里三块积木刚好，
  /// Android 上被裁得只剩中间一块。
  ///
  /// 取 0.75 而不是保险的 0.667：真机上 MIUI 用的是接近满画布的圆角方形
  /// 遮罩，0.667 在一排图标里显得缩了一圈、四周一圈空底色。0.75 之下最外
  /// 那个角距中心 0.318，仍在 0.33 的保证可见半径内——**是算过的，不是
  /// 试出来的**：两侧积木中心在 ±0.265×0.75 处，块高 0.26×0.75，
  /// 外上角到中心 √(0.296² + 0.116²) = 0.318。
  double get _scale => layer == _Layer.combined ? 1.0 : 0.75;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.save();
    if (cornerRadiusFactor > 0) {
      canvas.clipRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(s * cornerRadiusFactor),
        ),
      );
    }

    // 背景层的天色要铺满整张画布再缩放，否则缩完四角会露白。
    if (layer != _Layer.foreground) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, s, s),
        Paint()..color = BlockColors.skyBackground,
      );
    }

    canvas.save();
    canvas.translate(s / 2, s / 2);
    canvas.scale(_scale);
    canvas.translate(-s / 2, -s / 2);

    if (layer != _Layer.foreground) _paintPlanet(canvas, s);
    if (layer != _Layer.background) _paintBlocks(canvas, s);

    canvas.restore();
    canvas.restore();
  }

  /// 星球。
  void _paintPlanet(Canvas canvas, double s) {
    final radius = s * _planetRadius;
    final center = Offset(s * 0.5, s * _horizon + radius);
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFD3E4C7));
    // 一条深一点的地表线，让地平线在 48px 下也不至于糊掉。
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFAFCB9C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.016,
    );
  }

  /// 三块积木**站在星球表面上**。
  ///
  /// 每一块都按所在位置的切线转一个角度——星球是圆的，站在上面的东西就该
  /// 跟着歪。三块一样正着摆的话，那条弧就只是背景里的一道装饰，而不是
  /// 它们脚下的地。这一点在 48px 下也看得出来：外侧两块是斜的。
  void _paintBlocks(Canvas canvas, double s) {
    final radius = s * _planetRadius;
    final center = Offset(s * 0.5, s * _horizon + radius);

    // 中间那块大、正对着你；两侧小半号、各自向外倾。一眼有个主角，
    // 而不是三个一样的方块排排站。
    //
    // **带脸那块最后画。** 两侧的会和它挨上一点点（那点重叠正是深度感的
    // 来源），谁后画谁压在上面——先画中间的话，珊瑚色那块会压住它半张脸。
    const specs = [
      (dx: -0.265, size: 0.260, colorIndex: 2, face: false), // 琥珀
      (dx: 0.265, size: 0.260, colorIndex: 1, face: false), // 珊瑚
      (dx: 0.0, size: 0.330, colorIndex: 0, face: true), // 青
    ];

    for (final spec in specs) {
      final dx = spec.dx * s;
      // 接地点：星球表面在这个横坐标上的高度。
      final contact = Offset(
        center.dx + dx,
        center.dy - math.sqrt(radius * radius - dx * dx),
      );
      // 切线角 = 该点法线相对竖直方向的夹角。
      final tilt = math.asin(dx / radius);

      final size = spec.size * s;
      canvas.save();
      canvas.translate(contact.dx, contact.dy);
      canvas.rotate(tilt);
      // 稍稍陷进地表一点点，看着是「站着」而不是「浮着」。
      final rect = Rect.fromLTWH(-size / 2, -size + s * 0.012, size, size);
      final r = RRect.fromRectAndRadius(rect, Radius.circular(size * 0.2));

      // 一点点落影，和 App 里的积木一致——它们是摆在星球上的，不是印上去的。
      canvas.drawRRect(
        r.shift(Offset(0, s * 0.008)),
        Paint()..color = Colors.black.withValues(alpha: 0.10),
      );
      canvas.drawRRect(r, Paint()..color = BlockColors.palette[spec.colorIndex]);
      if (spec.face) _paintFace(canvas, rect);
      canvas.restore();
    }
  }

  /// 积木的脸。比例抄 `BlockFace`：眼睛在 38% 高处、间距 ±18%，嘴是一段上弯弧。
  void _paintFace(Canvas canvas, Rect rect) {
    final unit = math.min(rect.width, rect.height);
    final eye = Paint()..color = BlockColors.eye;
    final stroke = Paint()
      ..color = BlockColors.eye
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.075
      ..strokeCap = StrokeCap.round;

    final eyeY = rect.top + rect.height * 0.4;
    final eyeRadius = unit * 0.088;
    canvas.drawCircle(
      Offset(rect.left + rect.width * 0.33, eyeY),
      eyeRadius,
      eye,
    );
    canvas.drawCircle(
      Offset(rect.left + rect.width * 0.67, eyeY),
      eyeRadius,
      eye,
    );

    final mouth = Rect.fromCenter(
      center: Offset(rect.center.dx, rect.top + rect.height * 0.62),
      width: rect.width * 0.36,
      height: rect.height * 0.26,
    );
    canvas.drawArc(mouth, 0.15 * math.pi, 0.7 * math.pi, false, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
