/// 播报语言。中英是同一内容的两个声道，不是两套课程——见 numbers-addition
/// 规格「中英双声道」，因此没有语言开关，也没有两个入口。
enum VoiceLang {
  zh,
  en;

  /// 语音键前缀。与 `tool/gen_audio.dart` 产出的键名一一对应。
  String get prefix => name;
}

/// 把算式翻译成一串语音键。
///
/// **词片拼播而非整句录音**：10 以内的加法有 45 个有序算式、分解也有 45 个，
/// 整句要 180 条音频（约 16 MB），词片只要 8 条连接词（约 0.2 MB），而且能拼
/// 出任意算式——他已经在数 100 了，迟早要报到 10 以外。
///
/// 真正决定性的理由是家长录音：覆盖层的全部意义是「录四十来条就能把打底语音
/// 换成爸妈的声音」。词片方案下录一次「加」覆盖全部算式；整句方案下要录 45
/// 句，那个覆盖层就名存实亡了。
///
/// 交给 [AudioBus.speakSequence] 按顺序播报，词片之间天然留一个小停顿——
/// 对正在学的孩子反而比连读更清楚。
class Narration {
  const Narration._();

  static String number(int value, VoiceLang lang) =>
      '${lang.prefix}.number.$value';

  static String _word(String name, VoiceLang lang) =>
      '${lang.prefix}.word.$name';

  /// 「三 加 二 等于 五」/「three plus two equals five」
  static List<String> addition(int a, int b, VoiceLang lang) => [
    number(a, lang),
    _word('plus', lang),
    number(b, lang),
    _word('equals', lang),
    number(a + b, lang),
  ];

  /// 「三 加 二」——出题时只报两个加数，**不报得数**。
  ///
  /// 报出得数就等于把答案先说了，他要做的事情就没了。
  static List<String> additionQuestion(int a, int b, VoiceLang lang) => [
    number(a, lang),
    _word('plus', lang),
    number(b, lang),
  ];

  /// 任意多个加数的整条算式：「三 加 二 加 一 等于 六」。
  ///
  /// [addition] 是它两项时的特例，保留是因为两项才是出题的形态，而这个通用
  /// 版本是给沙盒用的——那里没有出题人，他自己摆几块就是几项。
  static List<String> sum(List<int> addends, VoiceLang lang) => [
    for (var i = 0; i < addends.length; i++) ...[
      if (i > 0) _word('plus', lang),
      number(addends[i], lang),
    ],
    _word('equals', lang),
    number(addends.fold(0, (a, b) => a + b), lang),
  ];

  /// 「五 可以分成 二 和 三」/「five is made of two and three」
  ///
  /// 反向分解的播报。见规格「反向分解」——它的权重不低于合体求和，
  /// 因为凑十法与进位加法全建在这上面。
  static List<String> decomposition(int total, int a, int b, VoiceLang lang) =>
      [
        number(total, lang),
        _word('isMadeOf', lang),
        number(a, lang),
        _word('and', lang),
        number(b, lang),
      ];

  /// 双声道：同一内容先中文后英文。
  static List<String> bilingual(List<String> Function(VoiceLang lang) build) =>
      [...build(VoiceLang.zh), ...build(VoiceLang.en)];

  static List<String> bilingualNumber(int value) =>
      bilingual((lang) => [number(value, lang)]);

  static List<String> bilingualAddition(int a, int b) =>
      bilingual((lang) => addition(a, b, lang));

  static List<String> bilingualAdditionQuestion(int a, int b) =>
      bilingual((lang) => additionQuestion(a, b, lang));

  static List<String> bilingualDecomposition(int total, int a, int b) =>
      bilingual((lang) => decomposition(total, a, b, lang));

  /// 「十个一，是一个十」——位值换十时的播报。
  ///
  /// 这句拼不出来（数词加连接词组不成它），且只有这一句，所以整句生成。
  /// 凡是能拼的一律走 [addition] / [decomposition]。
  static const List<String> tenOnesMakeATen = [
    'zh.phrase.tenOnesMakeATen',
    'en.phrase.tenOnesMakeATen',
  ];

  /// 本类会用到的全部非数词语音键。供 CI 校验音频是否齐备。
  static const Set<String> connectiveKeys = {
    ...tenOnesMakeATen,
    'zh.word.plus',
    'zh.word.equals',
    'zh.word.and',
    'zh.word.isMadeOf',
    'en.word.plus',
    'en.word.equals',
    'en.word.and',
    'en.word.isMadeOf',
  };
}
