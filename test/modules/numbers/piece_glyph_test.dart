import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/numbers/piece_glyph.dart';
import 'package:baby_pal/modules/numbers/place_value.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 缩略图里的每一小格。
Finder _segments() => find.descendant(
  of: find.byType(PieceGlyph),
  matching: find.byType(DecoratedBox),
);

void main() {
  /// 真机验收才发现的回归：`DecoratedBox` 没有子节点时，在 `Row` 默认的
  /// `center` 对齐下拿到松约束、取 `constraints.smallest`，高度塌成 0，
  /// 托盘里两个「源」看上去就是空白方块。
  ///
  /// 之前的用例只量了外层瓦片的尺寸——瓦片是对的，里面什么都没有。
  /// 所以这里量的是**每一小格实际占了多大**。
  Future<void> pumpGlyph(
    WidgetTester tester,
    PlacePiece piece, {
    Size box = const Size(240, 74),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: PieceGlyph(piece: piece),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('十条画成 10 个小格，每格都真的有尺寸', (tester) async {
    await pumpGlyph(tester, PlacePiece.rod);

    expect(_segments(), findsNWidgets(PlacePiece.rod.widthUnits));
    for (var i = 0; i < PlacePiece.rod.widthUnits; i++) {
      final size = tester.getSize(_segments().at(i));
      expect(size.height, greaterThan(0), reason: '第 $i 格高度塌了');
      expect(size.width, greaterThan(0), reason: '第 $i 格宽度塌了');
    }
  });

  testWidgets('单块是一格，同样有尺寸', (tester) async {
    await pumpGlyph(tester, PlacePiece.unit);

    expect(_segments(), findsOneWidget);
    final size = tester.getSize(_segments().first);
    expect(size.height, greaterThan(0));
    expect(size.width, greaterThan(0));
  });

  testWidgets('十条的 10 道分隔线是「一条等于十块」的全部证据，不能省', (tester) async {
    await pumpGlyph(tester, PlacePiece.rod);

    final lefts = <double>[];
    for (var i = 0; i < PlacePiece.rod.widthUnits; i++) {
      lefts.add(tester.getTopLeft(_segments().at(i)).dx);
    }
    // 10 个小格横向依次排开，互不重叠。
    for (var i = 1; i < lefts.length; i++) {
      expect(lefts[i], greaterThan(lefts[i - 1]), reason: '第 $i 格没有排开');
    }
  });

  testWidgets('扁而宽、窄而高的容器里都不塌', (tester) async {
    for (final box in const [
      Size(240, 74), // 托盘里十条的实际形状
      Size(74, 74), // 单块那格
      Size(400, 20), // 极扁
      Size(60, 200), // 极窄
    ]) {
      await pumpGlyph(tester, PlacePiece.rod, box: box);
      final size = tester.getSize(_segments().first);
      expect(size.height, greaterThan(0), reason: '$box 下高度塌了');
      expect(size.width, greaterThan(0), reason: '$box 下宽度塌了');
      expect(tester.takeException(), isNull, reason: '$box 下溢出');
    }
  });

  test('十条与单块的取色固定，两个玩法共用', () {
    expect(PieceColors.indexOf(PlacePiece.rod), PieceColors.rodIndex);
    expect(PieceColors.indexOf(PlacePiece.unit), PieceColors.unitIndex);
    expect(
      PieceColors.of(PlacePiece.rod),
      isNot(PieceColors.of(PlacePiece.unit)),
      reason: '两种规格必须一眼分得开',
    );
    expect(PieceColors.of(PlacePiece.rod), BlockColors.forIndex(6));
  });
}
