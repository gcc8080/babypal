import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/content/content_providers.dart';
import '../core/content/pack_loader.dart';
import '../core/progress/progress_providers.dart';
import '../core/progress/progress_store.dart';
import '../modules/home/module_id.dart';
import 'parent_shell.dart';

/// 学习看板。
///
/// 见 parent-zone 规格「学习看板」：今日玩了什么 + 哪些内容还生疏，
/// **只用本机存档，零网络请求**——这个 App 里根本没有任何联网代码，
/// 这条与其说是要求，不如说是这一页天然的样子。
///
/// 刻意**不做趋势图、不做连续天数、不做成就**。那些东西会把一个三岁孩子的
/// 玩耍变成一份需要维持的指标，而看板的用处只有一个：明天陪他玩的时候，
/// 知道该多带他玩哪几个。
class ParentDashboardPage extends ConsumerWidget {
  const ParentDashboardPage({super.key});

  /// 「还生疏」最多列这么多条。
  ///
  /// 列长了就没人看了，而这一页的全部价值是「明天先带他玩这几个」。
  static const int weakestCount = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressStoreProvider);
    final library = ref.watch(contentLibraryProvider);

    return ParentShell(
      title: '今天玩了什么',
      child: ListenableBuilder(
        listenable: progress,
        builder: (context, _) {
          final snapshot = progress.snapshot;
          final weakest = progress.weakestItems(limit: weakestCount);

          return ListView(
            children: [
              ParentTile(
                icon: Icons.schedule_rounded,
                title: '今日已玩 ${_minutes(progress.todayPlayed)}',
                subtitle:
                    '上限 ${_minutes(progress.dailyLimit)}，'
                    '还剩 ${_minutes(progress.remaining)}',
              ),
              const Divider(height: 1),
              const ParentNote('各块大陆'),
              if (snapshot.moduleSeconds.isEmpty)
                const ParentNote('今天还没开始玩。')
              else
                for (final entry in _byTime(snapshot.moduleSeconds))
                  ParentTile(
                    key: ValueKey('module-time-${entry.key}'),
                    icon: Icons.square_rounded,
                    title: _moduleLabel(entry.key),
                    subtitle: _minutes(Duration(seconds: entry.value)),
                  ),
              const Divider(height: 1),
              const ParentNote('还生疏的（练过、但对得少）'),
              if (weakest.isEmpty)
                const ParentNote(
                  '还没有练得不好的内容。没练过的不会出现在这里——'
                  '「还没教」和「没掌握」是两回事。',
                )
              else
                for (final key in weakest)
                  ParentTile(
                    key: ValueKey('weak-$key'),
                    icon: Icons.refresh_rounded,
                    title: _describe(key, library),
                    subtitle: _accuracy(progress.statFor(key)),
                  ),
              const ParentNote('以上全部来自这台设备上的存档。这个 App 不联网，也不上传任何东西。'),
            ],
          );
        },
      ),
    );
  }

  static List<MapEntry<String, int>> _byTime(Map<String, int> modules) =>
      modules.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  static String _moduleLabel(String name) {
    for (final module in ModuleId.values) {
      if (module.name == name) return module.label;
    }
    return name;
  }

  static String _minutes(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} 秒';
    return '${d.inMinutes} 分钟';
  }

  static String _accuracy(ItemStat stat) {
    final accuracy = stat.accuracy;
    if (accuracy == null) return '还没练过';
    return '对 ${stat.successes} / 共 ${stat.attempts}';
  }

  /// 把 voiceKey 翻译成家长看得懂的东西。
  ///
  /// 存档里存的是 `zh.hanzi.6797` 这类键——那是给音频文件用的名字，不是给人
  /// 读的。翻不出来时**原样显示**而不是藏起来：一条看不懂的键至少还能对着
  /// 查，藏起来就等于这条练习从没发生过。
  static String _describe(String key, ContentLibrary library) {
    for (final item in library.hanzi) {
      if (item.voiceKey == key) return '${item.char}（${item.pinyin}）';
    }
    for (final item in library.letters) {
      if (item.voiceKey == key || item.phonemeVoiceKey == key) {
        return '字母 ${item.letter}';
      }
    }
    for (final item in library.nouns) {
      if (item.voiceKey == key || item.voiceKeyEn == key) {
        return '${item.text}${item.textEn == null ? '' : ' / ${item.textEn}'}';
      }
    }
    for (final item in library.numbers) {
      if (item.voiceKey == key || item.voiceKeyEn == key) {
        return '数字 ${item.value}';
      }
    }
    return key;
  }
}
