import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../design/tokens.dart';
import 'block_model.dart';

/// 网格吸附的纯逻辑实现。
///
/// 刻意不持有任何 Widget / BuildContext：格位尺寸与原点由渲染层算好后传入，
/// 这样吸附行为可以完全用单测覆盖，不需要 pump 组件树。
///
/// 见 design.md D1：不引入物理引擎——幼儿要的是「吸附到位」的确定感，
/// 不是自由落体。
@immutable
class SnapGrid {
  const SnapGrid({
    required this.columns,
    required this.rows,
    required this.cellSize,
    this.origin = Offset.zero,
  })  : assert(columns > 0),
        assert(rows > 0),
        assert(cellSize > 0);

  /// 棋盘列数。
  final int columns;

  /// 棋盘行数。
  final int rows;

  /// 单个格位的边长（**已含缩放因子**的像素值）。
  final double cellSize;

  /// 棋盘左上角在父坐标系中的位置。
  final Offset origin;

  /// 吸附半径 = 格位尺寸 × 宽容系数。
  ///
  /// 幼儿拖不准，宁可「抢着吸过去」也不要让他反复试。见 tokens 的
  /// [BlockMetrics.snapToleranceFactor]。
  double get snapRadius => cellSize * BlockMetrics.snapToleranceFactor;

  /// 指定格位中心点的像素坐标。
  Offset centerOf(GridCell cell) => Offset(
        origin.dx + (cell.col + 0.5) * cellSize,
        origin.dy + (cell.row + 0.5) * cellSize,
      );

  /// 以 [anchor] 为左上角、尺寸为 [widthUnits]×[heightUnits] 的积木，
  /// 其整体覆盖区域的中心点。
  ///
  /// 1×1 积木时退化为 [centerOf]，与规格中「格位中心」的表述一致。
  Offset footprintCenter(
    GridCell anchor, {
    int widthUnits = 1,
    int heightUnits = 1,
  }) =>
      Offset(
        origin.dx + (anchor.col + widthUnits / 2) * cellSize,
        origin.dy + (anchor.row + heightUnits / 2) * cellSize,
      );

  /// 该锚点是否完全落在棋盘内。
  bool isInBounds(
    GridCell anchor, {
    int widthUnits = 1,
    int heightUnits = 1,
  }) =>
      anchor.col >= 0 &&
      anchor.row >= 0 &&
      anchor.col + widthUnits <= columns &&
      anchor.row + heightUnits <= rows;

  /// 求积木释放后应当落入的格位锚点。
  ///
  /// [releaseCenter] 是积木**中心**在父坐标系中的释放位置。
  ///
  /// 判定规则（对应 block-engine 规格的四个场景）：
  /// 1. 只考虑完全在棋盘内、且覆盖区域不与 [occupied] 相交的候选锚点；
  /// 2. 在这些候选中取覆盖区域中心距 [releaseCenter] 最近者；
  /// 3. 若最近者的距离仍超过 [snapRadius]，返回 null——调用方据此让积木
  ///    带动画返回起点，**且不播放任何错误提示**（无挫败红线）。
  ///
  /// 「目标格位已被占用」不是一种失败：被占用的候选直接从集合中排除，
  /// 因此结果自然落到最近的空闲格位上。
  GridCell? snap({
    required Offset releaseCenter,
    required Set<GridCell> occupied,
    int widthUnits = 1,
    int heightUnits = 1,
  }) {
    GridCell? best;
    var bestDistance = double.infinity;

    for (var col = 0; col + widthUnits <= columns; col++) {
      for (var row = 0; row + heightUnits <= rows; row++) {
        final anchor = GridCell(col, row);

        if (_overlapsOccupied(
          anchor,
          occupied,
          widthUnits: widthUnits,
          heightUnits: heightUnits,
        )) {
          continue;
        }

        final distance = (releaseCenter -
                footprintCenter(
                  anchor,
                  widthUnits: widthUnits,
                  heightUnits: heightUnits,
                ))
            .distance;

        if (distance < bestDistance) {
          bestDistance = distance;
          best = anchor;
        }
      }
    }

    return bestDistance <= snapRadius ? best : null;
  }

  bool _overlapsOccupied(
    GridCell anchor,
    Set<GridCell> occupied, {
    required int widthUnits,
    required int heightUnits,
  }) {
    for (var dc = 0; dc < widthUnits; dc++) {
      for (var dr = 0; dr < heightUnits; dr++) {
        if (occupied.contains(GridCell(anchor.col + dc, anchor.row + dr))) {
          return true;
        }
      }
    }
    return false;
  }
}
