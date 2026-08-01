import 'dart:io';

import 'package:baby_pal/core/audio/audio_bus.dart';
import 'package:baby_pal/core/audio/audio_providers.dart';
import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:baby_pal/core/content/content_providers.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/parent/recorder_page.dart';
import 'package:baby_pal/parent/voice_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假录音设备：把「录音」变成「写一个合法的 WAV 头」。
///
/// 这样整条链路都是真的——真的写文件、真的由 [VoiceResolver] 去解析、
/// 真的判断「录完之后播的是哪一个」。唯一被替掉的是麦克风本身。
class FakeRecorder implements VoiceRecorderBackend {
  FakeRecorder({this.permitted = true});

  bool permitted;
  final List<String> started = [];
  int stopped = 0;
  String? _path;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> start(String path) async {
    started.add(path);
    _path = path;
  }

  @override
  Future<String?> stop() async {
    stopped++;
    final path = _path;
    if (path == null) return null;
    final file = File(path);
    // 同步写：`testWidgets` 的假时钟不推进真实 IO，异步写会永远挂着。
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_wavBytes());
    _path = null;
    return path;
  }

  @override
  Future<void> dispose() async {}

  /// 44 字节 RIFF/WAVE 头 + 一点点数据。够 [VoiceResolver] 认它是条好音频。
  static List<int> _wavBytes() => [
    ...'RIFF'.codeUnits,
    36, 0, 0, 0,
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    16, 0, 0, 0, 1, 0, 1, 0,
    0x22, 0x56, 0, 0,
    0x44, 0xAC, 0, 0,
    2, 0, 16, 0,
    ...'data'.codeUnits,
    8, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,
  ];
}

/// 记下总线被要求丢弃了哪些缓存——「录完立即生效」就靠这一步。
class SpyAudioBus extends AudioBus {
  SpyAudioBus(VoiceResolver resolver) : super(resolver: resolver);

  final List<String> invalidated = [];
  final List<String> spoken = [];

  @override
  Future<void> invalidateVoice(String key) async => invalidated.add(key);

  @override
  Future<void> speak(String voiceKey, {VoicePolicy policy = VoicePolicy.queue}) async =>
      spoken.add(voiceKey);
}

ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "hanzi": [
    {"char": "木", "pinyin": "mù", "type": "pictograph", "imageKey": "tree",
     "voiceKey": "zh.hanzi.6728"}
  ],
  "spellingTargets": [
    {"id": "child", "letters": "Emmett", "voiceKey": "en.name.child"}
  ]
}
''', source: 'test.json')!,
]);

void main() {
  late Directory overridesDir;
  late SpyAudioBus audio;
  late FakeRecorder recorder;

  setUp(() {
    overridesDir = Directory.systemTemp.createTempSync('voice_overrides_test');
    audio = SpyAudioBus(VoiceResolver(overridesDir: overridesDir));
  });

  tearDown(() {
    if (overridesDir.existsSync()) overridesDir.deleteSync(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester, {bool permitted = true}) async {
    recorder = FakeRecorder(permitted: permitted);
    // 这一页是个长列表，`ListView` 只建可见的那几行。默认 800×600 的画布上
    // 汉字那一组根本没被建出来，findsNothing 于是与「功能坏了」长得一模一样。
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioBusProvider.overrideWithValue(audio),
          contentLibraryProvider.overrideWithValue(_library()),
        ],
        child: MaterialApp(home: ParentRecorderPage(backend: recorder)),
      ),
    );
    await tester.pumpAndSettle();
  }

  const key = 'zh.hanzi.6728';

  group('录音', () {
    testWidgets('录完写进 voice_overrides/，且立刻会被解析为覆盖', (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const ValueKey('record-$key')));
      await tester.pumpAndSettle();
      expect(recorder.started.single, endsWith('$key.wav'));

      await tester.tap(find.byKey(const ValueKey('record-$key')));
      await tester.pumpAndSettle();

      // 走真的解析器：这一步才是「立即生效」的实质。
      // `runAsync` 是必须的——解析要读文件头，而假时钟不会推进真实 IO。
      final source = await tester.runAsync(
        () => VoiceResolver(overridesDir: overridesDir).resolve(key),
      );
      expect(source, isA<OverrideVoice>());
    });

    testWidgets('录完让总线丢掉旧缓存——少了这一步就是「录了没生效」', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('record-$key')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('record-$key')));
      await tester.pumpAndSettle();

      expect(audio.invalidated, contains(key));
    });

    testWidgets('录第二条会先把第一条停掉，不会同时录两条', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('record-$key')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('record-en.name.child')));
      await tester.pumpAndSettle();

      expect(recorder.stopped, 1);
      expect(recorder.started, hasLength(2));
    });
  });

  group('删除', () {
    testWidgets('删掉之后回落打包的 TTS', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('record-$key')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('record-$key')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('delete-$key')));
      await tester.pumpAndSettle();

      final source = await tester.runAsync(
        () => VoiceResolver(overridesDir: overridesDir).resolve(key),
      );
      expect(source, isA<AssetVoice>(), reason: '删了就该回到打包的那条');
      expect(File('${overridesDir.path}/$key.wav').existsSync(), isFalse);
    });

    testWidgets('没录过的条目，删除键是灰的', (tester) async {
      await pumpPage(tester);
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('delete-$key')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('试听', () {
    testWidgets('点试听就念这一条', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('preview-$key')));
      await tester.pumpAndSettle();
      expect(audio.spoken, [key]);
    });
  });

  group('没有麦克风权限', () {
    testWidgets('录音键禁用并给出说明，其余功能照常', (tester) async {
      await pumpPage(tester, permitted: false);

      expect(find.byKey(const ValueKey('no-permission')), findsOneWidget);
      final record = tester.widget<IconButton>(
        find.byKey(const ValueKey('record-$key')),
      );
      expect(record.onPressed, isNull);

      // 「其余功能全部正常」——试听不需要麦克风，就不该被一起禁掉。
      await tester.tap(find.byKey(const ValueKey('preview-$key')));
      await tester.pumpAndSettle();
      expect(audio.spoken, [key]);
    });
  });

  group('可录清单', () {
    testWidgets('从内容库派生：内容包里有的，这里就有', (tester) async {
      await pumpPage(tester);
      expect(find.byKey(const ValueKey('recordable-$key')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('recordable-en.name.child')),
        findsOneWidget,
      );
      // 连接词不来自任何内容包，但少一条算式就会说一半，也得能录。
      expect(
        find.byKey(const ValueKey('recordable-zh.word.plus')),
        findsOneWidget,
      );
    });
  });
}
