import 'package:baby_pal/birthday/birthday_egg.dart';
import 'package:baby_pal/birthday/birthday_store.dart';
import 'package:baby_pal/birthday/candle_scene.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_audio_bus.dart';
import 'candle_scene_test.dart' show FakeBreathSource;

void main() {
  late FakeBreathSource breath;
  late int done;

  Future<void> pumpEgg(WidgetTester tester) async {
    breath = FakeBreathSource(available: false);
    done = 0;
    addTearDown(breath.dispose);

    tester.view.physicalSize = const Size(738, 393);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioBusProvider.overrideWithValue(RecordingAudioBus())],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: BirthdayEgg(breathSource: breath, onDone: () => done++),
        ),
      ),
    );
    // 蜡烛的火苗是永不停止的循环动画，pumpAndSettle 会一直等。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('放彩蛋', () {
    testWidgets('第一幕是蜡烛', (tester) async {
      await pumpEgg(tester);
      expect(find.byType(CandleScene), findsOneWidget);
      expect(done, 0);
    });

    testWidgets('跳过键一直在，按下就走完，且只走一次', (tester) async {
      await pumpEgg(tester);
      expect(find.byKey(const ValueKey('skip')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('skip')));
      await tester.pump();
      expect(done, 1);

      // 连按两下不该弹掉两层——他一定会连按。
      await tester.tap(find.byKey(const ValueKey('skip')));
      await tester.pump();
      expect(done, 1, reason: '出口只许走一次');
    });

    testWidgets('多幕依次放，最后一幕演完走同一个出口', (tester) async {
      var finished = 0;
      final played = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [audioBusProvider.overrideWithValue(RecordingAudioBus())],
          child: MaterialApp(
            home: BirthdayEgg(
              onDone: () => finished++,
              scenes: [
                for (final id in ['一', '二'])
                  BirthdayScene(
                    id: id,
                    build: (context, onFinished) {
                      played.add(id);
                      return ElevatedButton(
                        onPressed: onFinished,
                        child: Text(id),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(played, ['一']);
      await tester.tap(find.text('一'));
      await tester.pumpAndSettle();
      expect(played, ['一', '二'], reason: '第一幕演完该换第二幕');
      expect(finished, 0, reason: '还没到最后一幕');

      await tester.tap(find.text('二'));
      await tester.pumpAndSettle();
      expect(finished, 1, reason: '最后一幕演完才走出口');
    });

    testWidgets('被动那一幕碰哪儿都跳过', (tester) async {
      // 拼名字动画（8.2）会是这一类：看着就好，他一碰就说明想往下走了。
      var finished = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [audioBusProvider.overrideWithValue(RecordingAudioBus())],
          child: MaterialApp(
            home: BirthdayEgg(
              onDone: () => finished++,
              scenes: [
                BirthdayScene(
                  id: 'passive',
                  tapAnywhereSkips: true,
                  build: (context, onFinished) => const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('skip-surface')), findsOneWidget);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(finished, 1);
    });

    testWidgets('互动那一幕不能碰哪儿都跳过——他伸手是在玩', (tester) async {
      // 蜡烛这一幕要点着、要吹、要点。若把任何触摸都当成「跳过」，
      // 这一幕根本没法玩。
      await pumpEgg(tester);
      final scenes = birthdayScenes();
      expect(scenes.every((s) => !s.tapAnywhereSkips), isTrue);
      expect(find.byKey(const ValueKey('skip-surface')), findsNothing);

      // 点画面中间（蛋糕上）不该结束彩蛋。
      await tester.tapAt(const Offset(369, 150));
      await tester.pump();
      expect(done, 0);
    });
  });

  group('首启一次', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await (await SharedPreferences.getInstance()).clear();
    });

    test('新装的 App 认为还没放过', () async {
      final store = BirthdayStore(await SharedPreferences.getInstance());
      expect(store.hasPlayed, isFalse);
    });

    test('放过之后记住了，重启也记得', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = BirthdayStore(prefs);
      await first.markPlayed();
      expect(first.hasPlayed, isTrue);
      first.dispose();

      final second = BirthdayStore(prefs);
      expect(second.hasPlayed, isTrue, reason: '重启之后不该再自动放一次');
      second.dispose();
    });

    test('reset 之后又能自动放——供家长区「再放一次」', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = BirthdayStore(prefs);
      await store.markPlayed();
      await store.reset();
      expect(store.hasPlayed, isFalse);
      store.dispose();
    });

    test('存档打不开时按「还没放过」处理', () async {
      // 宁可多放一次，也不要在他生日当天一次都没放。
      final store = BirthdayStore();
      expect(store.hasPlayed, isFalse);
      await store.markPlayed();
      expect(store.hasPlayed, isTrue);
      store.dispose();
    });
  });

  group('内容缺失', () {
    testWidgets('一幕都没有时不留白屏，直接走完', (tester) async {
      // 规格「彩蛋数据与资源可缺失」：姓名、照片、家人语音都没配置时，
      // 彩蛋仍要能启动并完成，缺的那部分优雅省略。
      var finished = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [audioBusProvider.overrideWithValue(RecordingAudioBus())],
          child: MaterialApp(
            home: BirthdayEgg(onDone: () => finished++, scenes: const []),
          ),
        ),
      );
      await tester.pump();
      expect(finished, 1, reason: '不该停在一个空白页面上');
    });
  });
}
