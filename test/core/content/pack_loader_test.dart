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
            {
              'value': 7,
              'voiceKey': 'zh.number.7',
              'voiceKeyEn': 'en.number.7',
            },
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
      expect(loader.parse('{ 这不是 json', source: 'broken.json'), isNull);
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
    /// 部件齐不齐是**整个内容库**的问题，不是单个包的问题——所以这一组断言
    /// 全都落在 [ContentLibrary] 上。逐包校验会把「新包引用老包里的部件」
    /// 这种再正常不过的写法误杀，而那正是内容可扩展性的主场景。
    ContentPack packOf(List<Map<String, Object?>> hanzi, String source) =>
        loader.parse(
          pack({'schemaVersion': 1, 'hanzi': hanzi}),
          source: source,
        )!;

    const mu = {
      'char': '木',
      'pinyin': 'mù',
      'type': 'pictograph',
      'voiceKey': 'zh.hanzi.mu',
    };
    const lin = {
      'char': '林',
      'pinyin': 'lín',
      'type': 'compound',
      'parts': ['木', '木'],
      'voiceKey': 'zh.hanzi.lin',
    };
    const ming = {
      'char': '明',
      'pinyin': 'míng',
      'type': 'compound',
      'parts': ['日', '月'],
      'voiceKey': 'zh.hanzi.ming',
    };

    test('部件缺失 → 剔除该合体字，不产生空引用', () {
      final library = ContentLibrary([
        packOf([mu, lin, ming], 'hanzi.json'),
      ]);

      expect(library.hanzi.map((h) => h.char), ['木', '林']);
      expect(library.unresolvedCompounds.single, contains('明'));
      expect(library.unresolvedCompounds.single, contains('日'));
      expect(library.skipped.single, contains('明'));
    });

    test('部件定义在合体字之后也算齐全', () {
      // 「林」在前、「木」在后。一趟扫描会误判为部件缺失。
      final library = ContentLibrary([
        packOf([lin, mu], 'order.json'),
      ]);

      expect(library.hanzi.map((h) => h.char), ['林', '木']);
      expect(library.skipped, isEmpty);
    });

    test('部件来自**另一个包**也算齐全——内容可扩展性靠这条', () {
      // 明年的 hanzi_l2.json 就长这样：只写新字，部件引用老包里的。
      final library = ContentLibrary([
        packOf([mu], 'hanzi.json'),
        packOf([lin], 'hanzi_l2.json'),
      ]);

      expect(library.hanzi.map((h) => h.char), ['木', '林']);
      expect(library.skipped, isEmpty);
    });

    test('单个包自己看是「部件缺失」，也不该在解析阶段就被丢掉', () {
      // 解析阶段留着，合并之后再判——否则第二个包永远等不到第一个包。
      final l2 = packOf([lin], 'hanzi_l2.json');
      expect(l2.hanzi.map((h) => h.char), ['林']);
      expect(l2.skipped, isEmpty);
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
            {
              'value': 1,
              'voiceKey': 'zh.number.1',
              'voiceKeyEn': 'en.number.1',
            },
          ],
          'letters': [
            {
              'letter': 'a',
              'voiceKey': 'en.letter.a',
              'phonemeVoiceKey': 'en.phoneme.a',
              'wordNounIds': ['apple', 'ant'],
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
      expect(result.letters.single.wordNounIds, ['apple', 'ant']);
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

    test('字母按 wordNounIds 取到名词，取不到的静默跳过', () {
      final letters = loader.parse(
        pack({
          'schemaVersion': 1,
          'letters': [
            {
              'letter': 'A',
              'voiceKey': 'en.letter.a',
              // 中间那个 id 在名词包里不存在。
              'wordNounIds': ['apple', 'aardvark', 'ant'],
            },
          ],
        }),
        source: 'letters.json',
      )!;
      final nouns = loader.parse(
        pack({
          'schemaVersion': 1,
          'nouns': [
            {
              'id': 'apple',
              'category': 'fruit',
              'iconKey': '1F34E',
              'text': '苹果',
              'textEn': 'apple',
              'voiceKey': 'zh.noun.apple',
              'voiceKeyEn': 'en.noun.apple',
            },
            {
              'id': 'ant',
              'category': 'animal',
              'iconKey': '1F41C',
              'text': '蚂蚁',
              'voiceKey': 'zh.noun.ant',
            },
          ],
        }),
        source: 'nouns.json',
      )!;

      final library = ContentLibrary([letters, nouns]);
      expect(library.nounById('apple')!.textEn, 'apple');
      expect(library.nounById('aardvark'), isNull);
      expect(library.letterByChar('a')!.letter, 'A');

      // 引用不到的那条被跳过，而不是让整个字母打不开——少一张卡片是可以
      // 接受的降级，模块崩掉不是。
      final words = library.wordsFor(library.letterByChar('A')!);
      expect(words.map((n) => n.id), ['apple', 'ant']);
    });
  });

  group('名词', () {
    test('缺 text 的名词被跳过并记录原因', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'nouns': [
            {
              'id': 'apple',
              'category': 'fruit',
              'iconKey': '1F34E',
              'voiceKey': 'zh.noun.apple',
            },
          ],
        }),
        source: 'n.json',
      );

      // 没有名字的名词既合不出语音，家长录音界面也没法显示在录什么。
      expect(result!.nouns, isEmpty);
      expect(result.skipped.single, contains('n.json[0]'));
    });
  });

  group('拼字目标', () {
    test('字母序列拆成大写单字母，重复字母保留', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'spellingTargets': [
            {'id': 'child', 'letters': 'Emmett', 'voiceKey': 'en.name.child'},
          ],
        }),
        source: 's.json',
      );

      final target = result!.spellingTargets.single;
      // 两个 M、两个 T 必须都在——去重会让拼字关直接错。
      expect(target.letters, ['E', 'M', 'M', 'E', 'T', 'T']);
      expect(result.allVoiceKeys, contains('en.name.child'));
    });

    test('含非字母字符的目标被跳过', () {
      final result = loader.parse(
        pack({
          'schemaVersion': 1,
          'spellingTargets': [
            {'id': 'bad', 'letters': '小明', 'voiceKey': 'zh.name.bad'},
            {'id': 'dash', 'letters': 'A-B', 'voiceKey': 'en.name.dash'},
            {'id': 'ok', 'letters': 'Mama', 'voiceKey': 'en.name.mama'},
          ],
        }),
        source: 's.json',
      );

      // 拼字关是把字母积木一个个摆上去，摆不出的字符留在数据里只会变成
      // 一个永远填不上的空位。
      expect(result!.spellingTargets.map((t) => t.id), ['ok']);
      expect(result.skipped.length, 2);
    });
  });
}
