import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/progress/progress_providers.dart';
import 'package:baby_pal/core/progress/progress_store.dart';
import 'package:baby_pal/modules/home/module_id.dart';
import 'package:baby_pal/parent/about_page.dart';
import 'package:baby_pal/parent/dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "hanzi": [
    {"char": "木", "pinyin": "mù", "type": "pictograph", "imageKey": "tree",
     "voiceKey": "zh.hanzi.6728"}
  ]
}
''', source: 'test.json')!,
]);

void main() {
  late ProgressStore progress;
  late DateTime now;

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressStoreProvider.overrideWithValue(progress),
          contentLibraryProvider.overrideWithValue(_library()),
        ],
        child: const MaterialApp(home: ParentDashboardPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    now = DateTime(2026, 8, 2, 9);
    progress = ProgressStore(null, clock: () => now)..load();
    addTearDown(progress.dispose);
  });

  testWidgets('还没玩过时说得清清楚楚，不是空白', (tester) async {
    await pumpPage(tester);
    expect(find.text('今天还没开始玩。'), findsOneWidget);
  });

  testWidgets('列出各块大陆的时长，长的排前面', (tester) async {
    progress.beginSession();
    now = now.add(const Duration(minutes: 2));
    await progress.flush(module: ModuleId.hanzi.name);
    now = now.add(const Duration(minutes: 7));
    await progress.flush(module: ModuleId.sandbox.name);

    await pumpPage(tester);

    final tiles = find.byKey(const ValueKey('module-time-sandbox'));
    expect(tiles, findsOneWidget);
    expect(find.byKey(const ValueKey('module-time-hanzi')), findsOneWidget);

    // 沙盒 7 分钟 > 汉字 2 分钟，应排在前面。
    final sandboxY = tester.getTopLeft(tiles).dy;
    final hanziY = tester
        .getTopLeft(find.byKey(const ValueKey('module-time-hanzi')))
        .dy;
    expect(sandboxY, lessThan(hanziY));
  });

  testWidgets('生疏条目按 voiceKey 翻译成看得懂的名字', (tester) async {
    await progress.recordAttempt('zh.hanzi.6728', success: false);
    await progress.recordAttempt('zh.hanzi.6728', success: true);
    await pumpPage(tester);

    expect(find.byKey(const ValueKey('weak-zh.hanzi.6728')), findsOneWidget);
    expect(find.text('木（mù）'), findsOneWidget);
    expect(find.text('对 1 / 共 2'), findsOneWidget);
  });

  testWidgets('没练过的不进「还生疏」——那是「还没教」', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('还没有练得不好的内容'), findsOneWidget);
  });

  testWidgets('翻不出来的键原样显示，不是藏起来', (tester) async {
    await progress.recordAttempt('zh.mystery.999', success: false);
    await pumpPage(tester);
    expect(find.text('zh.mystery.999'), findsOneWidget);
  });

  testWidgets('关于页把三件事都写全了：隐私 / 署名 / 防误退出', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ParentAboutPage()));
    await tester.pumpAndSettle();

    // 署名是 CC BY-SA 4.0 的发行条件，不是礼节。
    expect(find.textContaining('CC BY-SA 4.0'), findsOneWidget);
    expect(find.textContaining('OpenMoji'), findsWidgets);
    expect(find.textContaining('不收集、不上传'), findsOneWidget);
    expect(find.textContaining('引导式访问'), findsOneWidget);
  });
}
