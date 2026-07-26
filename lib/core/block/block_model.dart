import 'package:flutter/foundation.dart';

/// 积木表情。由 `CustomPainter` 程序化绘制，不依赖任何素材文件。
///
/// 见 design.md D6：几何积木风格与程序化绘制天然一致，零素材、零依赖、
/// 零许可问题，且参数化后表情可由内容包驱动。
enum BlockExpression {
  /// 待机。会按随机间隔自发眨眼。
  idle,

  /// 开心。正确合体、完成关卡时切换。
  happy,

  /// 惊讶。被点击、被拾起时的瞬时反应。
  surprised,
}

/// 棋盘上的一个格位坐标。
///
/// 这是纯粹的逻辑坐标（列、行），不含任何像素信息——像素换算由
/// [SnapGrid] 负责，便于纯逻辑单测。
@immutable
class GridCell {
  const GridCell(this.col, this.row);

  final int col;
  final int row;

  @override
  bool operator ==(Object other) =>
      other is GridCell && other.col == col && other.row == row;

  @override
  int get hashCode => Object.hash(col, row);

  @override
  String toString() => 'GridCell($col, $row)';
}

/// 两块积木是否**拼到一起**了：同一行、同高、边挨着边。
///
/// 规格里加法的说法是「两组积木**拼接**合体」，不是「叠在一起」——对 3 岁的
/// 手来说，把 A 放到 B 旁边比放到 B 正上方容易得多，前者只要落在同一行附近，
/// 后者要瞄准一块可能只有一格宽的目标。
///
/// 未落位的积木（[BlockBody.anchor] 为 null）永远返回 false：正被捏在手里的
/// 积木不算拼上了。
bool blocksAreJoined(BlockBody x, BlockBody y) {
  final ax = x.anchor;
  final ay = y.anchor;
  if (ax == null || ay == null) return false;
  if (ax.row != ay.row || x.heightUnits != y.heightUnits) return false;
  return ax.col + x.widthUnits == ay.col || ay.col + y.widthUnits == ax.col;
}

/// 一块积木。
///
/// 尺寸以「单位格」计而非像素：一个单位块是 1×1，数字模块的「十条」是 10×1。
/// 像素尺寸 = 单位数 × 格位边长 × 缩放因子，在渲染层才发生。
@immutable
class BlockBody {
  const BlockBody({
    required this.id,
    required this.colorIndex,
    this.widthUnits = 1,
    this.heightUnits = 1,
    this.expression = BlockExpression.idle,
    this.groupId,
    this.anchor,
  })  : assert(widthUnits > 0),
        assert(heightUnits > 0);

  /// 稳定标识。合体/分裂会生成新 id，便于动画层做进出场匹配。
  final String id;

  /// 调色板索引，经 `BlockColors.forIndex` 取色。
  ///
  /// 刻意不直接存 `Color`：配色属于设计系统，积木只持有语义索引，
  /// 日后换配色不需要改任何积木数据。
  final int colorIndex;

  final int widthUnits;
  final int heightUnits;

  final BlockExpression expression;

  /// 所属群组。同组积木整体拖动时保持相对位置。
  final String? groupId;

  /// 当前落位的格位锚点（左上角所在格）。为 null 表示尚未落位（在托盘里或拖拽中）。
  final GridCell? anchor;

  /// 占用的格位数。
  int get cellCount => widthUnits * heightUnits;

  /// 以 [anchor] 为左上角时，本积木覆盖的全部格位。
  ///
  /// 未落位（[anchor] 为 null）时返回空集合。
  Set<GridCell> footprintAt(GridCell? at) {
    final origin = at ?? anchor;
    if (origin == null) return const {};
    return {
      for (var dc = 0; dc < widthUnits; dc++)
        for (var dr = 0; dr < heightUnits; dr++)
          GridCell(origin.col + dc, origin.row + dr),
    };
  }

  BlockBody copyWith({
    int? colorIndex,
    int? widthUnits,
    int? heightUnits,
    BlockExpression? expression,
    String? groupId,
    GridCell? anchor,
    bool clearGroup = false,
    bool clearAnchor = false,
  }) {
    return BlockBody(
      id: id,
      colorIndex: colorIndex ?? this.colorIndex,
      widthUnits: widthUnits ?? this.widthUnits,
      heightUnits: heightUnits ?? this.heightUnits,
      expression: expression ?? this.expression,
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      anchor: clearAnchor ? null : (anchor ?? this.anchor),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BlockBody &&
      other.id == id &&
      other.colorIndex == colorIndex &&
      other.widthUnits == widthUnits &&
      other.heightUnits == heightUnits &&
      other.expression == expression &&
      other.groupId == groupId &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(
        id,
        colorIndex,
        widthUnits,
        heightUnits,
        expression,
        groupId,
        anchor,
      );

  @override
  String toString() =>
      'BlockBody($id, ${widthUnits}x$heightUnits, color=$colorIndex, '
      'expr=${expression.name}, anchor=$anchor)';
}
