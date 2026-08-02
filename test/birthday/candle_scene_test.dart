import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:baby_pal/birthday/breath_source.dart';
import 'package:baby_pal/birthday/candle_cake.dart';
import 'package:baby_pal/birthday/candle_scene.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/block/block_widget.dart';
import 'package:baby_pal/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_audio_bus.dart';

/// 假麦克风：想让它「吹」的时候就推一段高能量数据进去。
class FakeBreathSource implements BreathSource {
  FakeBreathSource({this.available = true});

  bool available;
  bool started = false;
  int stopCalls = 0;
  final _controller = StreamController<Uint8List>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Stream<Uint8List>> start() async {
    started = true;
    return _controller.stream;
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }

  void push(double amplitude, {int samples = 1600}) {
    final bytes = Uint8List(samples * 2);
    final view = ByteData.sublistView(bytes);
    for (var i = 0; i < samples; i++) {
      view.setInt16(
        i * 2,
        (math.sin(i * 0.3) * amplitude * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    _controller.add(bytes);
  }
}

const Size _phone = Size(738, 393);

void main() {
  late RecordingAudioBus audio;
  late FakeBreathSource breath;
  late int finished;

  Future<void> pumpScene(WidgetTester tester, {bool mic = true}) async {
    audio = RecordingAudioBus();
    breath = FakeBreathSource(available: mic);
    finished = 0;
    addTearDown(breath.dispose);

    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioBusProvider.overrideWithValue(audio)],
        child: MaterialApp(
          theme: buildBlockPlanetTheme(),
          home: CandleScene(
            breathSource: breath,
            onFinished: () => finished++,
          ),
        ),
      ),
    );
    // 蜡烛的火苗是永不停止的循环动画，pumpAndSettle 会一直等下去。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  CandleCake cake(WidgetTester tester) =>
      tester.widget<CandleCake>(find.byType(CandleCake));

  Finder blockOfWidth(int units) => find.byWidgetPredicate(
    (w) => w is BlockWidget && w.body.widthUnits == units,
  );

  /// 点两下把两块合起来——引擎的点选通道。
  ///
  /// 两块同宽时**必须取到不同的两块**：`.first` 两次是同一块点了两下，
  /// 引擎那边等于选中再取消，什么都不会发生。
  Future<void> mergeTwo(WidgetTester tester, int a, int b) async {
    await tester.tap(blockOfWidth(a).first);
    await tester.pump();
    final second = a == b ? blockOfWidth(b).at(1) : blockOfWidth(b).first;
    await tester.tap(second);
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('三块合体点燃蜡烛', () {
    testWidgets('一开始三块是分开的，蜡烛没点着', (tester) async {
      await pumpScene(tester);
      expect(blockOfWidth(1), findsNWidgets(3));
      expect(cake(tester).lit, isFalse);
    });

    testWidgets('起始状态两两不相邻——否则一进来就自己合了', (tester) async {
      await pumpScene(tester);
      final anchors = tester
          .widgetList<BlockWidget>(find.byType(BlockWidget))
          .map((w) => w.body.anchor!.col)
          .toList()
        ..sort();
      for (var i = 0; i < anchors.length - 1; i++) {
        expect(anchors[i + 1] - anchors[i], greaterThan(1));
      }
    });

    testWidgets('1+1=2，再 +1=3 → 点燃三根，播报「一加一加一等于三」', (tester) async {
      await pumpScene(tester);
      await mergeTwo(tester, 1, 1);
      expect(blockOfWidth(2), findsOneWidget);
      expect(cake(tester).lit, isFalse, reason: '才 2，还没到 3');

      await mergeTwo(tester, 2, 1);
      await tester.pump(const Duration(milliseconds: 100));

      expect(cake(tester).lit, isTrue);
      expect(cake(tester).remaining, 3);
      expect(
        audio.spoken,
        containsAllInOrder([
          'zh.number.1',
          'zh.word.plus',
          'zh.number.1',
          'zh.word.plus',
          'zh.number.1',
          'zh.word.equals',
          'zh.number.3',
        ]),
      );
      expect(audio.spoken, contains('zh.birthday.blowTheCandles'));
    });

    testWidgets('点着之后拼搭台让位给蛋糕', (tester) async {
      await pumpScene(tester);
      await mergeTwo(tester, 1, 1);
      await mergeTwo(tester, 2, 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BlockWidget), findsNothing);
    });

    testWidgets('没点着之前吹也没用——先得把蜡烛插上', (tester) async {
      await pumpScene(tester);
      expect(breath.started, isFalse, reason: '还没点着就不该开麦克风');
    });
  });

  group('吹灭', () {
    Future<void> light(WidgetTester tester) async {
      await mergeTwo(tester, 1, 1);
      await mergeTwo(tester, 2, 1);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('持续吹 → 三根依次灭掉，然后庆祝', (tester) async {
      await pumpScene(tester);
      await light(tester);
      expect(breath.started, isTrue);

      // 先让它量完本底（安静）。
      for (var i = 0; i < 6; i++) {
        breath.push(0.005);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(cake(tester).remaining, 3);

      for (var i = 0; i < 30 && cake(tester).remaining > 0; i++) {
        breath.push(0.9);
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(cake(tester).remaining, 0);
      expect(audio.spoken, contains('zh.birthday.happyBirthday'));
      expect(finished, 0, reason: '生日快乐还没说完，别急着撤画面');

      await tester.pump(kCelebrateHold);
      expect(finished, 1);
    });

    testWidgets('持续的环境噪音吹不灭——规格场景「环境噪音」', (tester) async {
      await pumpScene(tester);
      await light(tester);
      for (var i = 0; i < 6; i++) {
        breath.push(0.005);
        await tester.pump(const Duration(milliseconds: 20));
      }
      for (var i = 0; i < 40; i++) {
        breath.push(0.02); // 持续低强度
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(cake(tester).remaining, 3);
      expect(finished, 0);
    });

    testWidgets('灭完之后把麦克风停掉——不该一直听着', (tester) async {
      await pumpScene(tester);
      await light(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('cake')));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cake(tester).remaining, 0);
      expect(breath.stopCalls, greaterThan(0));
    });
  });

  group('点一下也能灭', () {
    testWidgets('没有麦克风时立刻演「点一下」，且点得灭', (tester) async {
      // 规格场景「无麦克风权限降级」：改为点击熄灭，彩蛋 MUST 完整可玩。
      await pumpScene(tester, mic: false);
      await mergeTwo(tester, 1, 1);
      await mergeTwo(tester, 2, 1);
      await tester.pump(const Duration(milliseconds: 100));

      expect(breath.started, isFalse);
      expect(cake(tester).showTapHint, isTrue, reason: '没麦克风就别让他干等 8 秒');

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('cake')));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cake(tester).remaining, 0);
      await tester.pump(kCelebrateHold);
      expect(finished, 1);
    });

    testWidgets('有麦克风时点击照样能灭——这一关不允许存在「过不去」', (tester) async {
      await pumpScene(tester);
      await mergeTwo(tester, 1, 1);
      await mergeTwo(tester, 2, 1);
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('cake')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(cake(tester).remaining, 2);
    });

    testWidgets('久久没进展就把「点一下」演出来，不会卡死', (tester) async {
      // 规格场景「长时间未吹灭」：提供点击熄灭的动画提示，MUST NOT 卡死。
      await pumpScene(tester);
      await mergeTwo(tester, 1, 1);
      await mergeTwo(tester, 2, 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(cake(tester).showTapHint, isFalse, reason: '别一上来就说「你吹不灭的」');

      await tester.pump(kTapHintDelay + const Duration(seconds: 1));
      expect(cake(tester).showTapHint, isTrue);
    });

    testWidgets('点着之前点蛋糕不会灭——蜡烛还没插上', (tester) async {
      await pumpScene(tester);
      await tester.tap(find.byKey(const ValueKey('cake')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(cake(tester).remaining, 3);
      expect(cake(tester).lit, isFalse);
    });

    testWidgets('全灭之后再点不会灭成负数，也不会重复庆祝', (tester) async {
      await pumpScene(tester, mic: false);
      await mergeTwo(tester, 1, 1);
      await mergeTwo(tester, 2, 1);
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(const ValueKey('cake')));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cake(tester).remaining, 0);
      await tester.pump(kCelebrateHold);
      expect(finished, 1);
    });
  });
}
