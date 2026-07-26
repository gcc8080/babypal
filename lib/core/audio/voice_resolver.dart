import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 一条语音的来源。
sealed class VoiceSource {
  const VoiceSource(this.key);
  final String key;
}

/// 家长录制的覆盖文件，位于应用文档目录。
class OverrideVoice extends VoiceSource {
  const OverrideVoice(super.key, this.path);
  final String path;

  @override
  String toString() => 'OverrideVoice($key -> $path)';
}

/// 打包进 App 的 TTS 打底资源。
class AssetVoice extends VoiceSource {
  const AssetVoice(super.key, this.assetKey);
  final String assetKey;

  @override
  String toString() => 'AssetVoice($key -> $assetKey)';
}

/// 两处都没有。调用方应静默跳过并记录，**绝不能崩溃**。
class MissingVoice extends VoiceSource {
  const MissingVoice(super.key);

  @override
  String toString() => 'MissingVoice($key)';
}

/// 语音覆盖层解析器。
///
/// 见 design.md D5：覆盖层把「录音」从发布流程里彻底解耦——TTS 保证功能完整，
/// 真人语音录一条替换一条，**永远不需要重新打包**。
///
/// 刻意把文档目录作为构造参数而非内部调用 `path_provider`：这样三种优先级
/// 场景（有覆盖 / 无覆盖 / 覆盖损坏）都能用临时目录做纯逻辑单测。
class VoiceResolver {
  VoiceResolver({
    required this.overridesDir,
    this.availableAssetKeys,
  });

  /// 音频扩展名。**全链路唯一常量**——见 design.md D4：日后若要压体积改用
  /// OGG，只需改这一处加一步离线转码，不动任何调用方。
  static const String audioExtension = '.wav';

  /// 家长录音的存放目录名（位于应用文档目录下）。
  static const String overridesFolderName = 'voice_overrides';

  /// 打包资源的前缀。
  static const String assetPrefix = 'assets/audio/';

  /// WAV 文件的最小合法长度：44 字节的 RIFF 头。
  static const int _minimumWavBytes = 44;

  /// 家长录音所在目录。
  final Directory overridesDir;

  /// 打包资源清单。为 null 时不做存在性校验（一律认为资源存在）。
  ///
  /// 由 `tool/gen_audio.dart` 产出，使「内容包引用了某个 voiceKey 但音频没生成」
  /// 这类问题可以离线检出，而不是等孩子点下去才发现没声音。
  final Set<String>? availableAssetKeys;

  /// 生产环境入口：文档目录由 `path_provider` 提供。
  static Future<VoiceResolver> forApp({
    Set<String>? availableAssetKeys,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$overridesFolderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return VoiceResolver(
      overridesDir: dir,
      availableAssetKeys: availableAssetKeys,
    );
  }

  /// 某个语音键对应的覆盖文件路径（无论是否存在）。
  ///
  /// 家长端录音时用它决定写到哪里——写完**立即生效**，因为解析是每次播放
  /// 时实时进行的，不做缓存。
  String overridePathFor(String key) =>
      '${overridesDir.path}/$key$audioExtension';

  String assetKeyFor(String key) => '$assetPrefix$key$audioExtension';

  /// 按固定优先级解析：家长录音 → 打包资源 → 缺失。
  ///
  /// 覆盖文件存在但**损坏**时必须回落到打包资源，而不是表现为「没声音」——
  /// 静默是 3 岁用户无法理解的失败模式（design.md D5）。
  Future<VoiceSource> resolve(String key) async {
    final overridePath = overridePathFor(key);
    if (await _isUsableOverride(overridePath)) {
      return OverrideVoice(key, overridePath);
    }

    final assetKey = assetKeyFor(key);
    final manifest = availableAssetKeys;
    if (manifest != null && !manifest.contains(key)) {
      // 两处都没有。记录但不抛——缺一条语音不该让整个模块崩掉。
      debugPrint('VoiceResolver: 语音资源缺失，已静默跳过 -> $key');
      return MissingVoice(key);
    }
    return AssetVoice(key, assetKey);
  }

  /// 覆盖文件是否可用。
  ///
  /// 这里只做**廉价的**完整性校验（存在、非空、RIFF/WAVE 头正确）。
  /// 真正的解码失败由音频总线在播放时捕获并二次回落，两层保险。
  Future<bool> _isUsableOverride(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;

      final length = await file.length();
      if (length < _minimumWavBytes) return false;

      final header = await _readHead(file, 12);
      if (header.length < 12) return false;

      // "RIFF" .... "WAVE"
      final isRiff = header[0] == 0x52 &&
          header[1] == 0x49 &&
          header[2] == 0x46 &&
          header[3] == 0x46;
      final isWave = header[8] == 0x57 &&
          header[9] == 0x41 &&
          header[10] == 0x56 &&
          header[11] == 0x45;
      return isRiff && isWave;
    } on FileSystemException catch (e) {
      // 权限问题、文件被删掉了等等——一律当作不可用并回落。
      debugPrint('VoiceResolver: 覆盖文件读取失败，回落打包资源 -> $path ($e)');
      return false;
    }
  }

  Future<Uint8List> _readHead(File file, int byteCount) async {
    final handle = await file.open();
    try {
      return await handle.read(byteCount);
    } finally {
      await handle.close();
    }
  }
}
