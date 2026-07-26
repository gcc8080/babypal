import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'block_model.dart';
import 'snap_grid.dart';

/// 合体规则由内容模块注入：引擎只负责「两块碰到一起了」，
/// 至于 `3 + 2` 该变成 `5`、`木 + 木` 该变成 `林`，是内容层的事。
///
/// 返回 null 表示这两块不能合体。
typedef MergeResolver = BlockBody? Function(BlockBody moving, BlockBody target);

/// 内容模块对「点击某块积木」的自行处理。
///
/// 返回 true 表示模块已消费这次点击（例如把积木收回托盘），引擎不再让它
/// 进入选中态。返回 false 则走引擎默认的点选通道。
///
/// 存在这个钩子是因为「选中→点目标位落子」并非所有模块的最优点击语义：
/// 位值工作台上位置不参与判定，点一下直接收回比先选中再决定少一步。
/// 但**点选通道本身仍是全局不变量**——模块必须在别处（如托盘源）提供它。
///
/// [localPosition] 是手指落点相对该积木左上角的偏移。反向分解要靠它决定
/// 从哪一格切开：「点哪儿切哪儿」。
typedef BlockTapHandler = bool Function(BlockBody block, Offset localPosition);

/// 拼搭台上发生的、需要出声的语义事件。
///
/// 由 controller 发出而非各模块自行判断——「什么时候该响」是引擎的知识：
/// 只有它知道这次释放到底是合体、落位还是退回。让五个内容模块各猜一遍
/// 必然出现行为不一致。
enum BlockSoundEvent {
  /// 按下积木。
  tap,

  /// 拾起（拖拽开始）。
  pickup,

  /// 吸附落位成功。
  snap,

  /// 合体。
  merge,

  /// 分裂。
  split,

  /// 退回原位。**不是失败**，见 [Sfx.returned] 的说明。
  returned,
}

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
    this.onSound,
    this.onBlockTapped,
  }) : _blocks = List.of(blocks);

  /// 语义事件回调，供调用方接音效。为 null 时静默。
  final void Function(BlockSoundEvent event)? onSound;

  /// 模块对点击的自行处理。见 [BlockTapHandler]。
  final BlockTapHandler? onBlockTapped;

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
    onSound?.call(BlockSoundEvent.pickup);
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
    if (target != null && mergeBlocks(block.id, target.id) != null) {
      return;
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
    onSound?.call(
      cell != null ? BlockSoundEvent.snap : BlockSoundEvent.returned,
    );

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
  ///
  /// 音效**先于**任何逻辑分支触发——「触摸必有回应」这条红线优先于
  /// 这次点击最终被谁消费。
  void tapBlock(String blockId, {Offset localPosition = Offset.zero}) {
    onSound?.call(BlockSoundEvent.tap);

    final block = blockById(blockId);
    if (block != null &&
        (onBlockTapped?.call(block, localPosition) ?? false)) {
      _selectedId = null;
      notifyListeners();
      return;
    }

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
    onSound?.call(BlockSoundEvent.snap);
    notifyListeners();
    return true;
  }

  void clearSelection() {
    if (_selectedId == null) return;
    _selectedId = null;
    notifyListeners();
  }

  // ─── 合体 / 分裂 / 群组 ─────────────────────────────────────────────

  /// 把 [movingId] 合到 [targetId] 上。
  ///
  /// 合体成不成由 [mergeResolver] 说了算；返回合体后的积木，不能合体时返回
  /// null 且**不改动任何状态**。
  ///
  /// 三条路径共用这一个实现：拖拽落在目标身上、点选通道点中目标、内容模块
  /// 自行判定「两块拼到一起了」。合体是有语义的动作（3+2=5、木+木=林），
  /// 让三条路径各写一遍必然出现行为不一致。
  ///
  /// 落位规则：合体结果优先用 [MergeResolver] 返回的锚点，未指定则落在
  /// 目标原处——「被撞的那块不动」符合直觉。
  BlockBody? mergeBlocks(String movingId, String targetId) {
    final resolver = mergeResolver;
    if (resolver == null || movingId == targetId) return null;

    final moving = blockById(movingId);
    final target = blockById(targetId);
    if (moving == null || target == null) return null;

    final merged = resolver(moving, target);
    if (merged == null) return null;

    _blocks.removeWhere((b) => b.id == movingId || b.id == targetId);
    final landed = merged.copyWith(anchor: merged.anchor ?? target.anchor);
    _blocks.add(landed);
    onSound?.call(BlockSoundEvent.merge);
    notifyListeners();
    return landed;
  }

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
    onSound?.call(BlockSoundEvent.split);
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

  /// 就地替换若干积木（按 id 匹配）。
  ///
  /// 用于改表情、换颜色这类**不涉及位置规则**的更新——保留原有顺序与 id，
  /// 动画层的进出场匹配因此不会被打断。
  void updateBlocks(Iterable<BlockBody> updated) {
    for (final block in updated) {
      _replace(block);
    }
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
