import 'package:baby_pal/birthday/birthday_egg.dart';
import 'package:baby_pal/birthday/name_scene.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/models.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/core/design/glyph_tile.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_audio_bus.dart';

const Size _phone = Size(738, 393);

/// 内容包里的名字**刻意与真实的不一样**（真的是 Emmett）：这一幕若把名字
/// 写死在代码里，这里就会露馅。规格对 8.2 的硬要求正是「姓名来自可配置数据」。
///
/// [child] 为 null 时内容包里就没有 `child` 这个目标，只剩字母模块终关的
/// 备选目标 mama——用来验「姓名未配置」那条路。
ContentLibrary library({String? child = 'Bo'}) {
  final targets = [
    if (child != null)
      '{"id": "child", "letters": "$child", "voiceKey": "en.name.child"}',
    '{"id": "mama", "letters": "Mama", "voiceKey": "en.name.mama"}',
  ];
  return ContentLibrary([
    const PackLoader().parse('''
{
  "schemaVersion": 1,
  "letters": [
    {"letter": "A", "voiceKey": "en.letter.a"},
    {"letter": "B", "voiceKey": "en.letter.b"},
    {"letter": "M", "voiceKey": "en.letter.m"},
    {"letter": "O", "voiceKey": "en.letter.o"}
  ],
  "spellingTargets": [${targets.join(',')}]
}
''', source: 'letters.json')!,
  ]);
}

SpellingTarget childOf(ContentLibrary lib) =>
    lib.spellingTargets.firstWhere((t) => t.id == kChildSpellingId);

void main() {
  late RecordingAudioBus audio;
  late int finished;

  Future<void> pumpScene(WidgetTester tester, {String name = 'Bo'}) async {
    audio = RecordingAudioBus();
    finished = 0;
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final lib = library(child: name);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioBusProvider.overrideWithValue(audio),
          contentLibraryProvider.overrideWithValue(lib),
        ],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: NameScene(
            key: ValueKey(name),
            target: childOf(lib),
            onFinished: () => finished++,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// 已经落地的字母，按屏幕上的先后顺序。
  ///
  /// 读的是 `AnimatedSlide` 的目标位移——隐式动画的目标值就是这一幕的全部
  /// 状态。直接读它，比给组件开一个只有测试用得上的出口要诚实：测的是真的
  /// 画在屏幕上的东西。
  List<String> landed(WidgetTester tester) => [
    for (final element in find.byType(AnimatedSlide).evaluate())
      if ((element.widget as AnimatedSlide).offset == Offset.zero)
        tester
            .widget<GlyphTile>(
              find.descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(GlyphTile),
              ),
            )
            .glyph,
  ];

  group('字母逐个飞入', () {
    testWidgets('一个一个来，不是一起蹦出来', (tester) async {
      // 「逐个飞入」是规格原话。同时出现他只会看见一团，逐个出现他的眼睛
      // 才会跟着一个一个看过去。
      await pumpScene(tester, name: 'Bo');
      expect(landed(tester), isEmpty, reason: '开场一个都还没落');

      await tester.pump(kNameLetterStagger);
      expect(landed(tester), ['B']);

      await tester.pump(kNameLetterStagger);
      expect(landed(tester), ['B', 'O']);
    });

    testWidgets('每落一个念一个字母，拼完念整个名字再说生日快乐', (tester) async {
      await pumpScene(tester, name: 'Bo');
      await tester.pump(kNameLetterStagger);
      expect(audio.spoken, ['en.letter.b']);

      await tester.pump(kNameLetterStagger);
      expect(audio.spoken, [
        'en.letter.b',
        'en.letter.o',
        // 名字整体用的是 `target.voiceKey`——家长最该录的那一条（见 6.6，
        // 录音顺序里名字排第一）。
        'en.name.child',
        'zh.birthday.happyBirthday',
      ]);
    });

    testWidgets('拼完之后停一会儿才交给下一幕', (tester) async {
      // 蜡烛那一幕犯过一次这个错：庆祝和「交出去」写在同一行，8.1 接上流程
      // 之后就成了「最后一下的同一帧把画面撤掉」。
      await pumpScene(tester, name: 'Bo');
      await tester.pump(kNameLetterStagger);
      await tester.pump(kNameLetterStagger);
      expect(finished, 0, reason: '刚拼完就走，他还没看清');

      await tester.pump(kNameHold);
      expect(finished, 1);
    });

    testWidgets('名字来自内容包，不是写死的', (tester) async {
      await pumpScene(tester, name: 'Mob');
      await tester.pump(kNameLetterStagger * 4);
      expect(landed(tester), ['M', 'O', 'B']);
    });

    testWidgets('名字长起来也放得下，不溢出屏幕', (tester) async {
      // 90dp 那条是**可抓取目标**的下限，而这一幕一个字母都点不了。
      // 硬守 90dp 只会让长名字排到屏幕外面去——那才是真的看不见。
      await pumpScene(tester, name: 'Bobobobobobo'); // 12 个字母
      await tester.pump(kNameLetterStagger * 13);
      // 落地之后还要飞 420ms 才到位——量的是**站定之后**的排布。
      await tester.pump(kNameLetterFlyIn);

      final tiles = find.byType(GlyphTile).evaluate().toList();
      expect(tiles.length, 12);
      for (final tile in tiles) {
        final box = tile.renderObject! as RenderBox;
        final left = box.localToGlobal(Offset.zero).dx;
        expect(left, greaterThanOrEqualTo(0.0));
        expect(left + box.size.width, lessThanOrEqualTo(_phone.width));
      }
    });
  });

  group('幕次是算出来的', () {
    // 规格「彩蛋数据与资源可缺失」：姓名没配置时彩蛋**仍要能启动并完成**。
    test('内容包里没有 child 就不放这一幕——也不退而求其次拿 mama', () {
      // `spellingTargets` 里还躺着字母模块终关的备选目标。拿第一个，
      // 就会在他生日当天拼出别人的名字。
      final scenes = birthdayScenes(library: library(child: null));
      expect(scenes.map((s) => s.id), ['candles']);
    });

    test('没有内容库时同样只剩蜡烛', () {
      expect(birthdayScenes().map((s) => s.id), ['candles']);
    });

    test('配了名字时，名字在蜡烛前面', () {
      // 先叫他的名字，再请他吹蜡烛。倒过来就成了「吹完了，顺便告诉你
      // 这是给谁的」。
      expect(birthdayScenes(library: library()).map((s) => s.id), [
        'name',
        'candles',
      ]);
    });

    test('名字那一幕碰哪儿都能跳过，蜡烛那一幕不行', () {
      // 名字是看着就好的被动画面；蜡烛要点、要吹，把触摸当跳过就没法玩了。
      final scenes = birthdayScenes(library: library());
      expect(scenes.firstWhere((s) => s.id == 'name').tapAnywhereSkips, isTrue);
      expect(
        scenes.firstWhere((s) => s.id == 'candles').tapAnywhereSkips,
        isFalse,
      );
    });
  });
}
