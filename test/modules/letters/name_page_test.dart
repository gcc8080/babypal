import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/letters/letters_page.dart';
import 'package:baby_pal/modules/letters/name_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

const Size _phone = Size(738, 393);

/// 目标名字**来自内容包**，不是代码里的常量——规格对 5.6 的硬要求。
/// 这里刻意用一个与真实内容包不同的名字，用来证明页面确实是读数据的。
ContentLibrary _library({String name = 'Emmett'}) => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "letters": [
    {"letter": "E", "voiceKey": "en.letter.e", "phonemeVoiceKey": "en.phoneme.e"},
    {"letter": "M", "voiceKey": "en.letter.m", "phonemeVoiceKey": "en.phoneme.m"},
    {"letter": "T", "voiceKey": "en.letter.t", "phonemeVoiceKey": "en.phoneme.t"}
  ],
  "spellingTargets": [
    {"id": "child", "letters": "$name", "voiceKey": "en.name.child"},
    {"id": "mama", "letters": "Mem", "voiceKey": "en.name.mama"}
  ]
}
''', source: 'letters.json')!,
]);

void main() {
  late RecordingAudioBus audio;

  Future<void> pumpName(WidgetTester tester, {String name = 'Emmett'}) async {
    audio = RecordingAudioBus();
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioBusProvider.overrideWithValue(audio),
          contentLibraryProvider.overrideWithValue(_library(name: name)),
        ],
        // 每个名字一个 Key：同一个测试里换目标重新 pump 时，State 必须重建，
        // 否则留着上一关的槽位——那是测试自己制造的假象，不是产品的行为。
        child: MaterialApp(home: NamePage(key: ValueKey(name))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 托盘里现存的积木 id。
  List<int> trayIds(WidgetTester tester) => tester
      .widgetList(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('tile-'),
        ),
      )
      .map((w) => int.parse((w.key! as ValueKey<String>).value.substring(5)))
      .toList();

  /// 托盘里第一块写着 [letter] 的积木。
  Finder trayTile(WidgetTester tester, String letter) {
    for (final id in trayIds(tester)) {
      final key = ValueKey('tile-$id');
      final text = find.descendant(
        of: find.byKey(key),
        matching: find.byWidgetPredicate((w) => w is Text && w.data == letter),
      );
      if (text.evaluate().isNotEmpty) return find.byKey(key);
    }
    fail('托盘里没有字母 $letter');
  }

  Future<void> tapTile(WidgetTester tester, String letter) async {
    await tester.tap(trayTile(tester, letter));
    await tester.pump();
  }

  group('目标来自可配置数据', () {
    testWidgets('槽位数与名字长度一致，换个名字就换个关', (tester) async {
      await pumpName(tester);
      expect(find.byKey(const ValueKey('slot-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-6')), findsNothing);

      await pumpName(tester, name: 'Tem');
      expect(find.byKey(const ValueKey('slot-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-3')), findsNothing);
    });

    testWidgets('重复字母各有各的积木：Emmett 给出 6 块而不是 3 块', (tester) async {
      await pumpName(tester);
      // 两个 M、两个 T 都得在——按字母去重会让这一关根本拼不完。
      expect(trayIds(tester).length, 6);
      expect(trayIds(tester).toSet().length, 6);
    });
  });

  group('放对与放歪都会到该去的地方', () {
    testWidgets('点选通道：点一块积木，它自己飞到正确的槽', (tester) async {
      await pumpName(tester);
      await tapTile(tester, 'E');

      // Emmett 的第 0 位是 E。
      expect(trayIds(tester).length, 5);
    });

    testWidgets('规格场景：放到不属于它的槽，它照样落到正确位置且无失败态', (tester) async {
      await pumpName(tester);
      audio.sfx.clear();

      // 把 T 拖到 0 号槽——那里该是 E。
      final slot0 = tester.getCenter(find.byKey(const ValueKey('slot-0')));
      final source = trayTile(tester, 'T');
      await tester.drag(source, slot0 - tester.getCenter(source));
      await tester.pump();

      // 它去了自己的位置（Emmett 的 4 号槽），托盘少了一块。
      expect(trayIds(tester).length, 5);
      // **没有任何失败信号**：没有回位音、没有分裂音。
      expect(audio.sfx, isNot(contains('return')));
      expect(audio.sfx, isNot(contains('split')));
    });

    testWidgets('全部拼完 → 念出这个名字', (tester) async {
      await pumpName(tester);
      audio.spoken.clear();

      for (final l in ['E', 'M', 'M', 'E', 'T', 'T']) {
        await tapTile(tester, l);
      }
      await tester.pump();

      expect(trayIds(tester), isEmpty);
      // 终关的奖励就是听见自己的名字。
      expect(audio.spoken.last, 'en.name.child');

      final next = tester.widget<RoundActionButton>(
        find.byKey(const ValueKey('next')),
      );
      expect(next.highlighted, isTrue);
    });
  });

  group('收回与复位', () {
    testWidgets('点槽里的积木把它拿回托盘', (tester) async {
      await pumpName(tester);
      await tapTile(tester, 'E');
      expect(trayIds(tester).length, 5);

      await tester.tap(find.byKey(const ValueKey('slot-0')));
      await tester.pump();

      expect(trayIds(tester).length, 6);
    });

    testWidgets('重来把全部积木收回托盘', (tester) async {
      await pumpName(tester);
      await tapTile(tester, 'E');
      await tapTile(tester, 'M');

      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pump();

      expect(trayIds(tester).length, 6);
    });

    testWidgets('下一关换目标，走到头绕回第一关', (tester) async {
      await pumpName(tester);
      expect(find.byKey(const ValueKey('slot-5')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 300));
      // 第二个目标是 Mem，3 个槽。
      expect(find.byKey(const ValueKey('slot-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-3')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('slot-5')), findsOneWidget);
    });

    testWidgets('玩法切换回 A is for Apple', (tester) async {
      await pumpName(tester);
      await tester.tap(find.byKey(const ValueKey('mode')));
      await tester.pumpAndSettle();
      expect(find.byType(LettersPage), findsOneWidget);
    });
  });

  group('降级与红线', () {
    testWidgets('内容包里没有拼字目标时静默留白，不弹文字', (tester) async {
      audio = RecordingAudioBus();
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioBusProvider.overrideWithValue(audio),
            contentLibraryProvider.overrideWithValue(const ContentLibrary([])),
          ],
          child: const MaterialApp(home: NamePage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('托盘块与按钮都不小于 90dp', (tester) async {
      await pumpName(tester);
      for (final id in trayIds(tester)) {
        expect(
          tester.getSize(find.byKey(ValueKey('tile-$id'))).shortestSide,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
        );
      }
      for (final tile in tester.widgetList<PressableTile>(
        find.byType(PressableTile),
      )) {
        expect(
          tester.getSize(find.byWidget(tile)).shortestSide,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
        );
      }
    });
  });
}
