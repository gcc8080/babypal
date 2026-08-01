import 'package:flutter/material.dart' show Color;

import '../../core/audio/narration.dart';
import '../../core/content/models.dart';
import '../../core/design/tokens.dart';

/// 字母模块的播报。
///
/// 与 [Narration] 分开放，是因为字母这一课**不是双声道**：`A is for Apple`
/// 里的 A 只有英文读法，中文没有对应的「字母名」。数字模块那套「先中文再
/// 英文」的对称在这里不成立，硬套只会让播报多出一段没有内容的停顿。
class LetterNarration {
  const LetterNarration._();

  /// 点击字母积木：先字母名，再音素。
  ///
  /// 规格明确要求这**是两次可区分的播报**，不得合并成一条音频。语音队列
  /// 在两条之间天然留一个小停顿，「ay……/æ/」听起来正是他看的那些字母儿歌
  /// 的节奏。合成一条就变成「ay æ」连读，音素会被当成字母名的一部分。
  static List<String> letterAndPhoneme(LetterItem letter) => [
    letter.voiceKey,
    ?letter.phonemeVoiceKey,
  ];

  /// 名词卡飞入时的播报：**只念英文**。
  ///
  /// 这一刻要立的是「A —— Apple」这条字母与英文词的联系，中文名插进来会把
  /// 这条线打断。中文留给点击那张卡时（[wordTapped]）——那时他问的是「这是
  /// 什么」，双语才有意义。
  static List<String> wordFlyIn(NounItem noun) => [
    if (noun.voiceKeyEn case final en?) en else noun.voiceKey,
  ];

  /// 点击名词卡：中英各一遍。
  static List<String> wordTapped(NounItem noun) => [
    noun.voiceKey,
    ?noun.voiceKeyEn,
  ];

  /// 选中一个字母的完整播报：字母名 → 音素 → 三张卡的英文名。
  static List<String> letterIntro(LetterItem letter, List<NounItem> words) => [
    ...letterAndPhoneme(letter),
    for (final word in words) ...wordFlyIn(word),
  ];
}

/// 名词卡飞入的节奏。
///
/// 三张卡错开出场而不是一起蹦出来：错开时他的眼睛会**跟着**一张一张看过去，
/// 同时出现则只会看见一团。间隔取 220ms——比这短就糊成一片，比这长他已经
/// 移开视线了。
const Duration kWordStagger = Duration(milliseconds: 220);
const Duration kWordFlyIn = Duration(milliseconds: 420);

/// 一屏最多显示几张名词卡。
///
/// 内容包里某个字母给多了也只取前几张：横屏放得下三张 ≥90dp 的卡，第四张
/// 就得压缩尺寸，而压缩会击穿抓取阈值。
const int kMaxWordCards = 3;

/// 在字母表里前后翻页，到头就绕回去。
///
/// **绕回而不是禁用**：走到 Z 还按「下一个」时，一个按不动的按钮对三岁的他
/// 是「坏了」，绕回 A 是「又从头开始了」。无挫败红线在导航层的体现。
int nextLetterIndex(int current, int count, {bool forward = true}) {
  if (count <= 0) return 0;
  return (current + (forward ? 1 : -1) + count) % count;
}

/// 字母的取色。
///
/// 按字母在表中的位置取，因此 A 永远是同一个颜色——「我的名字第一个字母是
/// 蓝色的那个」是三岁孩子真的会用的记忆抓手。
Color letterColor(String letter) => BlockColors.forIndex(letterColorIndex(letter));

/// 同上，但取的是调色板下标——积木存的是语义索引而不是 `Color`
/// （见 `BlockBody.colorIndex`）。与汉字那边 `hanziColorIndex` 同一个道理。
int letterColorIndex(String letter) => letter.toUpperCase().codeUnitAt(0) - 0x41;
