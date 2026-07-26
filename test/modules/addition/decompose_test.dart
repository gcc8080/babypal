import 'package:baby_pal/modules/addition/addition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('分解枚举', () {
    test('规格场景：5 的全部两加数分解', () {
      expect(decompositions(5), const [
        AdditionProblem(1, 4),
        AdditionProblem(2, 3),
        AdditionProblem(3, 2),
        AdditionProblem(4, 1),
      ]);
    });

    test('有序：2+3 与 3+2 各算一种', () {
      final all = decompositions(5);
      expect(all, contains(const AdditionProblem(2, 3)));
      expect(all, contains(const AdditionProblem(3, 2)));
    });

    test('每一种分解的两个加数都是正整数，且加起来等于原数', () {
      for (var total = 2; total <= 10; total++) {
        for (final d in decompositions(total)) {
          expect(d.a, greaterThan(0), reason: '$total → $d');
          expect(d.b, greaterThan(0), reason: '$total → $d');
          expect(d.sum, total, reason: '$total → $d');
        }
      }
    });

    test('n 的分解恰好有 n-1 种', () {
      for (var total = 2; total <= 10; total++) {
        expect(decompositions(total), hasLength(total - 1), reason: '$total');
      }
    });

    test('规格边界：1 的分解是空集', () {
      expect(decompositions(1), isEmpty);
    });

    test('0 与负数同样返回空集，不抛异常', () {
      expect(decompositions(0), isEmpty);
      expect(decompositions(-3), isEmpty);
    });

    test('分解与合体是同一件事的两个方向', () {
      for (final d in decompositions(7)) {
        expect(d.sum, 7);
        // 合体求和用的是同一个模型，没有第二套数据结构。
        expect(AdditionProblem(d.a, d.b).sum, 7);
      }
    });
  });

  group('切点判定', () {
    const cell = 60.0;

    test('点哪儿切哪儿——落点取最近的格边界', () {
      expect(cutIndexAt(cell * 2.1, cell, 5), 2);
      expect(cutIndexAt(cell * 2.6, cell, 5), 3);
      expect(cutIndexAt(cell * 1.4, cell, 5), 1);
    });

    test('点在最左端也切得出 1 + (n-1)', () {
      expect(cutIndexAt(0, cell, 5), 1);
      expect(cutIndexAt(cell * 0.2, cell, 5), 1);
    });

    test('点在最右端也切得出 (n-1) + 1', () {
      expect(cutIndexAt(cell * 5, cell, 5), 4);
      expect(cutIndexAt(cell * 4.9, cell, 5), 4);
    });

    test('落点跑到积木外面也仍然给得出合法切点——不存在「没切中」', () {
      expect(cutIndexAt(-500, cell, 5), 1);
      expect(cutIndexAt(9999, cell, 5), 4);
    });

    test('2 格积木只有一个切点', () {
      for (final x in [0.0, cell * 0.5, cell, cell * 2]) {
        expect(cutIndexAt(x, cell, 2), 1, reason: 'x=$x');
      }
    });

    test('切点扫一遍整块积木，能覆盖全部分解', () {
      const total = 5;
      final reached = <int>{};
      for (var px = 0.0; px <= cell * total; px += 1) {
        reached.add(cutIndexAt(px, cell, total));
      }
      expect(reached, {1, 2, 3, 4}, reason: '每一种分法都点得到');
    });

    test('格边长非法时不崩，退回第一个切点', () {
      expect(cutIndexAt(100, 0, 5), 1);
    });
  });

  group('题序', () {
    test('5 打头——最经典的那个数', () {
      expect(kDecompositionTargets.first, 5);
    });

    test('每个数都切得开，且一行摆得下', () {
      for (final total in kDecompositionTargets) {
        expect(total, greaterThanOrEqualTo(2));
        expect(total, lessThanOrEqualTo(kAdditionColumns));
        expect(decompositions(total), isNotEmpty);
      }
    });
  });
}
