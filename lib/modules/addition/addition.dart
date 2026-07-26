import 'package:flutter/foundation.dart';

/// 一道加法题。
@immutable
class AdditionProblem {
  const AdditionProblem(this.a, this.b)
      : assert(a > 0),
        assert(b > 0);

  final int a;
  final int b;

  int get sum => a + b;

  /// 凑十：`6+4`、`7+3` 这类。他明年学进位加法时全部建在这上面，
  /// 因此题序里必须有，且要放在后段——先把「合体就是加法」这件事坐实。
  bool get makesTen => sum == 10;

  @override
  bool operator ==(Object other) =>
      other is AdditionProblem && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'AdditionProblem($a + $b = $sum)';
}

/// 合体求和的题序。
///
/// 他已经会背 10 以内加法表，所以这里不是教他算，而是让他**看见**
/// 「三块加两块真的变成了五块」——把背下来的口诀接回实物。
///
/// 排序有意：从 1+1 起步坐实规则，中段放他熟悉的算式，后段全是凑十。
const List<AdditionProblem> kAdditionProblems = [
  AdditionProblem(1, 1),
  AdditionProblem(2, 1),
  AdditionProblem(2, 2),
  AdditionProblem(3, 2),
  AdditionProblem(1, 4),
  AdditionProblem(3, 3),
  AdditionProblem(5, 2),
  AdditionProblem(4, 3),
  AdditionProblem(2, 6),
  AdditionProblem(5, 5),
  AdditionProblem(6, 4),
  AdditionProblem(7, 3),
];

/// 拼搭台列数。得数最大的那道题也必须一行摆得下。
const int kAdditionColumns = 10;

/// 拼搭台行数。两个加数各占一行还余一行，够他把积木挪来挪去。
const int kAdditionRows = 3;
