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

/// 全部可录内容，按「先录哪些」排序。
///
/// 见 6.6：生日前优先录的是**家人称谓、孩子的名字、鼓励语**——那几条是
/// 这个覆盖层存在的全部理由。TTS 打底保证功能完整，真人语音录一条替换一条，
/// 永远不需要重新打包（design.md D5）。
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

  add('名词', [
    for (final item in library.nouns) ...[
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
