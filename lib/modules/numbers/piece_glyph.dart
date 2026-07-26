import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import 'place_value.dart';

/// 十条与单块的取色。
///
/// 刻意固定而非按数值轮换——「十条永远是这个颜色」本身就是一条要被记住的
/// 信息。位值工作台与百格板共用，两个玩法之间不需要重新学配色。
class PieceColors {
  const PieceColors._();

  static const int rodIndex = 6; // 天蓝
  static const int unitIndex = 2; // 琥珀

  static int indexOf(PlacePiece piece) =>
      piece == PlacePiece.rod ? rodIndex : unitIndex;

  static Color of(PlacePiece piece) => BlockColors.forIndex(indexOf(piece));
}

/// 托盘「源」里那块积木的缩略图。
///
/// 十条画成 10 个连着的小格而不是一根光溜的长条——那 10 道分隔线正是
/// 「一条等于十块」这句话的全部证据，不能省。
class PieceGlyph extends StatelessWidget {
  const PieceGlyph({super.key, required this.piece});

  final PlacePiece piece;

  @override
  Widget build(BuildContext context) {
    final color = PieceColors.of(piece);

    return LayoutBuilder(
      builder: (context, constraints) {
        final segments = piece.widthUnits;
        final segment = math.min(
          constraints.maxWidth / segments,
          constraints.maxHeight,
        );
        return Center(
          child: SizedBox(
            width: segment * segments,
            height: segment,
            child: Row(
              // **必须 stretch**：`DecoratedBox` 没有子节点，在 `Row` 默认的
              // `center` 对齐下拿到的是松约束，于是取 `constraints.smallest`
              // ——高度 0，整个缩略图什么都画不出来，托盘看上去就是两个空白
              // 方块。真机验收才发现，组件测试只量了外层瓦片的尺寸。
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < segments; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: segments > 1 ? segment * 0.04 : 0,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(segment * 0.22),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
