import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/block/block_widget.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/hanzi/component_page.dart';
import 'package:baby_pal/modules/hanzi/seesaw_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

const Size _phone = Size(738, 393);

/// 第一题是「林 = 木 + 木」，第二题是「森 = 木 + 木 + 木」，第三题是
/// 「明 = 日 + 月」。刻意与真实内容包排序不同，用来证明页面读的是数据。
ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "hanzi": [
    {"char": "木", "pinyin": "mù", "type": "pictograph", "imageKey": "tree",
     "voiceKey": "zh.hanzi.mu"},
    {"char": "日", "pinyin": "rì", "type": "pictograph", "imageKey": "sun",
     "voiceKey": "zh.hanzi.ri"},
    {"char": "月", "pinyin": "yuè", "type": "pictograph", "imageKey": "moon",
     "voiceKey": "zh.hanzi.yue"},
    {"char": "林", "pinyin": "lín", "type": "compound", "parts": ["木", "木"],
     "voiceKey": "zh.hanzi.lin"},
    {"char": "森", "pinyin": "sēn", "type": "compound",
     "parts": ["木", "木", "木"], "voiceKey": "zh.hanzi.sen"},
    {"char": "明", "pinyin": "míng", "type": "compound", "parts": ["日", "月"],
     "voiceKey": "zh.hanzi.ming"}
  ]
}
''', source: 'hanzi.json')!,
]);

void main() {
  late RecordingAudioBus audio;

  Future<void> pumpPage(WidgetTester tester) async {
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
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: const ComponentPage(),
        ),
      ),
    );
    await tester.pump();
  }

  List<BlockWidget> blocks(WidgetTester tester) =>
      tester.widgetList<BlockWidget>(find.byType(BlockWidget)).toList();

  List<String?> labels(WidgetTester tester) =>
      blocks(tester).map((w) => w.body.label).toList();

  /// 台面上第 [skip] 块写着 [char] 的积木。
  ///
  /// 必须能按序号取：一题里的两个部件常常是**同一个字**（木+木），只按字找
  /// 会两次都拿到同一块，于是「点 A 再点 B」变成了「同一块点两下」——那是
  /// 取消选中，不是合体。
  Finder blockOf(WidgetTester tester, String char, {int skip = 0}) {
    final matches = blocks(tester).where((w) => w.body.label == char).toList();
    if (matches.length <= skip) fail('台面上没有第 ${skip + 1} 块「$char」');
    return find.byWidget(matches[skip]);
  }

  /// 点选通道合体：点 a，再点 b。
  Future<void> tapMerge(WidgetTester tester, String a, String b) async {
    await tester.tap(blockOf(tester, a));
    await tester.pump();
    await tester.tap(blockOf(tester, b, skip: a == b ? 1 : 0));
    await tester.pumpAndSettle();
  }

  group('题目来自内容包', () {
    testWidgets('开局摆出目标字的部件，两两不相邻', (tester) async {
      await pumpPage(tester);

      expect(labels(tester), ['木', '木']);
      // **绝不能一开局就挨着**，否则它们自己就合了，等于替他做完了。
      final cols = blocks(tester).map((w) => w.body.anchor!.col).toList()
        ..sort();
      expect(cols[1] - cols[0], greaterThanOrEqualTo(2));
    });

    testWidgets('下一题换目标，走到头绕回第一题', (tester) async {
      await pumpPage(tester);
      expect(labels(tester), ['木', '木']);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      expect(labels(tester), ['木', '木', '木']);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      expect(labels(tester), ['日', '月']);

      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      expect(labels(tester), ['木', '木']);
    });

    testWidgets('出题只念部件，不念答案', (tester) async {
      await pumpPage(tester);
      await tester.pump();

      expect(audio.spoken, isNot(contains('zh.hanzi.lin')));
      expect(audio.spoken, contains('zh.hanzi.mu'));
    });
  });

  group('合体', () {
    testWidgets('点选通道：木 + 木 = 林', (tester) async {
      await pumpPage(tester);
      await tapMerge(tester, '木', '木');

      expect(labels(tester), ['林']);
    });

    testWidgets('合成时念出算式「木 加 木 等于 林」', (tester) async {
      await pumpPage(tester);
      audio.spoken.clear();
      await tapMerge(tester, '木', '木');

      expect(audio.spoken, [
        'zh.hanzi.mu',
        'zh.word.plus',
        'zh.hanzi.mu',
        'zh.word.equals',
        'zh.hanzi.lin',
      ]);
    });

    testWidgets('三个部件分两步搭：木+木 先成林，林+木 再成森', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('next')));
      await tester.pumpAndSettle();
      expect(labels(tester), ['木', '木', '木']);

      await tapMerge(tester, '木', '木');
      // 半路上真的出现了「林」——他顺带看见了森里面有林。
      expect(labels(tester)..sort(), ['木', '林']);

      audio.spoken.clear();
      await tapMerge(tester, '林', '木');
      expect(labels(tester), ['森']);
      // 念的是**刚才那两块**，不是目标字的部件表。
      expect(audio.spoken, [
        'zh.hanzi.lin',
        'zh.word.plus',
        'zh.hanzi.mu',
        'zh.word.equals',
        'zh.hanzi.sen',
      ]);
    });

    testWidgets('合成后造字式显示目标字，下一题键点亮', (tester) async {
      await pumpPage(tester);
      expect(find.text('?'), findsOneWidget);

      await tapMerge(tester, '木', '木');

      expect(find.text('?'), findsNothing);
      final next = tester.widget<RoundActionButton>(
        find.byKey(const ValueKey('next')),
      );
      expect(next.highlighted, isTrue);
    });
  });

  group('非法组合', () {
    /// 一个**故意不完整**的内容包：定义了「森 = 木+木+木」，却没有「林」。
    /// 于是 `木 + 木` 合不出任何字——这正是规格里「非法组合」要的那个场面，
    /// 而且它只可能来自内容包，不可能来自代码。
    ContentLibrary broken() => ContentLibrary([
      const PackLoader().parse('''
{
  "schemaVersion": 1,
  "hanzi": [
    {"char": "木", "pinyin": "mù", "type": "pictograph", "imageKey": "tree",
     "voiceKey": "zh.hanzi.mu"},
    {"char": "森", "pinyin": "sēn", "type": "compound",
     "parts": ["木", "木", "木"], "voiceKey": "zh.hanzi.sen"}
  ]
}
''', source: 'hanzi.json')!,
    ]);

    Future<void> pumpBroken(WidgetTester tester) async {
      audio = RecordingAudioBus();
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioBusProvider.overrideWithValue(audio),
            contentLibraryProvider.overrideWithValue(broken()),
          ],
          child: MaterialApp(
            theme: buildBlockPlanetTheme(),
            home: const ComponentPage(),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('点选通道合不出字：两块原样留着，不合并也不消失', (tester) async {
      await pumpBroken(tester);
      expect(labels(tester), ['木', '木', '木']);

      await tapMerge(tester, '木', '木');

      expect(labels(tester), ['木', '木', '木'], reason: '合不出字就该什么都不发生');
    });

    testWidgets('拖拽通道合不出字：积木保持并列，且没有任何失败信号', (tester) async {
      await pumpBroken(tester);
      audio.sfx.clear();

      // 把第二块拖到第一块身上。合不出字 → 引擎让它落到最近的空格位。
      final source = blockOf(tester, '木', skip: 1);
      final target = blockOf(tester, '木');
      await tester.drag(
        source,
        tester.getCenter(target) - tester.getCenter(source),
      );
      await tester.pumpAndSettle();

      expect(labels(tester), ['木', '木', '木'], reason: '三块都还在');
      // 规格：MUST NOT 呈现错误标记。分裂音是「拆开了」，这里不该有；
      // 合体音更不该有。`return` 是「它自己回家了」，不是失败音。
      expect(audio.sfx, isNot(contains('split')));
      expect(audio.sfx, isNot(contains('merge')));
    });

    testWidgets('合不出字时不播报任何东西', (tester) async {
      await pumpBroken(tester);
      audio.spoken.clear();

      await tapMerge(tester, '木', '木');

      expect(audio.spoken, isEmpty);
    });
  });

  group('重来与切换', () {
    testWidgets('重来把部件放回起点', (tester) async {
      await pumpPage(tester);
      await tapMerge(tester, '木', '木');
      expect(labels(tester), ['林']);

      await tester.tap(find.byKey(const ValueKey('retry')));
      await tester.pumpAndSettle();

      expect(labels(tester), ['木', '木']);
    });

    testWidgets('玩法切换到跷跷板', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('mode')));
      await tester.pumpAndSettle();
      expect(find.byType(SeesawPage), findsOneWidget);
    });
  });

  group('降级与红线', () {
    testWidgets('内容包里没有合体字时静默留白，不弹文字', (tester) async {
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
          child: const MaterialApp(home: ComponentPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('积木与按钮都不小于 90dp', (tester) async {
      await pumpPage(tester);
      for (final block in blocks(tester)) {
        expect(
          tester.getSize(find.byWidget(block)).shortestSide,
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
