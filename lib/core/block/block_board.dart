import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'block_board_controller.dart';
import 'block_model.dart';
import 'block_widget.dart';

/// 拼搭台。
///
/// 用原始 [Listener] 而非 `GestureDetector` 处理指针：`GestureDetector` 的
/// pan 只跟踪单个指针，无法满足规格里「两指同时拖动两个不同积木、互不干扰」
/// 这条要求。改用按 pointer id 索引的原始事件后，多指是天然支持的。
class BlockBoard extends StatefulWidget {
  const BlockBoard({
    super.key,
    required this.controller,
    this.onBlockSound,
  });

  final BlockBoardController controller;

  /// 触摸音效回调，待 2.9 音频总线接入。
  final void Function(BlockBody block)? onBlockSound;

  @override
  State<BlockBoard> createState() => _BlockBoardState();
}

class _BlockBoardState extends State<BlockBoard> with WidgetsBindingObserver {
  /// 判定「这是点击还是拖拽」的位移阈值。
  ///
  /// 取值偏大：3 岁的手指按下时几乎必然带一点位移，阈值太小会把每一次点击
  /// 都误判成拖拽，点选通道就形同虚设。
  static const double _dragSlop = 14.0;

  /// 已按下但尚未判定为拖拽的触点。
  final Map<int, _PendingTouch> _pending = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(BlockBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 规格：拖拽中 App 切后台 → 恢复后积木必须处于合法位置，
    // 不允许留下悬空的拖拽态。
    if (state != AppLifecycleState.resumed) {
      _pending.clear();
      widget.controller.releaseAllDrags();
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  // ─── 指针事件 ───────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event, BlockBody block, Offset topLeft) {
    _pending[event.pointer] = _PendingTouch(
      blockId: block.id,
      startPosition: event.localPosition,
      grabOffset: event.localPosition - topLeft,
      blockTopLeft: topLeft,
    );
    widget.onBlockSound?.call(block);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final pending = _pending[event.pointer];
    if (pending != null) {
      final moved = (event.localPosition - pending.startPosition).distance;
      if (moved < _dragSlop) return;
      // 越过阈值，升格为拖拽。
      _pending.remove(event.pointer);
      widget.controller.beginDrag(
        pointer: event.pointer,
        blockId: pending.blockId,
        grabOffset: pending.grabOffset,
        position: event.localPosition - pending.grabOffset,
      );
      return;
    }

    final drag = widget.controller.drags[event.pointer];
    if (drag == null) return;
    widget.controller.updateDrag(
      pointer: event.pointer,
      position: event.localPosition - drag.grabOffset,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    final pending = _pending.remove(event.pointer);
    if (pending != null) {
      // 位移未越过阈值 → 判定为点击，走点选通道。
      widget.controller.tapBlock(pending.blockId);
      return;
    }
    widget.controller.endDrag(pointer: event.pointer);
  }

  /// 手指移出屏幕边缘、被系统抢走手势、来电打断——全部按释放处理。
  void _onPointerCancel(PointerCancelEvent event) {
    _pending.remove(event.pointer);
    widget.controller.endDrag(pointer: event.pointer);
  }

  void _onBoardTap(TapUpDetails details) {
    // 有选中积木时，点棋盘即落子；否则取消选中。
    widget.controller.tapPosition(details.localPosition);
  }

  // ─── 渲染 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final grid = controller.grid;
    final cell = grid.cellSize;

    // 未落位且未被拖拽的积木排在底部托盘里，从左到右依次摆放。
    var trayCol = 0;

    final children = <Widget>[];
    for (final block in controller.blocks) {
      final drag = controller.drags.values
          .where((d) => d.blockId == block.id)
          .firstOrNull;

      final Offset topLeft;
      final bool animated;

      if (drag != null) {
        topLeft = drag.position;
        animated = false; // 跟手，不能有插值延迟
      } else if (block.anchor != null) {
        topLeft = Offset(
          grid.origin.dx + block.anchor!.col * cell,
          grid.origin.dy + block.anchor!.row * cell,
        );
        animated = true; // 落位/飞入/退回都要有过程动画
      } else {
        topLeft = Offset(
          grid.origin.dx + trayCol * cell,
          grid.origin.dy + grid.rows * cell + BlockMetrics.gap,
        );
        trayCol += block.widthUnits;
        animated = true;
      }

      children.add(
        AnimatedPositioned(
          key: ValueKey(block.id),
          duration: animated
              ? const Duration(milliseconds: 260)
              : Duration.zero,
          curve: Curves.easeOutBack,
          left: topLeft.dx,
          top: topLeft.dy,
          child: Listener(
            onPointerDown: (e) => _onPointerDown(e, block, topLeft),
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: BlockWidget(
              body: block,
              cellSize: cell,
              selected: controller.selectedId == block.id,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onBoardTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: grid.origin.dx,
            top: grid.origin.dy,
            child: _GridBackdrop(
              columns: grid.columns,
              rows: grid.rows,
              cellSize: cell,
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

@immutable
class _PendingTouch {
  const _PendingTouch({
    required this.blockId,
    required this.startPosition,
    required this.grabOffset,
    required this.blockTopLeft,
  });

  final String blockId;
  final Offset startPosition;
  final Offset grabOffset;
  final Offset blockTopLeft;
}

/// 棋盘底纹。**只是展示面与落点区域**，不是可操作对象——
/// 见 design.md D3：不得要求孩子点中小于 90dp 的单格。
class _GridBackdrop extends StatelessWidget {
  const _GridBackdrop({
    required this.columns,
    required this.rows,
    required this.cellSize,
  });

  final int columns;
  final int rows;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: columns * cellSize,
        height: rows * cellSize,
        child: CustomPaint(
          painter: _GridPainter(
            columns: columns,
            rows: rows,
            cellSize: cellSize,
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.columns,
    required this.rows,
    required this.cellSize,
  });

  final int columns;
  final int rows;
  final double cellSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = BlockColors.ink.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (var c = 0; c <= columns; c++) {
      final x = c * cellSize;
      canvas.drawLine(Offset(x, 0), Offset(x, rows * cellSize), paint);
    }
    for (var r = 0; r <= rows; r++) {
      final y = r * cellSize;
      canvas.drawLine(Offset(0, y), Offset(columns * cellSize, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.columns != columns || old.rows != rows || old.cellSize != cellSize;
}
