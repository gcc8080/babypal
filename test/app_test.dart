import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/progress/progress_providers.dart';
import 'package:baby_pal/core/progress/progress_store.dart';
import 'package:baby_pal/core/settings/settings_providers.dart';
import 'package:baby_pal/core/settings/settings_store.dart';
import 'package:baby_pal/main.dart';
import 'package:baby_pal/modules/home/bedtime_overlay.dart';
import 'package:baby_pal/modules/home/module_id.dart';
import 'package:baby_pal/parent/gate.dart';
import 'package:baby_pal/parent/parent_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_audio_bus.dart';

/// 整个 App 接起来之后才成立的那些行为。
///
/// 单个 store 的语义（墙钟计时、跨日归零）在 `progress_store_test` 里验过了；
/// 这里验的是**接线**：到点之后谢幕画面是不是真的盖得住他正在玩的那一页、
/// 家长关掉一个模块首页是不是真的少一块大陆、家长门是不是真的在门后。
void main() {
  const phone = Size(738, 393);

  late SettingsStore settings;
  late ProgressStore progress;
  late DateTime now;

  Future<void> pumpApp(WidgetTester tester) async {
    now = DateTime(2026, 8, 2, 9);
    settings = SettingsStore();
    progress = ProgressStore(null, clock: () => now)..load();
    addTearDown(settings.dispose);
    addTearDown(progress.dispose);

    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioBusProvider.overrideWithValue(RecordingAudioBus()),
          contentLibraryProvider.overrideWithValue(
            ContentLibrary([
              const PackLoader().parse(
                '{"schemaVersion": 1}',
                source: 'empty.json',
              )!,
            ]),
          ),
          settingsStoreProvider.overrideWithValue(settings),
          progressStoreProvider.overrideWithValue(progress),
        ],
        child: const BlockPlanetApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('首页跟着设置走', () {
    testWidgets('默认五块大陆都在', (tester) async {
      await pumpApp(tester);
      for (final module in ModuleId.values) {
        expect(find.byKey(ValueKey(module)), findsOneWidget);
      }
    });

    testWidgets('家长关掉汉字 → 首页立刻少一块大陆', (tester) async {
      await pumpApp(tester);
      await settings.setModuleEnabled(ModuleId.hanzi, false);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey(ModuleId.hanzi)), findsNothing);
      expect(find.byKey(const ValueKey(ModuleId.numbers)), findsOneWidget);
    });
  });

  /// 谢幕画面里的「呼吸」是**永不停止**的循环动画（静止的画面像卡住了），
  /// 因此这一组只能 pump 固定帧数，不能 pumpAndSettle——后者会一直等下去。
  Future<void> settleOverlay(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  group('到点了', () {
    testWidgets('没到点时没有谢幕画面', (tester) async {
      await pumpApp(tester);
      expect(find.byType(BedtimeOverlay), findsNothing);
    });

    testWidgets('额度用完 → 谢幕画面盖上来，不是对话框', (tester) async {
      await pumpApp(tester);
      now = now.add(const Duration(minutes: 16));
      await progress.flush();
      await settleOverlay(tester);

      expect(find.byType(BedtimeOverlay), findsOneWidget);
      // 「MUST NOT 弹出强制对话框」——盖上来的必须是一层画面，不是路由。
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('他正在玩法里的时候也盖得住', (tester) async {
      // 这是最容易写错的一处：把谢幕画面挂在 `home` 上，它会被压在整个
      // 路由栈底下——他在沙盒里玩到超时，屏幕上什么也不会发生。
      await pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey(ModuleId.sandbox)));
      await tester.pumpAndSettle();

      now = now.add(const Duration(minutes: 16));
      await progress.flush();
      await settleOverlay(tester);

      expect(find.byType(BedtimeOverlay), findsOneWidget);
    });

    testWidgets('家长把上限调高 → 谢幕画面自己消失，不用重启', (tester) async {
      await pumpApp(tester);
      now = now.add(const Duration(minutes: 16));
      await progress.flush();
      await settleOverlay(tester);
      expect(find.byType(BedtimeOverlay), findsOneWidget);

      await progress.setDailyLimit(const Duration(minutes: 30));
      await tester.pumpAndSettle();
      expect(find.byType(BedtimeOverlay), findsNothing);
    });

    testWidgets('谢幕画面上必须留着家长门，否则上限再也调不了', (tester) async {
      await pumpApp(tester);
      now = now.add(const Duration(minutes: 16));
      await progress.flush();
      await settleOverlay(tester);

      final gate = find.descendant(
        of: find.byType(BedtimeOverlay),
        matching: find.byType(ParentGateEntry),
      );
      expect(gate, findsOneWidget);
    });
  });

  group('时长记到对的地方', () {
    testWidgets('在沙盒里待的时间记在沙盒名下', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey(ModuleId.sandbox)));
      await tester.pumpAndSettle();

      now = now.add(const Duration(minutes: 3));
      await progress.flush(module: ModuleId.sandbox.name);
      await tester.pumpAndSettle();

      expect(progress.snapshot.moduleSeconds[ModuleId.sandbox.name], 180);
      expect(progress.todayPlayed, greaterThanOrEqualTo(
        const Duration(minutes: 3),
      ));
    });

    testWidgets('切后台那段不算——他没在玩', (tester) async {
      await pumpApp(tester);
      now = now.add(const Duration(minutes: 5));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      now = now.add(const Duration(minutes: 30)); // 放在一边半小时
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      now = now.add(const Duration(minutes: 2));
      await progress.flush();

      expect(progress.snapshot.playedSeconds, 7 * 60);
    });
  });

  group('家长门在门后', () {
    testWidgets('首页有入口，但按一下进不去', (tester) async {
      await pumpApp(tester);
      final gate = find.descendant(
        of: find.byType(Stack),
        matching: find.byType(ParentGateEntry),
      );
      expect(gate, findsWidgets);

      await tester.tap(gate.first);
      await tester.pumpAndSettle();
      expect(find.byType(ParentGatePage), findsNothing);
      expect(find.byType(ParentHomePage), findsNothing);
    });

    testWidgets('长按 3 秒才出乘法题；答对才进得去家长区', (tester) async {
      await pumpApp(tester);
      final gate = find.byType(ParentGateEntry).first;

      final press = await tester.startGesture(tester.getCenter(gate));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      await press.up();
      await tester.pumpAndSettle();

      expect(find.byType(ParentGatePage), findsOneWidget);

      // 从题面读出这道题，再答给它——测试不该知道随机数会抽到哪一道。
      final question = tester.widget<Text>(
        find.byKey(const ValueKey('question')),
      );
      final parts = question.data!.split(RegExp(r'[×=?\s]+'));
      final answer = int.parse(parts[0]) * int.parse(parts[1]);

      for (final digit in '$answer'.split('')) {
        await tester.tap(find.byKey(ValueKey('gate-key-$digit')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('gate-key-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(ParentHomePage), findsOneWidget);
    });
  });
}
