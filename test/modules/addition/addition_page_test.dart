import 'dart:io';

import 'package:baby_pal/core/audio/audio_bus.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:baby_pal/core/block/block_widget.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/addition/addition.dart';
import 'package:baby_pal/modules/addition/addition_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AudioBus _silentBus() => AudioBus(
      resolver: VoiceResolver(overridesDir: Directory.systemTemp),
    );

/// 两个加数各自的取色，页面里写死的常量——测试靠它认人。
const int _colorA = 1;
const int _colorB = 3;
const int _colorSum = 4;

Finder _blockOfColor(int colorIndex) => find.byWidgetPredicate(
      (w) => w is BlockWidget && w.body.colorIndex == colorIndex,
    );

extension on WidgetTester {
  Future<void> pumpAddition() async {
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(738, 393);
    addTearDown(view.reset);

    await pumpWidget(
      ProviderScope(
        overrides: [audioBusProvider.overrideWithValue(_silentBus())],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: const AdditionPage(),
        ),
      ),
    );
    await pump();
  }

  List<BlockWidget> get blocks =>
      widgetList<BlockWidget>(find.byType(BlockWidget)).toList();
}

void main() {
  final first = kAdditionProblems.first;

  testWidgets('开局是两块分开的积木，得数还是问号', (tester) async {
    await tester.pumpAddition();

    expect(tester.blocks, hasLength(2));
    expect(
      tester.blocks.map((w) => w.body.widthUnits).toList()..sort(),
      [first.a, first.b]..sort(),
    );
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('两个加数起始分置首尾两行——凑十题也不能一开局就自己贴住', (tester) async {
    await tester.pumpAddition();

    final rows = tester.blocks.map((w) => w.body.anchor?.row).toSet();
    expect(rows, {0, kAdditionRows - 1});
  });

  testWidgets('点选通道：点 A 选中，再点 B 就合体', (tester) async {
    await tester.pumpAddition();

    await tester.tap(_blockOfColor(_colorA));
    await tester.pump();
    expect(tester.blocks, hasLength(2), reason: '第一下只是选中');

    await tester.tap(_blockOfColor(_colorB));
    await tester.pumpAndSettle();

    expect(tester.blocks, hasLength(1));
    expect(tester.blocks.single.body.widthUnits, first.sum);
    expect(tester.blocks.single.body.colorIndex, _colorSum);
  });

  testWidgets('合体后等式条显示得数', (tester) async {
    await tester.pumpAddition();

    await tester.tap(_blockOfColor(_colorA));
    await tester.pump();
    await tester.tap(_blockOfColor(_colorB));
    await tester.pumpAndSettle();

    expect(find.text('?'), findsNothing);
    expect(find.text('${first.sum}'), findsWidgets);
  });

  testWidgets('拼到一起就合体：把 B 拖到 A 旁边（同一行、边挨着边）', (tester) async {
    await tester.pumpAddition();

    final a = tester.blocks.firstWhere((w) => w.body.colorIndex == _colorA);
    final cell = tester.getSize(_blockOfColor(_colorA)).height;

    // B 在最后一行、最左边；把它拖到第一行、紧挨 A 的右侧。
    await tester.drag(
      _blockOfColor(_colorB),
      Offset(a.body.widthUnits * cell, -(kAdditionRows - 1) * cell),
    );
    await tester.pumpAndSettle();

    expect(tester.blocks, hasLength(1));
    expect(tester.blocks.single.body.widthUnits, first.sum);
  });

  testWidgets('叠到一起也合体：把 B 拖到 A 身上', (tester) async {
    await tester.pumpAddition();

    final target = tester.getCenter(_blockOfColor(_colorA));
    final start = tester.getCenter(_blockOfColor(_colorB));
    await tester.dragFrom(start, target - start);
    await tester.pumpAndSettle();

    expect(tester.blocks, hasLength(1));
    expect(tester.blocks.single.body.widthUnits, first.sum);
  });

  testWidgets('合体后的积木一行摆得下——得数最大的题也不例外', (tester) async {
    await tester.pumpAddition();

    for (var i = 0; i < kAdditionProblems.length; i++) {
      await tester.tap(_blockOfColor(_colorA));
      await tester.pump();
      await tester.tap(_blockOfColor(_colorB));
      await tester.pumpAndSettle();

      final sum = tester.blocks.single.body;
      expect(sum.widthUnits, lessThanOrEqualTo(kAdditionColumns));
      expect(
        (sum.anchor?.col ?? 0) + sum.widthUnits,
        lessThanOrEqualTo(kAdditionColumns),
        reason: '第 $i 题的得数积木越界了',
      );

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('重来把两个加数摆回去', (tester) async {
    await tester.pumpAddition();

    await tester.tap(_blockOfColor(_colorA));
    await tester.pump();
    await tester.tap(_blockOfColor(_colorB));
    await tester.pumpAndSettle();
    expect(tester.blocks, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('retry')));
    await tester.pumpAndSettle();

    expect(tester.blocks, hasLength(2));
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('下一题换算式，走到头绕回第一题', (tester) async {
    await tester.pumpAddition();

    await tester.tap(find.byKey(const ValueKey('next')));
    await tester.pumpAndSettle();

    final second = kAdditionProblems[1];
    expect(
      tester.blocks.map((w) => w.body.widthUnits).toList()..sort(),
      [second.a, second.b]..sort(),
    );

    for (var i = 1; i < kAdditionProblems.length; i++) {
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
    }
    expect(
      tester.blocks.map((w) => w.body.widthUnits).toList()..sort(),
      [first.a, first.b]..sort(),
    );
  });

  testWidgets('托盘里可按的东西都不小于 90dp', (tester) async {
    await tester.pumpAddition();

    for (final key in const [
      ValueKey('equation'),
      ValueKey('retry'),
      ValueKey('next'),
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.height, greaterThanOrEqualTo(BlockMetrics.minGrabTarget));
      expect(size.width, greaterThanOrEqualTo(BlockMetrics.minGrabTarget));
    }
  });

  testWidgets('题序：从 1+1 起步，后段是凑十', (tester) async {
    expect(kAdditionProblems.first, const AdditionProblem(1, 1));
    expect(
      kAdditionProblems.skip(kAdditionProblems.length - 3).every(
            (p) => p.makesTen,
          ),
      isTrue,
    );
    for (final p in kAdditionProblems) {
      expect(p.sum, lessThanOrEqualTo(kAdditionColumns));
    }
  });
}
