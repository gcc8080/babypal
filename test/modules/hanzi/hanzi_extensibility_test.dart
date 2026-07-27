import 'dart:io';

import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/block/block_widget.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/models.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/glyph_tile.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/hanzi/component_page.dart';
import 'package:baby_pal/modules/hanzi/hanzi.dart';
import 'package:baby_pal/modules/hanzi/seesaw_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

const Size _phone = Size(738, 393);

/// 内容可扩展性（openspec 任务 6.5）。
///
/// 规格的原话是：**新增一个包含更多合体字的汉字内容包，新字在部件加法玩法中
/// 直接可用，无代码改动。** 这是这个 App 能陪他从 3 岁用到 5 岁的全部前提——
/// 明年他会认更多字，那时应该是加一个 JSON 文件，而不是我再写一遍这个模块。
///
/// 所以这条验证刻意做成「真的加一个文件」：`test/fixtures/hanzi_l2.json` 是一个
/// 货真价实的内容包，走的是与 `assets/packs/*.json` 完全相同的解析路径。
///
/// 它里面的「炎 = 火 + 火」还顺带压住了一个更隐蔽的要求：**部件「火」在老包
/// 里**。这正是明年扩内容时最自然的写法，也正是逐包校验会误杀的那一条。
void main() {
  /// 线上内容包 + 新增的 L2 包，与运行时的加载方式一致。
  ContentLibrary extended() {
    const loader = PackLoader();
    return ContentLibrary([
      for (final path in [
        'assets/packs/hanzi.json',
        'test/fixtures/hanzi_l2.json',
      ])
        loader.parse(File(path).readAsStringSync(), source: path)!,
    ]);
  }

  ContentLibrary baseline() {
    const loader = PackLoader();
    return ContentLibrary([
      loader.parse(
        File('assets/packs/hanzi.json').readAsStringSync(),
        source: 'hanzi.json',
      )!,
    ]);
  }

  group('新包解析后就活着', () {
    test('新字进了内容库，且部件跨包也认得出', () {
      final library = extended();
      expect(library.hanziByChar('炎'), isNotNull);
      expect(
        library.unresolvedCompounds,
        isEmpty,
        reason: '「炎」的部件「火」在老包里——跨包引用必须成立',
      );
    });

    test('合体规则直接认新字：火 + 火 = 炎', () {
      final library = extended();
      expect(compoundFrom(['火', '火'], library)?.char, '炎');
    });

    test('新的反义词对也直接可用', () {
      expect(extended().antonyms, contains(const AntonymPair('凸', '凹')));
    });

    test('不加这个包就没有这些字——证明它们真的来自文件', () {
      final library = baseline();
      expect(library.hanziByChar('炎'), isNull);
      expect(compoundFrom(['火', '火'], library), isNull);
    });
  });

  group('新字在玩法里真的能玩', () {
    Future<void> pumpComponent(WidgetTester tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioBusProvider.overrideWithValue(RecordingAudioBus()),
            contentLibraryProvider.overrideWithValue(extended()),
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

    testWidgets('部件加法能翻到「炎」这一题并拼出来', (tester) async {
      await pumpComponent(tester);

      // 一路按「下一题」，直到出现火 + 火。
      // 上限跟着数据走：写死一个 20 会在内容包变大时静默失效——反义词那条
      // 用例就是这么挂的（反义词涨到 71 对，第 71 关永远翻不到）。
      final rounds = extended().hanzi.where((h) => h.isCompound).length + 1;
      var found = false;
      for (var i = 0; i < rounds; i++) {
        final labels = blocks(tester).map((w) => w.body.label).toList();
        if (labels.length == 2 && labels.every((l) => l == '火')) {
          found = true;
          break;
        }
        await tester.tap(find.byKey(const ValueKey('next')));
        await tester.pumpAndSettle();
      }
      expect(found, isTrue, reason: '新增的「炎」应该出现在题目里');

      // 每次点击之前重新查一遍：第一下点完棋盘会重建，先前抓到的第二块
      // 就是个已经不在树上的旧实例，`find.byWidget` 会一个都找不到。
      await tester.tap(
        find.byWidget(blocks(tester).where((w) => w.body.label == '火').first),
      );
      await tester.pump();
      await tester.tap(
        find.byWidget(blocks(tester).where((w) => w.body.label == '火').last),
      );
      await tester.pumpAndSettle();

      expect(blocks(tester).single.body.label, '炎');
    });

    testWidgets('跷跷板能翻到「凸 ↔ 凹」这一对并配上', (tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioBusProvider.overrideWithValue(RecordingAudioBus()),
            contentLibraryProvider.overrideWithValue(extended()),
          ],
          child: MaterialApp(
            theme: buildBlockPlanetTheme(),
            home: const SeesawPage(),
          ),
        ),
      );
      await tester.pump();

      String prompt() =>
          tester.widget<GlyphTile>(find.byKey(const ValueKey('prompt'))).glyph;

      final rounds = extended().antonyms.length + 1;
      var found = false;
      for (var i = 0; i < rounds; i++) {
        if (prompt() == '凸') {
          found = true;
          break;
        }
        await tester.tap(find.byKey(const ValueKey('next')));
        await tester.pumpAndSettle();
      }
      expect(found, isTrue, reason: '新增的反义词对应该出现在题目里');

      await tester.tap(find.byKey(const ValueKey('choice-凹')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('seat')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('choice-凹')), findsNothing);
    });
  });

  test('零代码改动：新字在 lib/ 下一处都不出现', () {
    // 这条断言才是「可扩展」真正的意思。上面几条只证明「加了能用」，
    // 而它证明的是「用的不是我为它写的代码」——只要有人为某个字开了特例，
    // 这里立刻就红。
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in sources) {
      final text = file.readAsStringSync();
      for (final char in ['炎', '凸', '凹']) {
        if (text.contains(char)) offenders.add('${file.path} 里出现了「$char」');
      }
    }
    expect(offenders, isEmpty);
  });
}
