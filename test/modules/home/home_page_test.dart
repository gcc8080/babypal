import 'package:baby_pal/core/design/tokens.dart';
import 'package:baby_pal/modules/home/home_page.dart';
import 'package:baby_pal/modules/home/module_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// MI 8 SE 横屏的实测逻辑尺寸——交付设备，所有布局都要在这个尺寸下成立。
const deliverySize = Size(738, 393);

Finder tile(ModuleId module) => find.byKey(ValueKey(module));

Future<void> pumpHome(
  WidgetTester tester, {
  Size size = deliverySize,
  List<ModuleId> modules = ModuleId.values,
  void Function(ModuleId)? onSelected,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: HomePage(enabledModules: modules, onModuleSelected: onSelected),
    ),
  );
  await tester.pump();
}

void main() {
  group('零文字界面', () {
    testWidgets('模块入口不含任何界面文字', (tester) async {
      await pumpHome(tester);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toSet();

      // 只允许出现「学习内容」本身（字母与汉字）。规格明确：字母与汉字作为
      // 学习内容呈现不受零文字限制，但不得被用作界面指令。
      const allowedAsContent = {'A', '木'};
      expect(
        texts.difference(allowedAsContent),
        isEmpty,
        reason: '首页除内容字形外不得有任何文字：$texts',
      );
    });
  });

  group('触控目标下限', () {
    testWidgets('交付设备上每个入口都不小于抓取阈值 90dp', (tester) async {
      await pumpHome(tester);

      for (final module in ModuleId.values) {
        final size = tester.getSize(tile(module));
        expect(
          size.width,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
          reason: '${module.name} 入口宽 ${size.width} 小于 90dp',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(BlockMetrics.minGrabTarget),
          reason: '${module.name} 入口高 ${size.height} 小于 90dp',
        );
      }
    });

    testWidgets('屏幕极窄时入口不缩到阈值以下，宁可横向滚动', (tester) async {
      await pumpHome(tester, size: const Size(320, 240));

      final size = tester.getSize(tile(ModuleId.numbers));
      expect(size.width, greaterThanOrEqualTo(BlockMetrics.minGrabTarget));
    });
  });

  group('模块入口', () {
    testWidgets('默认显示全部五个模块', (tester) async {
      await pumpHome(tester);
      for (final module in ModuleId.values) {
        expect(tile(module), findsOneWidget);
      }
    });

    testWidgets('家长关闭某模块后首页不再显示其入口', (tester) async {
      await pumpHome(
        tester,
        modules: const [ModuleId.numbers, ModuleId.sandbox],
      );

      expect(tile(ModuleId.numbers), findsOneWidget);
      expect(tile(ModuleId.sandbox), findsOneWidget);
      expect(tile(ModuleId.hanzi), findsNothing);
      expect(tile(ModuleId.letters), findsNothing);
      // 汉字模块被关掉，其字形也不应出现。
      expect(find.text('木'), findsNothing);
    });

    testWidgets('点击各入口回调对应模块', (tester) async {
      final tapped = <ModuleId>[];
      await pumpHome(tester, onSelected: tapped.add);

      await tester.tap(tile(ModuleId.hanzi));
      await tester.pumpAndSettle();
      await tester.tap(tile(ModuleId.sandbox));
      await tester.pumpAndSettle();

      expect(tapped, [ModuleId.hanzi, ModuleId.sandbox]);
    });

    testWidgets('滑动超出阈值不触发进入模块（避免滚动误入）', (tester) async {
      final tapped = <ModuleId>[];
      await pumpHome(tester, onSelected: tapped.add);

      final gesture = await tester.startGesture(
        tester.getCenter(tile(ModuleId.numbers)),
      );
      await gesture.moveBy(const Offset(60, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tapped, isEmpty);
    });
  });

  group('触摸反馈不变量', () {
    testWidgets('按下立刻形变——不等手势竞技场裁决', (tester) async {
      await pumpHome(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(tile(ModuleId.numbers)),
      );
      // 首帧只是让 ticker 对时（此时 value 仍为 0），第二帧才有真实推进。
      await tester.pump();
      // 只推进一帧多一点。若依赖 onTapDown，此时竞技场尚未裁决，不会有形变。
      await tester.pump(const Duration(milliseconds: 32));

      final transforms = tester.widgetList<Transform>(
        find.descendant(
          of: tile(ModuleId.numbers),
          matching: find.byType(Transform),
        ),
      );
      expect(
        transforms.any((t) => t.transform.getMaxScaleOnAxis() != 1.0),
        isTrue,
        reason: '按下必须立刻有可感知的形变，这是「触摸必有回应」红线',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('松手后回弹到原尺寸', (tester) async {
      await pumpHome(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(tile(ModuleId.numbers)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      final transforms = tester.widgetList<Transform>(
        find.descendant(
          of: tile(ModuleId.numbers),
          matching: find.byType(Transform),
        ),
      );
      expect(
        transforms.every(
          (t) => (t.transform.getMaxScaleOnAxis() - 1.0).abs() < 0.001,
        ),
        isTrue,
        reason: '回弹结束后应恢复原尺寸',
      );
    });
  });

  group('配色原创性', () {
    test('模块颜色索引刻意打散，不构成顺序彩虹', () {
      final indices = ModuleId.values.map((m) => m.colorIndex).toList();
      expect(indices.toSet(), hasLength(indices.length), reason: '不重复');
      // 不得是 0,1,2,3,4 这样的顺序序列——避免与受保护作品的
      // 数字—颜色对应关系产生相似（design.md D13）。
      expect(indices, isNot(List.generate(indices.length, (i) => i)));
    });
  });
}
