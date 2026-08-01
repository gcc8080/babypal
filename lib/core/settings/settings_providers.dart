import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/narration.dart';
import 'settings_store.dart';

/// 家长设置。
///
/// 与音频总线、内容库一样在 `main()` 里打开并 override，而不是做成异步
/// provider：首页要显示哪几块大陆取决于它，晚一帧知道就意味着孩子会看见
/// 大陆先出现再消失。
///
/// 默认值是**内存版**而不是抛异常（对比 [contentLibraryProvider]）：设置的
/// 缺省值本来就是一套能玩的配置，读不到存档时用它比起不来强。
final settingsStoreProvider = Provider<SettingsStore>((ref) {
  final store = SettingsStore();
  ref.onDispose(store.dispose);
  return store;
});

/// 按当前设置决定「念一遍还是念两遍」。
///
/// 显式挂上 store 的监听并 [Ref.invalidateSelf]：`Provider` 只在依赖变化时
/// 重算，而 `ChangeNotifier` 通知**不算依赖变化**——少了这几行，家长把英文
/// 关掉之后这里会一直返回旧值，表现为「设置不生效」。
final narrationProvider = Provider<NarrationStyle>((ref) {
  final store = ref.watch(settingsStoreProvider);
  void onChanged() => ref.invalidateSelf();
  store.addListener(onChanged);
  ref.onDispose(() => store.removeListener(onChanged));
  return NarrationStyle(bilingual: store.settings.bilingual);
});

/// 双声道的开关落在这一层，而不是散在每个页面的 `if`。
///
/// 方法名与 [Narration] 的 `bilingualXxx` 一一对应，改造call点时只是把
/// `Narration.bilingualNumber(n)` 换成 `narration.number(n)`——**语义不变，
/// 只是多了一个人管「要不要第二遍」**。
class NarrationStyle {
  const NarrationStyle({required this.bilingual});

  final bool bilingual;

  /// 关掉英文时只念中文。
  ///
  /// 刻意不是「只念英文」：中文是他的母语，任何时候都不该被关掉。
  List<String> _both(List<String> Function(VoiceLang lang) build) =>
      bilingual ? Narration.bilingual(build) : build(VoiceLang.zh);

  List<String> number(int value) => _both((l) => [Narration.number(value, l)]);

  List<String> addition(int a, int b) => _both((l) => Narration.addition(a, b, l));

  List<String> additionQuestion(int a, int b) =>
      _both((l) => Narration.additionQuestion(a, b, l));

  List<String> decomposition(int total, int a, int b) =>
      _both((l) => Narration.decomposition(total, a, b, l));

  List<String> sum(List<int> addends) => _both((l) => Narration.sum(addends, l));
}
