import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'voice_resolver.dart';

/// 新语音入队时的策略。
enum VoicePolicy {
  /// 排队，等前面的播完。用于「三」「加」「二」这类连续播报。
  queue,

  /// 打断当前并清空队列。用于切换模块。
  interrupt,
}

/// 音频总线。
///
/// 分成两条互不干扰的通道：
///
/// - **音效池**：预加载的短音效，`play()` 同步返回，同一音源可同时播放多个
///   实例。规格要求 1 秒内 10 次点击音效全部播出、不丢不截断——soloud 的
///   多实例播放天然满足，无需自己排队。
/// - **语音队列**：同一时刻只有一条语音，按 [VoicePolicy] 决定排队还是打断。
///
/// 两条通道并行：音效**绝不会**被语音打断（规格明确要求）。
class AudioBus {
  AudioBus({required this.resolver});

  final VoiceResolver resolver;

  SoLoud get _soloud => SoLoud.instance;

  bool _ready = false;
  bool get isReady => _ready;

  final Map<String, AudioSource> _sfx = {};
  final Map<String, AudioSource> _voices = {};

  final Queue<String> _voiceQueue = Queue<String>();
  bool _speaking = false;
  SoundHandle? _currentVoiceHandle;

  /// 初始化播放引擎。
  ///
  /// `lowLatency` 保持默认的 true——这个 App 是音效驱动的，
  /// 「每次触摸必有回应」这条红线对延迟极其敏感。
  Future<void> init() async {
    if (_ready) return;
    try {
      await _soloud.init();
      _ready = true;
    } on Exception catch (e) {
      // 起不来就静默降级：没有声音的 App 仍然能玩，崩溃的不能。
      debugPrint('AudioBus: 音频引擎初始化失败，已降级为静音 -> $e');
      _ready = false;
    }
  }

  // ─── 音效池 ────────────────────────────────────────────────────────

  /// 预加载音效。必须在进入模块前调用——首次加载会有磁盘 IO，
  /// 放到点击那一刻做就晚了。
  Future<void> preloadSfx(Map<String, String> nameToAssetKey) async {
    if (!_ready) return;
    for (final entry in nameToAssetKey.entries) {
      if (_sfx.containsKey(entry.key)) continue;
      try {
        _sfx[entry.key] = await _soloud.loadAsset(entry.value);
      } on Exception catch (e) {
        debugPrint('AudioBus: 音效加载失败 -> ${entry.value} ($e)');
      }
    }
  }

  /// 播放音效。
  ///
  /// 刻意是同步方法：调用方在手指按下的瞬间调它，不能 await。
  /// 未加载的音效静默跳过，绝不抛异常。
  void playSfx(String name, {double volume = 1.0}) {
    if (!_ready) return;
    final source = _sfx[name];
    if (source == null) return;
    try {
      _soloud.play(source, volume: volume);
    } on Exception catch (e) {
      debugPrint('AudioBus: 音效播放失败 -> $name ($e)');
    }
  }

  // ─── 语音队列 ──────────────────────────────────────────────────────

  /// 播报一条语音。
  Future<void> speak(
    String voiceKey, {
    VoicePolicy policy = VoicePolicy.queue,
  }) async {
    if (!_ready) return;

    if (policy == VoicePolicy.interrupt) {
      await stopSpeech();
    }

    _voiceQueue.add(voiceKey);
    if (!_speaking) {
      unawaited(_drainVoiceQueue());
    }
  }

  /// 停止当前语音并清空队列。切换模块时调用。
  Future<void> stopSpeech() async {
    _voiceQueue.clear();
    final handle = _currentVoiceHandle;
    _currentVoiceHandle = null;
    if (handle != null) {
      try {
        await _soloud.stop(handle);
      } on Exception catch (e) {
        debugPrint('AudioBus: 停止语音失败 -> $e');
      }
    }
  }

  Future<void> _drainVoiceQueue() async {
    if (_speaking) return;
    _speaking = true;
    try {
      while (_voiceQueue.isNotEmpty) {
        final key = _voiceQueue.removeFirst();
        await _playVoice(key);
      }
    } finally {
      _speaking = false;
    }
  }

  Future<void> _playVoice(String key) async {
    final source = await _loadVoice(key);
    if (source == null) return;

    try {
      final handle = _soloud.play(source);
      _currentVoiceHandle = handle;

      // 等这条播完再放下一条。用 allInstancesFinished 事件，并以音频长度
      // 作为兜底超时——事件没来也不能让队列永远卡住。
      final length = _soloud.getLength(source);
      final timeout = length + const Duration(milliseconds: 400);
      await source.allInstancesFinished.first.timeout(
        timeout,
        onTimeout: () {},
      );
    } on Exception catch (e) {
      debugPrint('AudioBus: 语音播放失败 -> $key ($e)');
    } finally {
      _currentVoiceHandle = null;
    }
  }

  /// 按覆盖层优先级加载语音。
  ///
  /// 这是**第二层保险**：[VoiceResolver] 只做廉价的文件头校验，真正的解码
  /// 失败在这里捕获，并二次回落到打包资源。见 design.md D5——覆盖文件坏了
  /// 必须回落，绝不能表现为「没声音」。
  Future<AudioSource?> _loadVoice(String key) async {
    final cached = _voices[key];
    if (cached != null) return cached;

    final source = await resolver.resolve(key);

    switch (source) {
      case MissingVoice():
        return null;

      case AssetVoice(assetKey: final assetKey):
        return _loadAssetVoice(key, assetKey);

      case OverrideVoice(path: final path):
        try {
          final loaded = await _soloud.loadFile(path);
          _voices[key] = loaded;
          return loaded;
        } on Exception catch (e) {
          debugPrint('AudioBus: 家长录音解码失败，回落打包资源 -> $key ($e)');
          return _loadAssetVoice(key, resolver.assetKeyFor(key));
        }
    }
  }

  Future<AudioSource?> _loadAssetVoice(String key, String assetKey) async {
    try {
      final loaded = await _soloud.loadAsset(assetKey);
      _voices[key] = loaded;
      return loaded;
    } on Exception catch (e) {
      debugPrint('AudioBus: 语音资源加载失败，静默跳过 -> $assetKey ($e)');
      return null;
    }
  }

  /// 丢弃某条语音的缓存。家长重录后调用，使下次播放重新解析。
  Future<void> invalidateVoice(String key) async {
    final source = _voices.remove(key);
    if (source != null) {
      try {
        await _soloud.disposeSource(source);
      } on Exception catch (_) {
        // 释放失败无所谓，缓存已经摘掉了。
      }
    }
  }

  Future<void> dispose() async {
    await stopSpeech();
    _sfx.clear();
    _voices.clear();
    if (_ready) {
      try {
        await _soloud.disposeAllSources();
      } on Exception catch (e) {
        debugPrint('AudioBus: 释放音源失败 -> $e');
      }
    }
  }
}
