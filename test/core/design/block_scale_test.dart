import 'package:baby_pal/core/design/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在指定屏幕尺寸下取出 [BlockScale.of] 的结果。
Future<double> scaleForSize(WidgetTester tester, Size size) async {
  late double captured;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(
        builder: (context) {
          captured = BlockScale.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('BlockScale', () {
    testWidgets('按短边缩放：设计基准尺寸得到 1.0', (tester) async {
      // 横屏下短边即高度。
      final scale = await scaleForSize(tester, const Size(800, kDesignShortSide));
      expect(scale, 1.0);
    });

    testWidgets('平板短边更大 → 放大', (tester) async {
      final scale = await scaleForSize(tester, const Size(1366, 1024));
      expect(scale, greaterThan(1.0));
    });

    testWidgets('小屏手机短边更小 → 缩小（iPhone SE 横屏 568×320）', (tester) async {
      final scale = await scaleForSize(tester, const Size(568, 320));
      expect(scale, lessThan(1.0));
      expect(scale, greaterThan(0.85)); // 未触及下限
    });

    testWidgets('主流手机横屏（844×390）略大于基准', (tester) async {
      final scale = await scaleForSize(tester, const Size(844, 390));
      expect(scale, greaterThan(1.0));
    });

    testWidgets('取短边而非高度，竖持时结论一致', (tester) async {
      final landscape = await scaleForSize(tester, const Size(800, 400));
      final portrait = await scaleForSize(tester, const Size(400, 800));
      expect(landscape, portrait);
    });

    testWidgets('极小屏被下限截断，积木不会小到按不准', (tester) async {
      final scale = await scaleForSize(tester, const Size(400, 200));
      expect(scale, 0.85);
    });

    testWidgets('超大屏被上限截断，一屏仍放得下多块积木', (tester) async {
      final scale = await scaleForSize(tester, const Size(4000, 3000));
      expect(scale, 2.2);
    });
  });

  group('BlockMetrics 的 3 岁交互红线（design.md D3）', () {
    test('抓取目标下限显著大于 Material 的 48dp 成人基准', () {
      expect(BlockMetrics.minGrabTarget, greaterThanOrEqualTo(90.0));
    });

    test('放置区阈值低于抓取阈值——手指只需落在附近', () {
      expect(BlockMetrics.minDropZone, lessThan(BlockMetrics.minGrabTarget));
      expect(BlockMetrics.minDropZone, greaterThanOrEqualTo(60.0));
    });

    test('吸附半径大于目标本身，宁可抢着吸过去', () {
      expect(BlockMetrics.snapToleranceFactor, greaterThan(1.0));
    });

    test('百格板单格在手机横屏下必然小于抓取阈值——故不得作为主动操作对象', () {
      // 手机横屏短边 360dp，扣安全区可用约 320dp，10 行 → 每格 32dp。
      const cellSize = 320.0 / 10;
      expect(cellSize, lessThan(BlockMetrics.minGrabTarget));
    });
  });

  group('BlockColors', () {
    test('forIndex 对任意整数都安全，包括负数与越界', () {
      expect(BlockColors.forIndex(0), BlockColors.palette[0]);
      expect(
        BlockColors.forIndex(BlockColors.palette.length),
        BlockColors.palette[0],
      );
      expect(BlockColors.forIndex(-1), BlockColors.palette[1]);
    });
  });
}
