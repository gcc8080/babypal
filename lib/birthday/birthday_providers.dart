import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'birthday_store.dart';

/// 生日彩蛋放过没有。
///
/// 与设置、时长同样在 `main()` 里打开并 override：**首启要不要放彩蛋这件事
/// 必须在画第一帧之前就知道**，否则他会先看见星球地图再被彩蛋盖上去。
///
/// 默认是内存版（每次启动都算「还没放过」）。这条降级刻意偏向多放一次：
/// 生日当天一次都没放，比多放一次糟糕得多。
final birthdayStoreProvider = Provider<BirthdayStore>((ref) {
  final store = BirthdayStore();
  ref.onDispose(store.dispose);
  return store;
});
