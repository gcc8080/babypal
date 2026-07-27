import 'package:flutter/material.dart';

import '../block/block_face.dart';
import '../block/block_model.dart';

/// 一块写着字的积木。
///
/// **字形占下 66%，脸占上 34%。** 把脸和字叠在一起试过，结果是两样都看不
/// 清；上下分区之后，脸还是那张熟悉的脸（眨眼、开心时眼睛弯成弧），字也
/// 还是那个字。他在数字模块认识的那套「方块是活的」的语汇，走进字母、汉字
/// 模块都不需要重新学。
///
/// 放在 `core/design/` 而不是某个模块里：字母积木和汉字积木**是同一个东西**，
/// 只是写的字不一样。它原本叫 `LetterTile` 住在 letters 模块，汉字模块要用时
/// 只有三条路——跨模块 import、复制一份、或者搬到公共层。前两条一条比一条
/// 糟，而它本来就不含任何字母专有的东西（取色是模块自己的事，见
/// `letterColor` 与 `hanziColor`）。
///
/// 儿童端零文字这条红线不适用于这里：这里的字**就是内容本身**，不是界面说明。
class GlyphTile extends StatelessWidget {
  const GlyphTile({
    super.key,
    required this.glyph,
    required this.color,
    this.expression = BlockExpression.idle,
    this.showFace = true,
    this.dimmed = false,
    this.glyphColor,
  });

  /// 显示的字形。字母的大小写、汉字写哪个字，都由调用方决定——
  /// 大小写配对玩法要的正是这个自由度。
  final String glyph;
  final Color color;
  final BlockExpression expression;

  /// 字形的颜色，默认白色。
  ///
  /// 拼名字的空槽要用它：影子槽的底色本来就淡，再用白字画上去就几乎看不见，
  /// 而那个字形正是「这一格要哪个字母」的全部提示——真机上一眼就发现读不出来。
  final Color? glyphColor;

  /// 关掉脸：轮廓填充里的小方块太小了，画上脸只会变成一团墨点。
  final bool showFace;

  /// 变暗。用于「已经完成、暂时不用管它」的状态，**不是错误标记**。
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return Opacity(
          opacity: dimmed ? 0.45 : 1.0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(side * 0.18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: side * 0.06,
                  offset: Offset(0, side * 0.03),
                ),
              ],
            ),
            child: Column(
              // **必须 stretch**：`BlockFace` 里是一个无子节点的 `CustomPaint`，
              // 默认尺寸是 `Size.zero`。`Column` 默认的 `center` 交叉轴对齐给的
              // 是松约束，于是宽度被约束成 0——高度被 `Expanded` 撑满，看上去
              // 一切正常，只是脸什么都没画出来。真机上就是一块没有五官的方块。
              //
              // 与托盘缩略图那次（`PieceGlyph`）是同一个坑。凡是「无子节点的
              // 绘制型组件放进 Flex」，交叉轴就必须给紧约束。
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showFace)
                  Expanded(
                    flex: 34,
                    child: BlockFace(
                      expression: expression,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                Expanded(
                  flex: showFace ? 66 : 100,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: side * 0.12,
                      right: side * 0.12,
                      bottom: side * 0.06,
                    ),
                    child: FittedBox(
                      child: Text(
                        glyph,
                        style: TextStyle(
                          color: glyphColor ?? Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
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
