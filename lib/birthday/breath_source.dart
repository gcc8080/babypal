import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// 麦克风的 PCM 流。
///
/// 抽成接口的理由与 [VoiceRecorderBackend] 完全相同：吹蜡烛这一段的全部
/// 行为——吹灭、噪音不误触发、没权限时降级为点击——**一条也不需要真的
/// 有麦克风才能验**，而它们全是规格里写死的。
abstract interface class BreathSource {
  /// 有没有麦克风可用（含权限）。
  Future<bool> isAvailable();

  /// 开始出流。每块是一段 PCM16 单声道数据。
  Future<Stream<Uint8List>> start();

  Future<void> stop();

  Future<void> dispose();
}

/// 真机实现：`record` 的 PCM 流。
///
/// **`startStream` 而不是 `start`**（design.md 与 birthday 规格都写死了这条）：
/// 后者要给一个文件路径，于是吹一次蜡烛就在磁盘上留一段孩子房间里的录音。
/// 一个不联网、不收集数据的 App 不该在自己盘上攒这种东西——而且流式还省掉
/// 了「录完再读回来算」的整段延迟，蜡烛才可能跟着气吹立刻灭。
class MicBreathSource implements BreathSource {
  MicBreathSource([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  /// 采样率取低的那一档。
  ///
  /// 判定只用到能量，不用到音色——16 kHz 已经远超需要，再高只是让每一块
  /// 要多算几千个乘法，而这段代码跑在每一帧的路上。
  static const RecordConfig config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: 16000,
    numChannels: 1,
    // 回声消除与降噪都关掉：它们会把持续气流当成噪声压下去，
    // 正好把要测的信号消掉。
    echoCancel: false,
    noiseSuppress: false,
    autoGain: false,
  );

  final AudioRecorder _recorder;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _recorder.hasPermission();
    } on Exception catch (e) {
      // 查不到就当没有：蜡烛改成点着灭，彩蛋照样完整。
      debugPrint('BreathSource: 麦克风不可用 -> $e');
      return false;
    }
  }

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(config);

  @override
  Future<void> stop() async {
    try {
      await _recorder.stop();
    } on Exception catch (e) {
      debugPrint('BreathSource: 停止失败，忽略 -> $e');
    }
  }

  @override
  Future<void> dispose() async => _recorder.dispose();
}
