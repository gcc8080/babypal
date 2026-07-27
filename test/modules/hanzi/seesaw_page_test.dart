import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/glyph_tile.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/hanzi/hanzi.dart';
import 'package:baby_pal/modules/hanzi/pictograph_page.dart';
import 'package:baby_pal/modules/hanzi/seesaw_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

const Size _phone = Size(738, 393);

/// 配对数据**来自内容包**——规格对 6.4 的硬要求。这里刻意只放三对，
/// 且顺序与真实内容包不同，用来证明页面读的是数据而不是常量。
ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "hanzi": [
    {"char": "大", "pinyin": "dà", "type": "simple", "voiceKey": "zh.hanzi.da"},
    {"char": "小", "pinyin": "xiǎo", "type": "simple", "voiceKey": "zh.hanzi.xiao"},
    {"char": "多", "pinyin": "duō", "type": "simple", "voiceKey": "zh.hanzi.duo"},
    {"char": "少", "pinyin": "shǎo", "type": "simple", "voiceKey": "zh.hanzi.shao"},
    {"char": "前", "pinyin": "qián", "type": "simple", "voiceKey": "zh.hanzi.qian"},
    {"char": "后", "pinyin": "hòu", "type": "simple", "voiceKey": "zh.hanzi.hou"}
  ],
  "antonyms": [["大", "小"], ["多", "少"], ["前", "后"]]
}
''', source: 'hanzi.json')!,
]);

void main() {
  late RecordingAudioBus audio;

  Future<void> pumpPage(WidgetTester tester, {ContentLibrary? library}) async {
    audio = RecordingAudioBus();
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioBusProvider.overrideWithValue(audio),
          contentLibraryProvider.overrideWithValue(library ?? _library()),
        ],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: const SeesawPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 右座上现在坐着哪个字，空着则为 null。
  String? seated(WidgetTester tester) {
    final tiles = tester.widgetList<GlyphTile>(
      find.descendant(
        of: find.byKey(const ValueKey('seat')),
        matching: find.byType(GlyphTile),
      ),
    );
    return tiles.isEmpty ? null : tiles.first.glyph;
  }

  Future<void> place(WidgetTester tester, String char) async {
    await tester.tap(find.byKey(ValueKey('choice-$char')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('seat')));
    await tester.pump();
  }

  group('题目来自内容包', () {
    testWidgets('左座是题面，托盘里有正确答案', (tester) async {
      await pumpPage(tester);

      final prompt = tester.widget<GlyphTile>(
        find.byKey(const ValueKey('prompt')),
      );
      expect(prompt.glyph, '大');
      expect(find.byKey(const ValueKey('choice-小')), findsOneWidget);
    });

    testWidgets('干扰项取自别的反义词对，不是随便找的字', (tester) async {
      await pumpPage(tester);
      // 他要做的判断因此是「哪个跟大是一对」，不是「哪个字我认识」。
      final choices = tester
          .widgetList<GlyphTile>(find.byType(GlyphTile))
          .map((t) => t.glyph)
          .toSet();
      expect(choices.contains('小'), isTrue);
      expect(
        choices.intersection({'多', '少', '前', '后'}),
        isNotEmpty,
        reason: '干扰项应来自其他反义词对',
      );
    });

    testWidgets('下一对换题，走到头绕回第一对', (tester) async {
      await pumpPage(tester);
      expect(
        tester.widget<GlyphTile>(find.byKey(const ValueKey('prompt'))).glyph,
        '大',
      );

      for (final expected in ['多', '前', '大']) {
        await tester.tap(find.byKey(const ValueKey('next')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<GlyphTile>(find.byKey(const ValueKey('prompt'))).glyph,
          expected,
        );
      }
    });
  });

  group('正确配对', () {
    testWidgets('规格场景：把「小」放到「大」的对侧 → 平衡、播报两个字', (tester) async {
      await pumpPage(tester);
      audio.spoken.clear();

      await place(tester, '小');

      expect(seated(tester), '小');
      expect(audio.spoken, ['zh.hanzi.da', 'zh.hanzi.xiao']);
      expect(audio.sfx, contains('merge'));
    });

    testWidgets('配好之后下一关键点亮，且那块从托盘里消失', (tester) async {
      await pumpPage(tester);
      await place(tester, '小');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('choice-小')), findsNothing);
      final next = tester.widget<RoundActionButton>(
        find.byKey(const ValueKey('next')),
      );
      expect(next.highlighted, isTrue);
    });

    testWidgets('拖拽通道也能放', (tester) async {
      await pumpPage(tester);

      final source = find.byKey(const ValueKey('choice-小'));
      final seat = find.byKey(const ValueKey('seat'));
      await tester.drag(
        source,
        tester.getCenter(seat) - tester.getCenter(source),
      );
      await tester.pumpAndSettle();

      expect(seated(tester), '小');
    });
  });

  group('配错只是演示，不是判错', () {
    testWidgets('规格场景：放错 → 演示正确答案，没有红叉也没有失败音', (tester) async {
      await pumpPage(tester);
      audio.sfx.clear();
      audio.spoken.clear();

      await place(tester, '多');

      // 系统把「小」请上来配好给他看。
      expect(seated(tester), '小');
      expect(audio.spoken, ['zh.hanzi.da', 'zh.hanzi.xiao']);
      // 「啪，配好了」，和配对成功同一族的声音，只是没有庆祝的那一下。
      expect(audio.sfx, contains('snap'));
      expect(audio.sfx, isNot(contains('return')));
      expect(audio.sfx, isNot(contains('split')));
    });

    testWidgets('他放错的那块原样留在托盘里，可以立刻再试', (tester) async {
      await pumpPage(tester);
      await place(tester, '多');

      expect(find.byKey(const ValueKey('choice-多')), findsOneWidget);
    });

    testWidgets('演示停留 1.8 秒后自己收回，这一关没有被判过', (tester) async {
      await pumpPage(tester);
      await place(tester, '多');
      expect(seated(tester), '小');

      await tester.pump(kSeesawDemoHold);
      await tester.pumpAndSettle();

      expect(seated(tester), isNull, reason: '演示完该原样退回，不留痕迹');
      final next = tester.widget<RoundActionButton>(
        find.byKey(const ValueKey('next')),
      );
      expect(next.highlighted, isFalse, reason: '演示不等于通关');
    });

    testWidgets('演示之后再放对，照样算成功', (tester) async {
      await pumpPage(tester);
      await place(tester, '多');
      await tester.pump(kSeesawDemoHold);
      await tester.pumpAndSettle();

      await place(tester, '小');
      await tester.pumpAndSettle();

      expect(seated(tester), '小');
      expect(find.byKey(const ValueKey('choice-小')), findsNothing);
    });
  });

  group('不算尝试的那些点击', () {
    testWidgets('没选中候选时点右座，只是重听题面', (tester) async {
      await pumpPage(tester);
      audio.spoken.clear();

      await tester.tap(find.byKey(const ValueKey('seat')));
      await tester.pump();

      expect(seated(tester), isNull, reason: '不该触发演示');
      expect(audio.spoken, ['zh.hanzi.da']);
    });

    testWidgets('点左座重听题面', (tester) async {
      await pumpPage(tester);
      audio.spoken.clear();

      await tester.tap(find.byKey(const ValueKey('prompt')));
      await tester.pump();

      expect(audio.spoken, ['zh.hanzi.da']);
    });
  });

  group('降级与红线', () {
    testWidgets('内容包里没有反义词时静默留白，不弹文字', (tester) async {
      await pumpPage(tester, library: const ContentLibrary([]));

      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('托盘里可按的东西都不小于 90dp', (tester) async {
      await pumpPage(tester);
      for (final tile in tester.widgetList<PressableTile>(
        find.byType(PressableTile),
      )) {
        expect(
          tester.getSize(find.byWidget(tile)).shortestSide,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
        );
      }
      for (final char in ['小', '多', '少']) {
        final finder = find.byKey(ValueKey('choice-$char'));
        if (finder.evaluate().isEmpty) continue;
        expect(
          tester.getSize(finder).shortestSide,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
        );
      }
    });

    testWidgets('座位是放置区，不低于 60dp', (tester) async {
      await pumpPage(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey('seat'))).shortestSide,
        greaterThanOrEqualTo(BlockMetrics.minDropZone),
      );
    });

    testWidgets('玩法切换回象形动画', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('mode')));
      await tester.pumpAndSettle();
      expect(find.byType(PictographPage), findsOneWidget);
    });
  });
}
