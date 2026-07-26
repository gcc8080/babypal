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

    return ContentPack(
      schemaVersion: version,
      source: source,
      numbers: numbers,
      letters: letters,
      hanzi: hanzi,
      nouns: nouns,
      antonyms: antonyms,
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
      wordIconKeys: _stringList(json['wordIconKeys']),
      voiceKeyEn: _optionalString(json['voiceKeyEn']),
    );
  }

  NounItem? _parseNoun(Map<String, dynamic> json) {
    final id = json['id'];
    final category = json['category'];
    final iconKey = json['iconKey'];
    final voiceKey = json['voiceKey'];
    if (id is! String || id.isEmpty) return null;
    if (category is! String || category.isEmpty) return null;
    if (iconKey is! String || iconKey.isEmpty) return null;
    if (voiceKey is! String || voiceKey.isEmpty) return null;
    return NounItem(
      id: id,
      category: category,
      iconKey: iconKey,
      voiceKey: voiceKey,
      voiceKeyEn: _optionalString(json['voiceKeyEn']),
    );
  }

  /// 汉字要分两趟解析。
  ///
  /// 第一趟解析出全部合法条目，第二趟才能校验合体字的 `parts` 是否都在包内——
  /// 因为部件可能定义在引用它的合体字**后面**，一趟扫描会误判。
  List<HanziItem> _parseHanziList(
    Object? raw, {
    required String source,
    required List<String> skipped,
  }) {
    final parsed = _parseList<HanziItem>(
      raw,
      source: source,
      skipped: skipped,
      parseOne: _parseHanzi,
    );

    final available = parsed.map((h) => h.char).toSet();
    final result = <HanziItem>[];
    for (final item in parsed) {
      if (item.isCompound) {
        final missing =
            item.parts.where((p) => !available.contains(p)).toList();
        if (missing.isNotEmpty) {
          // 不能留着——运行时会拿不到部件积木，变成空引用。
          skipped.add(
            '$source: 合体字「${item.char}」引用了包内不存在的部件 $missing',
          );
          continue;
        }
      }
      result.add(item);
    }
    return result;
  }

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
      if (left is! String || right is! String || left.isEmpty || right.isEmpty) {
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
  List<HanziItem> get hanzi => [for (final p in packs) ...p.hanzi];
  List<NounItem> get nouns => [for (final p in packs) ...p.nouns];
  List<AntonymPair> get antonyms => [for (final p in packs) ...p.antonyms];

  /// 全部被跳过的条目，供开发期排查内容包错误。
  List<String> get skipped => [for (final p in packs) ...p.skipped];

  Set<String> get allVoiceKeys => {
        for (final p in packs) ...p.allVoiceKeys,
      };

  HanziItem? hanziByChar(String char) {
    for (final item in hanzi) {
      if (item.char == char) return item;
    }
    return null;
  }

  NumberItem? numberByValue(int value) {
    for (final item in numbers) {
      if (item.value == value) return item;
    }
    return null;
  }
}
