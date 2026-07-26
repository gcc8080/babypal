import 'dart:io';

import 'package:baby_pal/core/audio/audio_bus.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:baby_pal/core/block/block_widget.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/addition/addition.dart';
import 'package:baby_pal/modules/addition/addition_page.dart';
import 'package:baby_pal/modules/addition/equation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AudioBus _silentBus() =>
    AudioBus(resolver: VoiceResolver(overridesDir: Directory.systemTemp));

Finder _slot() => find.byKey(const ValueKey('slot'));
Finder _choice(int value) => find.byKey(ValueKey('choice-$value'));

/// 槽里显示的数字。空槽返回 null。
String? _slotLabel(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: _slot(), matching: find.byType(Text)),
  );
  return texts.isEmpty ? null : texts.first.data;
}

extension on WidgetTester {
  Future<void> pumpEquation() async {
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(738, 393);
    addTearDown(view.reset);

    await pumpWidget(
      ProviderScope(
        overrides: [audioBusProvider.overrideWithValue(_silentBus())],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: const EquationPage(),
        ),
      ),
    );
    await pump();
  }

  List<BlockWidget> get blocks =>
      widgetList<BlockWidget>(find.byType(BlockWidget)).toList();

  /// 等演示放完、界面复位。
  Future<void> settleDemo() async {
    await pump(const Duration(milliseconds: 3500));
    await pumpAndSettle();
  }
}

void main() {
  final first = kAdditionProblems.first;

  group('候选答案', () {
    test('三个选项里恰好有一个是正确答案', () {
      for (var round = 0; round < kAdditionProblems.length; round++) {
        final p = kAdditionProblems[round];
        final choices = equationChoices(p, round);
        expect(choices, hasLength(kEquationChoices));
        expect(choices.where((c) => c == p.sum), hasLength(1), reason: '$p');
      }
    });

    test('正确答案的位置逐题轮换——不能靠位置记答案', () {
      final positions = <int>{};
      for (var round = 0; round < kEquationChoices; round++) {
        final p = kAdditionProblems[round];
        positions.add(equationChoices(p, round).indexOf(p.sum));
      }
      expect(positions, hasLength(kEquationChoices), reason: '三个位置都出现过');
    });

    test('干扰项紧贴正确答案，且都是正整数', () {
      for (var round = 0; round < kAdditionProblems.length; round++) {
        final p = kAdditionProblems[round];
        for (final c in equationChoices(p, round)) {
          expect(c, greaterThan(0), reason: '$p → $c');
          expect((c - p.sum).abs(), lessThanOrEqualTo(2), reason: '$p → $c');
        }
      }
    });

    test('选项互不重复', () {
      for (var round = 0; round < kAdditionProblems.length; round++) {
        final choices = equationChoices(kAdditionProblems[round], round);
        expect(choices.toSet(), hasLength(kEquationChoices));
      }
    });
  });

  group('等式槽', () {
    testWidgets('开局：等式显示两个加数，结果槽是空的', (tester) async {
      await tester.pumpEquation();

      expect(find.text('${first.a}'), findsWidgets);
      expect(find.text('+'), findsOneWidget);
      expect(find.text('='), findsOneWidget);
      expect(_slotLabel(tester), isNull);
    });

    testWidgets('点选通道：点候选直接填进槽', (tester) async {
      await tester.pumpEquation();

      await tester.tap(_choice(first.sum));
      await tester.pump();

      expect(_slotLabel(tester), '${first.sum}');
    });

    testWidgets('拖拽通道：把候选拖进槽', (tester) async {
      await tester.pumpEquation();

      final from = tester.getCenter(_choice(first.sum));
      final to = tester.getCenter(_slot());
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(_slotLabel(tester), '${first.sum}');
    });

    testWidgets('答对：槽点亮，「下一题」点亮', (tester) async {
      await tester.pumpEquation();

      RoundActionButton next() =>
          tester.widget<RoundActionButton>(find.byKey(const ValueKey('next')));
      expect(next().highlighted, isFalse);

      await tester.tap(_choice(first.sum));
      await tester.settleDemo();

      expect(_slotLabel(tester), '${first.sum}');
      expect(next().highlighted, isTrue);
    });

    testWidgets('规格场景：答错不出红叉、不扣分，用积木演示后允许重试', (tester) async {
      await tester.pumpEquation();

      final wrong = equationChoices(first, 0).firstWhere((c) => c != first.sum);
      await tester.tap(_choice(wrong));
      await tester.pump();

      // 演示阶段：两块积木被合成得数积木给他看。
      await tester.pumpAndSettle();
      expect(tester.blocks, hasLength(1));
      expect(
        tester.blocks.single.body.widthUnits,
        first.sum,
        reason: '演示的是真实得数，不是他填的那个数',
      );

      // 演示期间界面上不得出现任何否定信号。
      expect(find.text('✗'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);

      // 演示完：槽清空、积木摆回去，可以再试。
      await tester.settleDemo();
      expect(_slotLabel(tester), isNull);
      expect(tester.blocks, hasLength(2));

      await tester.tap(_choice(first.sum));
      await tester.settleDemo();
      expect(_slotLabel(tester), '${first.sum}');
    });

    testWidgets('答错次数不限，也不留任何痕迹', (tester) async {
      await tester.pumpEquation();

      final wrong = equationChoices(first, 0).firstWhere((c) => c != first.sum);
      for (var i = 0; i < 3; i++) {
        await tester.tap(_choice(wrong));
        await tester.settleDemo();
        expect(_slotLabel(tester), isNull, reason: '第 ${i + 1} 次答错后');
        expect(tester.blocks, hasLength(2));
      }

      RoundActionButton next() =>
          tester.widget<RoundActionButton>(find.byKey(const ValueKey('next')));
      expect(next().highlighted, isFalse, reason: '答错不该点亮下一题');
    });

    testWidgets('演示期间不接受新的作答——避免连点把演示打断', (tester) async {
      await tester.pumpEquation();

      final wrong = equationChoices(first, 0).firstWhere((c) => c != first.sum);
      await tester.tap(_choice(wrong));
      await tester.pump();

      await tester.tap(_choice(first.sum), warnIfMissed: false);
      await tester.pump();
      expect(_slotLabel(tester), '$wrong', reason: '槽里仍是第一次填的那个');
    });
  });

  group('积木区是随手可用的算盘', () {
    testWidgets('开局两块加数分列两端，他可以自己合起来数', (tester) async {
      await tester.pumpEquation();

      expect(tester.blocks, hasLength(2));
      final cols = tester.blocks.map((w) => w.body.anchor!.col).toList()
        ..sort();
      expect(cols.first, 0);
      expect(cols.last + first.b, kAdditionColumns);
    });

    testWidgets('自己把积木合起来不算作答——选哪个答案始终是他的决定', (tester) async {
      await tester.pumpEquation();

      final a = tester.blocks.first;
      final b = tester.blocks.last;
      await tester.dragFrom(
        tester.getCenter(
          find.byWidgetPredicate(
            (w) => w is BlockWidget && w.body.id == b.body.id,
          ),
        ),
        tester.getCenter(
              find.byWidgetPredicate(
                (w) => w is BlockWidget && w.body.id == a.body.id,
              ),
            ) -
            tester.getCenter(
              find.byWidgetPredicate(
                (w) => w is BlockWidget && w.body.id == b.body.id,
              ),
            ),
      );
      await tester.pumpAndSettle();

      expect(tester.blocks, hasLength(1));
      expect(tester.blocks.single.body.widthUnits, first.sum);
      expect(_slotLabel(tester), isNull, reason: '槽不会被自动填上');
    });
  });

  group('题目流转与布局', () {
    testWidgets('下一题换算式并复位', (tester) async {
      await tester.pumpEquation();

      await tester.tap(_choice(first.sum));
      await tester.settleDemo();

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();

      final second = kAdditionProblems[1];
      expect(_slotLabel(tester), isNull);
      expect(tester.blocks, hasLength(2));
      expect(
        tester.blocks.map((w) => w.body.widthUnits).toList()..sort(),
        [second.a, second.b]..sort(),
      );
    });

    testWidgets('玩法切换回到合体求和，且是替换不是叠层', (tester) async {
      await tester.pumpEquation();

      await tester.tap(find.byKey(const ValueKey('mode')));
      await tester.pumpAndSettle();

      expect(find.byType(AdditionPage), findsOneWidget);
      expect(find.byType(EquationPage), findsNothing);
    });

    testWidgets('槽与候选都不小于 90dp', (tester) async {
      await tester.pumpEquation();

      expect(
        tester.getSize(_slot()).shortestSide,
        greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
      );
      for (final value in equationChoices(first, 0)) {
        expect(
          tester.getSize(_choice(value)).shortestSide,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
          reason: '候选 $value',
        );
      }
    });

    testWidgets('最窄机型上不溢出', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(640, 360);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [audioBusProvider.overrideWithValue(_silentBus())],
          child: MaterialApp(
            theme: buildBlockPlanetTheme(),
            home: const EquationPage(),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
