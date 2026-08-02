import 'package:baby_pal/birthday/birthday_egg.dart';
import 'package:baby_pal/birthday/birthday_providers.dart';
import 'package:baby_pal/birthday/birthday_store.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/progress/progress_providers.dart';
import 'package:baby_pal/core/progress/progress_store.dart';
import 'package:baby_pal/core/settings/settings_providers.dart';
import 'package:baby_pal/core/settings/settings_store.dart';
import 'package:baby_pal/main.dart';
import 'package:baby_pal/modules/home/bedtime_overlay.dart';
import 'package:baby_pal/modules/home/home_page.dart';
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
  late BirthdayStore birthday;
  late DateTime now;

  /// 推完一层路由的进出场动画。
  ///
  /// 彩蛋那一层**不能用 `pumpAndSettle`**：里面的火苗与积木眨眼都是永不停止
  /// 的循环动画，它会一直等下去。所以按固定时长推——800ms 是留了余量的，
  /// Material 的进出场比 `transitionDuration` 那个 300ms 长（实测退场推到
  /// 500ms 才拆干净）。
  Future<void> settleRoute(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
  }

  /// 起 App。
  ///
  /// [birthdayPlayed] 默认 **true**：除了「首启放彩蛋」那一组，别的用例验的
  /// 都是他日常打开 App 之后的样子——那时彩蛋早放过了。若默认成 false，
  /// 每个用例一进来都会被彩蛋盖住，找不到星球地图。
  Future<void> pumpApp(WidgetTester tester, {bool birthdayPlayed = true}) async {
    now = DateTime(2026, 8, 2, 9);
    settings = SettingsStore();
    progress = ProgressStore(null, clock: () => now)..load();
    birthday = BirthdayStore();
    if (birthdayPlayed) await birthday.markPlayed();
    addTearDown(settings.dispose);
    addTearDown(progress.dispose);
    addTearDown(birthday.dispose);

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
          birthdayStoreProvider.overrideWithValue(birthday),
        ],
        child: const BlockPlanetApp(),
      ),
    );
    if (birthdayPlayed) {
      await tester.pumpAndSettle();
    } else {
      await settleRoute(tester);
    }
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

  group('生日彩蛋接在 App 上', () {
    testWidgets('新装的 App 一进来就放彩蛋', (tester) async {
      await pumpApp(tester, birthdayPlayed: false);
      expect(find.byType(BirthdayEgg), findsOneWidget);
    });

    testWidgets('放过了就不再自动放——第二天打开是星球地图', (tester) async {
      await pumpApp(tester);
      expect(find.byType(BirthdayEgg), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('跳过 → 回到星球地图，并记下放过了', (tester) async {
      // 「不许卡在中间状态」这条规格在 App 这一层的样子：跳过之后必须
      // 落在那张星球地图上，而不是一个空路由或者又一遍彩蛋。
      await pumpApp(tester, birthdayPlayed: false);
      expect(birthday.hasPlayed, isFalse);

      await tester.tap(find.byKey(const ValueKey('skip')));
      await settleRoute(tester);

      expect(find.byType(BirthdayEgg), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(birthday.hasPlayed, isTrue, reason: '否则每次打开都要重放一次');
    });

    testWidgets('首页那块蛋糕能重播', (tester) async {
      await pumpApp(tester);
      expect(find.byType(BirthdayEgg), findsNothing);

      await tester.tap(find.byKey(const ValueKey('birthday')));
      await settleRoute(tester);
      expect(find.byType(BirthdayEgg), findsOneWidget);
    });

    testWidgets('彩蛋放到一半到点了，谢幕画面也得让开', (tester) async {
      // 与家长门同一个道理（见 `_inParentZone`）：谢幕画面盖在路由栈之上，
      // 谁都盖得住。而他正在吹的那三根蜡烛是这个 App 存在的理由——
      // 「今天玩够 15 分钟了」绝不能在那一刻把画面糊掉。
      await pumpApp(tester, birthdayPlayed: false);
      expect(find.byType(BirthdayEgg), findsOneWidget);

      now = now.add(const Duration(minutes: 16));
      await progress.flush();
      await settleRoute(tester);

      expect(find.byType(BirthdayEgg), findsOneWidget);
      expect(find.byType(BedtimeOverlay), findsNothing, reason: '彩蛋不能被盖住');

      // 放完之后该盖还是要盖上——让开的是彩蛋那一段，不是把上限取消了。
      await tester.tap(find.byKey(const ValueKey('skip')));
      await settleRoute(tester);
      expect(find.byType(BedtimeOverlay), findsOneWidget);
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

    testWidgets('从谢幕画面上的家长门进去，画面必须让开——否则门开了人进不去', (tester) async {
      // 真机上撞到的：谢幕画面盖在路由栈之上，而家长门和家长区都是路由。
      // 长按之后乘法题被压在画面底下，看不见也点不着，而调高上限是唯一出路。
      await pumpApp(tester);
      now = now.add(const Duration(minutes: 16));
      await progress.flush();
      await settleOverlay(tester);

      final gate = find.descendant(
        of: find.byType(BedtimeOverlay),
        matching: find.byType(ParentGateEntry),
      );
      final press = await tester.startGesture(tester.getCenter(gate));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3, milliseconds: 100));
      await press.up();
      await tester.pumpAndSettle();

      expect(find.byType(ParentGatePage), findsOneWidget);
      expect(
        find.byType(BedtimeOverlay),
        findsNothing,
        reason: '乘法题不能被谢幕画面盖住',
      );
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
