import 'package:baby_pal/core/block/block_face.dart';
import 'package:baby_pal/core/design/glyph_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 字母积木**内容**是否真的画得出来。
///
/// 这条用例是被真机上的第二次同类 bug 逼出来的：字母积木在测试里尺寸全对、
/// 在真机上却没有脸。`BlockFace` 里是一个无子节点的 `CustomPaint`，而
/// `Column` 默认的 `center` 交叉轴对齐给的是**松约束**，`CustomPaint` 的默认
/// 尺寸是 `Size.zero`，于是宽度被约束成 0——高度被 `Expanded` 撑满了，看上去
/// 一切正常，只是什么都没画。
///
/// 与托盘缩略图那次（`piece_glyph_test.dart`）是同一个坑，**同一个教训**：
/// 断言容器尺寸不等于断言内容可见。所以这里量的是脸本身占了多大，
/// 不是瓦片占了多大。
void main() {
  Future<Size> faceSize(WidgetTester tester, Size box) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: const GlyphTile(glyph: 'A', color: Colors.teal),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.getSize(find.byType(BlockFace));
  }

  group('字母积木的脸', () {
    // 从正方形到极端长宽比都过一遍：约束怎么变，脸都得有面积。
    for (final box in const [
      Size(240, 240),
      Size(120, 320),
      Size(320, 120),
      Size(90, 90),
    ]) {
      testWidgets('${box.width.toInt()}×${box.height.toInt()} 的积木上脸有面积', (
        tester,
      ) async {
        final size = await faceSize(tester, box);

        expect(
          size.width,
          greaterThan(0),
          reason: '脸的宽度塌成了 0——真机上会看见一块没有五官的方块',
        );
        expect(size.height, greaterThan(0));
        // 脸该占上部三分之一左右，太小就等于没有。
        expect(size.width, greaterThanOrEqualTo(box.width * 0.5));
        expect(size.height, greaterThanOrEqualTo(box.height * 0.2));
      });
    }

    testWidgets('showFace 关掉时确实没有脸', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: GlyphTile(
                  glyph: 'a',
                  color: Colors.teal,
                  showFace: false,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(BlockFace), findsNothing);
    });

    testWidgets('字形也有面积——不能只有脸没有字母', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: GlyphTile(glyph: 'A', color: Colors.teal),
              ),
            ),
          ),
        ),
      );
      final glyph = tester.getSize(find.text('A'));
      expect(glyph.width, greaterThan(0));
      expect(glyph.height, greaterThan(0));
    });
  });
}
