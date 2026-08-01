import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../modules/home/module_id.dart';

/// 家长可以调的东西。
///
/// **只有两项。** 家长区不是控制面板：每多一个开关，就多一次「我是不是设错了」
/// 的机会，而这个 App 的默认值本来就是为他调好的。真正需要家长做决定的只有
/// 两件事——要不要英文、哪些模块现在给他玩。
@immutable
class AppSettings {
  const AppSettings({
    this.bilingual = true,
    this.enabledModules = const {...ModuleId.values},
  });

  /// 中英双声道。
  ///
  /// 默认开：他已经会说 0–100 的英文和常见名词的英文，双语对他是同一条内容的
  /// 两个声道而不是两套课程。关掉的场合是「今天只想练中文」，或者他刚开始学
  /// 一批新内容、两遍太长坐不住。
  final bool bilingual;

  /// 首页上出现的模块。
  ///
  /// 关掉一个模块只是首页不再显示它的入口——**不删任何进度、不清任何存档**。
  /// 明天打开又能玩，中间那段时间对他而言只是「今天这块大陆没在」。
  final Set<ModuleId> enabledModules;

  /// 首页要显示的模块，**保持枚举顺序**。
  ///
  /// 用集合存、按枚举顺序取：五块大陆的左右位置是他记路的方式，
  /// 关掉又打开之后跑到别的地方去，等于换了一张地图。
  List<ModuleId> get orderedModules => [
    for (final m in ModuleId.values)
      if (enabledModules.contains(m)) m,
  ];

  AppSettings copyWith({bool? bilingual, Set<ModuleId>? enabledModules}) =>
      AppSettings(
        bilingual: bilingual ?? this.bilingual,
        enabledModules: enabledModules ?? this.enabledModules,
      );

  Map<String, Object?> toJson() => {
    'bilingual': bilingual,
    'modules': [for (final m in enabledModules) m.name],
  };

  static AppSettings fromJson(Object? json) {
    if (json is! Map) return const AppSettings();
    final rawModules = json['modules'];
    return AppSettings(
      bilingual: json['bilingual'] is bool ? json['bilingual'] as bool : true,
      enabledModules: rawModules is List
          ? {
              for (final name in rawModules)
                for (final m in ModuleId.values)
                  if (m.name == name) m,
            }
          : const {...ModuleId.values},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.bilingual == bilingual &&
      setEquals(other.enabledModules, enabledModules);

  @override
  int get hashCode => Object.hash(bilingual, Object.hashAllUnordered(enabledModules));

  @override
  String toString() =>
      'AppSettings(bilingual: $bilingual, modules: ${orderedModules.length})';
}

/// 设置的读写与持久化。
///
/// 与 [ProgressStore] 同一套做法：`shared_preferences` 里一个 JSON 字符串。
/// 改完**立即生效**（规格要求），因此这是个 [ChangeNotifier]——落盘是异步的，
/// 但界面不等它。
class SettingsStore extends ChangeNotifier {
  /// [prefs] 为 null 时是内存版：改得动，但重启就回到默认值。
  ///
  /// 这不是「测试专用」的口子，而是一条**真实的降级路径**——`shared_preferences`
  /// 打不开时（磁盘满、存储损坏）App 仍然应该能玩，只是记不住设置。与内容包
  /// 读不到时降级为空库是同一个判断：宁可少一样东西，也不要打不开。
  SettingsStore([this._prefs]) {
    _load();
  }

  static const String storageKey = 'baby_pal.settings.v1';

  final SharedPreferences? _prefs;

  AppSettings _settings = const AppSettings();
  AppSettings get settings => _settings;

  static Future<SettingsStore> open() async {
    try {
      return SettingsStore(await SharedPreferences.getInstance());
    } on Exception catch (e) {
      debugPrint('SettingsStore: 存档打不开，降级为内存设置 -> $e');
      return SettingsStore();
    }
  }

  void _load() {
    final raw = _prefs?.getString(storageKey);
    if (raw == null) return;
    try {
      _settings = AppSettings.fromJson(jsonDecode(raw));
    } on FormatException catch (e) {
      // 设置读不回来就用默认值——**默认值本来就是能玩的那一套**，
      // 比弹一个「配置损坏」有用得多。
      debugPrint('SettingsStore: 解析失败，已用默认设置 -> $e');
    }
  }

  Future<void> _write(AppSettings next) async {
    if (next == _settings) return;
    _settings = next;
    // 先通知再落盘：规格要求设置「立即生效」，界面不该等磁盘。
    notifyListeners();
    await _prefs?.setString(storageKey, jsonEncode(next.toJson()));
  }

  Future<void> setBilingual(bool value) =>
      _write(_settings.copyWith(bilingual: value));

  /// 开关某个模块。
  ///
  /// **最后一个模块关不掉。** 全关之后首页是一片空地，孩子点不到任何东西，
  /// 而他没有办法知道「这是爸爸设的」——那是这个 App 能呈现的最费解的状态。
  Future<void> setModuleEnabled(ModuleId module, bool enabled) {
    final next = {..._settings.enabledModules};
    if (enabled) {
      next.add(module);
    } else {
      if (next.length <= 1) return Future<void>.value();
      next.remove(module);
    }
    return _write(_settings.copyWith(enabledModules: next));
  }

  bool canDisable(ModuleId module) =>
      !_settings.enabledModules.contains(module) ||
      _settings.enabledModules.length > 1;
}
