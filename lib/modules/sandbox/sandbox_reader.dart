import 'package:flutter/foundation.dart';

import '../../core/audio/narration.dart';
import '../../core/block/block_model.dart';
import '../../core/content/pack_loader.dart';

/// 一个被认出来的组合。
///
/// [signature] 是去重依据，[speech] 是要念的语音键。
@immutable
class SandboxFinding {
  const SandboxFinding({required this.signature, required this.speech});

  /// 同一个组合在盘上只庆祝一次。
  ///
  /// 取的是**内容**（`7+8=15`）而不是位置：他把摆好的等式整条挪到另一行，
  /// 那还是刚才那个等式，不该再庆祝一遍。反过来，拆散再拼回来会重新庆祝——
  /// 签名从活跃集合里消失过，那确实是他又做成了一次。
  final String signature;

  final List<String> speech;

  @override
  bool operator ==(Object other) =>
      other is SandboxFinding && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;

  @override
  String toString() => 'SandboxFinding($signature)';
}

/// 读盘：把拼搭台上的积木读成「他拼出了什么」。
///
/// 沙盒的正向反馈**只能是发现，不能是要求**（sandbox 规格：未构成组合时
/// MUST NOT 提示或催促）。所以这里只有「认出来了」一条出口，没有任何
/// 「没认出来」的分支——认不出就是什么都不发生，安静是默认状态。
///
/// 纯逻辑，不碰 Widget：识别规则是这个模块唯一需要反复调整的东西
/// （他会摆出各种我没想到的东西），得能用单测直接喂积木列表。
class SandboxReader {
  const SandboxReader(this.library);

  final ContentLibrary library;

  /// 至少两个字母才算「拼出了一个词」。
  ///
  /// 单个字母块本身就是内容，把它当成词会让托盘里随手放下的每一块都出声，
  /// 沙盒立刻变得聒噪——而聒噪就是催促的另一种形式。
  static const int minWordLength = 2;

  List<SandboxFinding> read(List<BlockBody> blocks) {
    final findings = <SandboxFinding>[];
    for (final run in _runs(blocks)) {
      final labels = [for (final b in run) b.label!];
      final finding = _interpret(labels);
      if (finding != null) findings.add(finding);
    }
    return findings;
  }

  /// 把落位的积木切成一段段**横向连续**的序列。
  ///
  /// 只读横排是因为他在电视上看到的、在地板上摆的都是横着的一行；竖着摞起来
  /// 的塔是另一种玩法（堆高），那里没有「读法」可言。
  ///
  /// 没有字的积木（纯色块）会**切断**当前段：色块夹在 `7` 和 `+` 中间时，
  /// 那已经不是一条算式了，硬把它读通等于替他脑补。
  List<List<BlockBody>> _runs(List<BlockBody> blocks) {
    final byRow = <int, List<BlockBody>>{};
    for (final b in blocks) {
      final anchor = b.anchor;
      if (anchor == null) continue; // 托盘里的、手上的都不算摆出来了
      byRow.putIfAbsent(anchor.row, () => []).add(b);
    }

    final runs = <List<BlockBody>>[];
    for (final row in byRow.values) {
      row.sort((a, b) => a.anchor!.col.compareTo(b.anchor!.col));
      var current = <BlockBody>[];
      int? expectedCol;
      for (final b in row) {
        final joined = expectedCol != null && b.anchor!.col == expectedCol;
        if (!joined || b.label == null) {
          if (current.length >= 2) runs.add(current);
          current = [];
        }
        if (b.label == null) {
          expectedCol = null;
          continue;
        }
        current.add(b);
        expectedCol = b.anchor!.col + b.widthUnits;
      }
      if (current.length >= 2) runs.add(current);
    }
    return runs;
  }

  SandboxFinding? _interpret(List<String> labels) =>
      _readEquation(labels) ?? _readWord(labels);

  // ─── 算式 ──────────────────────────────────────────────────────────

  /// `7 + 8 = 15`。多个加数也认：`3 + 2 + 1 = 6`。
  ///
  /// **只在等式成立时出声。** `7 + 8 = 16` 摆在那儿是安静的——不是「错了」，
  /// 是「还没成为一条算式」。给它任何反馈（哪怕只是一声「咦」）都会把沙盒
  /// 变成一道题，而沙盒里没有题。
  SandboxFinding? _readEquation(List<String> labels) {
    final equals = labels.indexOf(equalsLabel);
    if (equals <= 0 || equals != labels.length - 2) return null;

    final total = int.tryParse(labels.last);
    if (total == null) return null;

    final addends = <int>[];
    for (var i = 0; i < equals; i++) {
      if (i.isEven) {
        final n = int.tryParse(labels[i]);
        if (n == null) return null;
        addends.add(n);
      } else if (labels[i] != plusLabel) {
        return null;
      }
    }
    if (addends.length < 2) return null;
    if (addends.reduce((a, b) => a + b) != total) return null;

    return SandboxFinding(
      signature: labels.join(),
      speech: Narration.bilingual((lang) => Narration.sum(addends, lang)),
    );
  }

  // ─── 词 ────────────────────────────────────────────────────────────

  /// 一串字母块拼出了一个**内容库里有的**词。
  ///
  /// 先查拼字目标（他自己的名字、MAMA、BABA）再查名词：`Emmett` 摆出来时该
  /// 听见的是他的名字，不是随便一个以 E 开头的单词。
  SandboxFinding? _readWord(List<String> labels) {
    if (labels.length < minWordLength) return null;
    for (final label in labels) {
      if (label.length != 1 || !_isLetter(label)) return null;
    }
    final word = labels.join().toUpperCase();

    for (final target in library.spellingTargets) {
      if (target.letters.join().toUpperCase() == word) {
        return SandboxFinding(
          signature: 'word:$word',
          speech: [target.voiceKey],
        );
      }
    }

    for (final noun in library.nouns) {
      if (noun.textEn?.toUpperCase() != word) continue;
      return SandboxFinding(
        signature: 'word:$word',
        speech: [noun.voiceKey, ?noun.voiceKeyEn],
      );
    }
    return null;
  }

  static bool _isLetter(String s) {
    final c = s.toUpperCase().codeUnitAt(0);
    return c >= 0x41 && c <= 0x5A;
  }
}

/// 运算符积木身上写的字。
///
/// 是积木的 `label`，因此识别与渲染读的是同一个来源——没有第二张
/// 「哪块是加号」的表要维护。
const String plusLabel = '+';
const String equalsLabel = '=';
