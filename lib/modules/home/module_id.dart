/// 五个内容模块。
///
/// 首页「方块星球」上的五块大陆与之一一对应。
enum ModuleId {
  /// 数字积木：数数、位值、百格板。
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
