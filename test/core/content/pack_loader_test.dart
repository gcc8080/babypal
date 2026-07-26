import 'dart:convert';

import 'package:baby_pal/core/content/models.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:flutter_test/flutter_test.dart';

const loader = PackLoader();

String pack(Map<String, Object?> body) => jsonEncode(body);

void main() {
  group('场景一：版本受支持', () {
    test('schemaVersion 等于当前支持版本 → 正常解析', () {
      final result = loader.parse(
        pack({
          'schemaVersion': PackLoader.supportedSchemaVersion,
          'numbers': [
            {'value': 7, 'voiceKey': 'zh.number.7', 'voiceKeyEn': 'en.number.7'},
          ],
        }),
        source: 'test.json',
      );

      expect(result, isNotNull);
      expect(result!.numbers.single.value, 7);
      expect(result.numbers.single.voiceKeyEn, 'en.number.7');
      expect(result.skipped, isEmpty);
    });

    test('schemaVersion 低于当前支持版本 → 仍然接受（向后兼容）', () {
      final result = loader.parse(
        pack({'schemaVersion': 0, 'numbers': <Object>[]}),
        source: 'old.json',
      );
      expect(result, isNotNull);
      expect(result!.schemaVersion, 0);
    });
  });

  group('场景二：版本过高', () {
    test('schemaVersion 99 → 跳过整包，返回 null', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 99,
          'numbers': [
            {'value': 1, 'voiceKey': 'zh.number.1'},
          ],
        }),
        source: 'future.json',
      );
      expect(result, isNull);
    });
  });

  group('场景三：缺少 schemaVersion', () {
    test('完全没有该字段 → 跳过整包', () {
      final result = loader.parse(
        pack({
          'numbers': [
            {'value': 1, 'voiceKey': 'zh.number.1'},
          ],
        }),
        source: 'no_version.json',
      );
      expect(result, isNull);
    });

    test('字段类型不是整数 → 跳过整包', () {
      final result = loader.parse(
        pack({'schemaVersion': '1'}),
        source: 'string_version.json',
      );
      expect(result, isNull);
    });

    test('JSON 本身非法 → 跳过整包但不抛异常', () {
      expect(
        loader.parse('{ 这不是 json', source: 'broken.json'),
        isNull,
      );
    });

    test('顶层不是对象 → 跳过整包', () {
      expect(loader.parse('[1,2,3]', source: 'array.json'), isNull);
    });
  });

  group('场景四：单条目字段缺失 → 局部降级', () {
    test('缺 voiceKey 的汉字被跳过，同包其余条目正常可用', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'hanzi': [
            {
              'char': '木',
              'pinyin': 'mù',
              'type': 'pictograph',
              'imageKey': 'tree',
              'voiceKey': 'zh.hanzi.mu',
            },
            // 这条缺 voiceKey
            {'char': '日', 'pinyin': 'rì', 'type': 'pictograph'},
            {
              'char': '月',
              'pinyin': 'yuè',
              'type': 'pictograph',
              'voiceKey': 'zh.hanzi.yue',
            },
          ],
        }),
        source: 'hanzi.json',
      );

      expect(result, isNotNull);
      expect(result!.hanzi.map((h) => h.char), ['木', '月']);
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single, contains('hanzi.json[1]'));
    });

    test('type 非法的条目被跳过', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'hanzi': [
            {
              'char': '木',
              'pinyin': 'mù',
              'type': '不存在的类型',
              'voiceKey': 'zh.hanzi.mu',
            },
          ],
        }),
        source: 'h.json',
      );
      expect(result!.hanzi, isEmpty);
      expect(result.skipped, hasLength(1));
    });

    test('compound 但没声明 parts → 跳过（"合体"无从谈起）', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'hanzi': [
            {
              'char': '林',
              'pinyin': 'lín',
              'type': 'compound',
              'voiceKey': 'zh.hanzi.lin',
            },
          ],
        }),
        source: 'h.json',
      );
      expect(result!.hanzi, isEmpty);
    });

    test('条目不是对象 → 跳过该条', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'numbers': [
            'not an object',
            {'value': 3, 'voiceKey': 'zh.number.3'},
          ],
        }),
        source: 'n.json',
      );
      expect(result!.numbers.single.value, 3);
      expect(result.skipped, hasLength(1));
    });
  });

  group('场景五：合体字引用了不存在的部件', () {
    test('部件缺失 → 跳过该合体字，不产生空引用', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'hanzi': [
            {
              'char': '木',
              'pinyin': 'mù',
              'type': 'pictograph',
              'voiceKey': 'zh.hanzi.mu',
            },
            // 林 = 木 + 木，部件齐全
            {
              'char': '林',
              'pinyin': 'lín',
              'type': 'compound',
              'parts': ['木', '木'],
              'voiceKey': 'zh.hanzi.lin',
            },
            // 明 = 日 + 月，但包里没有「日」和「月」
            {
              'char': '明',
              'pinyin': 'míng',
              'type': 'compound',
              'parts': ['日', '月'],
              'voiceKey': 'zh.hanzi.ming',
            },
          ],
        }),
        source: 'hanzi.json',
      );

      expect(result!.hanzi.map((h) => h.char), ['木', '林']);
      expect(result.skipped.single, contains('明'));
      expect(result.skipped.single, contains('日'));
    });

    test('部件定义在合体字之后也算齐全（两趟解析）', () {
      // 「林」在前、「木」在后。一趟扫描会误判为部件缺失。
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'hanzi': [
            {
              'char': '林',
              'pinyin': 'lín',
              'type': 'compound',
              'parts': ['木', '木'],
              'voiceKey': 'zh.hanzi.lin',
            },
            {
              'char': '木',
              'pinyin': 'mù',
              'type': 'pictograph',
              'voiceKey': 'zh.hanzi.mu',
            },
          ],
        }),
        source: 'order.json',
      );

      expect(result!.hanzi.map((h) => h.char), ['林', '木']);
      expect(result.skipped, isEmpty);
    });
  });

  group('反义词', () {
    test('解析反义词对', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'antonyms': [
            ['大', '小'],
            ['多', '少'],
          ],
        }),
        source: 'a.json',
      );
      expect(result!.antonyms, [
        const AntonymPair('大', '小'),
        const AntonymPair('多', '少'),
      ]);
    });

    test('长度不为 2 的组被跳过，其余正常', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'antonyms': [
            ['前', '后'],
            ['左'],
          ],
        }),
        source: 'a.json',
      );
      expect(result!.antonyms, [const AntonymPair('前', '后')]);
      expect(result.skipped, hasLength(1));
    });
  });

  group('位值拆解', () {
    test('23 → 2 个十条 + 3 个单块', () {
      const item = NumberItem(value: 23, voiceKey: 'zh.number.23');
      expect(item.tens, 2);
      expect(item.ones, 3);
    });

    test('100 → 10 个十条 + 0 个单块', () {
      const item = NumberItem(value: 100, voiceKey: 'zh.number.100');
      expect(item.tens, 10);
      expect(item.ones, 0);
    });

    test('7 → 0 个十条 + 7 个单块', () {
      const item = NumberItem(value: 7, voiceKey: 'zh.number.7');
      expect(item.tens, 0);
      expect(item.ones, 7);
    });
  });

  group('语音键枚举（供构建工具离线检出缺失）', () {
    test('汇总全部条目的中英文与音素语音键', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'numbers': [
            {'value': 1, 'voiceKey': 'zh.number.1', 'voiceKeyEn': 'en.number.1'},
          ],
          'letters': [
            {
              'letter': 'a',
              'voiceKey': 'en.letter.a',
              'phonemeVoiceKey': 'en.phoneme.a',
              'wordIconKeys': ['apple', 'ant'],
            },
          ],
        }),
        source: 'v.json',
      );

      expect(result!.allVoiceKeys, {
        'zh.number.1',
        'en.number.1',
        'en.letter.a',
        'en.phoneme.a',
      });
      // 字母统一转成大写，内容包里写小写也不影响。
      expect(result.letters.single.letter, 'A');
      expect(result.letters.single.lowercase, 'a');
      expect(result.letters.single.wordIconKeys, ['apple', 'ant']);
    });
  });

  group('ContentLibrary 合并检索', () {
    test('跨包合并并按值/字检索', () {
      final a = loader.parse(
        pack({
          'schemaVersion': 1,
          'numbers': [
            {'value': 1, 'voiceKey': 'zh.number.1'},
          ],
        }),
        source: 'a.json',
      )!;
      final b = loader.parse(
        pack({
          'schemaVersion': 1,
          'hanzi': [
            {
              'char': '山',
              'pinyin': 'shān',
              'type': 'pictograph',
              'voiceKey': 'zh.hanzi.shan',
            },
          ],
        }),
        source: 'b.json',
      )!;

      final library = ContentLibrary([a, b]);
      expect(library.numberByValue(1)!.voiceKey, 'zh.number.1');
      expect(library.hanziByChar('山')!.pinyin, 'shān');
      expect(library.hanziByChar('水'), isNull);
      expect(library.numberByValue(99), isNull);
    });
  });
}
