import 'package:flutter/material.dart';

import '../../core/block/block_face.dart';
import '../../core/block/block_model.dart';
import '../../core/design/tokens.dart';

/// 一块字母积木。
///
/// **字形占下 66%，脸占上 34%。** 把脸和字母叠在一起试过，结果是两样都看不
/// 清；上下分区之后，脸还是那张熟悉的脸（眨眼、开心时眼睛弯成弧），字母也
/// 还是那个字母。他在数字模块认识的那套「方块是活的」的语汇，走进字母模块
/// 不需要重新学。
///
/// 儿童端零文字这条红线不适用于这里：字母**就是内容本身**，不是界面说明。
class LetterTile extends StatelessWidget {
  const LetterTile({
    super.key,
    required this.letter,
    required this.color,
    this.expression = BlockExpression.idle,
    this.showFace = true,
    this.dimmed = false,
  });

  /// 显示的字形。大写小写都由调用方决定——大小写配对玩法要的正是这个自由度。
  final String letter;
  final Color color;
  final BlockExpression expression;

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
                        letter,
                        style: const TextStyle(
                          color: Colors.white,
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

/// 字母的取色。
///
/// 按字母在表中的位置取，因此 A 永远是同一个颜色——「我的名字第一个字母是
/// 蓝色的那个」是三岁孩子真的会用的记忆抓手。
Color letterColor(String letter) {
  final code = letter.toUpperCase().codeUnitAt(0) - 0x41;
  return BlockColors.forIndex(code);
}
