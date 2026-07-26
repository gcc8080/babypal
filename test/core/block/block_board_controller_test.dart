import 'package:baby_pal/core/block/block_board_controller.dart';
import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/core/block/snap_grid.dart';
import 'package:flutter_test/flutter_test.dart';

const cell = 100.0;
const grid = SnapGrid(columns: 4, rows: 2, cellSize: cell);

BlockBody block(String id, {int color = 0, int w = 1, GridCell? at}) =>
    BlockBody(id: id, colorIndex: color, widthUnits: w, anchor: at);

/// 把积木左上角放到指定格位对应的像素位置。
Offset topLeftOf(GridCell c) => Offset(c.col * cell, c.row * cell);

void main() {
  group('拖拽通道（2.6）', () {
    test('拖到目标格位释放 → 吸附落位', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [block('a', at: const GridCell(0, 0))],
      );

      c.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: const Offset(50, 50),
        position: topLeftOf(const GridCell(0, 0)),
      );
      c.updateDrag(pointer: 1, position: topLeftOf(const GridCell(2, 1)));
      c.endDrag(pointer: 1);

      expect(c.blockById('a')!.anchor, const GridCell(2, 1));
      expect(c.drags, isEmpty);
    });

    test('拖到棋盘外释放 → 退回起点，且不留悬空拖拽态', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [block('a', at: const GridCell(1, 1))],
      );

      c.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(1, 1)),
      );
      c.updateDrag(pointer: 1, position: const Offset(5000, 5000));
      c.endDrag(pointer: 1);

      expect(c.blockById('a')!.anchor, const GridCell(1, 1));
      expect(c.drags, isEmpty);
    });

    test('拖拽中被占用的格位不会被抢占', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [
          block('a', at: const GridCell(0, 0)),
          block('b', color: 1, at: const GridCell(2, 0)),
        ],
      );

      c.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(0, 0)),
      );
      // 正对着 b 所在格位释放。
      c.updateDrag(pointer: 1, position: topLeftOf(const GridCell(2, 0)));
      c.endDrag(pointer: 1);

      expect(c.blockById('b')!.anchor, const GridCell(2, 0), reason: 'b 不动');
      expect(c.blockById('a')!.anchor, isNot(const GridCell(2, 0)));
    });

    test('两指同时拖拽两块积木，互不干扰', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [
          block('a', at: const GridCell(0, 0)),
          block('b', color: 1, at: const GridCell(1, 0)),
        ],
      );

      c.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(0, 0)),
      );
      c.beginDrag(
        pointer: 2,
        blockId: 'b',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(1, 0)),
      );
      expect(c.drags.length, 2);

      c.updateDrag(pointer: 1, position: topLeftOf(const GridCell(0, 1)));
      c.updateDrag(pointer: 2, position: topLeftOf(const GridCell(3, 1)));

      // 各自的拖拽状态互不串台。
      expect(c.drags[1]!.blockId, 'a');
      expect(c.drags[2]!.blockId, 'b');

      c.endDrag(pointer: 2);
      expect(c.blockById('b')!.anchor, const GridCell(3, 1));
      expect(c.drags.length, 1, reason: 'a 仍在拖拽中');

      c.endDrag(pointer: 1);
      expect(c.blockById('a')!.anchor, const GridCell(0, 1));
      expect(c.drags, isEmpty);
    });

    test('App 切后台 → 全部拖拽按释放处理，无悬空态', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [
          block('a', at: const GridCell(0, 0)),
          block('b', color: 1, at: const GridCell(1, 0)),
        ],
      );

      c.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(0, 0)),
      );
      c.beginDrag(
        pointer: 2,
        blockId: 'b',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(1, 0)),
      );

      c.releaseAllDrags();

      expect(c.drags, isEmpty);
      // 两块都落在合法位置上，没有 anchor 为 null 的悬空积木。
      expect(c.blocks.every((b) => b.anchor != null), isTrue);
    });
  });

  group('点选通道（2.7）', () {
    test('点积木进入选中态 → 点目标位落子', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [block('a', at: const GridCell(0, 0))],
      );

      c.tapBlock('a');
      expect(c.selectedId, 'a');

      final placed = c.tapPosition(grid.centerOf(const GridCell(3, 1)));
      expect(placed, isTrue);
      expect(c.blockById('a')!.anchor, const GridCell(3, 1));
      expect(c.selectedId, isNull);
    });

    test('再次点击同一块 → 取消选中', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [block('a', at: const GridCell(0, 0))],
      );

      c.tapBlock('a');
      c.tapBlock('a');
      expect(c.selectedId, isNull);
    });

    test('点击非法落点 → 取消选中且不放置', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [block('a', at: const GridCell(0, 0))],
      );

      c.tapBlock('a');
      final placed = c.tapPosition(const Offset(5000, 5000));
      expect(placed, isFalse);
      expect(c.selectedId, isNull);
      expect(c.blockById('a')!.anchor, const GridCell(0, 0));
    });

    test('无选中时点击棋盘不产生任何放置', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [block('a', at: const GridCell(0, 0))],
      );
      expect(c.tapPosition(grid.centerOf(const GridCell(2, 0))), isFalse);
      expect(c.blockById('a')!.anchor, const GridCell(0, 0));
    });

    test('点选通道与拖拽通道结果一致——都落到同一格', () {
      GridCell? viaDrag;
      GridCell? viaTap;

      final c1 = BlockBoardController(
        grid: grid,
        blocks: [block('a', at: const GridCell(0, 0))],
      );
      c1.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(0, 0)),
      );
      c1.updateDrag(pointer: 1, position: topLeftOf(const GridCell(2, 1)));
      c1.endDrag(pointer: 1);
      viaDrag = c1.blockById('a')!.anchor;

      final c2 = BlockBoardController(
        grid: grid,
        blocks: [block('a', at: const GridCell(0, 0))],
      );
      c2.tapBlock('a');
      c2.tapPosition(grid.centerOf(const GridCell(2, 1)));
      viaTap = c2.blockById('a')!.anchor;

      expect(viaDrag, viaTap);
    });
  });

  group('合体 / 分裂 / 群组（2.8）', () {
    test('拖到可合体的积木上 → 两块消失，生成新积木', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [
          block('three', at: const GridCell(0, 0)),
          block('two', color: 1, at: const GridCell(2, 0)),
        ],
        mergeResolver: (moving, target) =>
            const BlockBody(id: 'five', colorIndex: 4),
      );

      c.beginDrag(
        pointer: 1,
        blockId: 'three',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(0, 0)),
      );
      c.updateDrag(pointer: 1, position: topLeftOf(const GridCell(2, 0)));
      c.endDrag(pointer: 1);

      expect(c.blockById('three'), isNull);
      expect(c.blockById('two'), isNull);
      expect(c.blockById('five')!.anchor, const GridCell(2, 0));
    });

    test('mergeResolver 返回 null → 不合体，退回普通吸附', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [
          block('a', at: const GridCell(0, 0)),
          block('b', color: 1, at: const GridCell(2, 0)),
        ],
        mergeResolver: (moving, target) => null,
      );

      c.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(0, 0)),
      );
      c.updateDrag(pointer: 1, position: topLeftOf(const GridCell(2, 0)));
      c.endDrag(pointer: 1);

      expect(c.blockById('a'), isNotNull);
      expect(c.blockById('b')!.anchor, const GridCell(2, 0));
    });

    test('分裂：5 拆成 2 + 3，原积木消失，新积木依次排布', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [block('five', w: 4, at: const GridCell(0, 0))],
      );

      c.split('five', [
        block('two', w: 1, color: 1),
        block('three', w: 2, color: 2),
      ]);

      expect(c.blockById('five'), isNull);
      expect(c.blockById('two')!.anchor, const GridCell(0, 0));
      expect(c.blockById('three')!.anchor, const GridCell(1, 0));
    });

    test('群组：拖动其中一块，整组保持相对位置一同移动', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [
          block('a', at: const GridCell(0, 0)),
          block('b', color: 1, at: const GridCell(1, 0)),
        ],
      );
      c.group(['a', 'b'], 'g1');

      c.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(0, 0)),
      );
      // a: (0,0) → (0,1)，位移 (0, +1)
      c.updateDrag(pointer: 1, position: topLeftOf(const GridCell(0, 1)));
      c.endDrag(pointer: 1);

      expect(c.blockById('a')!.anchor, const GridCell(0, 1));
      expect(
        c.blockById('b')!.anchor,
        const GridCell(1, 1),
        reason: 'b 应随组一同下移一行，相对位置不变',
      );
    });

    test('解组后各块独立移动', () {
      final c = BlockBoardController(
        grid: grid,
        blocks: [
          block('a', at: const GridCell(0, 0)),
          block('b', color: 1, at: const GridCell(1, 0)),
        ],
      );
      c.group(['a', 'b'], 'g1');
      c.ungroup('g1');

      c.beginDrag(
        pointer: 1,
        blockId: 'a',
        grabOffset: Offset.zero,
        position: topLeftOf(const GridCell(0, 0)),
      );
      c.updateDrag(pointer: 1, position: topLeftOf(const GridCell(0, 1)));
      c.endDrag(pointer: 1);

      expect(c.blockById('a')!.anchor, const GridCell(0, 1));
      expect(c.blockById('b')!.anchor, const GridCell(1, 0), reason: 'b 不动');
    });
  });
}
