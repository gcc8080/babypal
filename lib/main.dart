import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/audio/audio_providers.dart';
import 'core/content/content_providers.dart';
import 'core/design/tokens.dart';
import 'modules/addition/addition_page.dart';
import 'modules/home/home_page.dart';
import 'modules/hanzi/pictograph_page.dart';
import 'modules/home/module_id.dart';
import 'modules/letters/letters_page.dart';
import 'modules/numbers/place_value_page.dart';
import 'modules/sandbox/sandbox_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局锁横屏。拼搭需要横向空间，孩子看视频本就习惯横持，
  // 手机与平板因此共用同一套布局。
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 全屏沉浸：藏起状态栏与导航栏，减少误触退出。
  // immersiveSticky 下孩子划出系统栏后会自动缩回去。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // 在 runApp 之前完成音频初始化与音效预加载：首次点击不能等在磁盘 IO 上。
  final audioBus = await createAudioBus();

  // 内容包同样在开屏前读完——只有几十 KB，而做成异步 provider 就得给儿童端
  // 加一个「加载中」的转圈，那对三岁的他没有任何意义。
  final content = await loadContentLibrary();

  runApp(
    ProviderScope(
      overrides: [
        audioBusProvider.overrideWithValue(audioBus),
        contentLibraryProvider.overrideWithValue(content),
      ],
      child: const BlockPlanetApp(),
    ),
  );
}

class BlockPlanetApp extends StatefulWidget {
  const BlockPlanetApp({super.key});

  @override
  State<BlockPlanetApp> createState() => _BlockPlanetAppState();
}

class _BlockPlanetAppState extends State<BlockPlanetApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 只在前台保持常亮，退到后台立刻释放，避免白白耗电。
    switch (state) {
      case AppLifecycleState.resumed:
        WakelockPlus.enable();
        // 系统栏可能在切换过程中重新出现，回前台时重新藏起来。
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '方块星球',
      debugShowCheckedModeBanner: false,
      theme: buildBlockPlanetTheme(),
      // 儿童端零文字界面，不需要 localizations；家长端固定中文。
      home: Builder(
        builder: (context) => HomePage(
          onModuleSelected: (module) {
            // 五块大陆全部有落点了，因此这里**穷尽**枚举、不留 `_` 兜底：
            // 日后新增模块时，忘了接线会在编译期就红，而不是在星球地图上
            // 点下去毫无反应——那是三岁的他唯一无法理解的失败模式。
            final WidgetBuilder builder = switch (module) {
              ModuleId.sandbox => (_) => const SandboxPage(),
              ModuleId.numbers => (_) => const PlaceValuePage(),
              ModuleId.addition => (_) => const AdditionPage(),
              ModuleId.letters => (_) => const LettersPage(),
              ModuleId.hanzi => (_) => const PictographPage(),
            };
            Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: builder));
          },
        ),
      ),
    );
  }
}
