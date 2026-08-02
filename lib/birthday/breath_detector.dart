import 'dart:math' as math;
import 'dart:typed_data';

/// 一段 PCM16 单声道数据的均方根能量，归一化到 0..1。
///
/// 用 RMS 而不是峰值：峰值会被一次桌面磕碰、一声咳嗽顶到满量程，而吹气是
/// **一段持续的气流**——它的特征在能量的平均值上，不在最大值上。
double rmsOfPcm16(Uint8List bytes) {
  final samples = bytes.length ~/ 2;
  if (samples == 0) return 0;
  final view = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final s = view.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  return math.sqrt(sum / samples);
}

/// 吹蜡烛的判定。
///
/// 见 birthday 规格「蜡烛吹气检测」：MUST 基于麦克风 PCM 流的 RMS 能量，
/// MUST NOT 写临时音频文件。
///
/// 三条判据，每一条都对应一种会让蜡烛乱灭的现实情况：
///
/// 1. **相对本底**而不是绝对阈值。客厅、饭桌、开着电视的房间，本底能量能差
///    一个数量级。写死一个阈值，安静房间里要用力吹半天，吵房间里说句话
///    蜡烛就全灭了。开头几百毫秒先量一遍本底，之后按倍数判定。
/// 2. **同时要过绝对下限**。全静音房间的本底接近 0，只按倍数的话一声呼吸
///    都能超出十倍。
/// 3. **必须持续**。这是把吹气和「拍一下手、掉个东西、喊一声」分开的关键——
///    冲击声是一个尖峰，吹气是一段平台。规格里「持续低强度噪音不熄灭」和
///    这条是同一件事的两面。
class BreathDetector {
  BreathDetector({
    this.calibrationChunks = 5,
    this.overBaseline = 3.5,
    this.absoluteFloor = 0.13,
    this.sustainChunks = 3,
  });

  /// 开头用多少块来量本底。
  ///
  /// 不能太长：他看见蜡烛就会立刻吹，标定期太长会把他第一口气当成本底，
  /// 之后再也吹不灭。真机上一块是 80ms（16kHz / 2560 字节），
  /// 5 块 = 0.4 秒，刚好够他把嘴凑过去。
  final int calibrationChunks;

  /// 判定为吹气所需的「高出本底多少倍」。
  final double overBaseline;

  /// 绝对能量下限。低于它一律不算，无论本底多安静。
  ///
  /// **这个数是量出来的，不是猜的，而且刻意往高了取。**
  ///
  /// 交付机（MI 8 SE）静置 48 秒实测：中位 0.0024、p99 0.020、最高 0.024，
  /// 三根蜡烛一根没灭。但把手机在房间里放着说话，几分钟内三根会自己灭光
  /// ——说明**人声在近处能持续越过 0.06**，而生日当天旁边一定有人在说话、
  /// 在唱歌。
  ///
  /// 于是取 0.13，约为静置本底最高值的 5 倍。往高了取是因为两种失败不对称：
  ///
  /// - 门限低了 → 蜡烛在他吹之前自己灭光。**那一下没有第二次机会**，
  ///   而这一段的全部意义就是他吹灭的那一刻。
  /// - 门限高了 → 他吹了没反应，8 秒后「点一下」的提示出来，他点掉。
  ///   扫兴，但事情做成了。
  ///
  /// 对着麦克风直吹通常能到 0.2–0.6（常常削顶），0.13 留得出余量。
  /// **这条仍然只有真人吹一次才算验过。**
  final double absoluteFloor;

  /// 连续多少块超标才算真的在吹。3 块 ≈ 240ms。
  final int sustainChunks;

  double _baseline = 0;
  int _calibrated = 0;
  int _streak = 0;

  /// 已经量完本底了吗。
  bool get isCalibrated => _calibrated >= calibrationChunks;

  /// 当前本底能量。
  double get baseline => _baseline;

  /// 当前判定门限。
  double get threshold => math.max(absoluteFloor, _baseline * overBaseline);

  /// 正在吹（连续超标已达 [sustainChunks]）。
  bool get isBlowing => _streak >= sustainChunks;

  /// 喂进一块 PCM16 数据，返回**这一块之后是否处于吹气状态**。
  bool add(Uint8List pcm16) => addEnergy(rmsOfPcm16(pcm16));

  /// 同上，但直接给能量值。测试与自检用——不必伪造一整段 PCM 才能验判据。
  bool addEnergy(double rms) {
    if (!isCalibrated) {
      // 标定期取**最大值**而不是平均：本底要按房间最吵的那一刻算，
      // 否则空调刚好停机的那半秒会把门限压得过低。
      _baseline = math.max(_baseline, rms);
      _calibrated++;
      return false;
    }
    if (rms >= threshold) {
      _streak++;
    } else {
      // 一块不达标就清零，**不做衰减**。断续的「呼、呼、呼」不是吹蜡烛，
      // 而允许它累积就等于允许说话把蜡烛说灭。
      _streak = 0;
    }
    return isBlowing;
  }

  /// 重开一轮（重播彩蛋、或者换了个房间）。
  void reset() {
    _baseline = 0;
    _calibrated = 0;
    _streak = 0;
  }
}
