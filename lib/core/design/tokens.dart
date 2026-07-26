import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 设计基准短边（横屏时即屏幕高度，单位为逻辑像素）。见 design.md D3。
///
/// 手机横屏短边约 360–430，平板约 768–1024。所有尺寸按 [BlockScale] 相对此
/// 基准缩放，因此手机与平板共用同一套横屏布局，不需要两套断点。
const double kDesignShortSide = 360.0;

/// 把设计尺寸换算到当前设备的缩放因子。
///
/// 用法：`BlockMetrics.unit * BlockScale.of(context)`
class BlockScale {
  const BlockScale._();

  static double of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final shortSide = math.min(size.width, size.height);
    // 下限 0.85 防止小屏把积木压到手指按不准；
    // 上限 2.2 防止大平板上积木大到一屏放不下几块。
    return (shortSide / kDesignShortSide).clamp(0.85, 2.2);
  }
}

/// 尺寸常量。凡是与「3 岁交互红线」相关的取值都集中在这里，便于统一收紧。
class BlockMetrics {
  const BlockMetrics._();

  /// 单位积木边长（设计尺寸）。所有积木都是它的整数倍。
  static const double unit = 56.0;

  /// 积木圆角。偏大的圆角让方块显得柔软、可抓握。
  static const double blockRadius = 12.0;

  /// 通用间距。
  static const double gap = 16.0;

  /// 【阈值一】可拖拽积木与按钮的下限——手指要「抓住」的东西。见 design.md D3。
  ///
  /// 注意这比 Material 的 48dp 大得多——那是给成人拇指定的。
  static const double minGrabTarget = 90.0;

  /// 【阈值二】放置区（drop zone）下限——手指只需「落在附近」，由引擎吸附到位。
  ///
  /// 拆成两个阈值是因为单一 90dp 与百格板几何冲突：手机横屏可用高度约 320dp，
  /// 10 行 → 每格 32dp，不可能满足 90dp。结论不是「百格板做不了」，而是
  /// **不能要求孩子点中单格**——他拖的是 ≥90dp 的十条或单块，落点是整片棋盘。
  ///
  /// 推论：任何小于 [minGrabTarget] 的元素都不得作为**主动操作对象**。
  static const double minDropZone = 60.0;

  /// 吸附宽容系数：实际吸附半径 = 目标尺寸 × 此系数。
  ///
  /// 幼儿拖不准，宁可「抢着吸过去」也不要让他反复试。
  static const double snapToleranceFactor = 1.5;

  /// 挤压回弹的形变幅度（1.0 = 不形变）。
  static const double squashScale = 0.88;

  /// 单次游戏时长上限。到点后积木「困了」，走温柔谢幕动画，不是硬锁屏。
  static const Duration sessionLimit = Duration(minutes: 15);
}

/// 配色。
///
/// 刻意避开 Numberblocks 的经典配色方案（1 红 / 2 橙 / 3 黄 / 4 绿 / 5 蓝 的
/// 彩虹序列）——教学法可以借鉴，角色形象与配色必须原创。
/// 这里用一组低饱和的宝石色调，并按不同顺序分配。
class BlockColors {
  const BlockColors._();

  /// 星球天空底色。
  static const Color skyBackground = Color(0xFFF4F1EA);

  /// 文字与线条（仅家长端使用；儿童端零文字）。
  static const Color ink = Color(0xFF3A3532);

  /// 积木脸部的眼睛颜色。
  static const Color eye = Color(0xFF2B2724);

  /// 积木调色板。按索引取色，与数值本身无固定绑定关系。
  static const List<Color> palette = [
    Color(0xFF4FB3A9), // 青
    Color(0xFFE8785C), // 珊瑚
    Color(0xFFF2B441), // 琥珀
    Color(0xFF8C6BB1), // 紫罗兰
    Color(0xFF7FBF6A), // 薄荷绿
    Color(0xFFE4779B), // 玫瑰
    Color(0xFF5B9BD5), // 天蓝
    Color(0xFFC5D14E), // 青柠
    Color(0xFFEF9A4E), // 橘
    Color(0xFF9C6B5A), // 李子棕
  ];

  /// 按任意整数稳定取色（负数也安全）。
  static Color forIndex(int index) => palette[index.abs() % palette.length];
}

ThemeData buildBlockPlanetTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: BlockColors.skyBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: BlockColors.palette[0],
      surface: BlockColors.skyBackground,
    ),
  );
}
