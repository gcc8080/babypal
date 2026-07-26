import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/design/tokens.dart';
import 'modules/home/home_page.dart';
import 'modules/home/module_id.dart';
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

  runApp(const ProviderScope(child: BlockPlanetApp()));
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
            // 目前只有沙盒接上了拼搭台，其余模块待 P2–P4 实现。
            if (module != ModuleId.sandbox) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SandboxPage()),
            );
          },
        ),
      ),
    );
  }
}
