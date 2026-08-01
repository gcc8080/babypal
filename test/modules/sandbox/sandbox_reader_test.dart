import 'package:baby_pal/core/block/block_model.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/modules/sandbox/sandbox_reader.dart';
import 'package:flutter_test/flutter_test.dart';

ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "letters": [
    {"letter": "C", "voiceKey": "zh.letter.C"},
    {"letter": "A", "voiceKey": "zh.letter.A"},
    {"letter": "T", "voiceKey": "zh.letter.T"},
    {"letter": "E", "voiceKey": "zh.letter.E"},
    {"letter": "M", "voiceKey": "zh.letter.M"}
  ],
  "nouns": [
    {"id": "cat", "category": "animal", "iconKey": "1F408",
     "text": "猫", "textEn": "cat",
     "voiceKey": "zh.noun.cat", "voiceKeyEn": "en.noun.cat"}
  ],
  "spellingTargets": [
    {"id": "child", "letters": "Emmett", "voiceKey": "en.name.child"}
  ]
}
''', source: 'test.json')!,
]);

/// 摆一行积木：从第 [col] 列起，逐块相邻。null 表示一块没字的纯色块。
List<BlockBody> _row(List<String?> labels, {int col = 0, int row = 0}) => [
  for (var i = 0; i < labels.length; i++)
    BlockBody(
      id: 'b$row-${col + i}',
      colorIndex: 0,
      label: labels[i],
      anchor: GridCell(col + i, row),
    ),
];

void main() {
  late SandboxReader reader;

  setUp(() => reader = SandboxReader(_library()));

  group('算式', () {
    test('7 + 8 = 15 被认出来并双声道播报', () {
      final findings = reader.read(_row(['7', '+', '8', '=', '15']));
      expect(findings, hasLength(1));
      expect(findings.single.speech, [
        'zh.number.7',
        'zh.word.plus',
        'zh.number.8',
        'zh.word.equals',
        'zh.number.15',
        'en.number.7',
        'en.word.plus',
        'en.number.8',
        'en.word.equals',
        'en.number.15',
      ]);
    });

    test('多个加数也认：3 + 2 + 1 = 6', () {
      final findings = reader.read(_row(['3', '+', '2', '+', '1', '=', '6']));
      expect(findings, hasLength(1));
      expect(findings.single.speech.take(8), [
        'zh.number.3',
        'zh.word.plus',
        'zh.number.2',
        'zh.word.plus',
        'zh.number.1',
        'zh.word.equals',
        'zh.number.6',
        'en.number.3',
      ]);
    });

    test('不成立的等式**一声不吭**——那不是错了，是还没成为一条算式', () {
      // 这条是 sandbox 规格「未构成组合时 MUST NOT 提示或催促」的核心：
      // 给 7+8=16 任何反馈（哪怕只是「咦」）都会把沙盒变成一道题。
      expect(reader.read(_row(['7', '+', '8', '=', '16'])), isEmpty);
    });

    test('缺等号、缺加号、等号右边多于一块，都不算算式', () {
      expect(reader.read(_row(['7', '+', '8'])), isEmpty);
      expect(reader.read(_row(['7', '8', '=', '15'])), isEmpty);
      expect(reader.read(_row(['7', '+', '8', '=', '1', '5'])), isEmpty);
    });

    test('等号在最前或最后都不算', () {
      expect(reader.read(_row(['=', '7', '+', '8'])), isEmpty);
      expect(reader.read(_row(['7', '+', '8', '='])), isEmpty);
    });

    test('0 + 0 = 0 也成立——他真的会摆这个', () {
      expect(reader.read(_row(['0', '+', '0', '=', '0'])), hasLength(1));
    });
  });

  group('词', () {
    test('CAT 认出名词，中英各念一遍', () {
      final findings = reader.read(_row(['C', 'A', 'T']));
      expect(findings.single.speech, ['zh.noun.cat', 'en.noun.cat']);
    });

    test('小写摆出来一样认', () {
      expect(reader.read(_row(['c', 'a', 't'])), hasLength(1));
    });

    test('拼字目标优先于名词：EMMETT 念的是他的名字', () {
      final findings = reader.read(_row(['E', 'M', 'M', 'E', 'T', 'T']));
      expect(findings.single.speech, ['en.name.child']);
    });

    test('单个字母不算拼出了词——否则随手放一块就出声', () {
      expect(reader.read(_row(['C'])), isEmpty);
    });

    test('内容库里没有的字母串保持安静', () {
      expect(reader.read(_row(['C', 'T', 'A'])), isEmpty);
    });
  });

  group('分段', () {
    test('中间空一格就断开，两段各自不成立', () {
      final blocks = [
        ..._row(['7', '+']),
        ..._row(['8', '=', '15'], col: 3),
      ];
      expect(reader.read(blocks), isEmpty);
    });

    test('纯色块夹在中间会切断算式——那已经不是一条算式了', () {
      expect(reader.read(_row(['7', '+', null, '8', '=', '15'])), isEmpty);
    });

    test('不同的行各读各的，两条都认', () {
      final blocks = [
        ..._row(['1', '+', '1', '=', '2']),
        ..._row(['C', 'A', 'T'], row: 1),
      ];
      expect(reader.read(blocks), hasLength(2));
    });

    test('托盘里的积木不参与识别——摆出来才算摆出来', () {
      final blocks = [
        for (final label in ['7', '+', '8', '=', '15'])
          BlockBody(id: label, colorIndex: 0, label: label),
      ];
      expect(reader.read(blocks), isEmpty);
    });

    test('宽度大于一格的积木按占位续接', () {
      // 引擎允许长条积木，识别必须按 col + widthUnits 判断相邻，
      // 否则一条 2 格宽的积木后面那块会被当成「隔了一格」。
      final blocks = [
        const BlockBody(
          id: 'wide',
          colorIndex: 0,
          label: '2',
          widthUnits: 2,
          anchor: GridCell(0, 0),
        ),
        const BlockBody(
          id: 'plus',
          colorIndex: 0,
          label: '+',
          anchor: GridCell(2, 0),
        ),
        const BlockBody(
          id: 'two',
          colorIndex: 0,
          label: '2',
          anchor: GridCell(3, 0),
        ),
        const BlockBody(
          id: 'eq',
          colorIndex: 0,
          label: '=',
          anchor: GridCell(4, 0),
        ),
        const BlockBody(
          id: 'four',
          colorIndex: 0,
          label: '4',
          anchor: GridCell(5, 0),
        ),
      ];
      expect(reader.read(blocks), hasLength(1));
    });
  });

  group('签名', () {
    test('内容相同、位置不同 → 同一个签名，只该庆祝一次', () {
      final here = reader.read(_row(['1', '+', '1', '=', '2'])).single;
      final there = reader.read(_row(['1', '+', '1', '=', '2'], row: 3)).single;
      expect(here.signature, there.signature);
    });

    test('不同的算式是不同的签名', () {
      final a = reader.read(_row(['1', '+', '1', '=', '2'])).single;
      final b = reader.read(_row(['2', '+', '2', '=', '4'])).single;
      expect(a.signature, isNot(b.signature));
    });
  });
}
