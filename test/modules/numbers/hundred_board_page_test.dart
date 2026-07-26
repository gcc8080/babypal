import 'dart:io';

import 'package:baby_pal/core/audio/audio_bus.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/numbers/hundred_board.dart';
import 'package:baby_pal/modules/numbers/hundred_board_page.dart';
import 'package:baby_pal/modules/numbers/place_value_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AudioBus _silentBus() =>
    AudioBus(resolver: VoiceResolver(overridesDir: Directory.systemTemp));

Finder _board() => find.byKey(const ValueKey('board'));

extension on WidgetTester {
  Future<void> pumpHundredBoard({Size size = const Size(738, 393)}) async {
    view.devicePixelRatio = 1.0;
    view.physicalSize = size;
    addTearDown(view.reset);

    await pumpWidget(
      ProviderScope(
        overrides: [audioBusProvider.overrideWithValue(_silentBus())],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: const HundredBoardPage(),
        ),
      ),
    );
    await pump();
  }

  /// 界面上那个大数字。
  String get shownCount => widget<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('count')),
      matching: find.byType(Text),
    ),
  ).data!;

  /// 棋盘里的绘制层数：底板 1 层，放烟花时 2 层。
  ///
  /// 按 key 限定在棋盘内部，不然会匹配到框架自己的 `CustomPaint`。
  int get boardLayers => widgetList(
    find.descendant(of: _board(), matching: find.byType(CustomPaint)),
  ).length;

  Future<void> tapRod() async {
    await tap(find.byKey(const ValueKey('source-rod')));
    await pump();
  }

  Future<void> tapUnit() async {
    await tap(find.byKey(const ValueKey('source-unit')));
    await pump();
  }
}

void main() {
  testWidgets('开局是 0', (tester) async {
    await tester.pumpHundredBoard();
    expect(tester.shownCount, '0');
  });

  testWidgets('点十条加 10，点单块加 1', (tester) async {
    await tester.pumpHundredBoard();

    await tester.tapRod();
    expect(tester.shownCount, '10');

    await tester.tapUnit();
    await tester.tapUnit();
    expect(tester.shownCount, '12');
  });

  testWidgets('一路填到 100 就停住，再点也不会超', (tester) async {
    await tester.pumpHundredBoard();

    for (var i = 0; i < HundredBoard.rows; i++) {
      await tester.tapRod();
    }
    expect(tester.shownCount, '100');

    await tester.tapRod();
    await tester.tapUnit();
    await tester.pumpAndSettle();
    expect(tester.shownCount, '100', reason: '满了只是加不上去，不是报错');
  });

  testWidgets('填满一行放烟花，动画结束后自行收场', (tester) async {
    await tester.pumpHundredBoard();

    await tester.tapRod();
    await tester.pump(const Duration(milliseconds: 100));
    // 烟花是画在棋盘上的一层 CustomPaint，起来时棋盘里会多一层。
    expect(tester.boardLayers, 2, reason: '底板 + 烟花');

    await tester.pumpAndSettle();
    expect(tester.boardLayers, 1, reason: '放完撤掉');
  });

  testWidgets('没跨过整十就不放烟花', (tester) async {
    await tester.pumpHundredBoard();
    await tester.pumpAndSettle();
    expect(tester.boardLayers, 1);

    await tester.tapUnit();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.boardLayers, 1, reason: '只填了 1 格，不该有烟花');
  });

  testWidgets('清空回到 0', (tester) async {
    await tester.pumpHundredBoard();

    await tester.tapRod();
    await tester.tapUnit();
    expect(tester.shownCount, '11');

    await tester.tap(find.byKey(const ValueKey('clear')));
    await tester.pumpAndSettle();
    expect(tester.shownCount, '0');
  });

  testWidgets('网格不接受触摸——格子只有约 28dp，不得作为操作对象', (tester) async {
    await tester.pumpHundredBoard();

    await tester.tapUnit();
    expect(tester.shownCount, '1');

    // 戳在网格正中间。若格子可点，这里就会改变计数。
    final board = tester.getRect(_board());
    await tester.tapAt(board.center);
    await tester.pumpAndSettle();

    expect(tester.shownCount, '1', reason: '点网格不产生任何效果');
  });

  testWidgets('规格场景：短边 360dp 时格子仍只作展示，托盘仍不小于 90dp', (tester) async {
    await tester.pumpHundredBoard(size: const Size(640, 360));

    for (final key in const [
      ValueKey('source-rod'),
      ValueKey('source-unit'),
      ValueKey('clear'),
      ValueKey('mode'),
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

    // 单格远小于抓取阈值，这正是它不能作为操作对象的原因。
    final board = tester.getSize(_board());
    final cell = board.height / HundredBoard.rows;
    expect(cell, lessThan(BlockMetrics.minGrabTarget));
    expect(tester.takeException(), isNull, reason: '不得溢出');
  });

  testWidgets('棋盘是正方形，10×10', (tester) async {
    await tester.pumpHundredBoard();

    final board = tester.getSize(_board());
    expect(board.width, closeTo(board.height, 0.5));
  });

  testWidgets('玩法切换回到位值工作台，且是替换不是叠层', (tester) async {
    await tester.pumpHundredBoard();

    await tester.tap(find.byKey(const ValueKey('mode')));
    await tester.pumpAndSettle();

    expect(find.byType(PlaceValuePage), findsOneWidget);
    expect(find.byType(HundredBoardPage), findsNothing);
  });

  testWidgets('位值工作台也能切到百格板', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(738, 393);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioBusProvider.overrideWithValue(_silentBus())],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: const PlaceValuePage(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mode')));
    await tester.pumpAndSettle();

    expect(find.byType(HundredBoardPage), findsOneWidget);
  });
}
