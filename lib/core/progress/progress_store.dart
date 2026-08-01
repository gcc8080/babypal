import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单个学习条目的练习统计。
///
/// 用于家长看板挑出「练得少」或「错得多」的条目——这是内容推荐的依据，
/// 不是给孩子看的分数。儿童端永远不出现任何计分。
@immutable
class ItemStat {
  const ItemStat({
    this.attempts = 0,
    this.successes = 0,
    this.lastSeenEpochMs = 0,
  });

  final int attempts;
  final int successes;
  final int lastSeenEpochMs;

  /// 正确率。没练过时返回 null 而非 0——「没练过」和「全错」是两回事。
  double? get accuracy => attempts == 0 ? null : successes / attempts;

  ItemStat merge({required bool success, required int nowMs}) => ItemStat(
    attempts: attempts + 1,
    successes: successes + (success ? 1 : 0),
    lastSeenEpochMs: nowMs,
  );

  Map<String, Object?> toJson() => {
    'a': attempts,
    's': successes,
    'l': lastSeenEpochMs,
  };

  static ItemStat fromJson(Object? json) {
    if (json is! Map) return const ItemStat();
    return ItemStat(
      attempts: _asInt(json['a']),
      successes: _asInt(json['s']),
      lastSeenEpochMs: _asInt(json['l']),
    );
  }

  @override
  String toString() => 'ItemStat($successes/$attempts)';
}

/// 一次持久化快照。
@immutable
class ProgressSnapshot {
  const ProgressSnapshot({
    this.dayKey = '',
    this.playedSeconds = 0,
    this.dailyLimitSeconds = _defaultLimitSeconds,
    this.items = const {},
    this.moduleSeconds = const {},
  });

  /// 默认每日上限 15 分钟。
  static const int _defaultLimitSeconds = 15 * 60;

  /// 自然日标识 `yyyy-MM-dd`。跨日时已用额度归零。
  final String dayKey;

  final int playedSeconds;
  final int dailyLimitSeconds;

  /// 条目键（通常是 voiceKey 或条目 id）→ 统计。
  final Map<String, ItemStat> items;

  /// 模块名 → 当日秒数。
  final Map<String, int> moduleSeconds;

  ProgressSnapshot copyWith({
    String? dayKey,
    int? playedSeconds,
    int? dailyLimitSeconds,
    Map<String, ItemStat>? items,
    Map<String, int>? moduleSeconds,
  }) => ProgressSnapshot(
    dayKey: dayKey ?? this.dayKey,
    playedSeconds: playedSeconds ?? this.playedSeconds,
    dailyLimitSeconds: dailyLimitSeconds ?? this.dailyLimitSeconds,
    items: items ?? this.items,
    moduleSeconds: moduleSeconds ?? this.moduleSeconds,
  );

  Map<String, Object?> toJson() => {
    'day': dayKey,
    'played': playedSeconds,
    'limit': dailyLimitSeconds,
    'items': {for (final e in items.entries) e.key: e.value.toJson()},
    'modules': moduleSeconds,
  };

  static ProgressSnapshot fromJson(Object? json) {
    if (json is! Map) return const ProgressSnapshot();
    final rawItems = json['items'];
    final rawModules = json['modules'];
    return ProgressSnapshot(
      dayKey: json['day'] is String ? json['day'] as String : '',
      playedSeconds: _asInt(json['played']),
      dailyLimitSeconds: json['limit'] is int
          ? json['limit'] as int
          : _defaultLimitSeconds,
      items: rawItems is Map
          ? {
              for (final e in rawItems.entries)
                if (e.key is String)
                  e.key as String: ItemStat.fromJson(e.value),
            }
          : const {},
      moduleSeconds: rawModules is Map
          ? {
              for (final e in rawModules.entries)
                if (e.key is String) e.key as String: _asInt(e.value),
            }
          : const {},
    );
  }
}

/// 进度与时长存档。
///
/// 见 design.md D7：时长统计用**墙钟时间戳**，在生命周期切换点累加持久化，
/// 不用 `Timer`。App 切后台时 Timer 会被暂停或杀死，孩子切出去再切回来即可
/// 重置额度，功能形同虚设。
///
/// 存储用 `shared_preferences` + 单个 JSON 字符串（design.md D8）：数据量是
/// 「哪些内容练过几次」量级，引入嵌入式数据库要付 codegen 与 schema 迁移
/// 成本，收益为零。
class ProgressStore extends ChangeNotifier {
  /// [_prefs] 为 null 时是内存版：记得住这一次会话，重启就没了。
  ///
  /// 与 [SettingsStore] 同一条降级路径——`shared_preferences` 打不开时
  /// App 仍然能玩，只是时长与统计不跨启动累积。
  ProgressStore(this._prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const String storageKey = 'baby_pal.progress.v1';

  final SharedPreferences? _prefs;
  final DateTime Function() _clock;

  ProgressSnapshot _snapshot = const ProgressSnapshot();
  ProgressSnapshot get snapshot => _snapshot;

  /// 当前会话的起点（墙钟）。为 null 表示不在前台。
  DateTime? _sessionStart;

  static Future<ProgressStore> open({DateTime Function()? clock}) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } on Exception catch (e) {
      debugPrint('ProgressStore: 存档打不开，降级为内存统计 -> $e');
    }
    final store = ProgressStore(prefs, clock: clock);
    store.load();
    return store;
  }

  void load() {
    final raw = _prefs?.getString(storageKey);
    if (raw == null) {
      _snapshot = ProgressSnapshot(dayKey: _todayKey());
      return;
    }
    try {
      _snapshot = ProgressSnapshot.fromJson(jsonDecode(raw));
    } on FormatException catch (e) {
      // 存档损坏就从零开始——丢进度总好过打不开 App。
      debugPrint('ProgressStore: 存档解析失败，已重置 -> $e');
      _snapshot = ProgressSnapshot(dayKey: _todayKey());
    }
    _rolloverIfNeeded();
  }

  Future<void> _persist() async {
    // 先通知再落盘：家长看板与谢幕判定都盯着这个快照，界面不该等磁盘。
    notifyListeners();
    await _prefs?.setString(storageKey, jsonEncode(_snapshot.toJson()));
  }

  String _todayKey() {
    final now = _clock();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// 跨自然日则清零当日额度与模块时长。条目统计是长期的，不清。
  void _rolloverIfNeeded() {
    final today = _todayKey();
    if (_snapshot.dayKey == today) return;
    _snapshot = _snapshot.copyWith(
      dayKey: today,
      playedSeconds: 0,
      moduleSeconds: const {},
    );
  }

  // ─── 时长 ──────────────────────────────────────────────────────────

  /// App 进入前台。只记起点，不落盘。
  void beginSession() {
    _rolloverIfNeeded();
    _sessionStart ??= _clock();
  }

  /// App 离开前台。用墙钟差值累加并持久化。
  ///
  /// [module] 非空时同时累加到该模块的当日时长。
  Future<void> endSession({String? module}) async {
    final start = _sessionStart;
    _sessionStart = null;
    if (start == null) return;

    final elapsed = _clock().difference(start);
    if (elapsed.isNegative) return; // 系统时间被往回调，忽略这段
    await _accumulate(elapsed, module: module);
  }

  /// 在不结束会话的前提下把已过时间落盘，并重开计时窗口。
  ///
  /// 供长时间连续游玩时定期调用——**计时依据仍是墙钟**，定时器只负责触发
  /// 落盘，不参与计数。这样即使进程被强杀，最多只丢失一个落盘间隔的时长。
  Future<void> flush({String? module}) async {
    final start = _sessionStart;
    if (start == null) return;
    final now = _clock();
    final elapsed = now.difference(start);
    if (elapsed.isNegative) {
      _sessionStart = now;
      return;
    }
    _sessionStart = now;
    await _accumulate(elapsed, module: module);
  }

  Future<void> _accumulate(Duration elapsed, {String? module}) async {
    _rolloverIfNeeded();
    final seconds = elapsed.inSeconds;
    if (seconds <= 0) return;

    final modules = Map<String, int>.from(_snapshot.moduleSeconds);
    if (module != null) {
      modules[module] = (modules[module] ?? 0) + seconds;
    }

    _snapshot = _snapshot.copyWith(
      playedSeconds: _snapshot.playedSeconds + seconds,
      moduleSeconds: modules,
    );
    await _persist();
  }

  /// 当日已玩时长。含当前会话中尚未落盘的部分，供 UI 实时显示。
  Duration get todayPlayed {
    final start = _sessionStart;
    final pending = start == null
        ? Duration.zero
        : _clock().difference(start).isNegative
        ? Duration.zero
        : _clock().difference(start);
    return Duration(seconds: _snapshot.playedSeconds) + pending;
  }

  Duration get dailyLimit => Duration(seconds: _snapshot.dailyLimitSeconds);

  Future<void> setDailyLimit(Duration limit) async {
    _snapshot = _snapshot.copyWith(dailyLimitSeconds: limit.inSeconds);
    await _persist();
  }

  /// 是否已达当日上限。
  ///
  /// 达到上限的表现是积木「困了」+ 温柔谢幕动画，**不是硬锁屏**——
  /// 目标是让孩子接受结束，不是强制中断。
  bool get isLimitReached => todayPlayed >= dailyLimit;

  Duration get remaining {
    final left = dailyLimit - todayPlayed;
    return left.isNegative ? Duration.zero : left;
  }

  // ─── 条目统计 ──────────────────────────────────────────────────────

  Future<void> recordAttempt(String itemKey, {required bool success}) async {
    final nowMs = _clock().millisecondsSinceEpoch;
    final items = Map<String, ItemStat>.from(_snapshot.items);
    items[itemKey] = (items[itemKey] ?? const ItemStat()).merge(
      success: success,
      nowMs: nowMs,
    );
    _snapshot = _snapshot.copyWith(items: items);
    await _persist();
  }

  ItemStat statFor(String itemKey) =>
      _snapshot.items[itemKey] ?? const ItemStat();

  /// 掌握较弱的条目：练过但正确率最低的若干条。
  ///
  /// 只取练过的——没练过的属于「还没教」，不是「没掌握」，混在一起会让家长
  /// 看板变成一份无用的长名单。
  List<String> weakestItems({int limit = 5}) {
    final practiced =
        _snapshot.items.entries.where((e) => e.value.attempts > 0).toList()
          ..sort((a, b) {
            final byAccuracy = a.value.accuracy!.compareTo(b.value.accuracy!);
            if (byAccuracy != 0) return byAccuracy;
            // 正确率相同时，练得少的排前面。
            return a.value.attempts.compareTo(b.value.attempts);
          });
    return practiced.take(limit).map((e) => e.key).toList();
  }

  Future<void> reset() async {
    _snapshot = ProgressSnapshot(dayKey: _todayKey());
    _sessionStart = null;
    await _persist();
  }
}

int _asInt(Object? value) => value is int ? value : 0;
