import 'dart:io';

import 'package:baby_pal/core/audio/audio_bus.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:baby_pal/core/block/block_widget.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/numbers/place_value.dart';
import 'package:baby_pal/modules/numbers/place_value_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 未 init 的音频总线：所有方法都会在 `_ready == false` 处提前返回，
/// 因此在测试里是天然的静音替身，不需要额外的 mock 框架。
AudioBus _silentBus() => AudioBus(
      resolver: VoiceResolver(overridesDir: Directory.systemTemp),
    );

extension on WidgetTester {
  /// MI 8 SE 横屏的逻辑尺寸——交付设备就是这台，布局按它把关。
  Future<void> pumpPlaceValue({Size size = const Size(738, 393)}) async {
    view.devicePixelRatio = 1.0;
    view.physicalSize = size;
    addTearDown(view.reset);

    await pumpWidget(
      ProviderScope(
        overrides: [audioBusProvider.overrideWithValue(_silentBus())],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: const PlaceValuePage(),
        ),
      ),
    );
    await pump();
  }

  int get blockCount => widgetList<BlockWidget>(find.byType(BlockWidget)).length;

  List<BlockWidget> get blocks =>
      widgetList<BlockWidget>(find.byType(BlockWidget)).toList();

  int get rodCount => blocks
      .where((w) => w.body.widthUnits == PlacePiece.rod.widthUnits)
      .length;

  int get unitCount => blocks
      .where((w) => w.body.widthUnits == PlacePiece.unit.widthUnits)
      .length;
}

void main() {
  testWidgets('开局台面是空的，目标是题序第一题', (tester) async {
    await tester.pumpPlaceValue();
    expect(tester.blockCount, 0);
    expect(find.text('${kPlaceValueTargets.first}'), findsOneWidget);
  });

  testWidgets('点托盘的源即出块——按下就出，不用瞄准落点', (tester) async {
    await tester.pumpPlaceValue();

    await tester.tap(find.byKey(const ValueKey('source-rod')));
    await tester.pump();
    expect(tester.rodCount, 1);

    await tester.tap(find.byKey(const ValueKey('source-unit')));
    await tester.pump();
    expect(tester.unitCount, 1);
    expect(tester.blockCount, 2);
  });

  testWidgets('摆出目标数后目标卡点亮（规格：13 = 1 十条 + 3 单块）', (tester) async {
    await tester.pumpPlaceValue();
    expect(kPlaceValueTargets.first, 13, reason: '本用例针对首题');

    Color? cardColor() {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('target')),
          matching: find.byType(DecoratedBox),
        ),
      );
      return (box.decoration as BoxDecoration).color;
    }

    final before = cardColor();

    await tester.tap(find.byKey(const ValueKey('source-rod')));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const ValueKey('source-unit')));
      await tester.pump();
    }

    expect(tester.rodCount, 1);
    expect(tester.unitCount, 3);
    expect(cardColor(), isNot(before), reason: '答对后目标卡换色');
  });

  testWidgets('十条与单块从两端相向生长，互不挤占', (tester) async {
    await tester.pumpPlaceValue();

    await tester.tap(find.byKey(const ValueKey('source-rod')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('source-unit')));
    await tester.pump();

    final rod = tester.blocks
        .firstWhere((w) => w.body.widthUnits == PlacePiece.rod.widthUnits);
    final unit = tester.blocks
        .firstWhere((w) => w.body.widthUnits == PlacePiece.unit.widthUnits);

    expect(rod.body.anchor?.row, 0);
    expect(unit.body.anchor?.row, kPlaceValueRows - 1);
  });

  testWidgets('点已放置的积木即收回', (tester) async {
    await tester.pumpPlaceValue();

    await tester.tap(find.byKey(const ValueKey('source-unit')));
    await tester.pump();
    expect(tester.blockCount, 1);

    await tester.tap(find.byType(BlockWidget));
    await tester.pumpAndSettle();
    expect(tester.blockCount, 0);
  });

  testWidgets('规格场景：10 个单块自动演示为 1 个十条，总数不变', (tester) async {
    await tester.pumpPlaceValue();

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const ValueKey('source-unit')));
      await tester.pump();
    }
    expect(tester.unitCount, 10, reason: '演示之前，10 个单块必须先被接受');
    expect(tester.rodCount, 0);

    // 留一拍再换十——他刚放下第 10 块，画面立刻变会让他以为是自己弄坏了。
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(tester.unitCount, 0);
    expect(tester.rodCount, 1);
  });

  testWidgets('清空按钮把台面收干净', (tester) async {
    await tester.pumpPlaceValue();

    await tester.tap(find.byKey(const ValueKey('source-rod')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('source-unit')));
    await tester.pump();
    expect(tester.blockCount, 2);

    await tester.tap(find.byKey(const ValueKey('clear')));
    await tester.pumpAndSettle();
    expect(tester.blockCount, 0);
  });

  testWidgets('下一题换目标并清空台面，走到头绕回第一题', (tester) async {
    await tester.pumpPlaceValue();

    await tester.tap(find.byKey(const ValueKey('source-rod')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('next')));
    await tester.pumpAndSettle();

    expect(tester.blockCount, 0);
    expect(find.text('${kPlaceValueTargets[1]}'), findsOneWidget);

    for (var i = 1; i < kPlaceValueTargets.length; i++) {
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('${kPlaceValueTargets.first}'), findsOneWidget);
  });

  testWidgets('托盘里每个可按的东西都不小于 90dp', (tester) async {
    await tester.pumpPlaceValue();

    for (final key in const [
      ValueKey('target'),
      ValueKey('source-rod'),
      ValueKey('source-unit'),
      ValueKey('clear'),
      ValueKey('next'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(
        size.height,
        greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
        reason: '$key 高度',
      );
      expect(
        size.width,
        greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
        reason: '$key 宽度',
      );
    }
  });

  testWidgets('交付设备（738×393）上格边长不低于放置区下限 60dp', (tester) async {
    await tester.pumpPlaceValue();

    await tester.tap(find.byKey(const ValueKey('source-unit')));
    await tester.pump();

    final cell = tester.getSize(find.byType(BlockWidget));
    expect(cell.width, greaterThanOrEqualTo(BlockMetrics.minDropZone));
    expect(cell.height, greaterThanOrEqualTo(BlockMetrics.minDropZone));
  });

  testWidgets('十条在最窄的目标机型上也完整摆得下', (tester) async {
    // 短边 360dp 的手机横屏，是设计基准里最紧的一档。
    await tester.pumpPlaceValue(size: const Size(640, 360));

    await tester.tap(find.byKey(const ValueKey('source-rod')));
    await tester.pump();

    final rod = tester.getSize(find.byType(BlockWidget));
    expect(rod.width, lessThanOrEqualTo(640));
    expect(
      rod.width / PlacePiece.rod.widthUnits,
      greaterThanOrEqualTo(BlockMetrics.minDropZone * 0.9),
      reason: '格边长即使触到下限，1.5 倍吸附半径仍能兜住落点',
    );
    expect(tester.takeException(), isNull, reason: '不得溢出');
  });
}
