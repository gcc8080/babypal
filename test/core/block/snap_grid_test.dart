import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/core/block/snap_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 格位边长取 100，吸附半径 = 100 × 1.5 = 150，便于心算。
  const cell = 100.0;

  group('场景一：释放点在吸附半径内', () {
    // 单格棋盘，排除多候选干扰，纯粹验证半径判定。
    const grid = SnapGrid(columns: 1, rows: 1, cellSize: cell);

    test('距格位中心 1.2 倍格位尺寸 → 吸附落位', () {
      final result = grid.snap(
        releaseCenter: const Offset(50 + 1.2 * cell, 50),
        occupied: const {},
      );
      expect(result, const GridCell(0, 0));
    });

    test('恰好落在格位中心 → 吸附落位', () {
      final result = grid.snap(
        releaseCenter: const Offset(50, 50),
        occupied: const {},
      );
      expect(result, const GridCell(0, 0));
    });

    test('恰好等于吸附半径 → 仍然吸附（边界取闭区间）', () {
      final result = grid.snap(
        releaseCenter: const Offset(50 + 1.5 * cell, 50),
        occupied: const {},
      );
      expect(result, const GridCell(0, 0));
    });
  });

  group('场景二：释放点在吸附半径外', () {
    const grid = SnapGrid(columns: 1, rows: 1, cellSize: cell);

    test('距任何格位中心均超过 1.5 倍 → 返回 null，调用方让积木退回起点', () {
      final result = grid.snap(
        releaseCenter: const Offset(50 + 1.6 * cell, 50),
        occupied: const {},
      );
      expect(result, isNull);
    });
  });

  group('场景三：多个候选格位', () {
    // 3×1 棋盘，格位中心分别为 x = 50 / 150 / 250。
    const grid = SnapGrid(columns: 3, rows: 1, cellSize: cell);

    test('三个候选都在半径内 → 取中心距离最近者', () {
      // 释放于 x=110：到 (0,0) 距 60、到 (1,0) 距 40、到 (2,0) 距 140，
      // 三者均 ≤150，应取最近的 (1,0)。
      final result = grid.snap(
        releaseCenter: const Offset(110, 50),
        occupied: const {},
      );
      expect(result, const GridCell(1, 0));
    });

    test('偏向右侧时改选右侧格位', () {
      // 释放于 x=210：到 (1,0) 距 60、到 (2,0) 距 40，应取 (2,0)。
      final result = grid.snap(
        releaseCenter: const Offset(210, 50),
        occupied: const {},
      );
      expect(result, const GridCell(2, 0));
    });

    test('落在两格正中间时取先遍历到的一格，行为确定不抖动', () {
      // x=100 到 (0,0) 与 (1,0) 距离同为 50。严格小于比较使结果稳定为 (0,0)，
      // 不会因浮点抖动在两格间跳变——对幼儿而言可预测比"更合理"更重要。
      final result = grid.snap(
        releaseCenter: const Offset(100, 50),
        occupied: const {},
      );
      expect(result, const GridCell(0, 0));
    });
  });

  group('场景四：目标格位已被占用', () {
    const grid = SnapGrid(columns: 3, rows: 1, cellSize: cell);

    test('落在已占用格位上 → 吸附到最近的空闲格位，而非失败', () {
      // 释放于 x=160，最近的是已被占用的 (1,0)；
      // 空闲候选中 (2,0) 距 90、(0,0) 距 110，应取 (2,0)。
      final result = grid.snap(
        releaseCenter: const Offset(160, 50),
        occupied: {const GridCell(1, 0)},
      );
      expect(result, const GridCell(2, 0));
    });

    test('半径内已无空闲格位 → 返回 null', () {
      final result = grid.snap(
        releaseCenter: const Offset(150, 50),
        occupied: {
          const GridCell(0, 0),
          const GridCell(1, 0),
          const GridCell(2, 0),
        },
      );
      expect(result, isNull);
    });

    test('占用不影响半径外的判定', () {
      final result = grid.snap(
        releaseCenter: const Offset(-200, 50),
        occupied: {const GridCell(0, 0)},
      );
      expect(result, isNull);
    });
  });

  group('场景五：边界与多格积木', () {
    test('十条（10×1）在 10 列棋盘中只有列 0 一个合法锚点', () {
      const grid = SnapGrid(columns: 10, rows: 2, cellSize: cell);
      final result = grid.snap(
        releaseCenter: grid.footprintCenter(
          const GridCell(0, 0),
          widthUnits: 10,
        ),
        occupied: const {},
        widthUnits: 10,
      );
      expect(result, const GridCell(0, 0));
    });

    test('多格积木的覆盖区域与占用格相交时该锚点被排除', () {
      const grid = SnapGrid(columns: 4, rows: 1, cellSize: cell);
      // 2×1 积木释放在 x=150（跨 (0,0)-(1,0) 的位置），但 (1,0) 已被占用，
      // 因此该锚点非法，应退到 (2,0)。
      final result = grid.snap(
        releaseCenter: const Offset(150, 50),
        occupied: {const GridCell(1, 0)},
        widthUnits: 2,
      );
      expect(result, const GridCell(2, 0));
    });

    test('永远不会返回越界锚点', () {
      const grid = SnapGrid(columns: 2, rows: 2, cellSize: cell);
      // 释放到棋盘右下角外侧很远处。
      final result = grid.snap(
        releaseCenter: const Offset(1000, 1000),
        occupied: const {},
      );
      expect(result, isNull);
    });

    test('积木比棋盘还大时无合法锚点', () {
      const grid = SnapGrid(columns: 3, rows: 1, cellSize: cell);
      final result = grid.snap(
        releaseCenter: const Offset(150, 50),
        occupied: const {},
        widthUnits: 5,
      );
      expect(result, isNull);
    });
  });

  group('几何换算', () {
    const grid = SnapGrid(
      columns: 3,
      rows: 3,
      cellSize: cell,
      origin: Offset(1000, 2000),
    );

    test('centerOf 计入棋盘原点偏移', () {
      expect(grid.centerOf(const GridCell(0, 0)), const Offset(1050, 2050));
      expect(grid.centerOf(const GridCell(2, 1)), const Offset(1250, 2150));
    });

    test('1×1 积木的 footprintCenter 退化为格位中心', () {
      expect(
        grid.footprintCenter(const GridCell(1, 1)),
        grid.centerOf(const GridCell(1, 1)),
      );
    });

    test('多格积木的 footprintCenter 落在整体覆盖区域中心', () {
      expect(
        grid.footprintCenter(const GridCell(0, 0), widthUnits: 3),
        const Offset(1150, 2050),
      );
    });

    test('isInBounds 正确排除越界锚点', () {
      expect(grid.isInBounds(const GridCell(2, 2)), isTrue);
      expect(grid.isInBounds(const GridCell(3, 0)), isFalse);
      expect(grid.isInBounds(const GridCell(-1, 0)), isFalse);
      expect(grid.isInBounds(const GridCell(1, 0), widthUnits: 3), isFalse);
      expect(grid.isInBounds(const GridCell(0, 0), widthUnits: 3), isTrue);
    });

    test('吸附半径 = 格位尺寸 × 1.5', () {
      expect(grid.snapRadius, 150.0);
    });
  });

  group('BlockBody', () {
    test('footprintAt 展开多格积木覆盖的全部格位', () {
      const block = BlockBody(id: 'b1', colorIndex: 0, widthUnits: 3);
      expect(block.footprintAt(const GridCell(1, 2)), {
        const GridCell(1, 2),
        const GridCell(2, 2),
        const GridCell(3, 2),
      });
    });

    test('未落位时 footprintAt 返回空集合', () {
      const block = BlockBody(id: 'b1', colorIndex: 0);
      expect(block.footprintAt(null), isEmpty);
    });

    test('copyWith 可显式清空 anchor 与 group', () {
      const block = BlockBody(
        id: 'b1',
        colorIndex: 0,
        groupId: 'g1',
        anchor: GridCell(1, 1),
      );
      expect(block.copyWith(clearAnchor: true).anchor, isNull);
      expect(block.copyWith(clearGroup: true).groupId, isNull);
      // 不传时保持原值。
      expect(block.copyWith().anchor, const GridCell(1, 1));
      expect(block.copyWith().groupId, 'g1');
    });
  });
}
