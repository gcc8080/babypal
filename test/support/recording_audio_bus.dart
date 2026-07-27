import 'dart:io';

import 'package:baby_pal/core/audio/audio_bus.dart';
import 'package:baby_pal/core/audio/voice_resolver.dart';

/// 记录下每一次播报与音效的音频总线。
///
/// 其余页面的测试用的是「静音总线」——真的 [AudioBus]，只是引擎没起来所以
/// 什么都不放。那足以验证「调它不会崩」，但验不了**播了什么**。
///
/// 字母模块必须验后者：规格里两条硬要求全都是关于播报内容的——「字母名与
/// 音素是两次可区分的播报」、「三张图行为一致」。这两条如果只看界面，坏掉的
/// 版本也能全绿。
class RecordingAudioBus extends AudioBus {
  RecordingAudioBus()
    : super(resolver: VoiceResolver(overridesDir: Directory.systemTemp));

  /// 按调用顺序记下的 voiceKey。
  final List<String> spoken = [];

  /// 按调用顺序记下的音效名。
  final List<String> sfx = [];

  @override
  Future<void> speak(
    String voiceKey, {
    VoicePolicy policy = VoicePolicy.queue,
  }) async {
    spoken.add(voiceKey);
    // 刻意不调 super：真实实现要走 soloud 引擎，而测试里它没起来。
    // 这里只需要「记录调用」这一件事。
  }

  @override
  void playSfx(String name, {double volume = 1.0}) => sfx.add(name);
}
