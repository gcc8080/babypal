import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/modules/hanzi/hanzi.dart';
import 'package:flutter_test/flutter_test.dart';

/// 部件加法的规则——纯逻辑，不用 pump 组件树。
///
/// 这里是整个汉字模块唯一「算」出来的东西：两块碰到一起该变成哪个字。
/// 页面上那些手势全是引擎的，只有这条规则是本模块自己的。
ContentLibrary _library() => ContentLibrary([
  const PackLoader().parse('''
{
  "schemaVersion": 1,
  "hanzi": [
    {"char": "木", "pinyin": "mù", "type": "pictograph", "imageKey": "tree",
     "voiceKey": "zh.hanzi.mu"},
    {"char": "日", "pinyin": "rì", "type": "pictograph", "imageKey": "sun",
     "voiceKey": "zh.hanzi.ri"},
    {"char": "月", "pinyin": "yuè", "type": "pictograph", "imageKey": "moon",
     "voiceKey": "zh.hanzi.yue"},
    {"char": "人", "pinyin": "rén", "type": "pictograph", "imageKey": "person",
     "voiceKey": "zh.hanzi.ren"},
    {"char": "林", "pinyin": "lín", "type": "compound", "parts": ["木", "木"],
     "voiceKey": "zh.hanzi.lin"},
    {"char": "森", "pinyin": "sēn", "type": "compound",
     "parts": ["木", "木", "木"], "voiceKey": "zh.hanzi.sen"},
    {"char": "明", "pinyin": "míng", "type": "compound", "parts": ["日", "月"],
     "voiceKey": "zh.hanzi.ming"},
    {"char": "休", "pinyin": "xiū", "type": "compound", "parts": ["人", "木"],
     "voiceKey": "zh.hanzi.xiu"},
    {"char": "大", "pinyin": "dà", "type": "simple", "voiceKey": "zh.hanzi.da"}
  ],
  "antonyms": [["大", "小"]]
}
''', source: 'hanzi.json')!,
]);

void main() {
  late ContentLibrary library;

  setUp(() => library = _library());

  group('摊成部件', () {
    test('单个部件就是它自己', () {
      expect(componentsOf('木', library), ['木']);
    });

    test('合体字摊成它的部件', () {
      expect(componentsOf('林', library), ['木', '木']);
      expect(componentsOf('明', library), ['日', '月']);
    });

    test('递归摊到底', () {
      expect(componentsOf('森', library), ['木', '木', '木']);
    });

    test('包里没有的字当作它自己，不抛异常', () {
      expect(componentsOf('张', library), ['张']);
    });
  });

  group('合出哪个字', () {
    test('木 + 木 = 林', () {
      expect(compoundFrom(['木', '木'], library)?.char, '林');
    });

    test('顺序无关：人+木 与 木+人 都是休', () {
      // 他把人放到木上、还是把木放到人上，造出来都该是同一个字。
      expect(compoundFrom(['人', '木'], library)?.char, '休');
      expect(compoundFrom(['木', '人'], library)?.char, '休');
    });

    test('数量有关：两个木是林，三个木是森', () {
      // 按多重集比而不是按集合比——去重会让林和森变成同一个东西。
      expect(compoundFrom(['木', '木'], library)?.char, '林');
      expect(compoundFrom(['木', '木', '木'], library)?.char, '森');
    });

    test('已合成的字可以继续合：林 + 木 = 森', () {
      // 这是三部件字唯一可行的玩法：三岁的手凑不齐三块，但能一步一步搭。
      final components = [
        ...componentsOf('林', library),
        ...componentsOf('木', library),
      ];
      expect(compoundFrom(components, library)?.char, '森');
    });

    test('合不出字时返回 null——非法组合没有「错误」这个结果', () {
      expect(compoundFrom(['日', '木'], library), isNull);
      expect(compoundFrom(['木'], library), isNull);
      expect(compoundFrom(['木', '木', '木', '木'], library), isNull);
    });
  });

  group('播报', () {
    test('两个部件：木 加 木 等于 林', () {
      final mu = library.hanziByChar('木')!;
      final lin = library.hanziByChar('林')!;
      expect(HanziNarration.composition([mu, mu], lin), [
        'zh.hanzi.mu',
        'zh.word.plus',
        'zh.hanzi.mu',
        'zh.word.equals',
        'zh.hanzi.lin',
      ]);
    });

    test('三个部件也拼得出，连接词一个不多一个不少', () {
      final mu = library.hanziByChar('木')!;
      final sen = library.hanziByChar('森')!;
      expect(HanziNarration.composition([mu, mu, mu], sen), [
        'zh.hanzi.mu',
        'zh.word.plus',
        'zh.hanzi.mu',
        'zh.word.plus',
        'zh.hanzi.mu',
        'zh.word.equals',
        'zh.hanzi.sen',
      ]);
    });

    test('连接词与加法模块是同一批键——「加」就该是同一个「加」', () {
      final mu = library.hanziByChar('木')!;
      final lin = library.hanziByChar('林')!;
      final spoken = HanziNarration.composition([mu, mu], lin).toSet();
      expect(spoken.intersection(HanziNarration.connectiveKeys), {
        'zh.word.plus',
        'zh.word.equals',
      });
    });

    test('反义词只念两个字，不加解释语', () {
      final da = library.hanziByChar('大')!;
      final mu = library.hanziByChar('木')!;
      expect(HanziNarration.antonym(da, mu), ['zh.hanzi.da', 'zh.hanzi.mu']);
    });
  });

  group('取色', () {
    test('同一个字永远同一个颜色', () {
      expect(hanziColor('木'), hanziColor('木'));
      expect(hanziColorIndex('木'), hanziColorIndex('木'));
    });

    test('不同的字大多不同色——否则一屏全是一个颜色', () {
      final colors = {
        for (final c in ['木', '日', '月', '人', '林', '森']) hanziColor(c),
      };
      expect(colors.length, greaterThanOrEqualTo(4));
    });
  });
}
