import 'dart:io';

import 'package:baby_pal/core/audio/audio_bus.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:baby_pal/core/block/block_widget.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/addition/addition.dart';
import 'package:baby_pal/modules/addition/equation_page.dart';
import 'package:baby_pal/modules/addition/decompose_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AudioBus _silentBus() =>
    AudioBus(resolver: VoiceResolver(overridesDir: Directory.systemTemp));

const int _colorWhole = 4;
const int _colorLeft = 1;
const int _colorRight = 3;

Finder _blockOfColor(int colorIndex) => find.byWidgetPredicate(
  (w) => w is BlockWidget && w.body.colorIndex == colorIndex,
);

extension on WidgetTester {
  Future<void> pumpDecompose() async {
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(738, 393);
    addTearDown(view.reset);

    await pumpWidget(
      ProviderScope(
        overrides: [audioBusProvider.overrideWithValue(_silentBus())],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: const DecomposePage(),
        ),
      ),
    );
    await pump();
  }

  List<BlockWidget> get blocks =>
      widgetList<BlockWidget>(find.byType(BlockWidget)).toList();

  /// 点在整块积木内、距左边缘 [cells] 格的位置。
  Future<void> cutAt(double cells) async {
    final rect = getRect(_blockOfColor(_colorWhole));
    final cell = rect.height;
    await tapAt(Offset(rect.left + cells * cell, rect.center.dy));
    await pumpAndSettle();
  }
}

void main() {
  final total = kDecompositionTargets.first;

  testWidgets('开局是一整块，两个加数都是问号', (tester) async {
    await tester.pumpDecompose();

    expect(tester.blocks, hasLength(1));
    expect(tester.blocks.single.body.widthUnits, total);
    expect(find.text('?'), findsNWidgets(2));
    expect(find.text('$total'), findsOneWidget);
  });

  testWidgets('规格场景：点在第 2 与第 3 格之间 → 切成 2 和 3', (tester) async {
    await tester.pumpDecompose();
    expect(total, 5, reason: '本用例针对首题 5');

    await tester.cutAt(2.0);

    expect(tester.blocks, hasLength(2));
    final left = tester.blocks.firstWhere(
      (w) => w.body.colorIndex == _colorLeft,
    );
    final right = tester.blocks.firstWhere(
      (w) => w.body.colorIndex == _colorRight,
    );
    expect(left.body.widthUnits, 2);
    expect(right.body.widthUnits, 3);
    expect(find.text('2'), findsWidgets);
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('点哪儿切哪儿——不同落点切出不同分法', (tester) async {
    await tester.pumpDecompose();

    for (final probe in const [
      (cells: 0.6, left: 1),
      (cells: 2.2, left: 2),
      (cells: 3.4, left: 3),
      (cells: 4.4, left: 4),
    ]) {
      await tester.cutAt(probe.cells);

      final left = tester.blocks.firstWhere(
        (w) => w.body.colorIndex == _colorLeft,
      );
      expect(left.body.widthUnits, probe.left, reason: '点在 ${probe.cells} 格处');

      // 合回去，好接着试下一种分法。
      await tester.tap(_blockOfColor(_colorLeft));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('点在积木最边上也切得开——不存在「没切中」', (tester) async {
    await tester.pumpDecompose();
    await tester.cutAt(0.02);

    expect(tester.blocks, hasLength(2), reason: '任何落点都必须切出点什么来');
    expect(
      tester.blocks
          .firstWhere((w) => w.body.colorIndex == _colorLeft)
          .body
          .widthUnits,
      1,
    );
  });

  testWidgets('切开后两块紧挨着，仍在棋盘内', (tester) async {
    await tester.pumpDecompose();
    await tester.cutAt(2.0);

    final left = tester.blocks
        .firstWhere((w) => w.body.colorIndex == _colorLeft)
        .body;
    final right = tester.blocks
        .firstWhere((w) => w.body.colorIndex == _colorRight)
        .body;

    expect(left.anchor!.row, right.anchor!.row);
    expect(left.anchor!.col + left.widthUnits, right.anchor!.col);
    expect(
      right.anchor!.col + right.widthUnits,
      lessThanOrEqualTo(kAdditionColumns),
    );
  });

  testWidgets('点任意一块碎片就合回去', (tester) async {
    await tester.pumpDecompose();
    await tester.cutAt(2.0);
    expect(tester.blocks, hasLength(2));

    await tester.tap(_blockOfColor(_colorLeft));
    await tester.pumpAndSettle();

    expect(tester.blocks, hasLength(1));
    expect(tester.blocks.single.body.widthUnits, total);
    expect(find.text('?'), findsNWidgets(2), reason: '回到未切状态');
  });

  testWidgets('切开—合回—换个地方再切，可以一直转', (tester) async {
    await tester.pumpDecompose();

    for (final cells in const [1.0, 3.0, 2.0]) {
      await tester.cutAt(cells);
      expect(tester.blocks, hasLength(2));

      await tester.tap(_blockOfColor(_colorLeft));
      await tester.pumpAndSettle();
      expect(tester.blocks, hasLength(1));
    }
  });

  testWidgets('拖一块到另一块上也合回去', (tester) async {
    await tester.pumpDecompose();
    await tester.cutAt(2.0);

    final target = tester.getCenter(_blockOfColor(_colorLeft));
    final start = tester.getCenter(_blockOfColor(_colorRight));
    await tester.dragFrom(start, target - start);
    await tester.pumpAndSettle();

    expect(tester.blocks, hasLength(1));
    expect(tester.blocks.single.body.widthUnits, total);
  });

  testWidgets('找齐全部分法后「下一个」点亮，但任何时候都能走', (tester) async {
    await tester.pumpDecompose();

    RoundActionButton nextButton() =>
        tester.widget<RoundActionButton>(find.byKey(const ValueKey('next')));

    expect(nextButton().highlighted, isFalse);

    for (var left = 1; left < total; left++) {
      await tester.cutAt(left.toDouble());
      await tester.tap(_blockOfColor(_colorLeft));
      await tester.pumpAndSettle();
    }

    expect(nextButton().highlighted, isTrue);
  });

  testWidgets('下一个数换目标并复位，走到头绕回第一个', (tester) async {
    await tester.pumpDecompose();
    await tester.cutAt(2.0);

    await tester.tap(find.byKey(const ValueKey('next')));
    await tester.pumpAndSettle();

    expect(tester.blocks, hasLength(1));
    expect(tester.blocks.single.body.widthUnits, kDecompositionTargets[1]);
    expect(find.text('?'), findsNWidgets(2));

    for (var i = 1; i < kDecompositionTargets.length; i++) {
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
    }
    expect(tester.blocks.single.body.widthUnits, total);
  });

  testWidgets('每个目标数都摆得下，且每种分法都切得到', (tester) async {
    await tester.pumpDecompose();

    for (var i = 0; i < kDecompositionTargets.length; i++) {
      final n = tester.blocks.single.body;
      expect(n.widthUnits, kDecompositionTargets[i]);
      expect(n.anchor!.col + n.widthUnits, lessThanOrEqualTo(kAdditionColumns));

      for (var left = 1; left < n.widthUnits; left++) {
        await tester.cutAt(left.toDouble());
        expect(
          tester.blocks
              .firstWhere((w) => w.body.colorIndex == _colorLeft)
              .body
              .widthUnits,
          left,
          reason: '$n 的第 $left 种分法',
        );
        await tester.tap(_blockOfColor(_colorLeft));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('玩法切换：合体 → 分解 → 等式 → 合体，环上的下一站是等式槽', (tester) async {
    await tester.pumpDecompose();

    await tester.tap(find.byKey(const ValueKey('mode')));
    await tester.pumpAndSettle();

    // pushReplacement 而非叠层——返回键始终直接回星球地图。
    expect(find.byType(EquationPage), findsOneWidget);
    expect(find.byType(DecomposePage), findsNothing);
  });

  testWidgets('托盘里可按的东西都不小于 90dp', (tester) async {
    await tester.pumpDecompose();

    for (final key in const [
      ValueKey('decomposition'),
      ValueKey('mode'),
      ValueKey('next'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(BlockMetrics.minGrabTarget));
      expect(size.width, greaterThanOrEqualTo(BlockMetrics.minGrabTarget));
    }
  });
}
