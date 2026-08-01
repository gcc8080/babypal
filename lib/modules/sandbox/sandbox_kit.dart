import 'package:flutter/foundation.dart';

import '../../core/block/block_model.dart';
import '../../core/content/models.dart';
import '../../core/content/pack_loader.dart';
import '../../core/design/tokens.dart';
import '../hanzi/hanzi.dart';
import '../letters/letters.dart';
import 'sandbox_reader.dart';

/// 托盘里一块可取用积木的样子。
///
/// 不直接存 [BlockBody]：托盘里的同一样东西可以被取用无数次，每次取用都得
/// 是一块**新的、id 不重复的**积木——共用 id 会让 `AnimatedPositioned`
/// 把两块认成一块，第二块取出来时会从第一块的位置飞出去。
@immutable
class SandboxPiece {
  const SandboxPiece({required this.label, required this.colorIndex});

  /// 写在积木上的字。为 null 时是纯色块。
  final String? label;

  final int colorIndex;

  BlockBody spawn(String id) =>
      BlockBody(id: id, colorIndex: colorIndex, label: label);

  @override
  bool operator ==(Object other) =>
      other is SandboxPiece &&
      other.label == label &&
      other.colorIndex == colorIndex;

  @override
  int get hashCode => Object.hash(label, colorIndex);

  @override
  String toString() => 'SandboxPiece(${label ?? '□'})';
}

/// 托盘里的一类货。
@immutable
class SandboxCategory {
  const SandboxCategory({
    required this.id,
    required this.sample,
    required this.pieces,
    this.pinned = const [],
  });

  final String id;

  /// 类别键上画的那一块——**它就是这类货的样子**。
  ///
  /// 类别键不写字（儿童端零文字），画一块写着「3」的积木就是「这里有数字」。
  /// 图标做不到这件事：一个抽象的「数字」图标他不认识，一块 3 他认识。
  final SandboxPiece sample;

  /// 分页轮转的货。
  final List<SandboxPiece> pieces;

  /// **每一页都出现**的货，排在页首。
  ///
  /// 只有数字类用得上：`+` 和 `=` 若跟着数字一起分页，他要拼一条算式就得
  /// 在页与页之间来回翻找运算符。它们不是内容，是把内容连起来的东西，
  /// 得一直在手边。
  final List<SandboxPiece> pinned;

  /// 给定托盘容量时的页数。
  int pageCount(int capacity) {
    final perPage = capacity - pinned.length;
    if (perPage <= 0) return 1;
    return (pieces.length / perPage).ceil().clamp(1, 1 << 30);
  }

  /// 第 [page] 页要摆进托盘的货。
  List<SandboxPiece> page(int page, int capacity) {
    final perPage = capacity - pinned.length;
    if (perPage <= 0) return pinned.take(capacity).toList();
    final start = (page % pageCount(capacity)) * perPage;
    return [
      ...pinned,
      ...pieces.skip(start).take(perPage),
    ];
  }
}

/// 沙盒的货架。
///
/// 四类货共用同一种积木、同一套拖拽与吸附规则——这正是 sandbox 规格
/// 「跨内容域混搭」要的：数字块和汉字部件在台面上不是两种东西，就是积木。
/// 他在数字模块学会的动作走到这里一个字都不用改。
///
/// 货全部从 [ContentLibrary] 派生，一处硬编码都没有：明年加一个内容包，
/// 沙盒托盘里自动就有了新字。
class SandboxKit {
  SandboxKit(this.library);

  final ContentLibrary library;

  /// 数字块最大到几。
  ///
  /// 他已经会数到 100，但托盘不是数轴——每多一个数就多翻一页。20 是
  /// 10 以内加法的全部和所能达到的上界（`9+9=18`），再往上他暂时摆不出
  /// 需要用到的算式。
  static const int maxNumber = 20;

  /// 沙盒里可取用的汉字。
  ///
  /// 只取**能参与造字的**：象形字本身，加上任何合体字的部件。反义词表里那
  /// 一百多个字（善恶勇怯真假……）拿进来只会把托盘撑成一本字典，而它们在
  /// 这里既合不出东西也没有别的玩法。
  List<String> get hanziChars {
    final all = library.hanzi;
    final parts = {for (final h in all) ...h.parts};
    final chars = <String>[];
    for (final item in all) {
      final usable = item.type == HanziType.pictograph || parts.contains(item.char);
      if (usable && !chars.contains(item.char)) chars.add(item.char);
    }
    return chars;
  }

  late final List<SandboxCategory> categories = [
    SandboxCategory(
      id: 'numbers',
      sample: const SandboxPiece(label: '3', colorIndex: 3),
      pinned: const [
        SandboxPiece(label: plusLabel, colorIndex: 9),
        SandboxPiece(label: equalsLabel, colorIndex: 9),
      ],
      pieces: [
        for (var n = 0; n <= maxNumber; n++)
          SandboxPiece(label: '$n', colorIndex: n),
      ],
    ),
    SandboxCategory(
      id: 'letters',
      sample: const SandboxPiece(label: 'A', colorIndex: 0),
      pieces: [
        for (final item in library.letters)
          SandboxPiece(
            label: item.letter,
            colorIndex: letterColorIndex(item.letter),
          ),
      ],
    ),
    SandboxCategory(
      id: 'hanzi',
      sample: const SandboxPiece(label: '木', colorIndex: 4),
      pieces: [
        for (final char in hanziChars)
          SandboxPiece(label: char, colorIndex: hanziColorIndex(char)),
      ],
    ),
    SandboxCategory(
      id: 'blocks',
      sample: const SandboxPiece(label: null, colorIndex: 6),
      pieces: [
        for (var i = 0; i < BlockColors.palette.length; i++)
          SandboxPiece(label: null, colorIndex: i),
      ],
    ),
  ];
}
