import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../core/audio/voice_resolver.dart';

/// 录音设备。
///
/// 抽成接口是为了让**录音界面的全部逻辑都能被测到**：权限被拒时入口怎么表现、
/// 录完有没有让音频总线丢缓存、删掉之后是不是真的回落 TTS——这些都是规格里
/// 写死的行为，而它们一条也不需要真的有麦克风才能验。
abstract interface class VoiceRecorderBackend {
  /// 有没有麦克风权限（必要时发起申请）。
  Future<bool> hasPermission();

  /// 开始录到 [path]。
  Future<void> start(String path);

  /// 停止。返回实际写出的文件路径，失败时返回 null。
  Future<String?> stop();

  Future<void> dispose();
}

/// 真机实现：`record` 包 + WAV。
///
/// **必须是 WAV，且必须和打包的 TTS 同规格**（单声道 / 22.05kHz / 16-bit）。
/// 覆盖层的意义是「这条音频换个来源」，两边格式不一致就会出现「爸爸的声音
/// 比别的响一截」或者干脆播不出来——`flutter_soloud` 不支持 AAC/M4A，
/// 而 opus 在 iOS 输出的是 CAF 容器（design.md D4）。
class RecordVoiceRecorder implements VoiceRecorderBackend {
  RecordVoiceRecorder([AudioRecorder? recorder])
    : _recorder = recorder ?? AudioRecorder();

  static const RecordConfig config = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 22050,
    numChannels: 1,
  );

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } on Exception catch (e) {
      // 权限查询本身失败（模拟器、无麦设备）一律当成没有权限：
      // 录音入口禁用，**App 其余部分照常**（规格明确要求）。
      debugPrint('VoiceRecorder: 权限查询失败 -> $e');
      return false;
    }
  }

  @override
  Future<void> start(String path) async {
    await File(path).parent.create(recursive: true);
    await _recorder.start(config, path: path);
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() async => _recorder.dispose();
}

/// 家长录音文件的读写。
///
/// 路径全部问 [VoiceResolver] 要——**覆盖文件放在哪里只能有一处说了算**。
/// 录音写到 A、播放去 B 找，表现就是「录完没生效」，而那正是这个功能唯一
/// 要保证的事。
///
/// **刻意全部同步。** 这里只有「删一个文件」「列一个目录」这种量级的操作，
/// 都发生在应用私有目录里，异步买不到任何东西；而异步要付的代价是整页的
/// 行为在 widget 测试里验不了——`testWidgets` 的假时钟不会推进真实 IO，
/// 一个 `await file.delete()` 就能让测试永远挂在那儿。
class VoiceOverrides {
  const VoiceOverrides(this.resolver);

  final VoiceResolver resolver;

  String pathFor(String voiceKey) => resolver.overridePathFor(voiceKey);

  bool hasOverride(String voiceKey) => File(pathFor(voiceKey)).existsSync();

  /// 当前已录了哪些。
  Set<String> recordedKeys() {
    final dir = resolver.overridesDir;
    if (!dir.existsSync()) return const {};
    const ext = VoiceResolver.audioExtension;
    return {
      for (final entry in dir.listSync())
        if (entry is File && entry.path.endsWith(ext))
          entry.uri.pathSegments.last.replaceRange(
            entry.uri.pathSegments.last.length - ext.length,
            null,
            '',
          ),
    };
  }

  /// 删掉一条覆盖 → 该键**自动回落到打包的 TTS**。
  ///
  /// 回落不需要在这里做任何事：[VoiceResolver.resolve] 每次播放都实时判断
  /// 文件在不在。这正是覆盖层做成「查文件」而不是「查一张表」的好处——
  /// 删除操作不可能忘了同步某张表。
  void delete(String voiceKey) {
    final file = File(pathFor(voiceKey));
    if (file.existsSync()) file.deleteSync();
  }
}
