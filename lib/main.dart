import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/audio/audio_providers.dart';
import 'core/design/tokens.dart';
import 'modules/addition/addition_page.dart';
import 'modules/home/home_page.dart';
import 'modules/home/module_id.dart';
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

  runApp(
    ProviderScope(
      overrides: [audioBusProvider.overrideWithValue(audioBus)],
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
            // 尚未实现的模块静默忽略——绝不能弹「敬请期待」之类的文字。
            final builder = switch (module) {
              ModuleId.sandbox => (_) => const SandboxPage(),
              ModuleId.numbers => (_) => const PlaceValuePage(),
              ModuleId.addition => (_) => const AdditionPage(),
              _ => null,
            };
            if (builder == null) return;
            Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
          },
        ),
      ),
    );
  }
}
