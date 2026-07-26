/// 音效名与资源路径。
///
/// 由 `tool/gen_sfx.dart` 程序化合成，全部取自五声音阶——快速连点时多个音效
/// 会叠在一起，五声音阶保证怎么叠都不难听。
class Sfx {
  const Sfx._();

  /// 按下积木。
  static const String tap = 'tap';

  /// 拾起积木（拖拽开始）。
  static const String pickup = 'pickup';

  /// 落位吸附成功。
  static const String snap = 'snap';

  /// 合体。
  static const String merge = 'merge';

  /// 分裂。
  static const String split = 'split';

  /// 退回原位。
  ///
  /// **不是失败音**：柔和下行、音量压低，听起来像「它自己回家了」，
  /// 而不是「你错了」。无挫败红线在音效层的体现。
  static const String returned = 'return';

  static const Map<String, String> assets = {
    tap: 'assets/audio/sfx.tap.wav',
    pickup: 'assets/audio/sfx.pickup.wav',
    snap: 'assets/audio/sfx.snap.wav',
    merge: 'assets/audio/sfx.merge.wav',
    split: 'assets/audio/sfx.split.wav',
    returned: 'assets/audio/sfx.return.wav',
  };
}
