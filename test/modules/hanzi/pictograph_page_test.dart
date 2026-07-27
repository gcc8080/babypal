import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/glyph_tile.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/hanzi/component_page.dart';
import 'package:baby_pal/modules/hanzi/hanzi.dart';
import 'package:baby_pal/modules/hanzi/pictograph_page.dart';
import 'package:baby_pal/modules/hanzi/pictograph_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

const Size _phone = Size(738, 393);

/// 三个象形字 + 一个没配图形的字 + 一个合体字。
///
/// 「云」是**故意**没有 `imageKey` 的：明年往内容包里加字时必然出现这种情况，
/// 那时应该少一段动画而不是崩掉。
ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "hanzi": [
    {"char": "山", "pinyin": "shān", "type": "pictograph", "imageKey": "mountain",
     "voiceKey": "zh.hanzi.shan"},
    {"char": "木", "pinyin": "mù", "type": "pictograph", "imageKey": "tree",
     "voiceKey": "zh.hanzi.mu"},
    {"char": "日", "pinyin": "rì", "type": "pictograph", "imageKey": "sun",
     "voiceKey": "zh.hanzi.ri"},
    {"char": "云", "pinyin": "yún", "type": "pictograph",
     "voiceKey": "zh.hanzi.yun"},
    {"char": "林", "pinyin": "lín", "type": "compound", "parts": ["木", "木"],
     "voiceKey": "zh.hanzi.lin"}
  ]
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
          home: const PictographPage(),
        ),
      ),
    );
    await tester.pump();
  }

  PictographView view(WidgetTester tester) =>
      tester.widget<PictographView>(find.byType(PictographView));

  group('只演象形字', () {
    testWidgets('合体字不在这一关里——它属于部件加法', (tester) async {
      await pumpPage(tester);
      expect(view(tester).char, '山');

      // 四个象形字轮一圈就该回到「山」，「林」一次都不该出现。
      final seen = <String>[];
      for (var i = 0; i < 4; i++) {
        seen.add(view(tester).char);
        await tester.tap(find.byKey(const ValueKey('next')));
        await tester.pump();
      }
      expect(seen, ['山', '木', '日', '云']);
      expect(view(tester).char, '山');
    });
  });

  group('播放与重播', () {
    testWidgets('进页面就自己演一遍并念出读音', (tester) async {
      await pumpPage(tester);
      await tester.pump();

      expect(audio.spoken, ['zh.hanzi.shan']);
      expect(view(tester).progress, lessThan(1.0), reason: '动画应该正在走');
    });

    testWidgets('演完停在字形上', (tester) async {
      await pumpPage(tester);
      await tester.pump(kMorphDuration);
      await tester.pump();

      expect(view(tester).progress, 1.0);
    });

    testWidgets('规格场景：再点一次，动画从头重播', (tester) async {
      await pumpPage(tester);
      await tester.pump(kMorphDuration);
      expect(view(tester).progress, 1.0);

      await tester.tap(find.byKey(const ValueKey('picture')));
      await tester.pump();

      // **从头**——不是「已经播过了所以不播」。
      expect(view(tester).progress, lessThan(0.1));
      expect(audio.spoken.last, 'zh.hanzi.shan');
      await tester.pumpAndSettle();
    });

    testWidgets('重播键与点画面是同一条路径', (tester) async {
      await pumpPage(tester);
      await tester.pump(kMorphDuration);

      await tester.tap(find.byKey(const ValueKey('replay')));
      await tester.pump();

      expect(view(tester).progress, lessThan(0.1));
      await tester.pumpAndSettle();
    });
  });

  group('翻字', () {
    testWidgets('点右侧邻居跳到下一个字并重新演', (tester) async {
      await pumpPage(tester);
      await tester.pump(kMorphDuration);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pump();

      expect(view(tester).char, '木');
      expect(view(tester).progress, lessThan(0.1));
      expect(audio.spoken.last, 'zh.hanzi.mu');
      await tester.pumpAndSettle();
    });

    testWidgets('点左侧邻居往回翻，第一个字往回是最后一个', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const ValueKey('prev')));
      await tester.pump();

      // 绕回而不是禁用：一个按不动的东西对他就是「坏了」。
      expect(view(tester).char, '云');
      await tester.pumpAndSettle();
    });

    testWidgets('两侧邻居显示的正是上一个和下一个字', (tester) async {
      await pumpPage(tester);

      expect(
        tester
            .widget<GlyphTile>(
              find.descendant(
                of: find.byKey(const ValueKey('prev')),
                matching: find.byType(GlyphTile),
              ),
            )
            .glyph,
        '云',
      );
      expect(
        tester
            .widget<GlyphTile>(
              find.descendant(
                of: find.byKey(const ValueKey('next')),
                matching: find.byType(GlyphTile),
              ),
            )
            .glyph,
        '木',
      );
      await tester.pumpAndSettle();
    });
  });

  group('降级与红线', () {
    testWidgets('没配图形的字直接显示字形，不崩也不空白', (tester) async {
      await pumpPage(tester);
      // 翻到「云」——它没有 imageKey。
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('next')));
        await tester.pump();
      }
      expect(view(tester).char, '云');
      expect(view(tester).imageKey, isNull);

      await tester.pump();
      expect(tester.takeException(), isNull);
      // 没有渐变可言时字形就该直接在那儿。
      expect(find.text('云'), findsWidgets);
      await tester.pumpAndSettle();
    });

    testWidgets('内容包读不到时静默留白，不弹文字', (tester) async {
      await pumpPage(tester, library: const ContentLibrary([]));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('邻居块与按钮都不小于 90dp', (tester) async {
      await pumpPage(tester);
      for (final id in ['prev', 'next']) {
        expect(
          tester.getSize(find.byKey(ValueKey(id))).shortestSide,
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
      await tester.pumpAndSettle();
    });

    testWidgets('玩法切换到部件加法', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('mode')));
      await tester.pumpAndSettle();
      expect(find.byType(ComponentPage), findsOneWidget);
    });
  });
}
