import 'dart:io';

import 'package:baby_pal/core/content/models.dart';
import 'package:baby_pal/core/content/pack_loader.dart';
import 'package:baby_pal/parent/recordables.dart';
import 'package:flutter_test/flutter_test.dart';

/// 录音清单的顺序**就是这个功能的全部设计**。
///
/// 见 6.6：生日前优先录的是家人称谓、孩子的名字、鼓励语、生日台词。全库有
/// 六百多条可录内容，那四类若不排在最前面，家长打开这一页看到的是一整屏汉字，
/// 而真正决定这份礼物是什么味道的那几条要往下翻很久才找得到。
void main() {
  ContentLibrary realLibrary() {
    const loader = PackLoader();
    final packs = Directory('assets/packs')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => loader.parse(f.readAsStringSync(), source: f.path))
        .whereType<ContentPack>()
        .toList();
    return ContentLibrary(packs);
  }

  test('最前面四节是名字 / 家人称谓 / 鼓励语 / 生日台词', () {
    final groups = recordableGroups(realLibrary());
    expect(
      groups.take(4).map((g) => g.title).toList(),
      ['名字', '家人称谓', '鼓励语', '生日台词'],
    );
  });

  test('这四节加起来是可以一晚上录完的量', () {
    // 6.6 说的是「约 40 条」。真的排到一百条以上，这件事就不会被做完——
    // 而没被做完的覆盖层等于没有覆盖层。
    final groups = recordableGroups(realLibrary());
    final priority = groups.take(4).fold<int>(0, (n, g) => n + g.items.length);
    expect(priority, lessThanOrEqualTo(60), reason: '优先录的条目太多了，录不完');
    expect(priority, greaterThanOrEqualTo(20), reason: '少到不像是「先录这些」');
  });

  test('每条都带「该念什么」，不是只有一个 voiceKey', () {
    // 照着 `zh.noun.waigong` 是录不出话的，而录错一条比没录更糟：
    // 他会听见一个大人用肯定的语气念错。
    for (final group in recordableGroups(realLibrary())) {
      for (final item in group.items) {
        expect(item.hint, isNotEmpty, reason: '${item.voiceKey} 没有提示');
        expect(item.label, isNotEmpty, reason: '${item.voiceKey} 没有名字');
        expect(
          item.hint,
          isNot(contains(item.voiceKey)),
          reason: '${item.voiceKey} 的提示只是把键名抄了一遍',
        );
      }
    }
  });

  test('家人称谓只出现一次，不会让家长以为要录两遍', () {
    final groups = recordableGroups(realLibrary());
    final keys = <String>[];
    for (final group in groups) {
      keys.addAll(group.items.map((i) => i.voiceKey));
    }
    final duplicates = <String>{};
    final seen = <String>{};
    for (final key in keys) {
      if (!seen.add(key)) duplicates.add(key);
    }
    expect(duplicates, isEmpty, reason: '这些键在清单里出现了不止一次：$duplicates');
  });

  test('爸爸妈妈在里面——这是整件事的起点', () {
    final family = recordableGroups(
      realLibrary(),
    ).firstWhere((g) => g.title == '家人称谓');
    final labels = family.items.map((i) => i.label).toList();
    expect(labels, containsAll(['爸爸', '妈妈']));
  });

  test('内容包里的每一句整句都有分组和文本', () {
    final phrases = realLibrary().phrases;
    expect(phrases, isNotEmpty);
    for (final phrase in phrases) {
      expect(phrase.group, isNotEmpty);
      expect(phrase.text, isNotEmpty);
    }
    expect(realLibrary().phrasesIn('praise'), isNotEmpty);
    expect(realLibrary().phrasesIn('birthday'), isNotEmpty);
    expect(realLibrary().phrasesIn('nonexistent'), isEmpty);
  });
}
