import 'dart:math' as math;
import 'dart:typed_data';

import 'package:baby_pal/birthday/breath_detector.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一段 PCM16 单声道数据：正弦波，幅度为满量程的 [amplitude]。
Uint8List tone(double amplitude, {int samples = 1600}) {
  final bytes = Uint8List(samples * 2);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    final v = math.sin(i * 0.3) * amplitude * 32767;
    view.setInt16(i * 2, v.round().clamp(-32768, 32767), Endian.little);
  }
  return bytes;
}

void main() {
  group('RMS', () {
    test('全静音是 0', () {
      expect(rmsOfPcm16(Uint8List(3200)), 0);
    });

    test('空数据不崩，返回 0', () {
      expect(rmsOfPcm16(Uint8List(0)), 0);
      expect(rmsOfPcm16(Uint8List(1)), 0); // 半个样本
    });

    test('正弦波的 RMS 约为幅度的 0.707 倍', () {
      expect(rmsOfPcm16(tone(1.0)), closeTo(0.707, 0.02));
      expect(rmsOfPcm16(tone(0.5)), closeTo(0.354, 0.02));
    });

    test('响的比轻的大', () {
      expect(rmsOfPcm16(tone(0.8)), greaterThan(rmsOfPcm16(tone(0.2))));
    });
  });

  group('标定本底', () {
    test('开头几块只用来量本底，不会当成吹气', () {
      // 他看见蜡烛就会立刻吹。若标定期把第一口气当成本底，
      // 门限会被顶得极高，之后再也吹不灭——这条盯的就是那个。
      final d = BreathDetector(calibrationChunks: 3);
      for (var i = 0; i < 3; i++) {
        expect(d.addEnergy(0.9), isFalse, reason: '标定期不该判定为吹气');
      }
      expect(d.isCalibrated, isTrue);
    });

    test('本底取标定期的最大值，不是平均', () {
      // 按平均算的话，空调刚好停机的那半秒会把门限压低，
      // 之后随便一点动静都能吹灭蜡烛。
      final d = BreathDetector(calibrationChunks: 3);
      d..addEnergy(0.02)..addEnergy(0.20)..addEnergy(0.02);
      expect(d.baseline, 0.20);
    });

    test('门限同时受本底倍数与绝对下限约束', () {
      final quiet = BreathDetector(
        calibrationChunks: 1,
        overBaseline: 3.0,
        absoluteFloor: 0.06,
      );
      quiet.addEnergy(0.001); // 极安静的房间
      // 只按倍数的话门限会是 0.003，一声呼吸都能过——绝对下限接管。
      expect(quiet.threshold, 0.06);

      final noisy = BreathDetector(
        calibrationChunks: 1,
        overBaseline: 3.0,
        absoluteFloor: 0.06,
      );
      noisy.addEnergy(0.1); // 开着电视
      expect(noisy.threshold, closeTo(0.3, 1e-9));
    });
  });

  group('判定', () {
    BreathDetector calibrated({int sustain = 3, double floor = 0.06}) {
      final d = BreathDetector(
        calibrationChunks: 1,
        sustainChunks: sustain,
        absoluteFloor: floor,
        overBaseline: 3.0,
      );
      d.addEnergy(0.01); // 安静房间
      return d;
    }

    test('持续超标才算吹气', () {
      final d = calibrated();
      expect(d.addEnergy(0.5), isFalse, reason: '第一块还不算');
      expect(d.addEnergy(0.5), isFalse, reason: '第二块还不算');
      expect(d.addEnergy(0.5), isTrue, reason: '第三块才算');
    });

    test('一次尖峰不算——那是拍手、磕碰、喊一声', () {
      // 规格里「持续低强度噪音不熄灭」与这一条是同一件事的两面：
      // 冲击声是尖峰，吹气是平台。
      final d = calibrated();
      for (var i = 0; i < 10; i++) {
        expect(d.addEnergy(0.9), isFalse);
        expect(d.addEnergy(0.01), isFalse);
      }
      expect(d.isBlowing, isFalse);
    });

    test('断续的「呼、呼、呼」不累积', () {
      final d = calibrated();
      d..addEnergy(0.5)..addEnergy(0.5); // 差一块就到
      d.addEnergy(0.01); // 断了
      expect(d.addEnergy(0.5), isFalse, reason: '断过就得重新数');
      expect(d.addEnergy(0.5), isFalse);
      expect(d.addEnergy(0.5), isTrue);
    });

    test('持续的环境噪音不会吹灭蜡烛', () {
      // 规格场景「环境噪音」：持续低强度噪音但未达阈值 → 蜡烛不熄灭。
      final d = calibrated();
      for (var i = 0; i < 50; i++) {
        expect(d.addEnergy(0.03), isFalse);
      }
    });

    test('吹完停下来就不再是吹气状态', () {
      final d = calibrated();
      d..addEnergy(0.5)..addEnergy(0.5)..addEnergy(0.5);
      expect(d.isBlowing, isTrue);
      d.addEnergy(0.01);
      expect(d.isBlowing, isFalse);
    });

    test('真的喂 PCM 也走得通，不只是喂能量值', () {
      final d = BreathDetector(calibrationChunks: 1, sustainChunks: 2);
      d.add(tone(0.01));
      expect(d.add(tone(0.9)), isFalse);
      expect(d.add(tone(0.9)), isTrue);
    });
  });

  group('重来', () {
    test('reset 之后从头标定', () {
      final d = BreathDetector(calibrationChunks: 2);
      d..addEnergy(0.5)..addEnergy(0.5);
      expect(d.isCalibrated, isTrue);
      d.reset();
      expect(d.isCalibrated, isFalse);
      expect(d.baseline, 0);
      expect(d.isBlowing, isFalse);
    });
  });
}
