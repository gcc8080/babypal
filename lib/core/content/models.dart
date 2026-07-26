import 'package:flutter/foundation.dart';

/// 汉字的构成方式。
enum HanziType {
  /// 象形字——由实物图渐变为字形。他已认识的 山田土木/日月水火 全是这类。
  pictograph,

  /// 合体字——由部件组合而成，如 木+木=林、日+月=明。
  ///
  /// 这类直接复用加法模块的合体交互：对他而言 `木+木=林` 和 `3+2=5`
  /// 是同一个动作的两种皮肤。
  compound,
}

/// 全部内容条目的共同契约：每条都必须能被播报。
abstract class ContentItem {
  const ContentItem({required this.voiceKey, this.voiceKeyEn});

  /// 主语音键（中文）。与 `assets/audio/<voiceKey>.wav` 一一对应。
  final String voiceKey;

  /// 英文语音键。他会说 0–100 的英文和常见名词的英文，
  /// 因此双语是同一条内容的「双声道」，不是两套课程。
  final String? voiceKeyEn;
}

@immutable
class NumberItem extends ContentItem {
  const NumberItem({
    required this.value,
    required super.voiceKey,
    super.voiceKeyEn,
  });

  final int value;

  /// 十进制拆解：23 → 2 个十条 + 3 个单块。
  ///
  /// 这是数字模块的核心——他已经会数到 100，下一台阶是**理解**位值，
  /// 而不是继续数数。
  int get tens => value ~/ 10;
  int get ones => value % 10;

  @override
  String toString() => 'NumberItem($value)';
}

@immutable
class LetterItem extends ContentItem {
  const LetterItem({
    required this.letter,
    required super.voiceKey,
    this.phonemeVoiceKey,
    this.wordIconKeys = const [],
    super.voiceKeyEn,
  });

  /// 大写字母，如 "A"。
  final String letter;

  /// 音素语音键，如 /æ/。字母名与字母音是两件事，分开存。
  final String? phonemeVoiceKey;

  /// 「A is for Apple」里那几张图的图标键。
  ///
  /// 列表里**每一个都是正确答案**——Apple / Ant / Alligator 都以 A 开头，
  /// 点哪个都欢呼。这是「无挫败」红线在内容层的体现。
  final List<String> wordIconKeys;

  String get lowercase => letter.toLowerCase();

  @override
  String toString() => 'LetterItem($letter)';
}

@immutable
class HanziItem extends ContentItem {
  const HanziItem({
    required this.char,
    required this.pinyin,
    required this.type,
    required super.voiceKey,
    this.imageKey,
    this.parts = const [],
    super.voiceKeyEn,
  });

  final String char;
  final String pinyin;
  final HanziType type;

  /// 象形字对应的实物图标键（如「木」→ tree）。
  final String? imageKey;

  /// 合体字的组成部件，如 林 → ["木", "木"]。
  final List<String> parts;

  bool get isCompound => type == HanziType.compound;

  @override
  String toString() => 'HanziItem($char, ${type.name})';
}

@immutable
class NounItem extends ContentItem {
  const NounItem({
    required this.id,
    required this.category,
    required this.iconKey,
    required super.voiceKey,
    super.voiceKeyEn,
  });

  final String id;

  /// 动物 / 颜色 / 形状 / 水果 / 交通工具。
  final String category;

  /// OpenMoji 图标键。
  final String iconKey;

  @override
  String toString() => 'NounItem($id, $category)';
}

/// 一组反义词，如 大↔小。做成跷跷板玩法。
@immutable
class AntonymPair {
  const AntonymPair(this.left, this.right);

  final String left;
  final String right;

  @override
  bool operator ==(Object other) =>
      other is AntonymPair && other.left == left && other.right == right;

  @override
  int get hashCode => Object.hash(left, right);

  @override
  String toString() => 'AntonymPair($left ↔ $right)';
}

/// 一个内容包的解析结果。
@immutable
class ContentPack {
  const ContentPack({
    required this.schemaVersion,
    required this.source,
    this.numbers = const [],
    this.letters = const [],
    this.hanzi = const [],
    this.nouns = const [],
    this.antonyms = const [],
    this.skipped = const [],
  });

  final int schemaVersion;

  /// 来源文件路径，仅用于日志定位。
  final String source;

  final List<NumberItem> numbers;
  final List<LetterItem> letters;
  final List<HanziItem> hanzi;
  final List<NounItem> nouns;
  final List<AntonymPair> antonyms;

  /// 被跳过的非法条目及原因。
  ///
  /// 保留下来而不是直接丢弃，是为了让「内容包写错了」这件事在开发期可见——
  /// 否则一个拼错的字段会安静地让某个字从 App 里消失。
  final List<String> skipped;

  bool get isEmpty =>
      numbers.isEmpty &&
      letters.isEmpty &&
      hanzi.isEmpty &&
      nouns.isEmpty &&
      antonyms.isEmpty;

  /// 本包引用到的全部语音键，供构建工具生成音频清单、离线检出缺失。
  Set<String> get allVoiceKeys => {
        for (final item in [...numbers, ...letters, ...hanzi, ...nouns]) ...[
          item.voiceKey,
          if (item.voiceKeyEn != null) item.voiceKeyEn!,
        ],
        for (final letter in letters)
          if (letter.phonemeVoiceKey != null) letter.phonemeVoiceKey!,
      };
}
