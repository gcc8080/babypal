import 'package:flutter/material.dart';

import '../../core/block/block_board.dart';
import '../../core/block/block_board_controller.dart';
import '../../core/block/block_model.dart';
import '../../core/block/snap_grid.dart';
import '../../core/design/tokens.dart';

/// 自由沙盒。
///
/// 见 sandbox 规格：**无关卡、无目标、无计分、无正误判定**。孩子把积木放哪
/// 都对，系统不给提示也不催促。这是决定这个 App 能玩两周还是两年的模块——
/// 关卡总会被玩通，空白拼搭台不会。
class SandboxPage extends StatefulWidget {
  const SandboxPage({super.key});

  @override
  State<SandboxPage> createState() => _SandboxPageState();
}

class _SandboxPageState extends State<SandboxPage> {
  /// 托盘里始终保持这么多**格宽**的可取用积木——孩子永远不会「用完」。
  ///
  /// 按格宽而非块数计：托盘里混有单块与长条，只数块数会让长条把托盘撑出
  /// 屏幕。留一格余量，保证末尾那块不被右边缘切掉。
  static const int _trayRefillUnits = 5;

  BlockBoardController? _controller;
  int _nextBlockId = 0;

  /// 补货重入保护。
  ///
  /// `addBlock` 会触发 `notifyListeners`，而本方法正是挂在该监听上——
  /// 不加保护会递归补货，托盘里的积木数远超预期。
  bool _refilling = false;

  @override
  void dispose() {
    _controller?.removeListener(_refillTray);
    _controller?.dispose();
    super.dispose();
  }

  BlockBody _spawn() {
    final id = 'b${_nextBlockId++}';
    // 尺寸与颜色轮换，让托盘里既有单块也有长条（长条用来验证多格吸附）。
    final width = _nextBlockId % 4 == 0 ? 2 : 1;
    return BlockBody(
      id: id,
      colorIndex: _nextBlockId % BlockColors.palette.length,
      widthUnits: width,
    );
  }

  void _refillTray() {
    final controller = _controller;
    if (controller == null || _refilling) return;

    _refilling = true;
    try {
      var units = controller.blocks
          .where((b) => b.anchor == null)
          .fold<int>(0, (sum, b) => sum + b.widthUnits);
      while (units < _trayRefillUnits) {
        final block = _spawn();
        // 别让新块把托盘撑出棋盘宽度。
        if (units + block.widthUnits > controller.grid.columns) break;
        controller.addBlock(block);
        units += block.widthUnits;
      }
    } finally {
      _refilling = false;
    }
  }

  /// 沙盒里的合体规则：两块同宽的积木碰到一起就并成一条更长的。
  ///
  /// 刻意**不做任何正误判定**——沙盒里没有"拼对了"这回事，合体只是一种
  /// 可以玩的物理行为。真正带语义的合体（3+2=5、木+木=林）属于内容模块。
  BlockBody? _resolveMerge(BlockBody moving, BlockBody target) {
    if (moving.heightUnits != target.heightUnits) return null;
    final width = moving.widthUnits + target.widthUnits;
    if (width > 6) return null; // 别长到一行放不下
    return BlockBody(
      id: 'm${_nextBlockId++}',
      colorIndex: target.colorIndex,
      widthUnits: width,
      heightUnits: target.heightUnits,
      expression: BlockExpression.happy,
    );
  }

  SnapGrid _buildGrid(BoxConstraints constraints) {
    const columns = 6;
    const rows = 2;
    final gap = BlockMetrics.gap;

    // 单块积木本身就是可拖拽对象，因此格位边长必须 ≥ 抓取阈值 90dp。
    // 高度要同时容纳棋盘与底部托盘（再加一行）。
    final byWidth = (constraints.maxWidth - gap * 2) / columns;
    final byHeight = (constraints.maxHeight - gap * 3) / (rows + 1);
    final cell = [byWidth, byHeight]
        .reduce((a, b) => a < b ? a : b)
        .clamp(BlockMetrics.minGrabTarget, double.infinity);

    final boardWidth = cell * columns;
    return SnapGrid(
      columns: columns,
      rows: rows,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - boardWidth) / 2).clamp(0, double.infinity),
        gap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final grid = _buildGrid(constraints);

            if (_controller == null) {
              _controller = BlockBoardController(
                grid: grid,
                mergeResolver: _resolveMerge,
              )..addListener(_refillTray);
              _refillTray();
            } else {
              // 屏幕尺寸变化（旋转、分屏）时刷新几何。
              _controller!.updateGrid(grid);
            }

            return BlockBoard(controller: _controller!);
          },
        ),
      ),
    );
  }
}
