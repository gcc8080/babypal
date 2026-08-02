import 'package:baby_pal/birthday/birthday_providers.dart';
import 'package:baby_pal/birthday/birthday_store.dart';
import 'package:baby_pal/core/audio/narration.dart';
import 'package:baby_pal/core/progress/progress_providers.dart';
import 'package:baby_pal/core/progress/progress_store.dart';
import 'package:baby_pal/core/settings/settings_providers.dart';
import 'package:baby_pal/core/settings/settings_store.dart';
import 'package:baby_pal/modules/home/module_id.dart';
import 'package:baby_pal/parent/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsStore settings;
  late ProgressStore progress;
  late BirthdayStore birthday;
  late ProviderContainer container;

  Future<void> pumpPage(WidgetTester tester, {bool birthdayPlayed = true}) async {
    settings = SettingsStore();
    progress = ProgressStore(null)..load();
    birthday = BirthdayStore();
    if (birthdayPlayed) await birthday.markPlayed();
    addTearDown(settings.dispose);
    addTearDown(progress.dispose);
    addTearDown(birthday.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(settings),
          progressStoreProvider.overrideWithValue(progress),
          birthdayStoreProvider.overrideWithValue(birthday),
        ],
        child: const MaterialApp(home: ParentSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(ParentSettingsPage)),
    );
  }

  group('中英双声道', () {
    testWidgets('默认开着，关掉之后播报只剩中文', (tester) async {
      await pumpPage(tester);
      expect(
        container.read(narrationProvider).addition(1, 2),
        Narration.bilingualAddition(1, 2),
      );

      await tester.tap(find.byKey(const ValueKey('bilingual')));
      await tester.pumpAndSettle();

      expect(container.read(narrationProvider).addition(1, 2), [
        'zh.number.1',
        'zh.word.plus',
        'zh.number.2',
        'zh.word.equals',
        'zh.number.3',
      ]);
    });

    testWidgets('立即生效：不用重进页面，也不用重启', (tester) async {
      // 「立即」是规格里的原话。这条实际盯的是 narrationProvider 有没有
      // 挂上 store 的监听——少了那几行，Provider 会一直返回旧值。
      await pumpPage(tester);
      final before = container.read(narrationProvider).bilingual;
      await tester.tap(find.byKey(const ValueKey('bilingual')));
      await tester.pump();
      expect(container.read(narrationProvider).bilingual, !before);
    });
  });

  group('模块开关', () {
    testWidgets('关掉汉字 → 首页要显示的模块里不再有它', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('module-hanzi')));
      await tester.pumpAndSettle();

      expect(settings.settings.orderedModules, isNot(contains(ModuleId.hanzi)));
      expect(settings.settings.orderedModules, contains(ModuleId.numbers));
    });

    testWidgets('剩下最后一块时关不掉——空首页是他无法理解的状态', (tester) async {
      await pumpPage(tester);
      for (final module in ModuleId.values) {
        await tester.tap(find.byKey(ValueKey('module-${module.name}')));
        await tester.pumpAndSettle();
      }
      expect(settings.settings.orderedModules, hasLength(1));

      final last = settings.settings.orderedModules.single;
      final tile = tester.widget<SwitchListTile>(
        find.byKey(ValueKey('module-${last.name}')),
      );
      expect(tile.onChanged, isNull, reason: '最后一块的开关必须是灰的');
    });

    testWidgets('开关顺序不影响首页的左右位置——他是靠位置记路的', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('module-numbers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('module-numbers')));
      await tester.pumpAndSettle();

      expect(settings.settings.orderedModules, ModuleId.values);
    });
  });

  group('每日时长', () {
    testWidgets('选 30 分钟，上限跟着变', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('limit-30')));
      await tester.pumpAndSettle();
      expect(progress.dailyLimit, const Duration(minutes: 30));
    });
  });

  group('持久化', () {
    test('重启之后设置还在', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      final first = SettingsStore(prefs);
      await first.setBilingual(false);
      await first.setModuleEnabled(ModuleId.hanzi, false);
      first.dispose();

      final second = SettingsStore(prefs);
      expect(second.settings.bilingual, isFalse);
      expect(second.settings.enabledModules, isNot(contains(ModuleId.hanzi)));
      second.dispose();
    });

    test('存档损坏 → 用默认值，不是打不开', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await prefs.setString(SettingsStore.storageKey, '{这不是 json');

      final store = SettingsStore(prefs);
      expect(store.settings, const AppSettings());
      store.dispose();
    });

    test('内存版改得动，只是不落盘', () async {
      final store = SettingsStore();
      await store.setBilingual(false);
      expect(store.settings.bilingual, isFalse);
      store.dispose();
    });
  });

  group('生日彩蛋', () {
    // 真机上撞出来的：8.1 首启自动播只在 `hasPlayed` 为假时触发，而这个标记
    // 一旦写上就没有任何界面能改回去——彩蛋在他生日之前被谁点开过一次，
    // 生日当天开机就只剩平常的星球地图。这个开关是那件事的出路。
    testWidgets('放过之后开关是关的，说明已经放过了', (tester) async {
      await pumpPage(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('birthday-replay')),
        200,
      );
      final tile = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('birthday-replay')),
      );
      expect(tile.value, isFalse);
      expect(birthday.hasPlayed, isTrue);
    });

    testWidgets('打开开关 → 下次启动会再自动放一次', (tester) async {
      await pumpPage(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('birthday-replay')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('birthday-replay')));
      await tester.pumpAndSettle();

      expect(birthday.hasPlayed, isFalse, reason: '这正是首启自动播的条件');
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const ValueKey('birthday-replay')))
            .value,
        isTrue,
        reason: '开关要立刻反映出来，否则家长不知道自己按上没有',
      );
    });

    testWidgets('再关回去 → 恢复成「已经放过了」', (tester) async {
      await pumpPage(tester, birthdayPlayed: false);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('birthday-replay')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('birthday-replay')));
      await tester.pumpAndSettle();
      expect(birthday.hasPlayed, isTrue);
    });
  });
}
