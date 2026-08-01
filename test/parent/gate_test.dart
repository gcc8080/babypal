import 'dart:math' as math;

import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/parent/gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('出题', () {
    test('两个因数都是两位数', () {
      final random = math.Random(7);
      for (var i = 0; i < 200; i++) {
        final c = ParentGateChallenge.next(random);
        expect(c.a, inInclusiveRange(10, 99));
        expect(c.b, inInclusiveRange(10, 99));
        expect(c.answer, c.a * c.b);
      }
    });

    test('重试时一定换题——同一道题重出等于刁难，不是验证', () {
      final random = math.Random(1);
      var previous = ParentGateChallenge.next(random);
      for (var i = 0; i < 200; i++) {
        final next = ParentGateChallenge.next(random, previous: previous);
        expect(next, isNot(previous));
        previous = next;
      }
    });

    test('答案不可能被乱按蒙对：至少三位数', () {
      // 11×11=121 是下界。三位数意味着乱按中的概率低于千分之一，
      // 而他连「答案要填在哪」都不知道。
      final random = math.Random(3);
      for (var i = 0; i < 100; i++) {
        expect(ParentGateChallenge.next(random).answer, greaterThanOrEqualTo(100));
      }
    });
  });

  group('长按 3 秒', () {
    testWidgets('按满 3 秒才开门', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParentGateEntry(onUnlockRequested: () => opened++),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ParentGateEntry)),
      );
      await tester.pump(); // 这一帧才是计时的起点
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      expect(opened, 1);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('不到 3 秒松手 → 什么都不发生，停在儿童端', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParentGateEntry(onUnlockRequested: () => opened++),
          ),
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ParentGateEntry)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2500));
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      expect(opened, 0);
    });

    testWidgets('松手不攒进度——反复乱按不会攒够 3 秒', (tester) async {
      // 这是这道门最容易被绕过的方式：孩子按一下、松、再按一下。
      // 若进度是累加的，他迟早会攒满。
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ParentGateEntry(onUnlockRequested: () => opened++),
          ),
        ),
      );

      for (var i = 0; i < 5; i++) {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ParentGateEntry)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(opened, 0);
    });

    testWidgets('入口刻意小于抓取阈值——它不该像个能按的地方', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ParentGateEntry(onUnlockRequested: () {})),
        ),
      );
      expect(
        tester.getSize(find.byType(ParentGateEntry)).width,
        lessThan(BlockMetrics.minGrabTarget),
      );
    });
  });

  group('乘法题', () {
    /// 家长门放行与否是这道门的**全部意义**，因此测试必须读到那个返回值。
    ///
    /// 只断言「页面关掉了」是不够的：答对和答错都会关页面，那样两条用例
    /// 的断言完全相同，等于什么都没验。
    late List<bool?> outcome;

    Future<void> pumpGate(WidgetTester tester, ParentGateChallenge c) async {
      outcome = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    outcome.add(
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute<bool>(
                          builder: (_) => ParentGatePage(challenge: c),
                        ),
                      ),
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    Future<void> type(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.byKey(ValueKey('gate-key-$d')));
        await tester.pump();
      }
    }

    testWidgets('答对 → 通过', (tester) async {
      const challenge = ParentGateChallenge(12, 13); // 156
      await pumpGate(tester, challenge);
      expect(find.byKey(const ValueKey('question')), findsOneWidget);

      await type(tester, '156');
      await tester.tap(find.byKey(const ValueKey('gate-key-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(ParentGatePage), findsNothing);
      expect(outcome, [true]);
    });

    testWidgets('答错 → 立刻回儿童端，不给「再试一次」', (tester) async {
      const challenge = ParentGateChallenge(12, 13);
      await pumpGate(tester, challenge);

      await type(tester, '150');
      await tester.tap(find.byKey(const ValueKey('gate-key-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(ParentGatePage), findsNothing, reason: '答错就退出去');
      expect(outcome, [false], reason: '答错必须是「没通过」，不是「关掉了」');
    });

    testWidgets('退格能改，输错了不至于只能重来', (tester) async {
      const challenge = ParentGateChallenge(12, 13);
      await pumpGate(tester, challenge);

      await type(tester, '159');
      await tester.tap(find.byKey(const ValueKey('gate-key-backspace')));
      await tester.pump();
      await type(tester, '6');
      await tester.tap(find.byKey(const ValueKey('gate-key-submit')));
      await tester.pumpAndSettle();

      expect(outcome, [true]);
    });

    testWidgets('直接返回 → 不通过', (tester) async {
      const challenge = ParentGateChallenge(12, 13);
      await pumpGate(tester, challenge);
      await tester.tap(find.byKey(const ValueKey('cancel')));
      await tester.pumpAndSettle();
      expect(outcome, [false]);
    });
  });
}
