import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/block/block_board.dart';
import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/letters/letter_shapes.dart';
import 'package:baby_pal/modules/letters/case_match_page.dart';
import 'package:baby_pal/modules/letters/outline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

const Size _phone = Size(738, 393);

/// 只放 L 和 A 两个字母：L 是规格场景里点名的那个，A 用来验翻页。
ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "letters": [
    {"letter": "L", "voiceKey": "en.letter.l", "phonemeVoiceKey": "en.phoneme.l"},
    {"letter": "A", "voiceKey": "en.letter.a", "phonemeVoiceKey": "en.phoneme.a"}
  ]
}
''', source: 'letters.json')!,
]);

void main() {
  late RecordingAudioBus audio;

  Future<void> pumpOutline(WidgetTester tester) async {
    audio = RecordingAudioBus();
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioBusProvider.overrideWithValue(audio),
          contentLibraryProvider.overrideWithValue(_library()),
        ],
        child: const MaterialApp(home: OutlinePage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 台面上现有的积木。
  List<BlockBody> blocks(WidgetTester tester) =>
      tester.widget<BlockBoard>(find.byType(BlockBoard)).controller.blocks;

  Future<void> fill(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byKey(const ValueKey('source')));
      await tester.pump();
    }
  }

  group('点选通道', () {
    testWidgets('按一下托盘就落一块，按顺序填满轮廓', (tester) async {
      await pumpOutline(tester);
      final shape = letterShapeOf('L')!;

      await fill(tester, 3);
      // 他一次都不用瞄——轮廓格只有 50 多 dp，要求点准就是设计错误。
      expect(blocks(tester).map((b) => b.anchor), shape.cells.take(3));
    });

    testWidgets('填满后字母整体点亮并播报字母名与音素', (tester) async {
      await pumpOutline(tester);
      final shape = letterShapeOf('L')!;
      audio.spoken.clear();

      await fill(tester, shape.size);
      await tester.pump();

      expect(blocks(tester).length, shape.size);
      // 规格「轮廓填满 → 字母整体点亮，播报字母名并庆祝」。
      expect(audio.spoken, ['en.letter.l', 'en.phoneme.l']);
      expect(
        blocks(tester).every((b) => b.expression == BlockExpression.happy),
        isTrue,
        reason: '填满后整个字母该一起笑',
      );
    });

    testWidgets('填满后继续按托盘：静默收手，不报错也不多放', (tester) async {
      await pumpOutline(tester);
      final shape = letterShapeOf('L')!;
      await fill(tester, shape.size);

      audio.sfx.clear();
      await fill(tester, 3);

      expect(blocks(tester).length, shape.size, reason: '不该放到轮廓外面去');
      // 柔和的回位音，不是失败音——无挫败红线。
      expect(audio.sfx.toSet(), {'return'});
    });

    testWidgets('点已放置的方块把它收回，下一块补回那个洞', (tester) async {
      await pumpOutline(tester);
      final shape = letterShapeOf('L')!;
      await fill(tester, 4);

      final third = blocks(tester)[2];
      final center = tester
          .widget<BlockBoard>(find.byType(BlockBoard))
          .controller
          .grid
          .centerOf(third.anchor!);
      await tester.tapAt(tester.getTopLeft(find.byType(BlockBoard)) + center);
      await tester.pump();

      expect(blocks(tester).length, 3);
      await fill(tester, 1);
      expect(
        blocks(tester).map((b) => b.anchor),
        containsAll(shape.cells.take(4)),
        reason: '被拿走的那格该被补回来',
      );
    });
  });

  group('吸附只落进笔画里', () {
    testWidgets('轮廓外的格位全部标成不可落子', (tester) async {
      await pumpOutline(tester);
      final shape = letterShapeOf('L')!;
      final controller = tester
          .widget<BlockBoard>(find.byType(BlockBoard))
          .controller;

      // 这是整个玩法的地基：吸附只可能落进笔画，所以他怎么拖都不会
      // 把方块放到 L 的右上角那片空白里。
      expect(controller.blockedCells, blockedCellsFor(shape));
      expect(
        controller.occupiedCells().containsAll(blockedCellsFor(shape)),
        isTrue,
      );
    });

    testWidgets('切换字母时不可落子的格位跟着换', (tester) async {
      await pumpOutline(tester);
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 400));

      final controller = tester
          .widget<BlockBoard>(find.byType(BlockBoard))
          .controller;
      expect(controller.blockedCells, blockedCellsFor(letterShapeOf('A')!));
      expect(controller.grid.columns, letterShapeOf('A')!.columns);
    });
  });

  group('翻页与清空', () {
    testWidgets('换字母时台面清空、完成态复位', (tester) async {
      await pumpOutline(tester);
      await fill(tester, letterShapeOf('L')!.size);
      expect(blocks(tester), isNotEmpty);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(blocks(tester), isEmpty);
    });

    testWidgets('重来把台面清空但不换字母', (tester) async {
      await pumpOutline(tester);
      await fill(tester, 3);

      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pump();

      expect(blocks(tester), isEmpty);
      final controller = tester
          .widget<BlockBoard>(find.byType(BlockBoard))
          .controller;
      expect(controller.blockedCells, blockedCellsFor(letterShapeOf('L')!));
    });

    testWidgets('玩法切换到大小写配对', (tester) async {
      await pumpOutline(tester);
      await tester.tap(find.byKey(const ValueKey('mode')));
      await tester.pumpAndSettle();

      // 字母模块四个玩法串成一个环：A is for Apple → 轮廓 → 大小写 → 拼名字
      // → 回到 A is for Apple。一律 pushReplacement，返回键始终直接回星球地图。
      expect(find.byType(CaseMatchPage), findsOneWidget);
    });
  });

  group('触控红线', () {
    testWidgets('托盘里可按的东西都不小于 90dp', (tester) async {
      await pumpOutline(tester);

      for (final tile in tester.widgetList<PressableTile>(
        find.byType(PressableTile),
      )) {
        final size = tester.getSize(find.byWidget(tile));
        expect(
          size.shortestSide,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
          reason: '${size.width}×${size.height} 击穿了 90dp 抓取阈值',
        );
      }
    });

    testWidgets('26 个字母的轮廓在交付机型上都摆得下', (tester) async {
      // 最宽的是 M W X Y V（5 列）。格子太小的话拖拽通道会难用到形同虚设。
      await pumpOutline(tester);
      final board = tester.getSize(find.byKey(const ValueKey('outline')));

      for (final key in kLetterPatterns.keys) {
        final shape = letterShapeOf(key)!;
        final cell = (board.width / shape.columns) < (board.height / shape.rows)
            ? board.width / shape.columns
            : board.height / shape.rows;
        expect(
          cell,
          greaterThan(50),
          reason: '$key 的格子只有 ${cell.toStringAsFixed(1)}dp，太小了',
        );
        expect(cell * shape.columns, lessThanOrEqualTo(board.width + 0.5));
        expect(cell * shape.rows, lessThanOrEqualTo(board.height + 0.5));
      }
    });
  });
}
