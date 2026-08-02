import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/audio/audio_providers.dart';
import 'core/content/content_providers.dart';
import 'core/design/controls.dart';
import 'core/design/tokens.dart';
import 'core/progress/progress_providers.dart';
import 'core/progress/progress_store.dart';
import 'core/settings/settings_providers.dart';
import 'core/settings/settings_store.dart';
import 'modules/addition/addition_page.dart';
import 'modules/hanzi/pictograph_page.dart';
import 'modules/home/bedtime_overlay.dart';
import 'modules/home/home_page.dart';
import 'modules/home/module_id.dart';
import 'modules/letters/letters_page.dart';
import 'modules/numbers/place_value_page.dart';
import 'birthday/birthday_egg.dart';
import 'birthday/birthday_providers.dart';
import 'birthday/birthday_store.dart';
import 'modules/sandbox/sandbox_page.dart';
import 'parent/gate.dart';
import 'parent/parent_home_page.dart';

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

  // 设置与时长存档也在开屏前打开：首页显示哪几块大陆、是不是已经到点了，
  // 都得在画第一帧之前就知道。晚一帧就意味着大陆先出现再消失。
  final settings = await SettingsStore.open();
  final progress = await ProgressStore.open();
  final birthday = await BirthdayStore.open();

  runApp(
    ProviderScope(
      overrides: [
        audioBusProvider.overrideWithValue(audioBus),
        contentLibraryProvider.overrideWithValue(content),
        settingsStoreProvider.overrideWithValue(settings),
        progressStoreProvider.overrideWithValue(progress),
        birthdayStoreProvider.overrideWithValue(birthday),
      ],
      child: const BlockPlanetApp(),
    ),
  );
}

class BlockPlanetApp extends ConsumerStatefulWidget {
  const BlockPlanetApp({super.key});

  @override
  ConsumerState<BlockPlanetApp> createState() => _BlockPlanetAppState();
}

class _BlockPlanetAppState extends ConsumerState<BlockPlanetApp>
    with WidgetsBindingObserver {
  /// 落盘间隔。
  ///
  /// **这个定时器不参与计时**——时长永远由墙钟时间戳相减得出（design.md D7），
  /// 它只负责隔一会儿把已过的时间写进存档。作用是限制「进程被强杀」时的损失：
  /// 最多丢一分钟，而不是丢掉整场。
  static const Duration _flushInterval = Duration(minutes: 1);

  Timer? _flushTimer;

  /// 当前在哪个模块里。用于把时长记到对的那块大陆上。
  ModuleId? _current;

  ProgressStore get _progress => ref.read(progressStoreProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setWakelock(true);
    _progress.beginSession();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());

    // 首启放一次生日彩蛋。放在首帧之后而不是把 `home` 换掉：这样「放完」
    // 和「跳过」都只是弹掉一层路由，回到的就是那张星球地图——**只有一个
    // 出口，也就没有卡在中间的可能**。星球地图会先闪一帧，人眼看不出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !ref.read(birthdayStoreProvider).hasPlayed) {
        unawaited(_openBirthday());
      }
    });
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _setWakelock(false);
    super.dispose();
  }

  void _flush() => unawaited(_progress.flush(module: _current?.name));

  /// 常亮开关。**失败必须被吞掉**——`wakelock_plus` 在部分设备与全部模拟器上
  /// 根本没有实现，而一个「屏幕会自己暗下去」的缺陷，代价远低于一个因为
  /// 未捕获异常而起不来的 App。
  void _setWakelock(bool on) {
    unawaited(
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError(
        (Object e) => debugPrint('wakelock: 不可用，忽略 -> $e'),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _setWakelock(true);
        // 系统栏可能在切换过程中重新出现，回前台时重新藏起来。
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        // 重开计时窗口。**后台那段时间不计入**——他没在玩。
        _progress.beginSession();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _setWakelock(false);
        // 切后台就把这一段结掉并落盘。切回来是接着算，不是从零开始。
        unawaited(_progress.endSession(module: _current?.name));
    }
  }

  Future<void> _openModule(BuildContext context, ModuleId module) async {
    // 先把在首页待的那段时间结掉，再开始记这个模块的。
    _flush();
    _current = module;

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
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

    _flush();
    _current = null;
  }

  /// 家长区（含家长门）正开着。
  ///
  /// 家长门与家长区都在路由栈里，而谢幕画面盖在路由栈**之上**。因此到点
  /// 之后必须把谢幕画面让开，否则家长长按进来的乘法题、进去之后的设置页，
  /// 全都被压在那层画面底下——看不见也点不着，**而调高上限是唯一的出路**。
  /// 真机上一走这条流程就撞上了：门开了，人进不去。
  bool _inParentZone = false;

  /// 走家长门，过了就进家长区。
  ///
  /// 用 [_navigatorKey] 而不是就近的 `context`：谢幕画面挂在 `MaterialApp`
  /// 的 `builder` 里，那一层**在 Navigator 之上**，`Navigator.of(context)`
  /// 在那儿取不到东西。而谢幕画面上的家长门恰恰是最必须能用的一个——
  /// 它盖住了整个 App，家长只能从那里进去把上限调高。

  Future<void> _openParentZone() async {
    final navigator = _navigatorKey.currentState;
    final context = _navigatorKey.currentContext;
    if (navigator == null || context == null || _inParentZone) return;

    setState(() => _inParentZone = true);
    try {
      if (!await runParentGate(context)) return;
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => const ParentHomePage()),
      );
    } finally {
      if (mounted) setState(() => _inParentZone = false);
    }
  }

  /// 放生日彩蛋。首启自动走这里，之后由首页那块蛋糕重播。
  ///
  /// 演完与跳过是同一个出口（[BirthdayEgg.onDone]），这里只做一件事：
  /// 弹掉那层路由并记下「放过了」。
  Future<void> _openBirthday() async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || _inBirthday) return;

    setState(() => _inBirthday = true);
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (context) =>
              BirthdayEgg(onDone: () => Navigator.of(context).pop()),
        ),
      );
      await ref.read(birthdayStoreProvider).markPlayed();
    } finally {
      if (mounted) setState(() => _inBirthday = false);
    }
  }

  /// 彩蛋正放着。与 [_inParentZone] 同理——谢幕画面不该盖住彩蛋，
  /// 那是他生日当天唯一真正重要的那一屏。
  bool _inBirthday = false;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStoreProvider);
    final progress = ref.watch(progressStoreProvider);

    return MaterialApp(
      title: '方块星球',
      debugShowCheckedModeBanner: false,
      theme: buildBlockPlanetTheme(),
      navigatorKey: _navigatorKey,
      // 儿童端零文字界面，不需要 localizations；家长端固定中文。
      //
      // 谢幕画面挂在 `builder` 而不是 `home`：他到点的时候多半正在某个玩法
      // 里面，而 `home` 那一层被压在整个路由栈底下——盖不住任何东西。
      builder: (context, navigator) => ListenableBuilder(
        listenable: progress,
        builder: (context, _) => Stack(
          children: [
            navigator ?? const SizedBox.shrink(),
            // 到点了就盖上谢幕画面。它**盖在最上层但不是路由**——
            // 一是不能弹强制对话框（规格），二是家长把上限调高之后
            // 它要能自己消失，而路由不会。
            //
            // 家长区打开时让开：见 [_inParentZone]。
            if (progress.isLimitReached && !_inParentZone && !_inBirthday)
              Positioned.fill(
                child: BedtimeOverlay(
                  key: const ValueKey('bedtime'),
                  corner: ParentGateEntry(onUnlockRequested: _openParentZone),
                ),
              ),
          ],
        ),
      ),
      home: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Builder(
          builder: (context) => Stack(
            children: [
              HomePage(
                enabledModules: settings.settings.orderedModules,
                onModuleSelected: (module) => _openModule(context, module),
              ),
              // 家长门放右下角：够得着，但长得不像能按的地方。
              Positioned(
                right: BlockMetrics.gap / 2,
                bottom: BlockMetrics.gap / 2,
                child: ParentGateEntry(onUnlockRequested: _openParentZone),
              ),
              // 重播生日彩蛋的固定入口（规格要求「固定入口可重播」）。
              // 与家长门正相反：这个是**给他按的**，所以够大、有颜色、
              // 一眼看得出能按。
              Positioned(
                right: BlockMetrics.gap / 2,
                top: BlockMetrics.gap / 2,
                child: PressableTile(
                  key: const ValueKey('birthday'),
                  width: BlockMetrics.minGrabTarget,
                  color: BlockColors.forIndex(5),
                  onPressed: () => unawaited(_openBirthday()),
                  child: Icon(
                    Icons.cake_rounded,
                    size: BlockMetrics.minGrabTarget * 0.46,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
