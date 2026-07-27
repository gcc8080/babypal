import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/letters/case_match_page.dart';
import 'package:baby_pal/modules/letters/letter_tile.dart';
import 'package:baby_pal/modules/letters/name_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

const Size _phone = Size(738, 393);

ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "letters": [
    {"letter": "A", "voiceKey": "en.letter.a", "phonemeVoiceKey": "en.phoneme.a"},
    {"letter": "B", "voiceKey": "en.letter.b", "phonemeVoiceKey": "en.phoneme.b"},
    {"letter": "C", "voiceKey": "en.letter.c", "phonemeVoiceKey": "en.phoneme.c"},
    {"letter": "D", "voiceKey": "en.letter.d", "phonemeVoiceKey": "en.phoneme.d"}
  ],
  "spellingTargets": [
    {"id": "child", "letters": "Ab", "voiceKey": "en.name.child"}
  ]
}
''', source: 'letters.json')!,
]);

void main() {
  late RecordingAudioBus audio;

  Future<void> pumpCase(WidgetTester tester) async {
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
        child: const MaterialApp(home: CaseMatchPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 某个大写槽当前显示的字形。配好或演示中会变成「Aa」。
  String glyphOf(WidgetTester tester, String letter) => tester
      .widget<LetterTile>(
        find.descendant(
          of: find.byKey(ValueKey('upper-$letter')),
          matching: find.byType(LetterTile),
        ),
      )
      .letter;

  Future<void> match(WidgetTester tester, String lower, String upper) async {
    await tester.tap(find.byKey(ValueKey('lower-$lower')));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('upper-$upper')));
    await tester.pump();
  }

  group('正确配对', () {
    testWidgets('小写 a 配到大写 A → 合并并庆祝', (tester) async {
      await pumpCase(tester);
      audio.sfx.clear();

      await match(tester, 'A', 'A');

      expect(glyphOf(tester, 'A'), 'Aa');
      expect(audio.sfx, contains('merge'));
      // 配好的小写从托盘里消失。
      expect(find.byKey(const ValueKey('lower-A')), findsNothing);
    });

    testWidgets('三对全配好后「下一轮」点亮', (tester) async {
      await pumpCase(tester);

      for (final l in ['A', 'B', 'C']) {
        await match(tester, l, l);
      }

      final next = tester.widget<RoundActionButton>(
        find.byKey(const ValueKey('next')),
      );
      expect(next.highlighted, isTrue);
      expect(glyphOf(tester, 'C'), 'Cc');
    });
  });

  group('配错：演示正确配对，不做任何错误标记', () {
    testWidgets('规格场景：小写 b 拖到大写 A 上', (tester) async {
      await pumpCase(tester);
      audio.sfx.clear();

      await match(tester, 'B', 'A');

      // A 自己把 a 请过来配好——他看见的是示范，不是判错。
      expect(glyphOf(tester, 'A'), 'Aa');
      // 音效是「啪，配好了」那一族，不是失败音。
      expect(audio.sfx, isNot(contains('return')));
      expect(audio.sfx, isNot(contains('split')));
      // b 原样留在托盘里，可以马上再试。
      expect(find.byKey(const ValueKey('lower-B')), findsOneWidget);
    });

    testWidgets('演示结束后自动复位，不留任何痕迹', (tester) async {
      await pumpCase(tester);
      await match(tester, 'B', 'A');
      expect(glyphOf(tester, 'A'), 'Aa');

      await tester.pump(kCaseDemoHold);
      await tester.pump();

      // 回到未配对的样子，A 还等着他。
      expect(glyphOf(tester, 'A'), 'A');
      expect(find.byKey(const ValueKey('lower-A')), findsOneWidget);
    });

    testWidgets('配错任意多次都不留痕迹，之后照样能配对成功', (tester) async {
      await pumpCase(tester);

      for (var i = 0; i < 4; i++) {
        await match(tester, 'B', 'A');
        await tester.pump(kCaseDemoHold);
        await tester.pump();
      }
      // 没有计数、没有变灰、没有任何「你错了 4 次」的痕迹。
      expect(glyphOf(tester, 'A'), 'A');

      await match(tester, 'A', 'A');
      expect(glyphOf(tester, 'A'), 'Aa');
    });
  });

  group('双通道', () {
    testWidgets('点两下完成：先点小写再点大写', (tester) async {
      await pumpCase(tester);
      await match(tester, 'B', 'B');
      expect(glyphOf(tester, 'B'), 'Bb');
    });

    testWidgets('没选中小写时点大写只是听读音，不算一次尝试', (tester) async {
      await pumpCase(tester);
      audio.spoken.clear();

      await tester.tap(find.byKey(const ValueKey('upper-A')));
      await tester.pump();

      expect(audio.spoken, ['en.letter.a', 'en.phoneme.a']);
      // 没有被演示，也没有被配对——什么都没发生过。
      expect(glyphOf(tester, 'A'), 'A');
    });

    testWidgets('拖拽通道：把小写拖到大写上', (tester) async {
      await pumpCase(tester);

      await tester.drag(
        find.byKey(const ValueKey('lower-C')),
        tester.getCenter(find.byKey(const ValueKey('upper-C'))) -
            tester.getCenter(find.byKey(const ValueKey('lower-C'))),
      );
      await tester.pump();

      expect(glyphOf(tester, 'C'), 'Cc');
    });
  });

  group('翻轮与切换', () {
    testWidgets('下一轮换一批字母并复位', (tester) async {
      await pumpCase(tester);
      await match(tester, 'A', 'A');

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 300));

      // 本例 4 个字母、每轮 3 个 → 第二轮只剩 D。
      expect(find.byKey(const ValueKey('upper-D')), findsOneWidget);
      expect(find.byKey(const ValueKey('upper-A')), findsNothing);
    });

    testWidgets('玩法切换到拼名字', (tester) async {
      await pumpCase(tester);
      await tester.tap(find.byKey(const ValueKey('mode')));
      await tester.pumpAndSettle();

      expect(find.byType(NamePage), findsOneWidget);
    });
  });

  group('触控红线', () {
    testWidgets('小写托盘块与按钮都不小于 90dp', (tester) async {
      await pumpCase(tester);

      for (final key in ['lower-A', 'lower-B', 'lower-C']) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(
          size.shortestSide,
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

    testWidgets('大写落位区撑满上半屏', (tester) async {
      await pumpCase(tester);
      final upper = tester.getSize(find.byKey(const ValueKey('upper-A')));
      expect(upper.height, greaterThan(BlockMetrics.minGrabTarget * 1.5));
      expect(upper.width, greaterThan(BlockMetrics.minGrabTarget));
    });
  });
}
