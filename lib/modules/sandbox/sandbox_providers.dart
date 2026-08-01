import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sandbox_store.dart';

/// 沙盒存档。
///
/// 与音频总线、内容库不同，这一个**做成异步 provider 而不是在 `main()` 里
/// 预先打开**：存档只有沙盒一个模块用得上，而 `SharedPreferences` 的首次
/// 读盘要几十毫秒——放进开屏路径上，五个模块里有四个白等。
///
/// 读不回来时的降级是「空台面」而不是转圈：见 [SandboxStore.load]。
final sandboxStoreProvider = FutureProvider<SandboxStore>(
  (ref) => SandboxStore.open(),
);
