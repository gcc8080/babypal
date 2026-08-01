import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/core/block/block_widget.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/sandbox/sandbox_page.dart';
import 'package:baby_pal/modules/sandbox/sandbox_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/recording_audio_bus.dart';

/// 交付机 MI 8 SE 的横屏逻辑尺寸。
const Size _phone = Size(738, 393);

ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "numbers": [
    {"value": 0, "voiceKey": "zh.number.0", "voiceKeyEn": "en.number.0"},
    {"value": 1, "voiceKey": "zh.number.1", "voiceKeyEn": "en.number.1"}
  ],
  "letters": [
    {"letter": "A", "voiceKey": "zh.letter.A"},
    {"letter": "B", "voiceKey": "zh.letter.B"}
  ],
  "hanzi": [
    {"char": "木", "pinyin": "mù", "type": "pictograph", "imageKey": "tree",
     "voiceKey": "zh.hanzi.mu"},
    {"char": "林", "pinyin": "lín", "type": "compound", "parts": ["木", "木"],
     "voiceKey": "zh.hanzi.lin"}
  ]
}
''', source: 'test.json')!,
]);

void main() {
  late RecordingAudioBus audio;

  // 与 `_SandboxPageState._buildGrid` 在 738×393 上算出来的几何一致。
  // 写死在这里是刻意的：布局一改这些数就对不上，测试会失败并逼我重新
  // 确认「他的手指还够得着吗」——那正是这几个数存在的理由。
  const double boardLeft = BlockMetrics.gap / 2;
  const double boardTop = BlockMetrics.gap / 2;
  const int columns = 6;
  const double cell = 104.0;

  Offset cellCenter(int col, int row) => Offset(
    boardLeft + (col + 0.5) * cell,
    boardTop + (row + 0.5) * cell,
  );

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
          home: const SandboxPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 台面上（含托盘）写着 [label] 的积木。
  Finder blockOf(String label) => find.byWidgetPredicate(
    (w) => w is BlockWidget && w.body.label == label && w.body.id != 'sample',
  );

  /// 只在**托盘里**（还没落位）的那些。
  ///
  /// place() 必须从这里取：`0 + 1 = 1` 要放两块 1，若不加这条过滤，第二次
  /// 会抓起已经摆在台面上的那一块挪走——等式在中途被自己拆掉。
  Finder trayBlockOf(String label) => find.byWidgetPredicate(
    (w) =>
        w is BlockWidget &&
        w.body.label == label &&
        w.body.id != 'sample' &&
        w.body.anchor == null,
  );

  /// 点两下把托盘里的一块放到指定格位——引擎的点选通道，
  /// 规格要求每个拖拽任务都必须有的那条「拖不动也做得到」的路。
  Future<void> place(
    WidgetTester tester,
    String label,
    int col,
    int row,
  ) async {
    await tester.tap(trayBlockOf(label).first);
    await tester.pumpAndSettle();
    await tester.tapAt(cellCenter(col, row));
    await tester.pumpAndSettle();
  }

  /// **`setMockInitialValues` 一个人不够。** `SharedPreferences` 内部缓存着
  /// 一个跨测试存活的单例，上一条用例存进去的作品会被下一条读回来——表现是
  /// 「台面上多了一块我没放的积木」，而且只在整文件连跑时出现。
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await (await SharedPreferences.getInstance()).clear();
  });

  /// 直接往**活着的那个实例**里塞存档，理由同上。
  Future<void> seedStore(String json) async {
    await (await SharedPreferences.getInstance()).setString(
      SandboxStore.storageKey,
      json,
    );
  }

  group('货架', () {
    test('几何前提：738×393 上算出 6 列、格位 104', () {
      // place() 的坐标全建在这两个数上。它们一旦变了，
      // 下面每一条「点这里」都在点别的地方，必须先失败在这里。
      const available = 738.0 - BlockMetrics.gap - BlockMetrics.gap / 2 -
          BlockMetrics.minGrabTarget;
      expect((available / BlockMetrics.minGrabTarget).floor(), columns);
      expect(available / columns, closeTo(cell, 0.01));
    });

    testWidgets('一进来托盘里是数字，加号等号常驻', (tester) async {
      await pumpPage(tester);
      expect(blockOf('+'), findsOneWidget);
      expect(blockOf('='), findsOneWidget);
      expect(blockOf('0'), findsOneWidget);
    });

    testWidgets('类别键换一类：数字 → 字母', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('category')));
      await tester.pumpAndSettle();

      expect(blockOf('A'), findsOneWidget);
      expect(blockOf('+'), findsNothing, reason: '换类之后托盘里不该还有数字类的货');
    });

    testWidgets('四次类别键回到数字——绕回而不是走到头按不动', (tester) async {
      await pumpPage(tester);
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('category')));
        await tester.pumpAndSettle();
      }
      expect(blockOf('+'), findsOneWidget);
    });

    testWidgets('换类不动台面上已经摆好的积木——这就是跨内容域混搭', (tester) async {
      await pumpPage(tester);
      await place(tester, '1', 0, 0);

      await tester.tap(find.byKey(const ValueKey('category')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category')));
      await tester.pumpAndSettle();

      // 数字 1 还在台面上，汉字「木」在托盘里，两者共存。
      expect(blockOf('1'), findsOneWidget);
      expect(blockOf('木'), findsWidgets);
    });

    testWidgets('拿走一块，托盘立刻补上——他永远不会「用完」', (tester) async {
      await pumpPage(tester);
      expect(blockOf('1'), findsOneWidget);
      await place(tester, '1', 0, 0);
      // 台面上一块 + 托盘里补的一块。
      expect(blockOf('1'), findsNWidgets(2));
    });
  });

  group('自发组合', () {
    testWidgets('自己摆出 0 + 1 = 1 → 播报并庆祝', (tester) async {
      await pumpPage(tester);
      await place(tester, '0', 0, 0);
      await place(tester, '+', 1, 0);
      await place(tester, '1', 2, 0);
      await place(tester, '=', 3, 0);
      await place(tester, '1', 4, 0);

      expect(
        audio.spoken,
        containsAllInOrder([
          'zh.number.0',
          'zh.word.plus',
          'zh.number.1',
          'zh.word.equals',
          'zh.number.1',
        ]),
      );
    });

    testWidgets('同一条算式不会庆祝第二次', (tester) async {
      await pumpPage(tester);
      await place(tester, '0', 0, 0);
      await place(tester, '+', 1, 0);
      await place(tester, '1', 2, 0);
      await place(tester, '=', 3, 0);
      await place(tester, '1', 4, 0);
      final after = audio.spoken.length;

      // 再往旁边放一块无关的积木，台面变了但那条算式还是刚才那条。
      await place(tester, '0', 0, 1);
      expect(audio.spoken.length, after);
    });

    testWidgets('没摆出组合时一声不吭', (tester) async {
      await pumpPage(tester);
      await place(tester, '0', 0, 0);
      await place(tester, '0', 2, 0);
      expect(audio.spoken, isEmpty, reason: '沙盒里没有「再试试」');
    });

    testWidgets('两个「木」拼一起 → 合体成「林」并播报', (tester) async {
      await pumpPage(tester);
      // 切到汉字类：数字 → 字母 → 汉字。
      await tester.tap(find.byKey(const ValueKey('category')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category')));
      await tester.pumpAndSettle();

      await place(tester, '木', 0, 0);
      await place(tester, '木', 1, 0);

      expect(blockOf('林'), findsOneWidget);
      expect(
        audio.spoken,
        containsAllInOrder([
          'zh.hanzi.mu',
          'zh.word.plus',
          'zh.hanzi.mu',
          'zh.word.equals',
          'zh.hanzi.lin',
        ]),
      );
    });
  });

  group('清空', () {
    testWidgets('按一下只是问一句，台面不动', (tester) async {
      await pumpPage(tester);
      await place(tester, '1', 0, 0);

      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pumpAndSettle();

      expect(blockOf('1'), findsNWidgets(2), reason: '第一下不该清掉任何东西');
      final button = tester.widget<RoundActionButton>(
        find.byKey(const ValueKey('clear')),
      );
      expect(button.highlighted, isTrue, reason: '要看得出「就等你再按一下」');
    });

    testWidgets('再按一下才真清空', (tester) async {
      await pumpPage(tester);
      await place(tester, '1', 0, 0);
      await place(tester, '0', 1, 0);

      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 台面空了，托盘按当前页重新上货：0 和 1 各只剩托盘里那一块。
      expect(blockOf('1'), findsOneWidget);
      expect(blockOf('0'), findsOneWidget);
    });

    testWidgets('等过确认窗口就自动放弃，不会误清', (tester) async {
      await pumpPage(tester);
      await place(tester, '1', 0, 0);

      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pump(const Duration(seconds: 4)); // 越过确认窗口
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pumpAndSettle();

      expect(blockOf('1'), findsNWidgets(2), reason: '两次按之间隔太久，不该当成确认');
    });
  });

  group('作品保留', () {
    testWidgets('离开沙盒再回来，台面原样还在', (tester) async {
      await pumpPage(tester);
      await place(tester, '1', 2, 1);
      await tester.pumpAndSettle();

      // 走掉：dispose 时落盘。
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      await pumpPage(tester);
      await tester.pumpAndSettle();

      final placed = tester
          .widgetList<BlockWidget>(blockOf('1'))
          .where((w) => w.body.anchor != null)
          .toList();
      expect(placed, hasLength(1));
      expect(placed.single.body.anchor, const GridCell(2, 1));
    });

    testWidgets('还原出来的算式不会在他下一次动手时被翻出来念', (tester) async {
      // 存档里本来就摆着 `0 + 1 = 1`。他回来之后在别处放了一块无关的积木——
      // 那一刻台面确实「有一条成立的算式」，但那是**上次**摆的。
      // 此时出声等于把他上一次的成果算到这一次头上。
      await seedStore(
        '[{"c":0,"l":"0","w":1,"h":1,"col":0,"row":0},'
        '{"c":0,"l":"+","w":1,"h":1,"col":1,"row":0},'
        '{"c":0,"l":"1","w":1,"h":1,"col":2,"row":0},'
        '{"c":0,"l":"=","w":1,"h":1,"col":3,"row":0},'
        '{"c":0,"l":"1","w":1,"h":1,"col":4,"row":0}]',
      );
      await pumpPage(tester);
      await tester.pumpAndSettle();

      // 先确认现场真的还原了，否则下面的断言什么都没验到。
      final restored = tester
          .widgetList<BlockWidget>(find.byType(BlockWidget))
          .where((w) => w.body.anchor != null);
      expect(restored, hasLength(5));

      await place(tester, '2', 0, 1);
      expect(audio.spoken, isEmpty, reason: '一进页面就邀功，是替他把事做了');
    });

    testWidgets('清空之后离开再回来，台面是空的', (tester) async {
      await pumpPage(tester);
      await place(tester, '1', 0, 0);
      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('clear')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await pumpPage(tester);
      await tester.pumpAndSettle();

      final placed = tester
          .widgetList<BlockWidget>(find.byType(BlockWidget))
          .where((w) => w.body.anchor != null);
      expect(placed, isEmpty);
    });
  });

  group('容量', () {
    testWidgets('30 块积木同时在台面上，布局不溢出', (tester) async {
      // sandbox 规格「高塔堆叠」：30 层不掉帧不崩。这里验的是**没有溢出、
      // 没有异常**——帧率要真机跑，`flutter test` 量不出来。
      // RenderFlex 溢出在测试里会直接抛，所以 pump 通过本身就是一条断言。
      tester.view.physicalSize = const Size(1069, 668); // Redmi 平板
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final blocks = [
        for (var i = 0; i < 30; i++)
          '{"c":${i % 10},"w":1,"h":1,"col":${i % 10},"row":${i ~/ 10}}',
      ];
      await seedStore('[${blocks.join(',')}]');

      await pumpPage(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widgetList<BlockWidget>(find.byType(BlockWidget))
            .where((w) => w.body.anchor != null)
            .length,
        30,
      );
    });
  });
}
