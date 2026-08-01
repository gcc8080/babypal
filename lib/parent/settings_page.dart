import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/tokens.dart';
import '../core/progress/progress_providers.dart';
import '../core/settings/settings_providers.dart';
import '../modules/home/module_id.dart';
import 'parent_shell.dart';

/// 家长设置。
///
/// 见 parent-zone 规格「设置项」：中英模式开关 + 各模块启用开关，
/// **立即生效并持久化**。这里三样东西：双声道、每日上限、模块开关。
class ParentSettingsPage extends ConsumerWidget {
  const ParentSettingsPage({super.key});

  /// 可选的每日上限。
  ///
  /// 给固定几档而不是一个滑块：滑块要精确到分钟，而「今天让他玩多久」
  /// 从来不是一个需要精确到分钟的决定。
  static const List<int> limitMinutes = [10, 15, 20, 30, 45];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStoreProvider);
    final progress = ref.watch(progressStoreProvider);

    // 两个 store 都是 ChangeNotifier，用 ListenableBuilder 而不是把它们塞成
    // riverpod 的状态：改一个开关要立即反映在这一页上，而 `Provider` 不会
    // 因为 `notifyListeners` 重算。
    return ParentShell(
      title: '设置',
      child: ListenableBuilder(
        listenable: Listenable.merge([settings, progress]),
        builder: (context, _) {
          final current = settings.settings;
          return ListView(
            children: [
              const ParentNote('这些设置改完立刻生效，不用重启。'),
              SwitchListTile(
                key: const ValueKey('bilingual'),
                value: current.bilingual,
                onChanged: settings.setBilingual,
                title: const Text('中英双声道'),
                subtitle: const Text('每条内容先念中文再念英文；关掉后只念中文'),
                activeThumbColor: BlockColors.forIndex(4),
              ),
              const Divider(height: 1),
              const ParentNote('每日游玩时长'),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BlockMetrics.gap,
                ),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final minutes in limitMinutes)
                      ChoiceChip(
                        key: ValueKey('limit-$minutes'),
                        label: Text('$minutes 分钟'),
                        selected:
                            progress.dailyLimit == Duration(minutes: minutes),
                        onSelected: (_) => progress.setDailyLimit(
                          Duration(minutes: minutes),
                        ),
                      ),
                  ],
                ),
              ),
              const ParentNote(
                '到点后积木会「困了」，走一段谢幕动画再回到星球地图——'
                '不锁屏，也不会突然黑掉。他还能继续待在 App 里，只是玩法都睡了。',
              ),
              const Divider(height: 1),
              const ParentNote('哪些大陆现在给他玩'),
              for (final module in ModuleId.values)
                SwitchListTile(
                  key: ValueKey('module-${module.name}'),
                  value: current.enabledModules.contains(module),
                  // 最后一块大陆关不掉：全关之后首页是一片空地，
                  // 而他没有办法知道那是爸爸设的。
                  onChanged: settings.canDisable(module)
                      ? (on) => settings.setModuleEnabled(module, on)
                      : null,
                  title: Text(module.label),
                  activeThumbColor: BlockColors.forIndex(module.colorIndex),
                ),
              const ParentNote(
                '关掉只是首页不再显示这块大陆的入口，进度和存档都留着，'
                '打开就还在。',
              ),
            ],
          );
        },
      ),
    );
  }
}
