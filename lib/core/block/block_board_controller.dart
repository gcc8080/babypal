import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'block_model.dart';
import 'snap_grid.dart';

/// 合体规则由内容模块注入：引擎只负责「两块碰到一起了」，
/// 至于 `3 + 2` 该变成 `5`、`木 + 木` 该变成 `林`，是内容层的事。
///
/// 返回 null 表示这两块不能合体。
typedef MergeResolver = BlockBody? Function(BlockBody moving, BlockBody target);

/// 一次进行中的拖拽。按指针 id 索引，因此多指同时拖拽天然互不干扰。
@immutable
class ActiveDrag {
  const ActiveDrag({
    required this.blockId,
    required this.grabOffset,
    required this.position,
    required this.originAnchor,
  });

  final String blockId;

  /// 手指落点相对积木左上角的偏移，拖动过程中保持不变——
  /// 否则积木会在按下瞬间"跳"到手指中心。
  final Offset grabOffset;

  /// 积木左上角当前位置（棋盘坐标系）。
  final Offset position;

  /// 拖拽开始时的格位。释放失败时回到这里。
  final GridCell? originAnchor;

  ActiveDrag copyWith({Offset? position}) => ActiveDrag(
        blockId: blockId,
        grabOffset: grabOffset,
        position: position ?? this.position,
        originAnchor: originAnchor,
      );
}

/// 拼搭台的状态与规则。
///
/// 刻意与渲染分离：合体、分裂、群组、吸附落位这些规则全部可以用纯逻辑单测
/// 覆盖，不需要 pump 组件树。
class BlockBoardController extends ChangeNotifier {
  BlockBoardController({
    required this.grid,
    List<BlockBody> blocks = const [],
    this.mergeResolver,
  }) : _blocks = List.of(blocks);

  /// 棋盘几何。屏幕尺寸变化（旋转、平板分屏）时由渲染层调用 [updateGrid] 刷新。
  SnapGrid grid;

  void updateGrid(SnapGrid value) {
    if (grid == value) return;
    grid = value;
    notifyListeners();
  }

  final List<BlockBody> _blocks;
  List<BlockBody> get blocks => List.unmodifiable(_blocks);

  final MergeResolver? mergeResolver;

  /// 进行中的拖拽，按指针 id 索引。
  final Map<int, ActiveDrag> _drags = {};
  Map<int, ActiveDrag> get drags => Map.unmodifiable(_drags);

  /// 点选通道的当前选中积木。
  String? _selectedId;
  String? get selectedId => _selectedId;

  BlockBody? blockById(String id) {
    for (final b in _blocks) {
      if (b.id == id) return b;
    }
    return null;
  }

  bool isDragging(String blockId) =>
      _drags.values.any((d) => d.blockId == blockId);

  /// 当前被占用的格位。[excluding] 用于把正在移动的积木自身排除在外，
  /// 否则它永远会挡住自己的落点。
  Set<GridCell> occupiedCells({Set<String> excluding = const {}}) {
    final cells = <GridCell>{};
    for (final b in _blocks) {
      if (excluding.contains(b.id)) continue;
      if (b.anchor == null) continue;
      cells.addAll(b.footprintAt(b.anchor));
    }
    return cells;
  }

  /// 与某积木同组的全部积木 id（含自身）。
  Set<String> groupMemberIds(BlockBody block) {
    final gid = block.groupId;
    if (gid == null) return {block.id};
    return _blocks.where((b) => b.groupId == gid).map((b) => b.id).toSet();
  }

  // ─── 拖拽通道 ───────────────────────────────────────────────────────

  void beginDrag({
    required int pointer,
    required String blockId,
    required Offset grabOffset,
    required Offset position,
  }) {
    final block = blockById(blockId);
    if (block == null) return;
    _drags[pointer] = ActiveDrag(
      blockId: blockId,
      grabOffset: grabOffset,
      position: position,
      originAnchor: block.anchor,
    );
    // 拖起来就离开格位，避免自己挡住自己的落点。
    _replace(block.copyWith(clearAnchor: true));
    _selectedId = null;
    notifyListeners();
  }

  void updateDrag({required int pointer, required Offset position}) {
    final drag = _drags[pointer];
    if (drag == null) return;
    _drags[pointer] = drag.copyWith(position: position);
    notifyListeners();
  }

  /// 结束一次拖拽。
  ///
  /// 手指移出屏幕边缘、指针被系统取消、App 切后台，全部走这条路径——
  /// 规格要求这些情况一律「按释放处理」，绝不能留下悬空的拖拽态。
  void endDrag({required int pointer}) {
    final drag = _drags.remove(pointer);
    if (drag == null) return;

    final block = blockById(drag.blockId);
    if (block == null) {
      notifyListeners();
      return;
    }

    final center = drag.position +
        Offset(
          block.widthUnits * grid.cellSize / 2,
          block.heightUnits * grid.cellSize / 2,
        );

    // ① 先看是否落在某块可合体的积木上。
    final target = _blockAt(center, excludingId: block.id);
    if (target != null && mergeResolver != null) {
      final merged = mergeResolver!(block, target);
      if (merged != null) {
        _blocks.removeWhere((b) => b.id == block.id || b.id == target.id);
        _blocks.add(merged.copyWith(anchor: target.anchor));
        notifyListeners();
        return;
      }
    }

    // ② 否则吸附到最近的空闲合法格位。
    final moving = groupMemberIds(block);
    final cell = grid.snap(
      releaseCenter: center,
      occupied: occupiedCells(excluding: moving),
      widthUnits: block.widthUnits,
      heightUnits: block.heightUnits,
    );

    // ③ 吸附失败就回到起点——不播放任何错误提示（无挫败红线）。
    final landed = cell ?? drag.originAnchor;
    _replace(block.copyWith(anchor: landed));

    // ④ 同组积木按相同的格位位移一同移动，保持相对位置不变。
    final origin = drag.originAnchor;
    if (landed != null && origin != null && moving.length > 1) {
      final dCol = landed.col - origin.col;
      final dRow = landed.row - origin.row;
      if (dCol != 0 || dRow != 0) {
        for (final id in moving) {
          if (id == block.id) continue;
          final sibling = blockById(id);
          final a = sibling?.anchor;
          if (sibling == null || a == null) continue;
          _replace(
            sibling.copyWith(anchor: GridCell(a.col + dCol, a.row + dRow)),
          );
        }
      }
    }

    notifyListeners();
  }

  /// 释放全部进行中的拖拽。App 切后台时调用。
  void releaseAllDrags() {
    for (final pointer in _drags.keys.toList()) {
      endDrag(pointer: pointer);
    }
  }

  BlockBody? _blockAt(Offset point, {required String excludingId}) {
    for (final b in _blocks) {
      if (b.id == excludingId || b.anchor == null) continue;
      final topLeft = Offset(
        grid.origin.dx + b.anchor!.col * grid.cellSize,
        grid.origin.dy + b.anchor!.row * grid.cellSize,
      );
      final contains = point.dx >= topLeft.dx &&
          point.dy >= topLeft.dy &&
          point.dx < topLeft.dx + b.widthUnits * grid.cellSize &&
          point.dy < topLeft.dy + b.heightUnits * grid.cellSize;
      if (contains) return b;
    }
    return null;
  }

  // ─── 点选通道 ───────────────────────────────────────────────────────
  //
  // 见 design.md D2：3 岁儿童的拖拽成功率不稳定，手指离屏、多指干扰、中途松手
  // 都很常见。「拖不动」不等于「做不到」——若只有拖拽通道，挫败感来自操作而非
  // 认知，与「无挫败」红线直接冲突。

  /// 点击积木：进入选中态；再次点击同一块则取消。
  void tapBlock(String blockId) {
    _selectedId = _selectedId == blockId ? null : blockId;
    notifyListeners();
  }

  /// 点击棋盘上的某个位置。
  ///
  /// 有选中积木且该处是合法落点 → 落子并返回 true（调用方据此播放飞入动画）；
  /// 否则取消选中并返回 false。
  bool tapPosition(Offset point) {
    final id = _selectedId;
    if (id == null) return false;
    final block = blockById(id);
    if (block == null) {
      _selectedId = null;
      notifyListeners();
      return false;
    }

    final cell = grid.snap(
      releaseCenter: point,
      occupied: occupiedCells(excluding: groupMemberIds(block)),
      widthUnits: block.widthUnits,
      heightUnits: block.heightUnits,
    );

    _selectedId = null;
    if (cell == null) {
      notifyListeners();
      return false;
    }
    _replace(block.copyWith(anchor: cell));
    notifyListeners();
    return true;
  }

  void clearSelection() {
    if (_selectedId == null) return;
    _selectedId = null;
    notifyListeners();
  }

  // ─── 合体 / 分裂 / 群组 ─────────────────────────────────────────────

  /// 把一块积木分裂成多块。
  ///
  /// 这是加法模块「反向分解」的引擎支撑：`5` 拖一刀切开变成 `2 + 3`。
  /// 原积木消失，新积木继承其锚点向右依次排布。
  void split(String blockId, List<BlockBody> parts) {
    final block = blockById(blockId);
    if (block == null || parts.isEmpty) return;

    _blocks.removeWhere((b) => b.id == blockId);
    final anchor = block.anchor;
    var col = anchor?.col ?? 0;
    for (final part in parts) {
      _blocks.add(
        part.copyWith(
          anchor: anchor == null ? null : GridCell(col, anchor.row),
        ),
      );
      col += part.widthUnits;
    }
    notifyListeners();
  }

  /// 把若干积木编为一组，此后拖动其中任意一块，整组一同移动。
  void group(Iterable<String> blockIds, String groupId) {
    for (final id in blockIds) {
      final b = blockById(id);
      if (b != null) _replace(b.copyWith(groupId: groupId));
    }
    notifyListeners();
  }

  void ungroup(String groupId) {
    for (final b in _blocks.where((b) => b.groupId == groupId).toList()) {
      _replace(b.copyWith(clearGroup: true));
    }
    notifyListeners();
  }

  void addBlock(BlockBody block) {
    _blocks.add(block);
    notifyListeners();
  }

  void removeBlock(String blockId) {
    _blocks.removeWhere((b) => b.id == blockId);
    if (_selectedId == blockId) _selectedId = null;
    notifyListeners();
  }

  void _replace(BlockBody block) {
    final i = _blocks.indexWhere((b) => b.id == block.id);
    if (i >= 0) {
      _blocks[i] = block;
    } else {
      _blocks.add(block);
    }
  }
}
