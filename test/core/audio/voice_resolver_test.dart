import 'dart:io';
import 'dart:typed_data';

import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个头部合法的最小 WAV 文件。
Uint8List validWavBytes({int payload = 16}) {
  final bytes = BytesBuilder();
  bytes.add('RIFF'.codeUnits);
  bytes.add([0, 0, 0, 0]); // chunk size，校验时不看
  bytes.add('WAVE'.codeUnits);
  bytes.add('fmt '.codeUnits);
  bytes.add(List<int>.filled(20, 0)); // 凑够 44 字节的头
  bytes.add(List<int>.filled(payload, 0));
  return bytes.toBytes();
}

void main() {
  late Directory tempDir;
  late VoiceResolver resolver;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('voice_overrides_test');
    resolver = VoiceResolver(overridesDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeOverride(String key, List<int> bytes) async {
    final file = File(resolver.overridePathFor(key));
    await file.writeAsBytes(bytes);
    return file;
  }

  group('场景一：存在家长录音覆盖', () {
    test('覆盖文件合法 → 使用覆盖', () async {
      await writeOverride('zh.hanzi.mu', validWavBytes());

      final source = await resolver.resolve('zh.hanzi.mu');

      expect(source, isA<OverrideVoice>());
      expect((source as OverrideVoice).path, endsWith('zh.hanzi.mu.wav'));
    });

    test('录完立即生效——解析不缓存，同一 key 前后两次结果不同', () async {
      final before = await resolver.resolve('zh.family.baba');
      expect(before, isA<AssetVoice>(), reason: '录音前回落打包资源');

      // 家长录了一条。
      await writeOverride('zh.family.baba', validWavBytes());

      final after = await resolver.resolve('zh.family.baba');
      expect(after, isA<OverrideVoice>(), reason: '无需重启即刻生效');
    });
  });

  group('场景二：不存在覆盖', () {
    test('回落到打包资源，asset key 拼接正确', () async {
      final source = await resolver.resolve('zh.hanzi.mu');

      expect(source, isA<AssetVoice>());
      expect((source as AssetVoice).assetKey, 'assets/audio/zh.hanzi.mu.wav');
    });
  });

  group('场景三：覆盖文件损坏', () {
    test('空文件 → 回落打包资源，绝不静默', () async {
      await writeOverride('zh.hanzi.mu', <int>[]);

      final source = await resolver.resolve('zh.hanzi.mu');

      expect(source, isA<AssetVoice>());
    });

    test('长度不足 44 字节的残片 → 回落', () async {
      await writeOverride('zh.hanzi.mu', List<int>.filled(20, 0));

      final source = await resolver.resolve('zh.hanzi.mu');

      expect(source, isA<AssetVoice>());
    });

    test('长度够但不是 RIFF/WAVE（比如误存成 mp3）→ 回落', () async {
      final notWav = List<int>.filled(200, 0)..setRange(0, 3, 'ID3'.codeUnits);

      await writeOverride('zh.hanzi.mu', notWav);

      final source = await resolver.resolve('zh.hanzi.mu');

      expect(source, isA<AssetVoice>());
    });

    test('RIFF 头对但不是 WAVE 容器 → 回落', () async {
      final bytes = BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add([0, 0, 0, 0])
        ..add('AVI '.codeUnits)
        ..add(List<int>.filled(40, 0));

      await writeOverride('zh.hanzi.mu', bytes.toBytes());

      final source = await resolver.resolve('zh.hanzi.mu');

      expect(source, isA<AssetVoice>());
    });
  });

  group('资源清单与缺失检出', () {
    test('清单中没有该键且无覆盖 → MissingVoice，不抛异常', () async {
      final r = VoiceResolver(
        overridesDir: tempDir,
        availableAssetKeys: {'zh.number.1'},
      );

      expect(await r.resolve('zh.number.1'), isA<AssetVoice>());
      expect(await r.resolve('zh.number.999'), isA<MissingVoice>());
    });

    test('清单中没有但家长录了 → 仍然用覆盖', () async {
      final r = VoiceResolver(
        overridesDir: tempDir,
        availableAssetKeys: const {},
      );
      await File(r.overridePathFor('custom.key')).writeAsBytes(validWavBytes());

      expect(await r.resolve('custom.key'), isA<OverrideVoice>());
    });
  });

  group('扩展名是全链路唯一常量', () {
    test('覆盖路径与 asset key 使用同一个扩展名常量', () {
      expect(VoiceResolver.audioExtension, '.wav');
      expect(
        resolver.overridePathFor('k'),
        endsWith(VoiceResolver.audioExtension),
      );
      expect(resolver.assetKeyFor('k'), endsWith(VoiceResolver.audioExtension));
    });
  });
}
