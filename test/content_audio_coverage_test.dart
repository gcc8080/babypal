import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baby_pal/core/audio/narration.dart';
import 'package:baby_pal/core/audio/voice_resolver.dart';
import 'package:baby_pal/core/content/models.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/modules/hanzi/hanzi.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内容包与音频资源的一致性校验（openspec 任务 3.5）。
///
/// 这条校验放在测试里而非只做成脚本，是为了让 CI 兜住它：内容包里加了一个新
/// 字却忘了跑 `dart run tool/gen_audio.dart`，构建阶段就应该发现，而不是等
/// 孩子点下去发现没声音——静默是 3 岁用户无法理解的失败模式。
void main() {
  late ContentLibrary library;
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
    library = ContentLibrary(packs);
    packVoiceKeys = library.allVoiceKeys;

    final dir = Directory('assets/audio');
    audioFiles = !dir.existsSync()
        ? <String>{}
        : dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith(VoiceResolver.audioExtension))
              .map((f) => f.uri.pathSegments.last)
              .map(
                (n) => n.substring(
                  0,
                  n.length - VoiceResolver.audioExtension.length,
                ),
              )
              .toSet();
  });

  test('内容包引用的每个 iconKey 都有对应 SVG 文件', () {
    // 与音频同理：名词图是「A is for Apple」里飞进来的那张卡，缺一张就是那个
    // 字母少一张卡片。而 flutter_svg 加载失败的表现是一片空白——正是上次托盘
    // 缩略图那类「测试全绿、真机什么都没有」的失败模式。
    final missing = <String>[];
    for (final noun in library.nouns) {
      if (!File('assets/icons/${noun.iconKey}.svg').existsSync()) {
        missing.add('${noun.iconKey} ← ${noun.id}');
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          '缺少 ${missing.length} 个图标，跑 '
          '`dart run tool/fetch_openmoji.dart` 补齐：\n${missing.join('\n')}',
    );
  });

  test('图标目录带着 CC BY-SA 4.0 许可与署名', () {
    // 不是礼节而是发行条件：CC BY-SA 要求署名，家长区素材署名页也直接读它。
    final license = File('assets/icons/LICENSE.txt');
    expect(license.existsSync(), isTrue, reason: 'OpenMoji 许可证文件缺失');
    final text = license.readAsStringSync();
    expect(text, contains('CC BY-SA 4.0'));
    expect(text, contains('OpenMoji'));
  });

  test('每个字母的名词都能解析到，且首字母对得上', () {
    // 「A is for Apple」的全部承诺就在这一句上：飞进来的每张图都必须真的以
    // 这个字母开头，否则规格里「全部为正确答案」就是假的。
    final problems = <String>[];
    for (final letter in library.letters) {
      final words = library.wordsFor(letter);
      if (words.length != letter.wordNounIds.length) {
        problems.add('${letter.letter}: 有 id 解析不到名词');
      }
      if (words.isEmpty) problems.add('${letter.letter}: 一个名词都没有');
      for (final noun in words) {
        final en = noun.textEn;
        if (en == null || !en.toUpperCase().startsWith(letter.letter)) {
          problems.add('${letter.letter}: ${noun.id} 的英文名「$en」不以该字母开头');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('拼字目标用到的字母都在字母表里', () {
    final known = library.letters.map((l) => l.letter).toSet();
    for (final target in library.spellingTargets) {
      expect(
        target.letters.toSet().difference(known),
        isEmpty,
        reason: '${target.id} 需要的字母积木不存在',
      );
    }
  });

  test('合体字的部件在内容库里都找得到', () {
    // 找不到的部件会被 ContentLibrary 悄悄剔除，表现为「这个字在游戏里没有」。
    expect(
      library.unresolvedCompounds,
      isEmpty,
      reason: library.unresolvedCompounds.join('\n'),
    );
  });

  test('三部件以上的合体字，都有一条两两合成的路可走', () {
    // 部件加法只能两块两块地合（三岁的手凑不齐三块），所以「森 = 木+木+木」
    // 必须先合得出「林」。少了这个中间字，这道题就**无解**——而它在界面上
    // 与一道普通题长得一模一样，孩子会一直试到放弃。
    final compounds = library.hanzi.where((h) => h.isCompound).toList();
    List<String> flatten(String char) {
      final item = library.hanziByChar(char);
      if (item == null || !item.isCompound) return [char];
      return [for (final p in item.parts) ...flatten(p)];
    }

    String tally(List<String> parts) => (parts.toList()..sort()).join();

    final available = {for (final c in compounds) tally(flatten(c.char))};
    final unsolvable = <String>[];
    for (final compound in compounds) {
      final parts = flatten(compound.char);
      if (parts.length <= 2) continue;
      // 任取两个部件先合，合出来的东西必须也是个字。
      final pair = tally([parts[0], parts[1]]);
      if (!available.contains(pair)) {
        unsolvable.add('${compound.char}（${parts.join('+')}）缺少两两合成的中间字');
      }
    }
    expect(unsolvable, isEmpty, reason: unsolvable.join('\n'));
  });

  test('反义词两边的字都在内容包里，否则跷跷板会哑掉', () {
    final missing = <String>[];
    for (final pair in library.antonyms) {
      for (final char in [pair.left, pair.right]) {
        if (library.hanziByChar(char) == null) {
          missing.add('$char（来自 ${pair.left}↔${pair.right}）');
        }
      }
    }
    expect(missing, isEmpty, reason: '这些字取不到读音：${missing.join('、')}');
  });

  test('内容包引用的每个 voiceKey 都有对应音频文件', () {
    final missing = packVoiceKeys.difference(audioFiles).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason:
          '缺少 ${missing.length} 条音频，跑 '
          '`dart run tool/gen_audio.dart` 补齐：\n${missing.take(20).join('\n')}',
    );
  });

  test('播报用的连接词与整句都已生成', () {
    // 这些键不来自任何内容包——它们是界面播报用词（加 / 等于 / 可以分成 /
    // 十个一是一个十），由 gen_audio 的内置表产出。少一条就会让算式播报
    // 中间缺一块，而这种缺失在儿童端表现为「说一半就停了」。
    // 汉字模块的「木 加 木 等于 林」复用的正是加法那两条，所以并进来一起查：
    // 它们哪天被从 gen_audio 的表里删掉，两个模块会一起哑，而不是只哑一个。
    final needed = {
      ...Narration.connectiveKeys,
      ...HanziNarration.connectiveKeys,
    };
    final missing = needed.difference(audioFiles).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason:
          '缺少 ${missing.length} 条播报用音频，跑 '
          '`dart run tool/gen_audio.dart` 补齐：\n${missing.join('\n')}',
    );
  });

  test('manifest 与实际文件一致', () {
    final file = File('assets/audio/manifest.json');
    expect(file.existsSync(), isTrue, reason: 'manifest 应由 gen_audio 产出');

    final manifest =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final keys = (manifest['keys'] as List).cast<String>().toSet();

    expect(keys.difference(audioFiles), isEmpty, reason: 'manifest 声称存在但文件缺失');
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
      final bytes = File(
        'assets/audio/$key${VoiceResolver.audioExtension}',
      ).readAsBytesSync();
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
