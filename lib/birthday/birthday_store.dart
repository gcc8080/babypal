import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 生日彩蛋放过没有。
///
/// 单独一个存档而不是塞进 [AppSettings]：那里装的是**家长的选择**（要不要
/// 英文、开哪几块大陆），而「放过了」是一件已经发生的事实。混在一起，
/// 设置页早晚会冒出一个「彩蛋已播放」的开关——那不是任何人需要的东西。
class BirthdayStore extends ChangeNotifier {
  BirthdayStore([this._prefs]) {
    _played = _prefs?.getBool(storageKey) ?? false;
  }

  static const String storageKey = 'baby_pal.birthday.played.v1';

  final SharedPreferences? _prefs;

  bool _played = false;

  /// 首启那一次已经放过了。
  bool get hasPlayed => _played;

  static Future<BirthdayStore> open() async {
    try {
      return BirthdayStore(await SharedPreferences.getInstance());
    } on Exception catch (e) {
      // 读不到就当没放过。**宁可多放一次，也不要在他生日当天一次都没放。**
      debugPrint('BirthdayStore: 存档打不开，按「还没放过」处理 -> $e');
      return BirthdayStore();
    }
  }

  Future<void> markPlayed() async {
    if (_played) return;
    _played = true;
    notifyListeners();
    await _prefs?.setBool(storageKey, true);
  }

  /// 供家长区日后提供「再放一次」用。
  Future<void> reset() async {
    if (!_played) return;
    _played = false;
    notifyListeners();
    await _prefs?.remove(storageKey);
  }
}
