import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/block/block_model.dart';

/// 沙盒作品的存档。
///
/// sandbox 规格「作品保留」：离开沙盒进别的模块再回来，拼搭现场必须原样还在。
/// 这条不是便利功能——他花十分钟堆起来的塔，回来发现没了，那是这个 App 能
/// 犯的最伤人的错。
///
/// 只存**落位的**积木：托盘里的货每次进页面都按当前类别重新补，存下来反而
/// 会和货架对不上（明年内容包变了，存档里的字可能已经不在托盘里了）。
///
/// **不存 id。** id 是渲染层的身份（`AnimatedPositioned` 靠它认出「还是那一块」），
/// 不是内容的一部分。存下来再原样读回，就会和这一次开页面时新补的托盘货撞号——
/// 撞了之后 `Stack` 直接抛「Duplicate keys」，整页白屏。读回时由 [load] 现发新号。
///
/// 存 `shared_preferences` 里的一个 JSON 字符串，与 [ProgressStore] 同一个
/// 理由（design.md D8）：数据量是「一台面积木」量级，上数据库是白付 codegen
/// 与迁移的成本。
class SandboxStore {
  const SandboxStore(this._prefs);

  static const String storageKey = 'baby_pal.sandbox.v1';

  /// 还原出来的积木的 id 前缀。与页面发给托盘的号段刻意不同，
  /// 两边永远不可能撞上。
  static const String restoredIdPrefix = 'saved-';

  final SharedPreferences _prefs;

  static Future<SandboxStore> open() async =>
      SandboxStore(await SharedPreferences.getInstance());

  /// 读回上次的现场。存档缺失或损坏时返回空台面——**丢作品也好过打不开**。
  List<BlockBody> load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      var n = 0;
      return [
        for (final entry in decoded) ?_decode(entry, '$restoredIdPrefix${n++}'),
      ];
    } on FormatException catch (e) {
      debugPrint('SandboxStore: 存档解析失败，已按空台面处理 -> $e');
      return const [];
    }
  }

  Future<void> save(List<BlockBody> blocks) async {
    final placed = [
      for (final b in blocks)
        if (b.anchor != null) _encode(b),
    ];
    if (placed.isEmpty) {
      await _prefs.remove(storageKey);
      return;
    }
    await _prefs.setString(storageKey, jsonEncode(placed));
  }

  Future<void> clear() => _prefs.remove(storageKey);

  static Map<String, Object?> _encode(BlockBody block) => {
    'c': block.colorIndex,
    if (block.label != null) 'l': block.label,
    'w': block.widthUnits,
    'h': block.heightUnits,
    'col': block.anchor!.col,
    'row': block.anchor!.row,
  };

  static BlockBody? _decode(Object? entry, String id) {
    if (entry is! Map) return null;
    final col = entry['col'];
    final row = entry['row'];
    if (col is! int || row is! int) return null;
    // 宽高必须为正，否则 BlockBody 的断言会在 release 下被跳过、
    // 留下一块 0 宽的积木——看不见、点不着、还占着格位。
    final w = entry['w'];
    final h = entry['h'];
    return BlockBody(
      id: id,
      colorIndex: entry['c'] is int ? entry['c'] as int : 0,
      label: entry['l'] is String ? entry['l'] as String : null,
      widthUnits: w is int && w > 0 ? w : 1,
      heightUnits: h is int && h > 0 ? h : 1,
      anchor: GridCell(col, row),
    );
  }
}
