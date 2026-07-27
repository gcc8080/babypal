import 'dart:io';

import 'package:baby_pal/core/block/block_board_controller.dart';
import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/core/block/snap_grid.dart';
import 'package:baby_pal/core/content/models.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把一个数拆成积木：tens 个「十条」(10×1) + ones 个单块 (1×1)。
///
/// 这是数字模块位值玩法的核心换算。放在测试里先跑通「内容包 → 加载器 → 积木」
/// 全链路，P2 实现数字模块时再挪进 `lib/modules/numbers/`。
List<BlockBody> blocksFor(NumberItem item) => [
  for (var i = 0; i < item.tens; i++)
    BlockBody(id: '${item.value}-ten-$i', colorIndex: 0, widthUnits: 10),
  for (var i = 0; i < item.ones; i++)
    BlockBody(id: '${item.value}-one-$i', colorIndex: 1),
];

void main() {
  late ContentPack pack;

  setUpAll(() {
    // 直接读真实的 asset 文件——这条链路要验的就是「打包进 App 的那份内容
    // 能不能被解析」，用内联 JSON 就失去意义了。
    final raw = File('assets/packs/numbers.json').readAsStringSync();
    final parsed = const PackLoader().parse(
      raw,
      source: 'assets/packs/numbers.json',
    );
    expect(parsed, isNotNull, reason: '真实内容包必须能被解析');
    pack = parsed!;
  });

  group('真实 numbers.json', () {
    test('0–100 共 101 条，无任何条目被跳过', () {
      expect(pack.numbers, hasLength(101));
      expect(pack.skipped, isEmpty);
      expect(pack.numbers.first.value, 0);
      expect(pack.numbers.last.value, 100);
    });

    test('每条都有中英双语语音键，共 202 个', () {
      expect(pack.allVoiceKeys, hasLength(202));
      expect(pack.allVoiceKeys, contains('zh.number.0'));
      expect(pack.allVoiceKeys, contains('en.number.100'));
    });

    test('值连续无缺漏', () {
      final values = pack.numbers.map((n) => n.value).toList();
      expect(values, List.generate(101, (i) => i));
    });
  });

  group('内容包 → 加载器 → 积木 全链路', () {
    test('23 拆成 2 个十条 + 3 个单块', () {
      final item = ContentLibrary([pack]).numberByValue(23)!;
      final blocks = blocksFor(item);

      expect(blocks.where((b) => b.widthUnits == 10), hasLength(2));
      expect(blocks.where((b) => b.widthUnits == 1), hasLength(3));
      // 总格数应等于数值本身——位值拆解的自洽性。
      expect(blocks.fold<int>(0, (sum, b) => sum + b.cellCount), 23);
    });

    test('100 拆成 10 个十条，正好填满百格板', () {
      final item = ContentLibrary([pack]).numberByValue(100)!;
      final blocks = blocksFor(item);

      expect(blocks, hasLength(10));
      expect(blocks.every((b) => b.widthUnits == 10), isTrue);
      expect(blocks.fold<int>(0, (sum, b) => sum + b.cellCount), 100);
    });

    test('十条能逐行落到 10×10 百格板上并填满', () {
      final item = ContentLibrary([pack]).numberByValue(100)!;
      const grid = SnapGrid(columns: 10, rows: 10, cellSize: 30);
      final controller = BlockBoardController(grid: grid);

      for (final block in blocksFor(item)) {
        controller.addBlock(block);
      }

      // 用点选通道逐行落子——这条通道和拖拽等价，且测试里更好表达。
      for (var row = 0; row < 10; row++) {
        final block = controller.blocks.firstWhere((b) => b.anchor == null);
        controller.tapBlock(block.id);
        final placed = controller.tapPosition(
          grid.footprintCenter(GridCell(0, row), widthUnits: 10),
        );
        expect(placed, isTrue, reason: '第 $row 行应能落子');
      }

      expect(controller.occupiedCells(), hasLength(100), reason: '百格板已填满');
      expect(
        controller.blocks.every((b) => b.anchor != null),
        isTrue,
        reason: '十条全部落位',
      );
    });

    test('0 不产生任何积木', () {
      final item = ContentLibrary([pack]).numberByValue(0)!;
      expect(blocksFor(item), isEmpty);
    });

    test('全部 0–100 的拆解都自洽', () {
      for (final item in pack.numbers) {
        final total = blocksFor(item).fold<int>(0, (s, b) => s + b.cellCount);
        expect(total, item.value, reason: '${item.value} 的拆解格数应等于其数值');
      }
    });
  });
}
