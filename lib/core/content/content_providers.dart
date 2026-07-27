import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show AssetBundle, AssetManifest, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pack_loader.dart';

/// 全部内容包合并后的检索入口。
///
/// 与 [audioBusProvider] 同样在 `main()` 中构造并 override，而不是做成异步
/// provider：儿童端是零文字界面，一个「加载中」的转圈对三岁的他没有任何意义，
/// 而内容包只有几十 KB，开屏前读完是最省事也最诚实的做法。
final contentLibraryProvider = Provider<ContentLibrary>(
  (ref) => throw UnimplementedError(
    'contentLibraryProvider 必须在 main() 中通过 overrideWithValue 提供',
  ),
);

/// 加载 `assets/packs/` 下的全部内容包。
///
/// **刻意从 AssetManifest 枚举，而不是写死一串文件名**：内容与代码分离是这个
/// App 能陪他从 3 岁用到 5 岁的前提（design.md D2）。明年丢一个 `hanzi_l2.json`
/// 进目录、在 pubspec 里已声明的 `assets/packs/` 会自动带上它，这里也就自动
/// 认得它——真正做到「加内容不改一行 Dart」。写死文件名的话，那句承诺每加一个
/// 包就要食言一次。
Future<ContentLibrary> loadContentLibrary({AssetBundle? bundle}) async {
  final b = bundle ?? rootBundle;
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(b);
    final paths =
        manifest
            .listAssets()
            .where((p) => p.startsWith('assets/packs/') && p.endsWith('.json'))
            .toList()
          ..sort();
    final library = await PackLoader(bundle: b).loadAll(paths);

    // 被跳过的条目在开发期必须可见，否则一个拼错的字段会安静地让某个字
    // 从 App 里消失——而三岁的用户不会来报 bug。
    for (final reason in library.skipped) {
      debugPrint('内容包: 已跳过 -> $reason');
    }
    return library;
  } on Exception catch (e) {
    // 读不到内容不该让 App 起不来：首页仍然能进，只是模块里没东西。
    debugPrint('内容包: 加载失败，已降级为空库 -> $e');
    return const ContentLibrary([]);
  }
}
