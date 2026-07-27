import 'package:flutter/material.dart' show Color;

import '../../core/content/models.dart';
import '../../core/content/pack_loader.dart';
import '../../core/design/tokens.dart';

/// 汉字模块的播报。
///
/// **不是双声道。** 数字模块「先中文再英文」的对称在这里不成立：`木 加 木
/// 等于 林` 没有英文版本，这一课教的就是这个字本身。硬加一段 "tree plus
/// tree" 只会在他刚看见「林」出现的那一刻插进一段与画面无关的话。
///
/// 连接词直接复用加法模块的 `zh.word.plus` / `zh.word.equals`——不是为了省两条
/// 音频，而是因为**那本来就是同一个「加」**。他在加法模块听到的「加」和这里
/// 听到的「加」是同一个人用同一种语气说的，`3+2=5` 与 `木+木=林` 是同一个动作
/// 这件事，才在耳朵里也成立。
class HanziNarration {
  const HanziNarration._();

  /// 念一个字。
  static List<String> character(HanziItem item) => [item.voiceKey];

  /// 「木 加 木 等于 林」。部件多于两个时照样拼得出：「木加木加木等于森」。
  static List<String> composition(List<HanziItem> parts, HanziItem result) => [
    for (var i = 0; i < parts.length; i++) ...[
      if (i > 0) 'zh.word.plus',
      parts[i].voiceKey,
    ],
    'zh.word.equals',
    result.voiceKey,
  ];

  /// 反义词配对成功：两个字各念一遍。
  ///
  /// 规格写的就是「播报『大』『小』并庆祝」——不加「的反义词是」这类连接语。
  /// 三岁的他要的是把两个字**并排听见**，中间那句解释是说给大人听的。
  static List<String> antonym(HanziItem a, HanziItem b) => [
    a.voiceKey,
    b.voiceKey,
  ];

  /// 本模块用到的、不来自内容包的语音键。供 CI 校验音频是否齐备。
  static const Set<String> connectiveKeys = {'zh.word.plus', 'zh.word.equals'};
}

/// 汉字的取色。
///
/// 按码点取，因此「木」在象形动画里、在部件加法的托盘里、在合成的「林」旁边
/// 永远是同一个颜色。**刻意不用 `hashCode`**：Dart 字符串的 hashCode 不保证
/// 跨进程稳定，今天绿明天紫，颜色这条记忆抓手就废了。
Color hanziColor(String char) => BlockColors.forIndex(hanziColorIndex(char));

/// 同上，但取的是调色板下标——积木存的是语义索引而不是 `Color`
/// （见 `BlockBody.colorIndex`）。
int hanziColorIndex(String char) {
  var sum = 0;
  for (final code in char.runes) {
    sum += code;
  }
  return sum;
}

/// 把一个字摊成它最底层的部件。
///
/// `林 → [木, 木]`、`森 → [木, 木, 木]`、`木 → [木]`。递归展开是部件加法能
/// **一步一步搭**的关键：`木+木` 先合成「林」，「林」再碰上一个「木」时，
/// 引擎看到的是 `[木,木] + [木] = [木,木,木]`，正好是「森」。
///
/// 他因此不需要一次凑齐三块——那对三岁的手太难了——而是先造出林，再把林变成森。
/// 顺带还看见了「森里面有林」。
List<String> componentsOf(String char, ContentLibrary library) {
  final item = library.hanziByChar(char);
  if (item == null || !item.isCompound) return [char];
  return [for (final part in item.parts) ...componentsOf(part, library)];
}

/// 找出部件恰好是 [components] 的合体字。
///
/// 按**多重集**比较：`[木,木]` 与 `[木,木]` 相等，而 `[人,木]` 与 `[木,人]`
/// 也相等——他把人放到木上、还是把木放到人上，造出来都该是「休」。
HanziItem? compoundFrom(List<String> components, ContentLibrary library) {
  final want = _tally(components);
  for (final item in library.hanzi) {
    if (!item.isCompound) continue;
    final have = _tally([
      for (final p in item.parts) ...componentsOf(p, library),
    ]);
    if (_sameTally(want, have)) return item;
  }
  return null;
}

Map<String, int> _tally(List<String> items) {
  final counts = <String, int>{};
  for (final item in items) {
    counts[item] = (counts[item] ?? 0) + 1;
  }
  return counts;
}

bool _sameTally(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// 象形动画的时长。
///
/// 前 70% 是图渐变成字骨架，后 30% 交叉淡入真正的字形。两秒是量出来的下限：
/// 再快他的眼睛跟不上那一下收拢，而收拢正是这个玩法的全部内容。
const Duration kMorphDuration = Duration(milliseconds: 2000);

/// 骨架让位给真字形的时刻（在 0..1 的时间轴上）。
///
/// **最后停在屏幕上的必须是真正的字**，不是我手画的骨架。骨架负责演「怎么变
/// 过来的」，真字形负责「他将来在书上看到的就是这个样子」。
const double kGlyphHandoff = 0.72;

/// 配错时演示正确答案的停留时长。与大小写配对同一个值，同一个道理：
/// 必须留够他看清「哦，大配的是小」的时间。
const Duration kSeesawDemoHold = Duration(milliseconds: 1800);

/// 跷跷板失衡时的倾角（弧度）。
const double kSeesawTilt = 0.13;
