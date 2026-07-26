import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/modules/numbers/hundred_board.dart';
import 'package:baby_pal/modules/numbers/place_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('填充状态', () {
    test('开局是空的', () {
      const board = HundredBoard();
      expect(board.filled, 0);
      expect(board.isEmpty, isTrue);
      expect(board.isFull, isFalse);
      expect(board.completedRows, 0);
    });

    test('十条加 10 格，单块加 1 格', () {
      var board = const HundredBoard();
      board = board.add(PlacePiece.rod);
      expect(board.filled, 10);
      board = board.add(PlacePiece.unit);
      expect(board.filled, 11);
    });

    test('整行数与零散格数——34 就是「三行十个」加「四个」', () {
      const board = HundredBoard(filled: 34);
      expect(board.completedRows, 3);
      expect(board.looseCells, 4);
      // 与位值拆解算的是同一件事，不该有第二套答案。
      final pv = PlaceValue.of(34);
      expect(board.completedRows, pv.tens);
      expect(board.looseCells, pv.ones);
    });

    test('整十数没有零散格', () {
      for (final n in [10, 20, 50, 100]) {
        final board = HundredBoard(filled: n);
        expect(board.looseCells, 0, reason: '$n');
        expect(board.completedRows, n ~/ 10, reason: '$n');
      }
    });

    test('填满 100 就停住，多按不会溢出也不会报错', () {
      var board = const HundredBoard(filled: 95);
      board = board.add(PlacePiece.rod);
      expect(board.filled, HundredBoard.capacity);
      expect(board.isFull, isTrue);

      board = board.add(PlacePiece.rod).add(PlacePiece.unit);
      expect(board.filled, HundredBoard.capacity, reason: '停在 100');
    });

    test('清空回到起点', () {
      expect(const HundredBoard(filled: 47).cleared, const HundredBoard());
    });

    test('相等只看填了多少', () {
      expect(const HundredBoard(filled: 20), const HundredBoard(filled: 20));
      expect(
        const HundredBoard(filled: 20),
        isNot(const HundredBoard(filled: 21)),
      );
    });
  });

  group('格位', () {
    test('行优先：第一行是 1–10，第二行 11–20', () {
      expect(HundredBoard.cellAt(0), const GridCell(0, 0));
      expect(HundredBoard.cellAt(9), const GridCell(9, 0));
      expect(HundredBoard.cellAt(10), const GridCell(0, 1));
      expect(HundredBoard.cellAt(99), const GridCell(9, 9));
    });

    test('100 格恰好铺满 10×10，无重复无遗漏', () {
      final cells = <GridCell>{};
      for (var i = 0; i < HundredBoard.capacity; i++) {
        cells.add(HundredBoard.cellAt(i));
      }
      expect(cells, hasLength(HundredBoard.capacity));
    });

    test('整行的格与零散格分得开——界面靠它上不同的颜色', () {
      const board = HundredBoard(filled: 34);
      expect(board.isInCompletedRow(0), isTrue, reason: '第 1 格在整行里');
      expect(board.isInCompletedRow(29), isTrue, reason: '第 30 格在整行里');
      expect(board.isInCompletedRow(30), isFalse, reason: '第 31 格是零散格');
      expect(board.isInCompletedRow(33), isFalse);
    });
  });

  group('整行判定（放烟花的依据）', () {
    test('规格场景：第 3 行的第 10 格被填充 → 该行完成', () {
      // 第 3 行是 21–30，填到第 30 格即 filled 从 29 变 30。
      expect(rowsCompletedBetween(29, 30), [2]);
    });

    test('一条十条正好填满一行', () {
      expect(rowsCompletedBetween(0, 10), [0]);
      expect(rowsCompletedBetween(20, 30), [2]);
    });

    test('跨行的十条只完成它跨过的那一行', () {
      expect(rowsCompletedBetween(5, 15), [0]);
      expect(rowsCompletedBetween(9, 19), [0]);
    });

    test('没跨过整十就没有烟花', () {
      expect(rowsCompletedBetween(1, 2), isEmpty);
      expect(rowsCompletedBetween(11, 19), isEmpty);
      expect(rowsCompletedBetween(30, 30), isEmpty);
    });

    test('一次最多完成一行——十条正好等于行宽', () {
      for (var from = 0; from < HundredBoard.capacity; from++) {
        final to = (from + PlacePiece.rod.value).clamp(
          0,
          HundredBoard.capacity,
        );
        expect(
          rowsCompletedBetween(from, to).length,
          lessThanOrEqualTo(1),
          reason: '$from → $to',
        );
      }
    });

    test('一格一格填到 100，恰好放 10 次烟花', () {
      var bursts = 0;
      for (var n = 0; n < HundredBoard.capacity; n++) {
        bursts += rowsCompletedBetween(n, n + 1).length;
      }
      expect(bursts, HundredBoard.rows);
    });

    test('填满最后一格时最后一行也完成', () {
      expect(rowsCompletedBetween(99, 100), [9]);
    });
  });

  group('取用块', () {
    test('只有十条与单块，没有「百板」——一步填完就没得玩了', () {
      expect(kHundredBoardPieces, [PlacePiece.rod, PlacePiece.unit]);
      expect(
        kHundredBoardPieces.every((p) => p.value < HundredBoard.capacity),
        isTrue,
      );
    });
  });
}
