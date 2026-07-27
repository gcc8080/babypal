import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/modules/letters/letter_shapes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('轮廓模板', () {
    test('26 个字母一个不缺', () {
      for (var c = 0x41; c <= 0x5A; c++) {
        final letter = String.fromCharCode(c);
        expect(
          letterShapeOf(letter),
          isNotNull,
          reason: '$letter 没有轮廓模板，那一关会直接空掉',
        );
      }
    });

    test('小写也认，字母表以外的返回 null', () {
      expect(letterShapeOf('a')!.letter, 'A');
      expect(letterShapeOf('木'), isNull);
      expect(letterShapeOf('1'), isNull);
    });

    test('每个模板都是 5 行、3–5 列', () {
      for (final entry in kLetterPatterns.entries) {
        final shape = letterShapeOf(entry.key)!;
        // 4 行画出来的 B 和 8 分不开，这个玩法就没意义了。
        expect(shape.rows, 5, reason: '${entry.key} 不是 5 行');
        expect(shape.columns, inInclusiveRange(3, 5));
        expect(
          entry.value.every((line) => line.length == shape.columns),
          isTrue,
          reason: '${entry.key} 各行宽度不一致——点阵会错位',
        );
      }
    });

    test('笔画连通：没有孤零零悬在半空的格子', () {
      // 断开的笔画在屏幕上是「一块方块飘在旁边」，孩子看不出那是字母的一部分。
      for (final key in kLetterPatterns.keys) {
        final shape = letterShapeOf(key)!;
        final all = shape.cells.toSet();
        final seen = <GridCell>{shape.cells.first};
        final queue = <GridCell>[shape.cells.first];
        while (queue.isNotEmpty) {
          final c = queue.removeLast();
          // 八邻域：斜着挨着也算连通——V W X Y 的斜笔画本来就是斜着走的。
          for (var dc = -1; dc <= 1; dc++) {
            for (var dr = -1; dr <= 1; dr++) {
              if (dc == 0 && dr == 0) continue;
              final n = GridCell(c.col + dc, c.row + dr);
              if (all.contains(n) && seen.add(n)) queue.add(n);
            }
          }
        }
        expect(seen.length, all.length, reason: '$key 的笔画不连通');
      }
    });

    test('每个字母的形状互不相同', () {
      // U 和 V、O 和 Q 这类最容易画重。画重了就是在教错。
      final seen = <String, String>{};
      for (final key in kLetterPatterns.keys) {
        final signature = kLetterPatterns[key]!.join('/');
        expect(
          seen[signature],
          isNull,
          reason: '$key 与 ${seen[signature]} 的轮廓一模一样',
        );
        seen[signature] = key;
      }
    });

    test('格数在可接受范围内', () {
      for (final key in kLetterPatterns.keys) {
        final shape = letterShapeOf(key)!;
        // 下限 6：再少就画不出字母。上限 16：托盘是按一下出一块，
        // 位值工作台里他一口气放过 34 块，但那是他自己数着放的。
        expect(
          shape.size,
          inInclusiveRange(6, 16),
          reason: '$key 有 ${shape.size} 格',
        );
      }
    });
  });

  group('不可落子的格位', () {
    test('轮廓之外的格子全部被封，轮廓之内一个都不封', () {
      final shape = letterShapeOf('L')!;
      final blocked = blockedCellsFor(shape);

      expect(blocked.intersection(shape.cells.toSet()), isEmpty);
      expect(blocked.length + shape.size, shape.columns * shape.rows);
      // L 是 3×5 共 15 格，笔画 7 格。
      expect(shape.size, 7);
      expect(blocked.length, 8);
    });
  });

  group('点选通道的落点', () {
    test('从上到下、从左到右一格一格填', () {
      final shape = letterShapeOf('L')!;
      final filled = <GridCell>{};
      final order = <GridCell>[];

      for (var i = 0; i < shape.size; i++) {
        final cell = nextEmptyCell(shape, filled)!;
        order.add(cell);
        filled.add(cell);
      }

      // 字母是从上往下写出来的；倒着填出来的 L 他认不出是在写 L。
      expect(order, shape.cells);
      expect(nextEmptyCell(shape, filled), isNull, reason: '填满后应返回 null');
    });

    test('中间被拿走一块时，下一块补回那个洞', () {
      final shape = letterShapeOf('L')!;
      final filled = shape.cells.toSet()..remove(shape.cells[3]);
      expect(nextEmptyCell(shape, filled), shape.cells[3]);
    });
  });
}
