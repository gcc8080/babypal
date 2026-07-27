import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/modules/numbers/place_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('位值拆解', () {
    test('两位数拆成十条与单块（规格场景：23）', () {
      final pv = PlaceValue.of(23);
      expect(pv.tens, 2);
      expect(pv.ones, 3);
      expect(pv.value, 23);
      expect(pv.isRound, isFalse);
    });

    test('整十数只要十条（规格场景：40）', () {
      final pv = PlaceValue.of(40);
      expect(pv.tens, 4);
      expect(pv.ones, 0);
      expect(pv.isRound, isTrue);
      expect(pv.pieces, everyElement(PlacePiece.rod));
      expect(pv.pieces, hasLength(4));
    });

    test('边界值', () {
      expect(PlaceValue.of(0), const PlaceValue(tens: 0, ones: 0));
      expect(PlaceValue.of(9), const PlaceValue(tens: 0, ones: 9));
      expect(PlaceValue.of(10), const PlaceValue(tens: 1, ones: 0));
      expect(PlaceValue.of(99), const PlaceValue(tens: 9, ones: 9));
      expect(PlaceValue.of(100), const PlaceValue(tens: 10, ones: 0));
    });

    test('pieces 十条在前，总值与原数一致', () {
      final pieces = PlaceValue.of(23).pieces;
      expect(pieces.take(2), everyElement(PlacePiece.rod));
      expect(pieces.skip(2), everyElement(PlacePiece.unit));
      expect(pieces.fold<int>(0, (sum, p) => sum + p.value), 23);
    });

    test('十条的格宽等于它的数值——「10 个单块 = 1 个十条」必须一眼可见', () {
      expect(PlacePiece.rod.widthUnits, PlacePiece.rod.value);
      expect(PlacePiece.unit.widthUnits, PlacePiece.unit.value);
    });
  });

  group('孩子摆出来的表达', () {
    test('只看总数，不看摆法', () {
      const canonical = PlaceValueAttempt(rods: 2, units: 3);
      const allUnits = PlaceValueAttempt(units: 23);
      const mixed = PlaceValueAttempt(rods: 1, units: 13);

      for (final attempt in [canonical, allUnits, mixed]) {
        expect(attempt.total, 23, reason: '$attempt');
        expect(attempt.matches(23), isTrue, reason: '$attempt');
      }
    });

    test('规格场景：10 个单块可以替代 1 个十条', () {
      const attempt = PlaceValueAttempt(rods: 1, units: 13);
      expect(attempt.matches(23), isTrue);
      expect(attempt.isCanonical, isFalse);
      expect(attempt.canCompact, isTrue);

      final compacted = attempt.compact();
      expect(compacted, const PlaceValueAttempt(rods: 2, units: 3));
      expect(compacted.total, attempt.total, reason: '换十不改变总数');
      expect(compacted.isCanonical, isTrue);
    });

    test('一路换到标准写法', () {
      expect(
        const PlaceValueAttempt(units: 34).canonical(),
        const PlaceValueAttempt(rods: 3, units: 4),
      );
      expect(
        const PlaceValueAttempt(rods: 2, units: 3).canonical(),
        const PlaceValueAttempt(rods: 2, units: 3),
        reason: '已是标准写法时原样返回',
      );
    });

    test('canonical 与 PlaceValue.of 对同一个数给出一致的拆解', () {
      for (var value = 0; value <= 40; value++) {
        final attempt = PlaceValueAttempt(units: value).canonical();
        final pv = PlaceValue.of(value);
        expect(attempt.rods, pv.tens, reason: '$value');
        expect(attempt.units, pv.ones, reason: '$value');
      }
    });

    test('增减积木', () {
      var attempt = const PlaceValueAttempt();
      expect(attempt.isEmpty, isTrue);

      attempt = attempt.add(PlacePiece.rod).add(PlacePiece.unit);
      expect(attempt, const PlaceValueAttempt(rods: 1, units: 1));

      attempt = attempt.remove(PlacePiece.unit);
      expect(attempt, const PlaceValueAttempt(rods: 1));
    });

    test('从空表达上再拿走一块不会变成负数', () {
      const empty = PlaceValueAttempt();
      expect(empty.remove(PlacePiece.rod), empty);
      expect(empty.remove(PlacePiece.unit), empty);
    });

    test('fromPieces 与 PlaceValue.pieces 往返一致', () {
      for (final value in [0, 7, 20, 23, 40]) {
        expect(
          PlaceValueAttempt.fromPieces(PlaceValue.of(value).pieces).total,
          value,
        );
      }
    });
  });

  group('题序', () {
    test('每一题都摆得下 10×4 的工作台', () {
      const capacity = kPlaceValueColumns * kPlaceValueRows;
      for (final target in kPlaceValueTargets) {
        expect(target, lessThanOrEqualTo(capacity), reason: '目标 $target');
        expect(target, greaterThan(0));
      }
    });

    test('头两题是他一看就会的十几、二十几', () {
      expect(kPlaceValueTargets.first, inInclusiveRange(11, 19));
      expect(kPlaceValueTargets[1], inInclusiveRange(20, 29));
    });

    test('题序覆盖整十数', () {
      expect(kPlaceValueTargets.where((t) => t % 10 == 0), isNotEmpty);
    });
  });

  group('自动落点', () {
    test('十条从上往下一行一条', () {
      final occupied = <GridCell>{};
      for (var expectedRow = 0; expectedRow < kPlaceValueRows; expectedRow++) {
        final anchor = nextFreeAnchor(
          piece: PlacePiece.rod,
          occupied: occupied,
        );
        expect(anchor, GridCell(0, expectedRow));
        for (var col = 0; col < kPlaceValueColumns; col++) {
          occupied.add(GridCell(col, expectedRow));
        }
      }
    });

    test('单块从下往上、从左往右填', () {
      final occupied = <GridCell>{};
      final first = nextFreeAnchor(piece: PlacePiece.unit, occupied: occupied);
      expect(first, const GridCell(0, kPlaceValueRows - 1));

      occupied.add(first!);
      expect(
        nextFreeAnchor(piece: PlacePiece.unit, occupied: occupied),
        const GridCell(1, kPlaceValueRows - 1),
      );
    });

    test('十条与单块从两端相向生长，互不挤占', () {
      final occupied = <GridCell>{};
      final rod = nextFreeAnchor(piece: PlacePiece.rod, occupied: occupied)!;
      expect(rod.row, 0);
      for (var col = 0; col < kPlaceValueColumns; col++) {
        occupied.add(GridCell(col, rod.row));
      }

      final unit = nextFreeAnchor(piece: PlacePiece.unit, occupied: occupied)!;
      expect(unit.row, kPlaceValueRows - 1);
    });

    test('十条跳过已被单块占掉的行', () {
      final occupied = {const GridCell(3, 0)};
      expect(
        nextFreeAnchor(piece: PlacePiece.rod, occupied: occupied),
        const GridCell(0, 1),
      );
    });

    test('放不下时返回 null——调用方据此静默忽略，不得提示错误', () {
      final full = <GridCell>{
        for (var col = 0; col < kPlaceValueColumns; col++)
          for (var row = 0; row < kPlaceValueRows; row++) GridCell(col, row),
      };
      expect(nextFreeAnchor(piece: PlacePiece.rod, occupied: full), isNull);
      expect(nextFreeAnchor(piece: PlacePiece.unit, occupied: full), isNull);
    });

    test('列数不足以容纳十条时返回 null 而不是越界', () {
      expect(
        nextFreeAnchor(
          piece: PlacePiece.rod,
          occupied: const {},
          columns: 6,
          rows: 4,
        ),
        isNull,
      );
    });
  });
}
