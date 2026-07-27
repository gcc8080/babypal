import 'package:baby_pal/core/audio/audio_bus.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/models.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/letters/letters.dart';
import 'package:baby_pal/modules/letters/letters_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

/// 交付设备 MI 8 SE 横屏的逻辑尺寸。
const Size _phone = Size(738, 393);

ContentLibrary _library() {
  const loader = PackLoader();
  final letters = loader.parse('''
{
  "schemaVersion": 1,
  "letters": [
    {"letter": "A", "voiceKey": "en.letter.a",
     "phonemeVoiceKey": "en.phoneme.a",
     "wordNounIds": ["apple", "ant", "airplane"]},
    {"letter": "B", "voiceKey": "en.letter.b",
     "phonemeVoiceKey": "en.phoneme.b",
     "wordNounIds": ["banana"]}
  ]
}
''', source: 'letters.json')!;
  final nouns = loader.parse('''
{
  "schemaVersion": 1,
  "nouns": [
    {"id": "apple", "category": "fruit", "iconKey": "1F34E", "text": "苹果",
     "textEn": "apple", "voiceKey": "zh.noun.apple", "voiceKeyEn": "en.noun.apple"},
    {"id": "ant", "category": "animal", "iconKey": "1F41C", "text": "蚂蚁",
     "textEn": "ant", "voiceKey": "zh.noun.ant", "voiceKeyEn": "en.noun.ant"},
    {"id": "airplane", "category": "vehicle", "iconKey": "2708", "text": "飞机",
     "textEn": "airplane", "voiceKey": "zh.noun.airplane",
     "voiceKeyEn": "en.noun.airplane"},
    {"id": "banana", "category": "fruit", "iconKey": "1F34C", "text": "香蕉",
     "textEn": "banana", "voiceKey": "zh.noun.banana",
     "voiceKeyEn": "en.noun.banana"}
  ]
}
''', source: 'nouns.json')!;
  return ContentLibrary([letters, nouns]);
}

void main() {
  late RecordingAudioBus audio;

  Future<void> pumpLetters(WidgetTester tester, {Size size = _phone}) async {
    audio = RecordingAudioBus();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioBusProvider.overrideWithValue(audio),
          contentLibraryProvider.overrideWithValue(_library()),
        ],
        child: const MaterialApp(home: LettersPage()),
      ),
    );
    // 进页面的自动演示挂在 postFrameCallback 上。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
  }

  group('字母名与音素分别播报', () {
    testWidgets('点击字母积木先报字母名、再报音素，是两条独立的语音', (tester) async {
      await pumpLetters(tester);
      audio.spoken.clear();

      await tester.tap(find.byKey(const ValueKey('letter')));
      await tester.pump();

      // 两条键，顺序固定。合并成一条音频就会只剩一个键——规格明确禁止。
      expect(audio.spoken, ['en.letter.a', 'en.phoneme.a']);
    });

    testWidgets('每个字母都有独立的音素键，不是共用一条', (tester) async {
      await pumpLetters(tester);
      audio.spoken.clear();

      await tester.tap(find.byKey(const ValueKey('letter')));
      await tester.pump();
      final first = List<String>.from(audio.spoken);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 1200));
      audio.spoken.clear();
      await tester.tap(find.byKey(const ValueKey('letter')));
      await tester.pump();

      expect(first, ['en.letter.a', 'en.phoneme.a']);
      expect(audio.spoken, ['en.letter.b', 'en.phoneme.b']);
    });
  });

  group('A is for Apple 交互版', () {
    testWidgets('选中字母后飞入该字母的全部名词卡', (tester) async {
      await pumpLetters(tester);

      expect(find.byKey(const ValueKey('word-apple')), findsOneWidget);
      expect(find.byKey(const ValueKey('word-ant')), findsOneWidget);
      expect(find.byKey(const ValueKey('word-airplane')), findsOneWidget);
    });

    testWidgets('进页面即演示：字母名 → 音素 → 三张卡各报英文名', (tester) async {
      await pumpLetters(tester);

      expect(audio.spoken, [
        'en.letter.a',
        'en.phoneme.a',
        'en.noun.apple',
        'en.noun.ant',
        'en.noun.airplane',
      ]);
    });

    testWidgets('点哪张卡都一样：三张的反馈完全一致', (tester) async {
      await pumpLetters(tester);

      // 规格「点击任意图片 → 三张图行为一致」。逐张点过去，比对反馈形状。
      final results = <String, List<String>>{};
      for (final id in ['apple', 'ant', 'airplane']) {
        audio.spoken.clear();
        audio.sfx.clear();
        await tester.tap(find.byKey(ValueKey('word-$id')));
        await tester.pump();
        results[id] = [...audio.sfx, ...audio.spoken];
        // 等庆祝结束，免得下一次点击落在放大中的卡片上。
        await tester.pump(const Duration(milliseconds: 1000));
      }

      // 三张卡的音效相同、播报结构相同（中文键 + 英文键），
      // 没有任何一张走了不同的分支。
      for (final id in ['apple', 'ant', 'airplane']) {
        expect(
          results[id]!.first,
          results['apple']!.first,
          reason: '$id 音效不一致',
        );
        expect(results[id]!.length, 3, reason: '$id 播报条数不一致');
        expect(results[id]![1], 'zh.noun.$id');
        expect(results[id]![2], 'en.noun.$id');
      }
    });
  });

  group('翻页', () {
    testWidgets('到表尾按下一个绕回表头，不出现按不动的按钮', (tester) async {
      await pumpLetters(tester);

      // 本例的字母表只有 A、B 两个。
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byKey(const ValueKey('word-banana')), findsOneWidget);

      audio.spoken.clear();
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump(const Duration(milliseconds: 1200));

      // 绕回 A：一个按不动的按钮对三岁的他是「坏了」。
      expect(audio.spoken.first, 'en.letter.a');
      expect(find.byKey(const ValueKey('word-apple')), findsOneWidget);
    });

    testWidgets('上一个从表头绕到表尾', (tester) async {
      await pumpLetters(tester);
      audio.spoken.clear();

      await tester.tap(find.byKey(const ValueKey('prev')));
      await tester.pump(const Duration(milliseconds: 1200));

      expect(audio.spoken.first, 'en.letter.b');
    });
  });

  group('触控红线', () {
    testWidgets('名词卡与全部按钮都不小于 90dp', (tester) async {
      await pumpLetters(tester);

      // 直接量渲染后的实际尺寸。**量外层容器不等于量内容**——托盘缩略图
      // 那次真机 bug 就是外层一直对、里面塌成 0（见 piece_glyph_test）。
      // 这里量的是 PressableTile 本身，因为卡片的可点区域就是它。
      for (final tile in tester.widgetList<PressableTile>(
        find.byType(PressableTile),
      )) {
        final size = tester.getSize(find.byWidget(tile));
        expect(
          size.shortestSide,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
          reason: '可点元素 ${size.width}×${size.height} 击穿了 90dp 抓取阈值',
        );
      }
    });

    testWidgets('名词卡撑满上半屏而不是缩在 90dp', (tester) async {
      await pumpLetters(tester);

      // expand=true 依赖父级给紧约束。父级哪天改回默认的 center 对齐，
      // 卡片会直接塌成 0——那是真机才看得见、测试却全绿的失败模式。
      final card = tester.getSize(find.byKey(const ValueKey('word-apple')));
      expect(card.height, greaterThan(BlockMetrics.minGrabTarget * 1.5));
    });
  });

  group('内容缺失时的降级', () {
    testWidgets('空内容库不崩、不弹任何文字', (tester) async {
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
          child: const MaterialApp(home: LettersPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNothing);
      // 按钮照常在，按下去也不该炸。
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('翻页索引', () {
    test('绕回而不是卡在两端', () {
      expect(nextLetterIndex(25, 26), 0);
      expect(nextLetterIndex(0, 26, forward: false), 25);
      expect(nextLetterIndex(3, 26), 4);
      // 空表不该算出负数下标。
      expect(nextLetterIndex(0, 0), 0);
    });
  });
}
