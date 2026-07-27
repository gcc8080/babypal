import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/letters/case_match_page.dart';
import 'package:baby_pal/modules/letters/letters_page.dart';
import 'package:baby_pal/modules/letters/name_page.dart';
import 'package:baby_pal/modules/letters/outline_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

/// 字母模块四个玩法在各种屏幕上的布局兜底。
///
/// **这条用例是被一个真 bug 逼出来的**：拼名字页最初把 6 块字母积木和 3 个
/// 按钮塞进同一行——540 + 270 + 间距 = 874dp，而交付机横屏只有 738dp，
/// 直接溢出 152dp。三样东西一样都不能让步（90dp 是抓取红线，按钮一个都不能
/// 少），只能改成字母单独占一行。
///
/// 溢出在 `flutter test` 里会抛异常，所以「把每个页面在每种屏幕上 pump 一遍」
/// 就是一条真能抓 bug 的用例。**别的模块也该有**——这次是名字长了一位就爆，
/// 而名字是内容包可配的。
void main() {
  /// 交付机 MI 8 SE、更窄的小屏、以及平板。
  const sizes = <String, Size>{
    'MI 8 SE 横屏': Size(738, 393),
    '窄屏（缩放下限）': Size(640, 360),
    '平板横屏': Size(1024, 768),
  };

  ContentLibrary library() => ContentLibrary([
    const PackLoader().parse('''
{
  "schemaVersion": 1,
  "letters": [
    {"letter": "M", "voiceKey": "en.letter.m", "phonemeVoiceKey": "en.phoneme.m",
     "wordNounIds": ["monkey", "moon", "milk"]},
    {"letter": "W", "voiceKey": "en.letter.w", "phonemeVoiceKey": "en.phoneme.w",
     "wordNounIds": ["whale"]},
    {"letter": "E", "voiceKey": "en.letter.e", "phonemeVoiceKey": "en.phoneme.e"},
    {"letter": "T", "voiceKey": "en.letter.t", "phonemeVoiceKey": "en.phoneme.t"}
  ],
  "spellingTargets": [
    {"id": "child", "letters": "Emmett", "voiceKey": "en.name.child"}
  ]
}
''', source: 'letters.json')!,
    const PackLoader().parse('''
{
  "schemaVersion": 1,
  "nouns": [
    {"id": "monkey", "category": "animal", "iconKey": "1F412", "text": "猴子",
     "textEn": "monkey", "voiceKey": "zh.noun.monkey", "voiceKeyEn": "en.noun.monkey"},
    {"id": "moon", "category": "nature", "iconKey": "1F319", "text": "月亮",
     "textEn": "moon", "voiceKey": "zh.noun.moon", "voiceKeyEn": "en.noun.moon"},
    {"id": "milk", "category": "food", "iconKey": "1F95B", "text": "牛奶",
     "textEn": "milk", "voiceKey": "zh.noun.milk", "voiceKeyEn": "en.noun.milk"},
    {"id": "whale", "category": "animal", "iconKey": "1F433", "text": "鲸鱼",
     "textEn": "whale", "voiceKey": "zh.noun.whale", "voiceKeyEn": "en.noun.whale"}
  ]
}
''', source: 'nouns.json')!,
  ]);

  final pages = <String, Widget>{
    'A is for Apple': const LettersPage(),
    '轮廓填充': const OutlinePage(),
    '大小写配对': const CaseMatchPage(),
    '拼名字': const NamePage(),
  };

  for (final page in pages.entries) {
    for (final size in sizes.entries) {
      testWidgets('${page.key} 在${size.key}上不溢出', (tester) async {
        tester.view.physicalSize = size.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              audioBusProvider.overrideWithValue(RecordingAudioBus()),
              contentLibraryProvider.overrideWithValue(library()),
            ],
            child: MaterialApp(home: page.value),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        // RenderFlex 溢出在测试里会抛异常，pump 一遍就是断言。
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.key} 在 ${size.value.width}×${size.value.height} 上溢出了',
        );

        // 同时把抓取红线也验一遍：小屏是最容易击穿它的地方。
        for (final tile in tester.widgetList<PressableTile>(
          find.byType(PressableTile),
        )) {
          expect(
            tester.getSize(find.byWidget(tile)).shortestSide,
            greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
            reason: '${page.key} 在${size.key}上有元素击穿了 90dp',
          );
        }
      });
    }
  }
}
