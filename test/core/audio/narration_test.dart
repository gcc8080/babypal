import 'package:baby_pal/core/audio/narration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('算式播报', () {
    test('「三 加 二 等于 五」', () {
      expect(Narration.addition(3, 2, VoiceLang.zh), [
        'zh.number.3',
        'zh.word.plus',
        'zh.number.2',
        'zh.word.equals',
        'zh.number.5',
      ]);
    });

    test('英文走同一套结构，只换前缀', () {
      expect(Narration.addition(3, 2, VoiceLang.en), [
        'en.number.3',
        'en.word.plus',
        'en.number.2',
        'en.word.equals',
        'en.number.5',
      ]);
    });

    test('出题时不报得数——报了他就没事可做了', () {
      final question = Narration.additionQuestion(3, 2, VoiceLang.zh);
      expect(question, ['zh.number.3', 'zh.word.plus', 'zh.number.2']);
      expect(question, isNot(contains('zh.number.5')));
      expect(question, isNot(contains('zh.word.equals')));
    });

    test('「五 可以分成 二 和 三」', () {
      expect(Narration.decomposition(5, 2, 3, VoiceLang.zh), [
        'zh.number.5',
        'zh.word.isMadeOf',
        'zh.number.2',
        'zh.word.and',
        'zh.number.3',
      ]);
    });
  });

  group('中英双声道', () {
    test('先中文后英文，是同一内容的两遍', () {
      final both = Narration.bilingualAddition(3, 2);
      expect(both, hasLength(10));
      expect(both.take(5), Narration.addition(3, 2, VoiceLang.zh));
      expect(both.skip(5), Narration.addition(3, 2, VoiceLang.en));
    });

    test('数字与分解同样是双声道', () {
      expect(Narration.bilingualNumber(23), ['zh.number.23', 'en.number.23']);
      expect(Narration.bilingualDecomposition(5, 2, 3), hasLength(10));
    });

    test('两个声道用的是同一份内容，不是两套课', () {
      final zh = Narration.addition(7, 3, VoiceLang.zh);
      final en = Narration.addition(7, 3, VoiceLang.en);
      expect(
        zh.map((k) => k.substring(2)),
        en.map((k) => k.substring(2)),
        reason: '去掉语言前缀后应完全一致',
      );
    });
  });

  group('键的构成', () {
    test('数词键覆盖 0–100，与内容包一致', () {
      for (final value in [0, 1, 23, 100]) {
        expect(Narration.number(value, VoiceLang.zh), 'zh.number.$value');
        expect(Narration.number(value, VoiceLang.en), 'en.number.$value');
      }
    });

    test('连接词清单与实际用到的键一致', () {
      final used = <String>{
        ...Narration.bilingualAddition(3, 2),
        ...Narration.bilingualDecomposition(5, 2, 3),
        ...Narration.tenOnesMakeATen,
      }.where((k) => !k.contains('.number.')).toSet();

      expect(
        used.difference(Narration.connectiveKeys),
        isEmpty,
        reason: '用到了未登记的键，CI 的音频齐备校验会漏掉它',
      );
    });

    test('词片拼播——10 以内全部算式只用这几个连接词', () {
      final connectives = <String>{};
      for (var a = 1; a <= 9; a++) {
        for (var b = 1; a + b <= 10; b++) {
          connectives.addAll(
            Narration.bilingualAddition(a, b).where(
              (k) => !k.contains('.number.'),
            ),
          );
        }
      }
      // 45 个算式，连接词只有 4 个（中英各 2）。整句录制要 90 条音频。
      expect(connectives, hasLength(4));
    });
  });
}
