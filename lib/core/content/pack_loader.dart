import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'models.dart';

/// 内容包加载器。
///
/// 见 design.md：内容与代码分离是这个 App 能陪他从 3 岁用到 5 岁的前提——
/// 明年加一个 `hanzi_l2.json` 就是新版本，不改一行 Dart。
///
/// 降级策略分两级：
/// - **整包级**：`schemaVersion` 缺失或过高 → 跳过整包，其余包照常加载
/// - **条目级**：单条数据非法 → 跳过该条，同包其余条目照常可用
///
/// 两级都只记录不抛异常。一个拼错的字段不该让孩子打不开 App。
class PackLoader {
  const PackLoader({this.bundle});

  /// 当前代码支持的最高 schema 版本。
  static const int supportedSchemaVersion = 1;

  final AssetBundle? bundle;

  AssetBundle get _bundle => bundle ?? rootBundle;

  /// 从 assets 加载并合并多个内容包。
  Future<ContentLibrary> loadAll(List<String> assetPaths) async {
    final packs = <ContentPack>[];
    for (final path in assetPaths) {
      try {
        final raw = await _bundle.loadString(path);
        final pack = parse(raw, source: path);
        if (pack != null) packs.add(pack);
      } on Exception catch (e) {
        debugPrint('PackLoader: 读取失败，已跳过 -> $path ($e)');
      }
    }
    return ContentLibrary(packs);
  }

  /// 解析单个内容包。
  ///
  /// 刻意是同步纯函数：给定字符串就能得到结果，不碰 IO 也不碰 AssetBundle，
  /// 因此全部降级路径都能直接单测。
  ///
  /// 返回 null 表示整包被拒（版本不受支持或 JSON 结构非法）。
  ContentPack? parse(String rawJson, {required String source}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (e) {
      debugPrint('PackLoader: JSON 解析失败，跳过整包 -> $source ($e)');
      return null;
    }

    if (decoded is! Map<String, dynamic>) {
      debugPrint('PackLoader: 顶层不是对象，跳过整包 -> $source');
      return null;
    }

    final version = decoded['schemaVersion'];
    if (version is! int) {
      debugPrint('PackLoader: 缺少或非法的 schemaVersion，跳过整包 -> $source');
      return null;
    }
    if (version > supportedSchemaVersion) {
      debugPrint(
        'PackLoader: schemaVersion $version 高于当前支持的 '
        '$supportedSchemaVersion，跳过整包 -> $source',
      );
      return null;
    }

    final skipped = <String>[];

    final numbers = _parseList(
      decoded['numbers'],
      source: source,
      skipped: skipped,
      parseOne: _parseNumber,
    );
    final letters = _parseList(
      decoded['letters'],
      source: source,
      skipped: skipped,
      parseOne: _parseLetter,
    );
    final nouns = _parseList(
      decoded['nouns'],
      source: source,
      skipped: skipped,
      parseOne: _parseNoun,
    );
    final hanzi = _parseHanziList(
      decoded['hanzi'],
      source: source,
      skipped: skipped,
    );
    final antonyms = _parseAntonyms(
      decoded['antonyms'],
      source: source,
      skipped: skipped,
    );
    final spellingTargets = _parseList(
      decoded['spellingTargets'],
      source: source,
      skipped: skipped,
      parseOne: _parseSpellingTarget,
    );
    final phrases = _parseList(
      decoded['phrases'],
      source: source,
      skipped: skipped,
      parseOne: _parsePhrase,
    );

    return ContentPack(
      schemaVersion: version,
      source: source,
      numbers: numbers,
      letters: letters,
      hanzi: hanzi,
      nouns: nouns,
      antonyms: antonyms,
      spellingTargets: spellingTargets,
      phrases: phrases,
      skipped: skipped,
    );
  }

  // ─── 条目解析 ──────────────────────────────────────────────────────

  List<T> _parseList<T>(
    Object? raw, {
    required String source,
    required List<String> skipped,
    required T? Function(Map<String, dynamic>) parseOne,
  }) {
    if (raw == null) return const [];
    if (raw is! List) {
      skipped.add('$source: 字段不是数组，已忽略');
      return const [];
    }

    final result = <T>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map<String, dynamic>) {
        skipped.add('$source[$i]: 条目不是对象');
        continue;
      }
      final parsed = parseOne(entry);
      if (parsed == null) {
        skipped.add('$source[$i]: 字段缺失或非法 -> $entry');
        continue;
      }
      result.add(parsed);
    }
    return result;
  }

  NumberItem? _parseNumber(Map<String, dynamic> json) {
    final value = json['value'];
    final voiceKey = json['voiceKey'];
    if (value is! int || voiceKey is! String || voiceKey.isEmpty) return null;
    return NumberItem(
      value: value,
      voiceKey: voiceKey,
      voiceKeyEn: _optionalString(json['voiceKeyEn']),
    );
  }

  LetterItem? _parseLetter(Map<String, dynamic> json) {
    final letter = json['letter'];
    final voiceKey = json['voiceKey'];
    if (letter is! String || letter.isEmpty) return null;
    if (voiceKey is! String || voiceKey.isEmpty) return null;
    return LetterItem(
      letter: letter.toUpperCase(),
      voiceKey: voiceKey,
      phonemeVoiceKey: _optionalString(json['phonemeVoiceKey']),
      wordNounIds: _stringList(json['wordNounIds']),
      voiceKeyEn: _optionalString(json['voiceKeyEn']),
    );
  }

  NounItem? _parseNoun(Map<String, dynamic> json) {
    final id = json['id'];
    final category = json['category'];
    final iconKey = json['iconKey'];
    final text = json['text'];
    final voiceKey = json['voiceKey'];
    if (id is! String || id.isEmpty) return null;
    if (category is! String || category.isEmpty) return null;
    if (iconKey is! String || iconKey.isEmpty) return null;
    // `text` 是必填：没有名字的名词既合不出语音，家长录音界面也没法显示
    // 「这条在录什么」。缺了它这条内容是死的，留下来只会安静地不出声。
    if (text is! String || text.isEmpty) return null;
    if (voiceKey is! String || voiceKey.isEmpty) return null;
    return NounItem(
      id: id,
      category: category,
      iconKey: iconKey,
      text: text,
      textEn: _optionalString(json['textEn']),
      voiceKey: voiceKey,
      voiceKeyEn: _optionalString(json['voiceKeyEn']),
    );
  }

  PhraseItem? _parsePhrase(Map<String, dynamic> json) {
    final id = json['id'];
    final group = json['group'];
    final text = json['text'];
    final voiceKey = json['voiceKey'];
    if (id is! String || id.isEmpty) return null;
    if (group is! String || group.isEmpty) return null;
    // `text` 必填，与名词同理：一句没有文本的话既合不出打底语音，
    // 录音页也没法告诉家长「这条该念什么」——而照着 voiceKey 是录不出话的。
    if (text is! String || text.isEmpty) return null;
    if (voiceKey is! String || voiceKey.isEmpty) return null;
    return PhraseItem(
      id: id,
      group: group,
      text: text,
      textEn: _optionalString(json['textEn']),
      voiceKey: voiceKey,
      voiceKeyEn: _optionalString(json['voiceKeyEn']),
    );
  }

  SpellingTarget? _parseSpellingTarget(Map<String, dynamic> json) {
    final id = json['id'];
    final voiceKey = json['voiceKey'];
    if (id is! String || id.isEmpty) return null;
    if (voiceKey is! String || voiceKey.isEmpty) return null;

    // 字母序列写成字符串（"Emmett"）而不是数组，内容包才好手写。
    final raw = json['letters'];
    if (raw is! String || raw.isEmpty) return null;
    final letters = raw.toUpperCase().split('');
    if (letters.any((c) => !RegExp(r'^[A-Z]$').hasMatch(c))) return null;

    return SpellingTarget(id: id, letters: letters, voiceKey: voiceKey);
  }

  /// 合体字的 `parts` **不在这里校验**。
  ///
  /// 原本是在这里查的：解析完一个包，把包内不存在的部件所引用的合体字丢掉。
  /// 那条检查看着合理，却把内容可扩展性堵死了——明年新增 `hanzi_l2.json`，
  /// 里面的新合体字引用的部件都在 `hanzi.json` 里，于是**整包新内容会被静默
  /// 丢弃**，表现为「加了内容但游戏里没有」，是最难查的那种故障。
  ///
  /// 部件能不能找到，是**整个内容库**的问题，不是单个包的问题。检查因此搬到
  /// [ContentLibrary.hanzi]，在所有包合并之后再做。
  List<HanziItem> _parseHanziList(
    Object? raw, {
    required String source,
    required List<String> skipped,
  }) => _parseList<HanziItem>(
    raw,
    source: source,
    skipped: skipped,
    parseOne: _parseHanzi,
  );

  HanziItem? _parseHanzi(Map<String, dynamic> json) {
    final char = json['char'];
    final pinyin = json['pinyin'];
    final typeName = json['type'];
    final voiceKey = json['voiceKey'];

    if (char is! String || char.isEmpty) return null;
    if (pinyin is! String || pinyin.isEmpty) return null;
    if (voiceKey is! String || voiceKey.isEmpty) return null;

    final type = switch (typeName) {
      'pictograph' => HanziType.pictograph,
      'compound' => HanziType.compound,
      'simple' => HanziType.simple,
      _ => null,
    };
    if (type == null) return null;

    final parts = _stringList(json['parts']);
    // 合体字必须声明部件，否则「合体」无从谈起。
    if (type == HanziType.compound && parts.length < 2) return null;

    return HanziItem(
      char: char,
      pinyin: pinyin,
      type: type,
      voiceKey: voiceKey,
      imageKey: _optionalString(json['imageKey']),
      parts: parts,
      voiceKeyEn: _optionalString(json['voiceKeyEn']),
    );
  }

  List<AntonymPair> _parseAntonyms(
    Object? raw, {
    required String source,
    required List<String> skipped,
  }) {
    if (raw == null) return const [];
    if (raw is! List) {
      skipped.add('$source: antonyms 不是数组，已忽略');
      return const [];
    }

    final result = <AntonymPair>[];
    for (var i = 0; i < raw.length; i++) {
      final pair = raw[i];
      if (pair is! List || pair.length != 2) {
        skipped.add('$source.antonyms[$i]: 不是长度为 2 的数组');
        continue;
      }
      final left = pair[0];
      final right = pair[1];
      if (left is! String ||
          right is! String ||
          left.isEmpty ||
          right.isEmpty) {
        skipped.add('$source.antonyms[$i]: 元素非法');
        continue;
      }
      result.add(AntonymPair(left, right));
    }
    return result;
  }

  static String? _optionalString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().where((s) => s.isNotEmpty).toList();
  }
}

/// 全部内容包合并后的检索入口。
@immutable
class ContentLibrary {
  const ContentLibrary(this.packs);

  final List<ContentPack> packs;

  List<NumberItem> get numbers => [for (final p in packs) ...p.numbers];
  List<LetterItem> get letters => [for (final p in packs) ...p.letters];
  List<NounItem> get nouns => [for (final p in packs) ...p.nouns];

  /// 全部汉字，**部件找不到的合体字已被剔除**。
  ///
  /// 剔除是必要的：留着它，部件加法会摆出一块写着不存在的字的积木，而那个字
  /// 既没有读音也合不出任何东西——比没有这条内容更糟。
  ///
  /// 校验放在这里而不是 [PackLoader]，是因为部件可以来自**另一个包**：
  /// 明年的 `hanzi_l2.json` 只写新合体字，部件仍在 `hanzi.json` 里。逐包校验
  /// 会把它整包误杀，而那正是内容可扩展性要保住的场景。
  List<HanziItem> get hanzi {
    final all = [for (final p in packs) ...p.hanzi];
    final available = all.map((h) => h.char).toSet();
    return [
      for (final item in all)
        if (!item.isCompound || item.parts.every(available.contains)) item,
    ];
  }

  /// 因为部件找不到而被剔除的合体字，供开发期排查内容包错误。
  List<String> get unresolvedCompounds {
    final all = [for (final p in packs) ...p.hanzi];
    final available = all.map((h) => h.char).toSet();
    return [
      for (final item in all)
        if (item.isCompound && !item.parts.every(available.contains))
          '合体字「${item.char}」引用了内容库里不存在的部件 '
              '${item.parts.where((p) => !available.contains(p)).toList()}',
    ];
  }

  List<AntonymPair> get antonyms => [for (final p in packs) ...p.antonyms];
  List<SpellingTarget> get spellingTargets => [
    for (final p in packs) ...p.spellingTargets,
  ];
  List<PhraseItem> get phrases => [for (final p in packs) ...p.phrases];

  /// 某一组整句，如 `praise` / `birthday`。保持包内顺序。
  List<PhraseItem> phrasesIn(String group) => [
    for (final item in phrases)
      if (item.group == group) item,
  ];

  /// 全部被跳过的条目，供开发期排查内容包错误。
  List<String> get skipped => [
    for (final p in packs) ...p.skipped,
    ...unresolvedCompounds,
  ];

  Set<String> get allVoiceKeys => {for (final p in packs) ...p.allVoiceKeys};

  HanziItem? hanziByChar(String char) {
    for (final item in hanzi) {
      if (item.char == char) return item;
    }
    return null;
  }

  LetterItem? letterByChar(String letter) {
    final upper = letter.toUpperCase();
    for (final item in letters) {
      if (item.letter == upper) return item;
    }
    return null;
  }

  NounItem? nounById(String id) {
    for (final item in nouns) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 按 [LetterItem.wordNounIds] 取出该字母的名词，跳过找不到的。
  ///
  /// 跳过而不是抛错：内容包写错一个 id，代价应该是「少飞进来一张图」，
  /// 而不是整个字母模块打不开。
  List<NounItem> wordsFor(LetterItem letter) => [
    for (final id in letter.wordNounIds) ?nounById(id),
  ];

  NumberItem? numberByValue(int value) {
    for (final item in numbers) {
      if (item.value == value) return item;
    }
    return null;
  }
}
