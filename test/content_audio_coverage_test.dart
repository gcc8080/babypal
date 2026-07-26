import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:baby_pal/core/content/models.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内容包与音频资源的一致性校验（openspec 任务 3.5）。
///
/// 这条校验放在测试里而非只做成脚本，是为了让 CI 兜住它：内容包里加了一个新
/// 字却忘了跑 `dart run tool/gen_audio.dart`，构建阶段就应该发现，而不是等
/// 孩子点下去发现没声音——静默是 3 岁用户无法理解的失败模式。
void main() {
  late Set<String> packVoiceKeys;
  late Set<String> audioFiles;

  setUpAll(() {
    const loader = PackLoader();
    final packs = Directory('assets/packs')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => loader.parse(f.readAsStringSync(), source: f.path))
        .whereType<ContentPack>()
        .toList();

    expect(packs, isNotEmpty, reason: 'assets/packs 下应有内容包');
    packVoiceKeys = ContentLibrary(packs).allVoiceKeys;

    final dir = Directory('assets/audio');
    audioFiles = !dir.existsSync()
        ? <String>{}
        : dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith(VoiceResolver.audioExtension))
            .map((f) => f.uri.pathSegments.last)
            .map((n) => n.substring(
                  0,
                  n.length - VoiceResolver.audioExtension.length,
                ))
            .toSet();
  });

  test('内容包引用的每个 voiceKey 都有对应音频文件', () {
    final missing = packVoiceKeys.difference(audioFiles).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason: '缺少 ${missing.length} 条音频，跑 '
          '`dart run tool/gen_audio.dart` 补齐：\n${missing.take(20).join('\n')}',
    );
  });

  test('manifest 与实际文件一致', () {
    final file = File('assets/audio/manifest.json');
    expect(file.existsSync(), isTrue, reason: 'manifest 应由 gen_audio 产出');

    final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final keys = (manifest['keys'] as List).cast<String>().toSet();

    expect(
      keys.difference(audioFiles),
      isEmpty,
      reason: 'manifest 声称存在但文件缺失',
    );
    expect(
      packVoiceKeys.difference(keys),
      isEmpty,
      reason: '内容包引用的键未出现在 manifest 中',
    );
  });

  test('音频均为合法的 WAV：单声道 / 22.05kHz / 16-bit', () {
    // 抽查而非全量——202 个文件全读一遍会让测试变慢，而格式由同一个工具
    // 统一产出，抽样足以发现格式性错误。
    final sample = audioFiles.take(12);
    for (final key in sample) {
      final bytes = File('assets/audio/$key${VoiceResolver.audioExtension}')
          .readAsBytesSync();
      expect(bytes.length, greaterThan(44), reason: '$key 文件过小');

      final header = bytes.buffer.asByteData(0, 44);
      expect(
        String.fromCharCodes(bytes.sublist(0, 4)),
        'RIFF',
        reason: '$key 不是 RIFF',
      );
      expect(
        String.fromCharCodes(bytes.sublist(8, 12)),
        'WAVE',
        reason: '$key 不是 WAVE',
      );
      expect(header.getUint16(22, Endian.little), 1, reason: '$key 应为单声道');
      expect(
        header.getUint32(24, Endian.little),
        22050,
        reason: '$key 采样率应为 22050',
      );
      expect(
        header.getUint16(34, Endian.little),
        16,
        reason: '$key 位深应为 16-bit',
      );
    }
  });
}
