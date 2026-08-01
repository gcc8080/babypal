import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'progress_store.dart';

/// 时长与练习统计。
///
/// 与 [settingsStoreProvider] 同一套：默认是内存版，`main()` 里用打开了存档的
/// 那个覆盖掉。默认值能用而不是抛异常，是因为「记不住时长」比「起不来」轻。
final progressStoreProvider = Provider<ProgressStore>((ref) {
  final store = ProgressStore(null)..load();
  ref.onDispose(store.dispose);
  return store;
});
