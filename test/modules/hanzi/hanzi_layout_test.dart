import 'dart:io';

import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/controls.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/hanzi/component_page.dart';
import 'package:baby_pal/modules/hanzi/pictograph_page.dart';
import 'package:baby_pal/modules/hanzi/seesaw_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/recording_audio_bus.dart';

/// 汉字模块三个玩法在各种屏幕上的布局兜底。
///
/// 与 `letters_layout_test.dart` 同一套做法，理由也一样：溢出在 `flutter test`
/// 里会抛异常，所以「把每个页面在每种屏幕上 pump 一遍」本身就是一条真能抓
/// bug 的用例。拼名字页那次是名字长了一位就溢出 152dp——**内容包可配的东西
/// 一变，布局就可能爆**，而汉字这边可配的更多：三部件的字比两部件的宽，
/// 反义词候选的个数也来自数据。
///
/// 用**真实的内容包**而不是精简的测试数据：这里要验的正是「线上这份内容摆得
/// 下摆不下」。
void main() {
  const sizes = <String, Size>{
    'MI 8 SE 横屏': Size(738, 393),
    '窄屏（缩放下限）': Size(640, 360),
    '平板横屏': Size(1024, 768),
  };

  ContentLibrary library() => ContentLibrary([
    const PackLoader().parse(
      File('assets/packs/hanzi.json').readAsStringSync(),
      source: 'assets/packs/hanzi.json',
    )!,
  ]);

  final pages = <String, Widget Function()>{
    '象形动画': () => const PictographPage(),
    '部件加法': () => const ComponentPage(),
    '反义词跷跷板': () => const SeesawPage(),
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
            child: MaterialApp(
              theme: buildBlockPlanetTheme(),
              home: page.value(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        expect(
          tester.takeException(),
          isNull,
          reason: '${page.key} 在 ${size.value.width}×${size.value.height} 上溢出了',
        );

        for (final tile in tester.widgetList<PressableTile>(
          find.byType(PressableTile),
        )) {
          expect(
            tester.getSize(find.byWidget(tile)).shortestSide,
            greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
            reason: '${page.key} 在${size.key}上有元素击穿了 90dp',
          );
        }

        await tester.pumpAndSettle();
      });
    }
  }

  /// 部件最多的那道题（森 / 众，三块）最容易把棋盘挤爆。
  testWidgets('部件加法：翻遍每一道题，每种屏幕都摆得下', (tester) async {
    for (final size in sizes.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioBusProvider.overrideWithValue(RecordingAudioBus()),
            contentLibraryProvider.overrideWithValue(library()),
          ],
          child: MaterialApp(
            theme: buildBlockPlanetTheme(),
            home: const ComponentPage(),
          ),
        ),
      );
      await tester.pump();

      final count = library().hanzi.where((h) => h.isCompound).length;
      for (var i = 0; i < count; i++) {
        expect(
          tester.takeException(),
          isNull,
          reason: '第 $i 题在 ${size.width}×${size.height} 上溢出了',
        );
        await tester.tap(find.byKey(const ValueKey('next')));
        await tester.pumpAndSettle();
      }
    }
  });
}
