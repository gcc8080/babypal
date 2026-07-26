import 'package:flutter/foundation.dart';

import '../../core/block/block_model.dart';
import 'place_value.dart';

/// 百格板的填充状态。
///
/// 见 numbers-addition 规格「百格板」：以 10×10 网格渐进填充呈现 1–100。
///
/// **只存一个「填了多少」的计数，不存每一格是谁填的。** 这不是偷懒——他放
/// 进去的十条与单块本来就没有身份，`10` 这个数不会因为是「一条十条」还是
/// 「十个单块」凑出来的而有所不同。位值的表达差异已经由位值工作台（4.1）
/// 讲透了，百格板讲的是另一件事：**100 是十行十列**。
@immutable
class HundredBoard {
  const HundredBoard({this.filled = 0}) : assert(filled >= 0);

  static const int columns = 10;
  static const int rows = 10;
  static const int capacity = columns * rows;

  /// 已填格数，即当前表示的数。
  final int filled;

  bool get isEmpty => filled == 0;
  bool get isFull => filled >= capacity;

  /// 已经填满的整行数。
  int get completedRows => filled ~/ columns;

  /// 最后一行里零散的那几格——也就是个位。
  int get looseCells => filled % columns;

  /// 加一块。
  ///
  /// 超过 100 就停在 100，**不报错也不拒绝**：他多按几下只是没反应加不上去，
  /// 而不是被告知「你错了」。调用方据 [isFull] 决定是否给一声柔和的回位音。
  HundredBoard add(PlacePiece piece) =>
      HundredBoard(filled: (filled + piece.value).clamp(0, capacity));

  HundredBoard get cleared => const HundredBoard();

  /// 第 [index] 格（0 起）在网格中的位置。
  ///
  /// 行优先：第一行是 1–10，第二行 11–20，与实体百格板一致。
  static GridCell cellAt(int index) =>
      GridCell(index % columns, index ~/ columns);

  /// 该格是否属于某个「整十」——即它所在的行是否已填满。
  ///
  /// 界面靠它给整行与零散格上不同的颜色：**34 看起来就是「三行十个」加
  /// 「四个」**，位值不用讲，看一眼就在那儿。
  bool isInCompletedRow(int index) => index ~/ columns < completedRows;

  @override
  bool operator ==(Object other) =>
      other is HundredBoard && other.filled == filled;

  @override
  int get hashCode => filled.hashCode;

  @override
  String toString() => 'HundredBoard($filled/$capacity)';
}

/// 从 [from] 填到 [to] 之间跨过了哪些整行（0 起的行号）。
///
/// 用来决定放几处烟花。一次最多加 10 格，而行宽正是 10，因此结果**至多一行**
/// ——但仍返回列表，免得日后加了「百板」之类的更大块时这里悄悄算错。
List<int> rowsCompletedBetween(int from, int to) => [
  for (var row = 0; row < HundredBoard.rows; row++)
    if ((row + 1) * HundredBoard.columns > from &&
        (row + 1) * HundredBoard.columns <= to)
      row,
];

/// 百格板的取用块。
///
/// 与位值工作台同一套：十条与单块。**不提供「百板」**——那会让 100 变成
/// 一步就能填完，而这个模块的乐趣恰恰在于一行一行地填上去。
const List<PlacePiece> kHundredBoardPieces = [PlacePiece.rod, PlacePiece.unit];
