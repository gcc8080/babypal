import 'package:flutter_test/flutter_test.dart';

import '../../tool/fetch_openmoji.dart';

/// OpenMoji 的文件命名规则——它不是一条规则，是两条互相打架的规则。
///
/// 这条用例是被一个真 bug 逼出来的：Z 的第二张卡本来配的是 🧮 算盘，要换成
/// 0️⃣ 键帽零时才发现抓不下来。原因是 [normalizeCodepoint] 无条件剥掉 FE0F，
/// 而键帽的文件名**必须带着它**（`0030-FE0F-20E3.svg`，剥掉是 404）。
///
/// 这个 bug 的隐蔽之处在于它不会报错：抓取工具只是少下一个文件，内容包里的
/// `iconKey` 指向一个不存在的 SVG，`flutter_svg` 加载失败的表现是**一片空白**
/// ——正是托盘缩略图那类「测试全绿、真机什么都没有」的失败模式。挡住它的是
/// 覆盖测试里那条「每个 iconKey 都有对应 SVG 文件」，但等到那里才发现就已经
/// 得回头猜原因了，不如在这里直接说清楚。
void main() {
  group('码点归一化', () {
    test('普通序列剥掉 FE0F：✈️ 2708 FE0F → 2708', () {
      // 变体选择符不进文件名，这是绝大多数图标的规则。
      expect(normalizeCodepoint('2708 FE0F'), '2708');
      expect(normalizeCodepoint('2708-FE0F'), '2708');
      expect(normalizeCodepoint('2708'), '2708');
    });

    test('键帽保留 FE0F：0️⃣ 0030 FE0F 20E3 原样留着', () {
      // 与上一条正好相反。分辨的依据是结尾的 U+20E3 COMBINING ENCLOSING
      // KEYCAP——有它就是键帽。
      expect(normalizeCodepoint('0030-FE0F-20E3'), '0030-FE0F-20E3');
      expect(normalizeCodepoint('0023 fe0f 20e3'), '0023-FE0F-20E3');
    });

    test('分隔符与大小写都归一', () {
      expect(normalizeCodepoint('1f34e'), '1F34E');
      expect(normalizeCodepoint('1F3F4_200D_2620_FE0F'), '1F3F4-200D-2620');
    });

    test('归一化是幂等的——内容包里的 iconKey 直接就是文件名', () {
      // `letters_page.dart` 读的是 `assets/icons/${noun.iconKey}.svg`，
      // 而工具写的是 `assets/icons/${normalizeCodepoint(iconKey)}.svg`。
      // 两者必须相等，否则抓下来的文件和要读的文件不是同一个。
      for (final key in ['2708', '1F34E', '0030-FE0F-20E3', '1FA7B']) {
        expect(normalizeCodepoint(key), key);
      }
    });
  });
}
