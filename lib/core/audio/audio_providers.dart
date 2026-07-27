import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_bus.dart';
import 'sfx.dart';
import 'voice_resolver.dart';

/// 全局音频总线。
///
/// 在 `main()` 中构造并 override——初始化涉及原生引擎与资源预加载，都是异步的，
/// 放到 provider 里惰性创建会让第一次点击等在磁盘 IO 上，而「触摸必有回应」
/// 这条红线对延迟极其敏感。
final audioBusProvider = Provider<AudioBus>(
  (ref) => throw UnimplementedError(
    'audioBusProvider 必须在 main() 中通过 overrideWithValue 提供',
  ),
);

/// 构造并初始化音频总线。失败时返回一个静音但可用的实例，绝不抛异常——
/// 没有声音的 App 仍然能玩，起不来的不能。
Future<AudioBus> createAudioBus() async {
  final manifestKeys = await _loadManifestKeys();
  final resolver = await VoiceResolver.forApp(availableAssetKeys: manifestKeys);
  final bus = AudioBus(resolver: resolver);
  await bus.init();
  await bus.preloadSfx(Sfx.assets);
  return bus;
}

/// 读取 `gen_audio.dart` 产出的清单，供 [VoiceResolver] 做缺失检出。
Future<Set<String>?> _loadManifestKeys() async {
  try {
    final raw = await rootBundle.loadString('assets/audio/manifest.json');
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final keys = json['keys'];
    if (keys is! List) return null;
    return keys.whereType<String>().toSet();
  } on Exception catch (e) {
    // 清单缺失不是致命问题：没有它只是失去「离线检出缺失语音」的能力，
    // 解析仍会正常回落到 assets。
    debugPrint('audio: manifest 读取失败，跳过缺失检出 -> $e');
    return null;
  }
}
