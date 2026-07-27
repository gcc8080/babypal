// 程序化音效合成工具。
//
// 点击积木那声「啵」不是 TTS 能生成的。与其引入外部音效包（体积 + 许可 +
// 风格不统一），不如像积木的脸一样**程序化合成**——参数可调、零许可问题、
// 风格自洽，而且能和挤压回弹的节奏对上。
//
// 输出与语音同格式：WAV 22.05 kHz / 单声道 / 16-bit（design.md D4）。
//
// 声音设计的两条约束：
//   1. **短**。音效要跟手，不能拖尾——超过 250ms 就跟不上快速连点了。
//   2. **没有负面音**。无挫败红线：连「积木退回原位」也不能听起来像失败，
//      只能是柔和的下行，不能是刺耳或不协和的音程。
//
// 全部音高取自五声音阶，避免任何不协和——快速连点时多个音效会叠在一起，
// 五声音阶保证怎么叠都不难听。
//
// 用法：dart run tool/gen_sfx.dart

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 22050;
const String outDir = 'assets/audio';

/// 五声音阶（C 大调），Hz。
const double c5 = 523.25;
const double d5 = 587.33;
const double e5 = 659.25;
const double g5 = 783.99;
const double a5 = 880.00;
const double c6 = 1046.50;

/// 一个音符片段。
class Tone {
  const Tone({
    required this.startMs,
    required this.durationMs,
    required this.freq,
    this.endFreq,
    this.gain = 1.0,
  });

  final int startMs;
  final int durationMs;
  final double freq;

  /// 非空时在时长内从 [freq] 滑到 [endFreq]。
  final double? endFreq;

  final double gain;
}

/// 音效定义：名字 → 音符序列。
final Map<String, List<Tone>> effects = {
  // 按下积木。极短、微微下滑，像手指按在橡胶上。
  'tap': const [Tone(startMs: 0, durationMs: 70, freq: e5, endFreq: d5)],

  // 拾起积木。比 tap 高一点，提示「它跟着你了」。
  'pickup': const [
    Tone(startMs: 0, durationMs: 60, freq: g5, endFreq: a5, gain: 0.8),
  ],

  // 落位吸附。两声上行，干脆利落，是「到位了」的确认。
  'snap': const [
    Tone(startMs: 0, durationMs: 55, freq: g5),
    Tone(startMs: 45, durationMs: 80, freq: c6),
  ],

  // 合体成功。三音上行琶音，庆祝但不夸张。
  'merge': const [
    Tone(startMs: 0, durationMs: 80, freq: c5),
    Tone(startMs: 65, durationMs: 80, freq: e5),
    Tone(startMs: 130, durationMs: 130, freq: g5),
  ],

  // 分裂。下行两音，与 merge 互为镜像。
  'split': const [
    Tone(startMs: 0, durationMs: 80, freq: g5),
    Tone(startMs: 65, durationMs: 110, freq: c5),
  ],

  // 积木退回原位。**这不是失败音**——柔和的下行小三度，音量压低，
  // 听起来像「它自己回家了」，而不是「你错了」。
  'return': const [
    Tone(startMs: 0, durationMs: 150, freq: d5, endFreq: c5, gain: 0.5),
  ],
};

Future<void> main() async {
  await Directory(outDir).create(recursive: true);

  var total = 0;
  for (final entry in effects.entries) {
    final samples = render(entry.value);
    final file = File('$outDir/sfx.${entry.key}.wav');
    await file.writeAsBytes(wrapAsWav(samples));
    total += file.lengthSync();
    stdout.writeln(
      '  sfx.${entry.key}.wav  '
      '${(samples.length / sampleRate * 1000).round()}ms  '
      '${file.lengthSync()} 字节',
    );
  }

  stdout.writeln('');
  stdout.writeln('生成 ${effects.length} 个音效，共 ${(total / 1024).round()} KB');
}

/// 把一组音符渲染成 PCM 采样。
Int16List render(List<Tone> tones) {
  final endMs = tones
      .map((t) => t.startMs + t.durationMs)
      .reduce((a, b) => a > b ? a : b);
  // 末尾留 20ms 静音，避免播放器截断尾音时产生爆音。
  final totalSamples = ((endMs + 20) * sampleRate / 1000).round();
  final buffer = Float64List(totalSamples);

  for (final tone in tones) {
    final start = (tone.startMs * sampleRate / 1000).round();
    final length = (tone.durationMs * sampleRate / 1000).round();
    var phase = 0.0;

    for (var i = 0; i < length; i++) {
      final index = start + i;
      if (index >= totalSamples) break;

      final progress = i / length;

      // 频率包络：可选的滑音。
      final freq = tone.endFreq == null
          ? tone.freq
          : tone.freq + (tone.endFreq! - tone.freq) * progress;
      phase += 2 * math.pi * freq / sampleRate;

      // 基频 + 二次谐波，让声音暖一点，不像纯正弦那么"电子"。
      final wave = math.sin(phase) + 0.25 * math.sin(phase * 2);

      // 振幅包络：3ms 快速起音（避免爆音）+ 指数衰减。
      const attackMs = 3.0;
      final attackSamples = attackMs * sampleRate / 1000;
      final attack = i < attackSamples ? i / attackSamples : 1.0;
      final decay = math.exp(-4.5 * progress);

      buffer[index] += wave * attack * decay * tone.gain * 0.42;
    }
  }

  // 转 16-bit 并做软削波，防止音符重叠处溢出。
  final samples = Int16List(totalSamples);
  for (var i = 0; i < totalSamples; i++) {
    final clipped = math.max(-1.0, math.min(1.0, buffer[i]));
    samples[i] = (clipped * 32767).round();
  }
  return samples;
}

/// 套上 44 字节的标准 WAV 头。
Uint8List wrapAsWav(Int16List samples) {
  const channels = 1;
  const bitsPerSample = 16;
  final dataBytes = samples.length * 2;
  final bytes = BytesBuilder();

  void ascii(String s) => bytes.add(s.codeUnits);
  void uint32(int v) => bytes.add(
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little),
  );
  void uint16(int v) => bytes.add(
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little),
  );

  ascii('RIFF');
  uint32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  uint32(16); // PCM 子块大小
  uint16(1); // PCM
  uint16(channels);
  uint32(sampleRate);
  uint32(sampleRate * channels * bitsPerSample ~/ 8); // 字节率
  uint16(channels * bitsPerSample ~/ 8); // 块对齐
  uint16(bitsPerSample);
  ascii('data');
  uint32(dataBytes);
  bytes.add(samples.buffer.asUint8List());

  return bytes.toBytes();
}
