import 'package:flutter/foundation.dart';

import '../../core/block/block_model.dart';

/// 位值积木的两种规格。
///
/// 这是 Base-10 教具（公共领域教学法）的最小集合：**十条**与**单块**。
/// 刻意不做「百板」——他还没到需要三位数的阶段，多一种规格只会让托盘变复杂。
enum PlacePiece {
  /// 十条：10 个单位格宽的长条，代表 10。
  rod,

  /// 单块：1 个单位格，代表 1。
  unit;

  /// 该积木代表的数值。
  int get value => this == PlacePiece.rod ? 10 : 1;

  /// 占用的格宽。与 [value] 相等**不是巧合**——十条之所以是 10 格宽，
  /// 正是为了让「10 个单块 = 1 个十条」在视觉上不证自明。
  int get widthUnits => value;
}

/// 一个数的标准位值拆解。
///
/// 他已经会数到 100，所以数字模块的台阶不是「数得更远」，而是**理解
/// 23 由 2 个十和 3 个一组成**。这个类就是那个理解的形式化。
@immutable
class PlaceValue {
  const PlaceValue({required this.tens, required this.ones})
    : assert(tens >= 0),
      assert(ones >= 0);

  factory PlaceValue.of(int value) {
    assert(value >= 0, '位值拆解不处理负数');
    return PlaceValue(tens: value ~/ 10, ones: value % 10);
  }

  final int tens;
  final int ones;

  int get value => tens * 10 + ones;

  /// 整十数：只需要十条，一个单块都不要。
  bool get isRound => ones == 0;

  /// 拆成一串积木，十条在前。用于「演示正确答案」时按顺序飞入。
  List<PlacePiece> get pieces => [
    for (var i = 0; i < tens; i++) PlacePiece.rod,
    for (var i = 0; i < ones; i++) PlacePiece.unit,
  ];

  @override
  bool operator ==(Object other) =>
      other is PlaceValue && other.tens == tens && other.ones == ones;

  @override
  int get hashCode => Object.hash(tens, ones);

  @override
  String toString() => 'PlaceValue($tens tens + $ones ones = $value)';
}

/// 孩子当前在工作台上摆出来的表达。
///
/// 与 [PlaceValue] 的区别是**它不一定是标准写法**：13 个单块也是 13，
/// 系统必须接受，然后演示「10 个单块可以换成 1 个十条」。这条区别就是
/// 位值这一课的全部内容。
@immutable
class PlaceValueAttempt {
  const PlaceValueAttempt({this.rods = 0, this.units = 0})
    : assert(rods >= 0),
      assert(units >= 0);

  factory PlaceValueAttempt.fromPieces(Iterable<PlacePiece> pieces) {
    var rods = 0;
    var units = 0;
    for (final piece in pieces) {
      switch (piece) {
        case PlacePiece.rod:
          rods++;
        case PlacePiece.unit:
          units++;
      }
    }
    return PlaceValueAttempt(rods: rods, units: units);
  }

  final int rods;
  final int units;

  int get total => rods * 10 + units;

  bool get isEmpty => rods == 0 && units == 0;

  /// 是否摆对了。**只看总数**——摆放位置、先后顺序、十条与单块的比例
  /// 一律不判。见 numbers-addition 规格「十条与单块可互换」。
  bool matches(int target) => total == target;

  /// 是否已是标准写法（单块少于 10 个）。
  bool get isCanonical => units < 10;

  /// 是否攒够了 10 个单块，可以换成 1 个十条。
  bool get canCompact => units >= 10;

  /// 换一次：10 个单块 → 1 个十条。总数不变。
  PlaceValueAttempt compact() =>
      canCompact ? PlaceValueAttempt(rods: rods + 1, units: units - 10) : this;

  /// 一路换到标准写法。
  PlaceValueAttempt canonical() {
    var result = this;
    while (result.canCompact) {
      result = result.compact();
    }
    return result;
  }

  PlaceValueAttempt add(PlacePiece piece) => switch (piece) {
    PlacePiece.rod => PlaceValueAttempt(rods: rods + 1, units: units),
    PlacePiece.unit => PlaceValueAttempt(rods: rods, units: units + 1),
  };

  PlaceValueAttempt remove(PlacePiece piece) => switch (piece) {
    PlacePiece.rod => PlaceValueAttempt(
      rods: rods > 0 ? rods - 1 : 0,
      units: units,
    ),
    PlacePiece.unit => PlaceValueAttempt(
      rods: rods,
      units: units > 0 ? units - 1 : 0,
    ),
  };

  @override
  bool operator ==(Object other) =>
      other is PlaceValueAttempt && other.rods == rods && other.units == units;

  @override
  int get hashCode => Object.hash(rods, units);

  @override
  String toString() => 'PlaceValueAttempt($rods rods + $units units = $total)';
}

/// 位值练习的题序。
///
/// 刻意写死而不是随机生成：3 岁的注意力窗口很短，头两题必须是他一看就
/// 会的典型两位数（十几、二十几），站稳了再引入整十数。工作台是
/// 10×4 = 40 格，因此上限 40。
const List<int> kPlaceValueTargets = [
  13,
  21,
  25,
  30,
  12,
  34,
  20,
  27,
  16,
  32,
  24,
  40,
];

/// 工作台容量：10 列 × 4 行。[kPlaceValueTargets] 的每一题都必须摆得下。
const int kPlaceValueColumns = 10;
const int kPlaceValueRows = 4;

/// 求下一块积木的自动落点。
///
/// 点选通道用：孩子点一下托盘里的「源」，积木自己飞到合适的位置。这比
/// 引擎默认的「先选中、再点目标位」少一步，且**对落点精度零要求**——
/// 位置本来就不参与判定，没有任何理由让他去瞄准。
///
/// 十条从上往下铺（一条占满一整行），单块从下往上、从左往右填。两者从
/// 两端相向生长，视觉上天然分区，不需要画分隔线去教他规矩。
///
/// 返回 null 表示已经放不下了——调用方**不得**给任何错误提示，静默忽略。
GridCell? nextFreeAnchor({
  required PlacePiece piece,
  required Set<GridCell> occupied,
  int columns = kPlaceValueColumns,
  int rows = kPlaceValueRows,
}) {
  bool free(int col, int row) => !occupied.contains(GridCell(col, row));

  switch (piece) {
    case PlacePiece.rod:
      if (piece.widthUnits > columns) return null;
      for (var row = 0; row < rows; row++) {
        var fits = true;
        for (var col = 0; col < piece.widthUnits; col++) {
          if (!free(col, row)) {
            fits = false;
            break;
          }
        }
        if (fits) return GridCell(0, row);
      }
      return null;

    case PlacePiece.unit:
      for (var row = rows - 1; row >= 0; row--) {
        for (var col = 0; col < columns; col++) {
          if (free(col, row)) return GridCell(col, row);
        }
      }
      return null;
  }
}
