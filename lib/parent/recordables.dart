import 'package:flutter/foundation.dart';

import '../core/audio/narration.dart';
import '../core/content/pack_loader.dart';
import '../modules/hanzi/hanzi.dart';

/// 一条可以被真人语音覆盖的内容。
@immutable
class Recordable {
  const Recordable({
    required this.voiceKey,
    required this.label,
    required this.hint,
  });

  final String voiceKey;

  /// 家长在列表里看到的名字。
  final String label;

  /// 「这条该念什么」。
  ///
  /// 没有它就只剩一个 `zh.hanzi.6797` ——**照着键名是录不出内容的**，
  /// 而录错一条比没录更糟：孩子会听见一个大人用肯定的语气念错的字。
  final String hint;
}

/// 一组可录内容。
@immutable
class RecordableGroup {
  const RecordableGroup({required this.title, required this.items});

  final String title;
  final List<Recordable> items;
}

/// 家人称谓在内容包里的分类名。
///
/// 与「先录这些」直接绑定：见 6.6，生日前优先录的就是家人称谓与孩子的名字。
const String kFamilyCategory = 'family';

/// 全部可录内容，按「先录哪些」排序。
///
/// 见 6.6：生日前优先录的是**家人称谓、孩子的名字、鼓励语、生日台词**——
/// 那几条是这个覆盖层存在的全部理由。TTS 打底保证功能完整，真人语音录一条
/// 替换一条，永远不需要重新打包（design.md D5）。
///
/// 所以这四类**排在最前面，且各自独立成节**。后面那五百多条（汉字、数字、
/// 名词、字母）不是不能录，是不该挡在前面：真正决定这份礼物是什么味道的，
/// 是他听见爸爸妈妈叫他名字的那一条。
///
/// 列表整个从 [ContentLibrary] 派生：明年加一个内容包，录音页里自动就有
/// 那些新条目，不改一行代码。
List<RecordableGroup> recordableGroups(ContentLibrary library) {
  final groups = <RecordableGroup>[];

  void add(String title, List<Recordable> items) {
    if (items.isNotEmpty) groups.add(RecordableGroup(title: title, items: items));
  }

  // 名字排第一：`en.name.child` 是他自己的名字，整个 App 里最值得用真人
  // 声音说出来的一条。
  add('名字', [
    for (final target in library.spellingTargets)
      Recordable(
        voiceKey: target.voiceKey,
        label: target.letters.join(),
        hint: '念出「${target.letters.join()}」这个名字',
      ),
  ]);

  final family = [
    for (final noun in library.nouns)
      if (noun.category == kFamilyCategory) noun,
  ];
  add('家人称谓', [
    for (final noun in family) ...[
      Recordable(
        voiceKey: noun.voiceKey,
        label: noun.text,
        // 谁来录这一条，比录得好不好重要得多：「爸爸」该是妈妈的声音，
        // 「妈妈」该是爸爸的声音——他会立刻听出来那是谁在叫谁。
        hint: '念「${noun.text}」',
      ),
      if (noun.voiceKeyEn != null && noun.textEn != null)
        Recordable(
          voiceKey: noun.voiceKeyEn!,
          label: '${noun.text}（英）',
          hint: 'say “${noun.textEn}”',
        ),
    ],
  ]);

  for (final entry in const [('praise', '鼓励语'), ('birthday', '生日台词')]) {
    final phrases = library.phrasesIn(entry.$1);
    add(entry.$2, [
      for (final phrase in phrases) ...[
        Recordable(
          voiceKey: phrase.voiceKey,
          label: phrase.text,
          hint: '念「${phrase.text}」',
        ),
        if (phrase.voiceKeyEn != null && phrase.textEn != null)
          Recordable(
            voiceKey: phrase.voiceKeyEn!,
            label: '${phrase.text}（英）',
            hint: 'say “${phrase.textEn}”',
          ),
      ],
    ]);
  }

  add('连接词', [
    for (final key in _sorted({
      ...Narration.connectiveKeys,
      ...HanziNarration.connectiveKeys,
    }))
      Recordable(voiceKey: key, label: _connectiveLabel(key), hint: _connectiveLabel(key)),
  ]);

  add('汉字', [
    for (final item in library.hanzi)
      Recordable(
        voiceKey: item.voiceKey,
        label: item.char,
        hint: '念「${item.char}」（${item.pinyin}）',
      ),
  ]);

  // 家人称谓已经在上面单独一节了，这里排除掉——同一条出现两次，
  // 家长会以为要录两遍。
  add('名词', [
    for (final item in library.nouns)
      if (item.category != kFamilyCategory) ...[
      Recordable(
        voiceKey: item.voiceKey,
        label: item.text,
        hint: '念「${item.text}」',
      ),
      if (item.voiceKeyEn != null && item.textEn != null)
        Recordable(
          voiceKey: item.voiceKeyEn!,
          label: item.textEn!,
          hint: 'say “${item.textEn}”',
        ),
    ],
  ]);

  add('字母', [
    for (final item in library.letters) ...[
      Recordable(
        voiceKey: item.voiceKey,
        label: item.letter,
        hint: '念字母名「${item.letter}」',
      ),
      if (item.phonemeVoiceKey != null)
        Recordable(
          voiceKey: item.phonemeVoiceKey!,
          label: '${item.letter} 的音',
          // 字母名与字母音是两件事：A 念「诶」，音是 /æ/。
          // 这条提示必须点破，否则两条会被录成同一段。
          hint: '念字母 ${item.letter} 的**发音**（不是字母名）',
        ),
    ],
  ]);

  add('数字', [
    for (final item in library.numbers) ...[
      Recordable(
        voiceKey: item.voiceKey,
        label: '${item.value}',
        hint: '念「${item.value}」',
      ),
      if (item.voiceKeyEn != null)
        Recordable(
          voiceKey: item.voiceKeyEn!,
          label: '${item.value}（英）',
          hint: 'say “${item.value}”',
        ),
    ],
  ]);

  return groups;
}

List<String> _sorted(Set<String> keys) => keys.toList()..sort();

String _connectiveLabel(String key) => switch (key) {
  'zh.word.plus' => '加',
  'zh.word.equals' => '等于',
  'zh.word.and' => '和',
  'zh.word.isMadeOf' => '可以分成',
  'zh.phrase.tenOnesMakeATen' => '十个一，是一个十',
  'en.word.plus' => 'plus',
  'en.word.equals' => 'equals',
  'en.word.and' => 'and',
  'en.word.isMadeOf' => 'is made of',
  'en.phrase.tenOnesMakeATen' => 'ten ones make one ten',
  _ => key,
};
