import 'package:flutter/foundation.dart';

/// 一道加法题。
@immutable
class AdditionProblem {
  const AdditionProblem(this.a, this.b) : assert(a > 0), assert(b > 0);

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

/// 把 [total] 拆成两个加数的全部**有序**分解。
///
/// 有序：`2+3` 与 `3+2` 分别算一种。规格里 5 的分解枚举写的就是
/// `1+4`、`2+3`、`3+2`、`4+1` 四种——对他而言「左边 2 右边 3」和
/// 「左边 3 右边 2」在积木上确实是两个不同的画面。
///
/// 加数必须是正整数，因此 `total <= 1` 返回空集，且界面
/// **MUST NOT** 因此给任何错误提示。
List<AdditionProblem> decompositions(int total) => [
  for (var a = 1; a < total; a++) AdditionProblem(a, total - a),
];

/// 反向分解的题序。
///
/// 5 打头——它是最经典的那个数（4 种分法，不多不少），也是凑十法真正的起点。
/// 其余按由少到多排，最后到 10。
const List<int> kDecompositionTargets = [5, 3, 4, 6, 7, 8, 9, 10];

/// 点在积木上的哪一格 → 从第几格后面切开。
///
/// [localX] 是手指落点相对积木左上角的横向偏移，[cellSize] 是格边长。
///
/// **这个函数永远给得出一个合法的切点**，`clamp` 保证结果落在
/// `[1, total-1]` 内：点在积木最左端也切得出 `1 + (total-1)`，点在最右端
/// 切得出 `(total-1) + 1`。反向分解不存在「没切中」这回事——他点在积木上
/// 的任何位置都必须切出点什么来，否则就是「点了没反应」。
int cutIndexAt(double localX, double cellSize, int total) {
  assert(total >= 2, '只有 2 格以上的积木才切得开');
  if (cellSize <= 0) return 1;
  return (localX / cellSize).round().clamp(1, total - 1);
}

/// 等式槽的候选答案个数。
///
/// 三个：两个太容易蒙对，四个在 90dp 的托盘里排不下（还要给等式条留位置）。
const int kEquationChoices = 3;

/// 生成等式槽的候选答案。
///
/// 正确答案的位置按 [round] 轮换——固定在中间他很快就会靠位置记答案，
/// 那就变成了记位置而不是算加法。
///
/// 干扰项取得**紧贴正确答案**（±1）：差得远的选项一眼就能排除，等于没考。
/// 全部保证为正整数。
List<int> equationChoices(AdditionProblem problem, int round) {
  final sum = problem.sum;
  final distractors = <int>[
    // sum 为 2 时 sum-1=1 仍合法；真正要防的是 sum<=1，那不会出现在题序里。
    if (sum > 1) sum - 1 else sum + 2,
    sum + 1,
  ];

  final slot = round % kEquationChoices;
  final out = <int>[];
  var next = 0;
  for (var i = 0; i < kEquationChoices; i++) {
    out.add(i == slot ? sum : distractors[next++]);
  }
  return out;
}

/// 拼搭台列数。得数最大的那道题也必须一行摆得下。
const int kAdditionColumns = 10;

/// 拼搭台行数。两个加数各占一行还余一行，够他把积木挪来挪去。
const int kAdditionRows = 3;
