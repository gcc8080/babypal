/// 五个内容模块。
///
/// 首页「方块星球」上的五块大陆与之一一对应。
enum ModuleId {
  /// 数字：数数、位值、百格板。
  numbers,

  /// 加法积木：合体、分解、等式槽。
  addition,

  /// 字母积木：A is for Apple、轮廓填充、大小写配对。
  letters,

  /// 汉字积木：象形动画、部件加法、反义词跷跷板。
  hanzi,

  /// 自由沙盒：无关卡、无对错。
  ///
  /// 决定这个 App 能玩两周还是两年的模块。
  sandbox;

  /// 模块名。**只在家长区出现**。
  ///
  /// 儿童端零文字，那边靠颜色、徽记与位置认路；这个名字是给看板和模块开关用的
  /// ——家长总得知道自己关掉的是哪一块。放在这里而不是家长区，是因为看板和
  /// 设置页都要用，两处各写一份迟早会对不上。
  ///
  /// **叫「大陆」不叫「积木」是有原因的。** 第一版写的是「数字积木」，而那
  /// 正好是受保护作品的中文译名（见 design.md D13 与 8.8 自查）——虽然只出现
  /// 在家长区、也只是描述性的，但它确实是一条会显示给人看的字符串，
  /// 没有任何理由踩在那四个字上。改成星球地图本来就在用的说法。
  String get label => switch (this) {
    ModuleId.numbers => '数字大陆',
    ModuleId.addition => '加法大陆',
    ModuleId.letters => '字母大陆',
    ModuleId.hanzi => '汉字大陆',
    ModuleId.sandbox => '自由沙盒',
  };

  /// 该模块在调色板中的颜色索引。
  ///
  /// 刻意打散而非按枚举顺序 0/1/2/3/4——避免与受保护作品的
  /// 数字—颜色对应关系产生任何相似（见 design.md D13）。
  int get colorIndex => switch (this) {
    ModuleId.numbers => 6,
    ModuleId.addition => 2,
    ModuleId.letters => 0,
    ModuleId.hanzi => 4,
    ModuleId.sandbox => 8,
  };
}
