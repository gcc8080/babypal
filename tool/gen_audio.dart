// 离线 TTS 音频生成工具。
//
// 读 assets/packs/*.json，枚举全部 voiceKey，调用 macOS 的 `say` 生成
// WAV（22.05 kHz / 单声道 / 16-bit），输出到 assets/audio/，并写一份 manifest。
//
// 见 design.md D4：全链路统一 WAV——flutter_soloud 不支持 AAC/M4A，
// record 的 opus 在 iOS 是 CAF 容器跨端不可读，两个约束求交后 WAV 是唯一解。
//
// 见 design.md D5：这里产出的是**打底**语音。家长随时可以录真人语音覆盖任意
// 一条，无需重新打包。因此 TTS 质量只要「能听懂」即可，不必追求完美。
//
// 用法：
//   dart run tool/gen_audio.dart            # 只生成缺失的
//   dart run tool/gen_audio.dart --force    # 全部重新生成
//   dart run tool/gen_audio.dart --dry-run  # 只列出将要生成什么
//
// 刻意不复用 lib/core/content/pack_loader.dart：那个文件 import 了
// package:flutter/services.dart，在纯 Dart VM 里跑不起来。这里只需要
// voiceKey 与朗读文本两样东西，轻量自解析反而更省事。

import 'dart:convert';
import 'dart:io';

/// 中文音色。macOS 自带，已实测可用。
const String zhVoice = 'Tingting';

/// 英文音色。
const String enVoice = 'Samantha';

const String packsDir = 'assets/packs';
const String audioDir = 'assets/audio';
const String manifestPath = '$audioDir/manifest.json';

/// 一条待生成的语音。
class VoiceEntry {
  VoiceEntry({
    required this.key,
    required this.text,
    required this.voice,
    required this.source,
  });

  final String key;
  final String text;
  final String voice;

  /// 来源内容包，仅用于报错定位。
  final String source;
}

Future<void> main(List<String> args) async {
  final force = args.contains('--force');
  final dryRun = args.contains('--dry-run');

  if (!Platform.isMacOS) {
    stderr.writeln('本工具依赖 macOS 的 `say` 命令，当前平台不支持。');
    exit(1);
  }

  final packs = Directory(packsDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (packs.isEmpty) {
    stderr.writeln('$packsDir 下没有内容包。');
    exit(1);
  }

  final entries = <String, VoiceEntry>{};
  final unresolved = <String>[];

  for (final pack in packs) {
    _collect(pack, entries, unresolved);
  }

  stdout.writeln('内容包 ${packs.length} 个，可生成语音 ${entries.length} 条。');
  if (unresolved.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('⚠️  ${unresolved.length} 条无法确定朗读文本，已跳过：');
    for (final u in unresolved.take(20)) {
      stdout.writeln('    $u');
    }
    if (unresolved.length > 20) {
      stdout.writeln('    …还有 ${unresolved.length - 20} 条');
    }
  }

  if (dryRun) {
    stdout.writeln('');
    stdout.writeln('--dry-run，未生成任何文件。');
    return;
  }

  await Directory(audioDir).create(recursive: true);

  var generated = 0;
  var skipped = 0;
  var failed = 0;

  for (final entry in entries.values) {
    final out = File('$audioDir/${entry.key}.wav');
    if (!force && out.existsSync() && out.lengthSync() > 44) {
      skipped++;
      continue;
    }

    final result = await Process.run('say', [
      '-v', entry.voice,
      '--file-format=WAVE',
      '--data-format=LEI16@22050',
      '-o', out.path,
      entry.text,
    ]);

    if (result.exitCode != 0 || !out.existsSync() || out.lengthSync() <= 44) {
      failed++;
      stderr.writeln('生成失败 ${entry.key}（"${entry.text}"）：${result.stderr}');
      continue;
    }
    generated++;
    if (generated % 50 == 0) {
      stdout.writeln('  已生成 $generated 条…');
    }
  }

  // manifest 供 VoiceResolver 做缺失检出——「内容包引用了某个 voiceKey 但
  // 音频没生成」这类问题要能离线发现，而不是等孩子点下去才没声音。
  final available = entries.keys.toList()..sort();
  await File(manifestPath).writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
          'generatedAt': DateTime.now().toIso8601String(),
          'zhVoice': zhVoice,
          'enVoice': enVoice,
          'format': 'WAV 22050Hz mono 16-bit',
          'keys': available,
        })}\n',
  );

  final totalBytes = Directory(audioDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.wav'))
      .fold<int>(0, (sum, f) => sum + f.lengthSync());

  stdout.writeln('');
  stdout.writeln('新生成 $generated 条，已存在跳过 $skipped 条，失败 $failed 条。');
  stdout.writeln(
    '音频总体积 ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB',
  );
  stdout.writeln('manifest 已写入 $manifestPath');
}

void _collect(
  File pack,
  Map<String, VoiceEntry> out,
  List<String> unresolved,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(pack.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('${pack.path}: JSON 解析失败，已跳过 ($e)');
    return;
  }
  if (decoded is! Map<String, dynamic>) return;

  void add(String? key, String? text, String voice) {
    if (key == null || key.isEmpty) return;
    if (text == null || text.isEmpty) {
      unresolved.add('${pack.path}: $key（无朗读文本）');
      return;
    }
    out[key] = VoiceEntry(
      key: key,
      text: text,
      voice: voice,
      source: pack.path,
    );
  }

  // 数字：从 value 推导中英读法，因此 numbers.json 不必逐条写文本。
  for (final item in _list(decoded['numbers'])) {
    final value = item['value'];
    if (value is! int) continue;
    add(item['voiceKey'] as String?, zhNumber(value), zhVoice);
    add(item['voiceKeyEn'] as String?, enNumber(value), enVoice);
  }

  // 汉字：字本身即朗读文本。
  for (final item in _list(decoded['hanzi'])) {
    add(item['voiceKey'] as String?, item['char'] as String?, zhVoice);
  }

  // 字母：字母本身。末尾加句点，让 TTS 读字母名而不是把它当冠词。
  for (final item in _list(decoded['letters'])) {
    final letter = (item['letter'] as String?)?.toUpperCase();
    add(item['voiceKey'] as String?, letter == null ? null : '$letter.', enVoice);
    // 音素（如 /æ/）无法由文本 TTS 可靠合成，留给真人录音覆盖。
    final phoneme = item['phonemeVoiceKey'];
    if (phoneme is String && phoneme.isNotEmpty) {
      unresolved.add('${pack.path}: $phoneme（音素需真人录音）');
    }
  }

  // 名词：模型目前不携带朗读文本。nouns.json 设计时需补 text / textEn 字段，
  // 在此之前一律报告缺失，绝不猜测——生成一条读错的音频比没有更糟。
  for (final item in _list(decoded['nouns'])) {
    add(item['voiceKey'] as String?, item['text'] as String?, zhVoice);
    add(item['voiceKeyEn'] as String?, item['textEn'] as String?, enVoice);
  }
}

List<Map<String, dynamic>> _list(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map<String, dynamic>>().toList();
}

// ─── 数字读法 ────────────────────────────────────────────────────────

const _zhDigits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

/// 0–100 的中文读法。
String zhNumber(int n) {
  if (n < 0 || n > 100) return '$n';
  if (n < 10) return _zhDigits[n];
  if (n == 100) return '一百';
  final tens = n ~/ 10;
  final ones = n % 10;
  // 10–19 读作「十一」而非「一十一」。
  final tensPart = tens == 1 ? '十' : '${_zhDigits[tens]}十';
  return ones == 0 ? tensPart : '$tensPart${_zhDigits[ones]}';
}

const _enOnes = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen',
];

const _enTens = [
  '', '', 'twenty', 'thirty', 'forty', 'fifty',
  'sixty', 'seventy', 'eighty', 'ninety',
];

/// 0–100 的英文读法。
String enNumber(int n) {
  if (n < 0 || n > 100) return '$n';
  if (n < 20) return _enOnes[n];
  if (n == 100) return 'one hundred';
  final tens = n ~/ 10;
  final ones = n % 10;
  return ones == 0 ? _enTens[tens] : '${_enTens[tens]}-${_enOnes[ones]}';
}
