import 'package:flutter/foundation.dart';

import '../../core/block/block_model.dart';

/// 一个字母的轮廓模板。
@immutable
class LetterShape {
  const LetterShape({
    required this.letter,
    required this.columns,
    required this.rows,
    required this.cells,
  });

  final String letter;
  final int columns;
  final int rows;

  /// 需要被填满的格位，按**从上到下、从左到右**排序。
  ///
  /// 顺序不是可有可无的：点选通道就是照这个顺序一格一格填的，而字母正是
  /// 从上往下写出来的。倒着填出来的 A 他认不出是在写 A。
  final List<GridCell> cells;

  int get size => cells.length;

  bool contains(GridCell cell) => cells.contains(cell);

  @override
  String toString() =>
      'LetterShape($letter, $columns×$rows, ${cells.length} 格)';
}

/// 26 个字母的点阵轮廓，一律 5 行。
///
/// **5 行是下限，不是审美选择**：4 行画出来的 B 和 8、S 和 5 会长得一样，
/// 而这个玩法的全部意义就是「我拼出来的这个东西是那个字母」。宽度按字母
/// 自己的形状定 3–5 列——M W X Y V 的斜笔画 3 列画不出来。
///
/// 每个字母的格数在 6（J）到 15（M）之间。看着多，但托盘是「按一下出一块」，
/// 他在位值工作台里一口气放过 34 块。
const Map<String, List<String>> kLetterPatterns = {
  'A': ['.#.', '#.#', '###', '#.#', '#.#'],
  'B': ['##.', '#.#', '##.', '#.#', '##.'],
  'C': ['.##', '#..', '#..', '#..', '.##'],
  'D': ['##.', '#.#', '#.#', '#.#', '##.'],
  'E': ['###', '#..', '##.', '#..', '###'],
  'F': ['###', '#..', '##.', '#..', '#..'],
  'G': ['.##', '#..', '#.#', '#.#', '.##'],
  'H': ['#.#', '#.#', '###', '#.#', '#.#'],
  'I': ['###', '.#.', '.#.', '.#.', '###'],
  'J': ['..#', '..#', '..#', '#.#', '.#.'],
  // K 用 4 列：3 列画不出那两条斜臂交汇的样子，会变成一根竖线加两个点。
  'K': ['#..#', '#.#.', '##..', '#.#.', '#..#'],
  'L': ['#..', '#..', '#..', '#..', '###'],
  'M': ['#...#', '##.##', '#.#.#', '#...#', '#...#'],
  'N': ['#..#', '##.#', '#.##', '#..#', '#..#'],
  'O': ['.#.', '#.#', '#.#', '#.#', '.#.'],
  'P': ['##.', '#.#', '##.', '#..', '#..'],
  'Q': ['.#.', '#.#', '#.#', '#.#', '.##'],
  'R': ['##.', '#.#', '##.', '#.#', '#.#'],
  'S': ['.##', '#..', '.#.', '..#', '##.'],
  'T': ['###', '.#.', '.#.', '.#.', '.#.'],
  // U 圆底、V 尖底：两个都用 3 列会画成同一个形状，那就等于教错了。
  'U': ['#.#', '#.#', '#.#', '#.#', '.#.'],
  'V': ['#...#', '#...#', '.#.#.', '.#.#.', '..#..'],
  'W': ['#...#', '#...#', '#.#.#', '##.##', '#...#'],
  'X': ['#...#', '.#.#.', '..#..', '.#.#.', '#...#'],
  'Y': ['#...#', '.#.#.', '..#..', '..#..', '..#..'],
  'Z': ['###', '..#', '.#.', '#..', '###'],
};

/// 取某个字母的轮廓。字母表里没有的返回 null，由调用方静默跳过。
LetterShape? letterShapeOf(String letter) {
  final key = letter.toUpperCase();
  final pattern = kLetterPatterns[key];
  if (pattern == null || pattern.isEmpty) return null;

  final rows = pattern.length;
  final columns = pattern.map((r) => r.length).reduce((a, b) => a > b ? a : b);

  final cells = <GridCell>[];
  for (var row = 0; row < rows; row++) {
    final line = pattern[row];
    for (var col = 0; col < line.length; col++) {
      if (line[col] == '#') cells.add(GridCell(col, row));
    }
  }
  if (cells.isEmpty) return null;

  return LetterShape(letter: key, columns: columns, rows: rows, cells: cells);
}

/// 轮廓**之外**的全部格位——交给引擎当作不可落子的格子。
///
/// 反过来算（列出轮廓内的格子让引擎只往里放）也能实现，但那要在引擎里加一条
/// 「允许落子的白名单」的概念；而「这一格不能放东西」本来就已经存在，
/// 只是原先只有被别的积木占着这一种来源。
Set<GridCell> blockedCellsFor(LetterShape shape) {
  final inside = shape.cells.toSet();
  return {
    for (var row = 0; row < shape.rows; row++)
      for (var col = 0; col < shape.columns; col++)
        if (!inside.contains(GridCell(col, row))) GridCell(col, row),
  };
}

/// 下一个还空着的轮廓格位。全填满时返回 null。
///
/// 点选通道用它：按一下托盘，方块自己落到该去的地方。**他不需要瞄准**——
/// 轮廓格只有 50 多 dp，远低于 90dp 抓取阈值，要求他点准就是设计错误。
GridCell? nextEmptyCell(LetterShape shape, Set<GridCell> filled) {
  for (final cell in shape.cells) {
    if (!filled.contains(cell)) return cell;
  }
  return null;
}
