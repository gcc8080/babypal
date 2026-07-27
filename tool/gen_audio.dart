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
import 'dart:math' as math;
import 'dart:typed_data';

/// 中文音色。
///
/// **从 Tingting 换到 Flo**：Tingting 读「三」时，声母 /s/ 的能量 98.8% 落在
/// 8–11 kHz，其中 24% 挤在 10–11 kHz——紧贴 22.05 kHz 采样率的奈奎斯特上限。
/// 那个位置任何一点高频衰减都会把 /s/ 抹掉，`sān` 剩下 `an`，听起来正好是英文
/// 字母 N。加上 Tingting 的「三」鼻音尾与元音一样长（各 120ms），退化得更彻底。
/// 「四」没有鼻音尾，掉了 /s/ 只剩 `ì`，不像任何熟悉的音，所以只有「三」暴露。
///
/// Flo 把 /s/ 放在 2–6 kHz，频带正中间。交付设备 MI 8 SE 是 5.88 寸机，小喇叭
/// 在 9 kHz 上基本没输出——**只提采样率治不了根，换音色才行**。
const String zhVoiceName = 'Flo';
const String zhVoiceLocale = 'zh_CN';

/// 英文音色。人耳验收无问题，不动。
const String enVoiceName = 'Samantha';
const String enVoiceLocale = 'en_US';

/// 解析后的实际音色名，由 [resolveVoice] 在 main 中填入，并写进 manifest。
late final String zhVoice;
late final String enVoice;

/// 裁剪静音的判定阈值（相对满量程）。
///
/// 取得很低是因为**擦音的起音本来就轻**：Tingting 的 /s/ 起始窗口只有满量程的
/// 0.7%。阈值定高一点就会把声母切掉，那正是我们要修的那个 bug。
const double silenceThreshold = 0.004;

/// 裁剪时在前后各留出的余量。
///
/// 前面留得比后面短：前导静音本来就只有 20ms 左右，而**切掉声母的代价远大于
/// 多留 40ms 静音**。
const int leadPadMs = 40;
const int tailPadMs = 60;

/// 峰值归一化目标（满量程 32767）。
///
/// 现状是中英响度不齐——中文峰值均值 17030、英文 22003，最低的中文条目只有
/// 9718（比英文低 10 dB）。而每次播报都是中英连着放，不齐就会一句响一句闷。
/// 统一到 22000（约 -3.5 dBFS），留出余量让语音叠音效时不削顶。
const int normalizePeak = 22000;

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

  final zh = await resolveVoice(zhVoiceName, zhVoiceLocale);
  final en = await resolveVoice(enVoiceName, enVoiceLocale);
  if (zh == null || en == null) {
    stderr.writeln(
      '找不到音色：${zh == null ? "$zhVoiceName($zhVoiceLocale) " : ""}'
      '${en == null ? "$enVoiceName($enVoiceLocale)" : ""}\n'
      '用 `say -v "?"` 看这台机器上有哪些，然后改本文件顶部的常量。',
    );
    exit(1);
  }
  zhVoice = zh;
  enVoice = en;
  stdout.writeln('音色：中文「$zhVoice」／英文「$enVoice」');

  final packs =
      Directory(packsDir)
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

  _collectNarrationWords(entries);
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
      '-v',
      entry.voice,
      '--file-format=WAVE',
      '--data-format=LEI16@22050',
      '-o',
      out.path,
      entry.text,
    ]);

    if (result.exitCode != 0 || !out.existsSync() || out.lengthSync() <= 44) {
      failed++;
      stderr.writeln('生成失败 ${entry.key}（"${entry.text}"）：${result.stderr}');
      continue;
    }

    if (!_postProcess(out)) {
      failed++;
      stderr.writeln('后处理失败 ${entry.key}（"${entry.text}"）');
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
  final manifest = <String, Object?>{
    'generatedAt': DateTime.now().toIso8601String(),
    'zhVoice': zhVoice,
    'enVoice': enVoice,
    'format': 'WAV 22050Hz mono 16-bit',
    'keys': available,
  };
  await File(
    manifestPath,
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');

  final totalBytes = Directory(audioDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.wav'))
      .fold<int>(0, (sum, f) => sum + f.lengthSync());

  stdout.writeln('');
  stdout.writeln('新生成 $generated 条，已存在跳过 $skipped 条，失败 $failed 条。');
  stdout.writeln('音频总体积 ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB');
  stdout.writeln('manifest 已写入 $manifestPath');
}

/// 播报用的连接词。
///
/// **刻意只生成词片，不生成整句。** 10 以内的加法有 45 个有序算式，分解也有
/// 45 个，整句录制要 180 条音频（约 16 MB），而词片只要这 8 条（约 0.25 MB），
/// 还能拼出任意算式——他已经在数 100 了，迟早要报到 10 以外。
///
/// 决定性的理由其实是家长录音：覆盖层的全部意义是「你录四十来条就能把打底
/// 语音换成爸妈的声音」。词片方案下录一次「加」就覆盖全部算式；整句方案下
/// 要录 45 句，那个覆盖层就名存实亡了。
///
/// `AudioBus` 的语音队列本来就是为连续播报设计的（见 `VoicePolicy.queue`
/// 的注释），词片间天然留一个小停顿——对正在学的孩子反而比连读更清楚。
///
/// 这些键不来自任何内容包：它们是界面播报用词，不是学习内容。
const Map<String, String> zhNarrationWords = {
  'zh.word.plus': '加',
  'zh.word.equals': '等于',
  'zh.word.and': '和',
  'zh.word.isMadeOf': '可以分成',
};

const Map<String, String> enNarrationWords = {
  'en.word.plus': 'plus',
  'en.word.equals': 'equals',
  'en.word.and': 'and',
  'en.word.isMadeOf': 'is made of',
};

/// 拼不出来、只能整句录的播报。
///
/// 「十个一是一个十」正是位值这一课要说的那句话，没法用数词加连接词拼出来，
/// 且只有这一句，整句生成是划算的。凡是能拼的一律走 [zhNarrationWords]。
const Map<String, String> zhNarrationPhrases = {
  'zh.phrase.tenOnesMakeATen': '十个一，是一个十',
};

const Map<String, String> enNarrationPhrases = {
  'en.phrase.tenOnesMakeATen': 'ten ones make one ten',
};

/// 字母音素（letter sound）的 TTS 拼写。
///
/// **`say` 没有音素输入通道**——`[[inpt PHON]]` 这套老的 Speech Manager 转义在
/// 当前 macOS 上不再被解析，实测会把 `inpt`、`PHON`、`1AE` 当三个词念出来。
/// 所以只能反过来做：写一个能让英文 TTS 的字素→音素规则**恰好吐出那个音**的
/// 拼写。
///
/// 分两类，界线是语音学事实而不是口味：
///
/// - **连续音**（l m n r s v z）可以拖长，写成延长拼写 `ll` `mm` `sss`，
///   听到的就是纯粹的 /l/ /m/ /s/，没有多余元音。
/// - **爆破音与塞擦音**（b d g j k p t…）**物理上发不出孤立的音**，离开元音
///   就只是一声气爆。写成 `buh` `kuh`，即他每天看的字母儿歌里的读法。
///   拼读教学法反对这个「schwa 尾巴」，但那是给已经能听辨音素的孩子的要求，
///   对一个三岁的中文母语者，能听清、能模仿比理论纯度重要。
///
/// f 本是连续音，但 `ff`/`fff` 都被 TTS 逐字母念成「эф эф」（实测切成 2–5 段），
/// 只能退回 `fuh`。
///
/// 这 26 条是**家长录音的第一优先级**：TTS 拼写再怎么调也只是逼近，爸爸对着
/// 麦克风说一句 /æ/ 就彻底解决了。见 design.md D5 的覆盖层。
const Map<String, String> letterPhonemes = {
  'a': 'ah',
  'b': 'buh',
  'c': 'kuh',
  'd': 'duh',
  'e': 'eh',
  'f': 'fuh',
  'g': 'guh',
  'h': 'huh',
  'i': 'ih',
  'j': 'juh',
  'k': 'kuh',
  'l': 'll',
  'm': 'mm',
  'n': 'nn',
  'o': 'aw',
  'p': 'puh',
  'q': 'kwuh',
  'r': 'rr',
  's': 'sss',
  't': 'tuh',
  'u': 'uh',
  'v': 'vv',
  'w': 'wuh',
  'x': 'ks',
  'y': 'yuh',
  'z': 'zzz',
};

// ─── 音色解析 ────────────────────────────────────────────────────────

/// 按「名字前缀 + 语言标签」找音色，而不是写死显示名。
///
/// 新一代音色的显示名是**本地化的**：中文系统下是「Flo (中文（中国大陆）)」，
/// 英文系统下是「Flo (Chinese (China mainland))」。写死会在另一台机器上直接
/// 失败，而且失败信息是 `say` 的一句 "Voice not found"，很难看出原因。
Future<String?> resolveVoice(String namePrefix, String locale) async {
  final result = await Process.run('say', ['-v', '?']);
  if (result.exitCode != 0) return null;

  for (final line in const LineSplitter().convert('${result.stdout}')) {
    // 每行形如：`Flo (中文（中国大陆）)      zh_CN    # 你好！我叫Flo。`
    // 名字里有空格和括号，所以先切掉注释，再从右边取语言标签。
    final head = line.split('#').first.trimRight();
    final split = head.lastIndexOf(RegExp(r'\s'));
    if (split < 0) continue;

    final name = head.substring(0, split).trim();
    if (head.substring(split).trim() != locale) continue;
    if (name == namePrefix || name.startsWith('$namePrefix ')) return name;
  }
  return null;
}

// ─── WAV 后处理 ──────────────────────────────────────────────────────

/// 裁掉首尾静音并做峰值归一化，然后以规范的 44 字节头重写。
///
/// 两件事都不是锦上添花：
///
/// - **裁静音**：新一代音色在词尾留了约 520ms 静音。算式播报是靠语音队列把
///   「三」「加」「二」「等于」「五」串起来的，队列**要等每条播完**才放下一条，
///   520ms × 5 = 多出 2.6 秒。这会把一句话拖成一段等待。
/// - **归一化**：中英是连着放的两个声道，响度不齐就会一句响一句闷。
///
/// 返回 false 表示这个文件没法处理（保持原样，由调用方计为失败）。
bool _postProcess(File file) {
  final bytes = file.readAsBytesSync();
  final pcm = _readWav(bytes);
  if (pcm == null) return false;

  final samples = pcm.samples;
  if (samples.isEmpty) return false;

  var peak = 0;
  for (final s in samples) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  if (peak == 0) return false;

  // 裁剪：阈值取「相对峰值」与「绝对下限」的较大者，避免整条都很轻时
  // 把有效声音当成静音切掉。
  final threshold = math.max(
    (peak * silenceThreshold).round(),
    (32767 * silenceThreshold).round(),
  );
  var first = 0;
  while (first < samples.length && samples[first].abs() < threshold) {
    first++;
  }
  var last = samples.length - 1;
  while (last > first && samples[last].abs() < threshold) {
    last--;
  }
  if (last <= first) return false;

  final lead = pcm.sampleRate * leadPadMs ~/ 1000;
  final tail = pcm.sampleRate * tailPadMs ~/ 1000;
  final start = math.max(0, first - lead);
  final end = math.min(samples.length, last + tail + 1);

  final gain = normalizePeak / peak;
  final trimmed = Int16List(end - start);
  for (var i = 0; i < trimmed.length; i++) {
    final v = (samples[start + i] * gain).round();
    trimmed[i] = v.clamp(-32768, 32767);
  }

  file.writeAsBytesSync(_writeWav(trimmed, pcm.sampleRate));
  return true;
}

class _Pcm {
  _Pcm(this.samples, this.sampleRate);
  final Int16List samples;
  final int sampleRate;
}

/// 解析 RIFF/WAVE，取出单声道 16-bit PCM。
///
/// **必须逐块遍历，不能假定 44 字节头**：`say` 在 `fmt ` 与 `data` 之间插了一个
/// 4044 字节的 `FLLR` 对齐填充块，按固定偏移读会拿到一堆零。
_Pcm? _readWav(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final data = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;

  int? sampleRate;
  var channels = 1;
  var bits = 16;

  var pos = 12;
  while (pos + 8 <= bytes.length) {
    final id = tag(pos);
    final size = data.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (body + size > bytes.length) break;

    if (id == 'fmt ' && size >= 16) {
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (sampleRate == null || channels != 1 || bits != 16) return null;
      final count = size ~/ 2;
      final out = Int16List(count);
      for (var i = 0; i < count; i++) {
        out[i] = data.getInt16(body + i * 2, Endian.little);
      }
      return _Pcm(out, sampleRate);
    }
    // 块长为奇数时有一个填充字节。
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

/// 写规范的 44 字节头单声道 WAV。
Uint8List _writeWav(Int16List samples, int sampleRate) {
  final dataBytes = samples.length * 2;
  final out = ByteData(44 + dataBytes);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      out.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  out.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // 单声道
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little); // byteRate
  out.setUint16(32, 2, Endian.little); // blockAlign
  out.setUint16(34, 16, Endian.little); // 位深
  tag(36, 'data');
  out.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    out.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}

void _collectNarrationWords(Map<String, VoiceEntry> out) {
  void addAll(Map<String, String> words, String voice) {
    for (final entry in words.entries) {
      out[entry.key] = VoiceEntry(
        key: entry.key,
        text: entry.value,
        voice: voice,
        source: '<narration>',
      );
    }
  }

  addAll(zhNarrationWords, zhVoice);
  addAll(enNarrationWords, enVoice);
  addAll(zhNarrationPhrases, zhVoice);
  addAll(enNarrationPhrases, enVoice);
}

void _collect(File pack, Map<String, VoiceEntry> out, List<String> unresolved) {
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
    add(
      item['voiceKey'] as String?,
      letter == null ? null : '$letter.',
      enVoice,
    );
    // 音素：查 [letterPhonemes] 的拼写近似。查不到就报告缺失而不是猜——
    // 一条读错的音素比没有音素更糟，它教的是错的东西。
    final phoneme = item['phonemeVoiceKey'];
    if (phoneme is String && phoneme.isNotEmpty) {
      add(phoneme, letterPhonemes[letter?.toLowerCase()], enVoice);
    }
  }

  // 名词：中英两个声道，朗读文本由内容包直接给出（无法从 id 推导）。
  for (final item in _list(decoded['nouns'])) {
    add(item['voiceKey'] as String?, item['text'] as String?, zhVoice);
    add(item['voiceKeyEn'] as String?, item['textEn'] as String?, enVoice);
  }

  // 拼字目标：朗读文本就是名字本身，从字母序列还原，避免同一个名字在包里
  // 写两遍然后哪天改了一处忘了另一处。
  for (final item in _list(decoded['spellingTargets'])) {
    final letters = item['letters'] as String?;
    final name = letters == null || letters.isEmpty
        ? null
        : letters[0].toUpperCase() + letters.substring(1).toLowerCase();
    add(item['voiceKey'] as String?, name, enVoice);
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
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];

const _enTens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
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
