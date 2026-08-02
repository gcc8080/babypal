import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/content/content_providers.dart';
import '../core/content/models.dart';
import '../core/content/pack_loader.dart';
import '../core/design/controls.dart';
import '../core/design/tokens.dart';
import 'breath_source.dart';
import 'candle_scene.dart';
import 'name_scene.dart';

/// 彩蛋里的一幕。
@immutable
class BirthdayScene {
  const BirthdayScene({
    required this.id,
    required this.build,
    this.tapAnywhereSkips = false,
  });

  final String id;

  /// 画这一幕。演完调 `onFinished` 交给下一幕。
  final Widget Function(BuildContext context, VoidCallback onFinished) build;

  /// 碰哪儿都跳过。
  ///
  /// **只给被动播放的画面**（拼名字动画那种看着就好的）。互动画面不能这样：
  /// 他伸手去吹蜡烛、去点蜡烛，那是在玩，不是想跳过——把那一下当成「跳过」
  /// 会让这一幕根本没法玩。互动幕靠右上角那个键跳过。
  final bool tapAnywhereSkips;
}

/// 组出这一次要放的几幕。
///
/// 见 birthday 规格「彩蛋数据与资源可缺失」：姓名、照片、家人语音没配置时
/// 彩蛋**仍要能启动并完成**，缺的那一幕优雅省略。所以幕次是算出来的，
/// 不是写死的一串——「今年有没有这一幕」在这里判断，各幕自己只管演。
///
/// 家人相册（8.6）落地后加进这个列表即可，[BirthdayEgg] 一个字都不用改。
List<BirthdayScene> birthdayScenes({
  ContentLibrary? library,
  BreathSource? breathSource,
}) {
  final name = _childName(library);
  return [
    // 名字在前、蜡烛在后：先叫他的名字，再请他吹蜡烛。倒过来就变成
    // 「吹完了，顺便告诉你这是给谁的」。
    if (name != null)
      BirthdayScene(
        id: 'name',
        // 被动画面：他什么都不用做，一碰就说明想往下走了。
        tapAnywhereSkips: true,
        build: (context, onFinished) =>
            NameScene(target: name, onFinished: onFinished),
      ),
    BirthdayScene(
      id: 'candles',
      build: (context, onFinished) =>
          CandleScene(breathSource: breathSource, onFinished: onFinished),
    ),
  ];
}

/// 内容包里他的名字。没配置就返回 null，那一幕整个省掉。
SpellingTarget? _childName(ContentLibrary? library) {
  if (library == null) return null;
  for (final target in library.spellingTargets) {
    if (target.id == kChildSpellingId) return target;
  }
  // **不退而求其次拿第一个。** `spellingTargets` 里还躺着 Mama / Baba，
  // 那是字母模块终关的备选目标；名字这一幕拼出「MAMA」是错的，不如不放。
  return null;
}

/// 生日彩蛋。
///
/// 见 birthday 规格「首启一次性生日彩蛋」：首次启动自动放一次，此后从固定
/// 入口重播；**播放中可跳过，且不许卡在中间状态**。
///
/// 「不卡在中间」在这里是一条具体的实现要求：跳过走的和演完走的是**同一个
/// 出口**（[onDone]），中途没有任何一条别的路能离开这个页面。少了这条，
/// 跳过就可能留下一个放了一半、又回不去首页的彩蛋——而那是他生日当天最
/// 不该出现的东西。
class BirthdayEgg extends ConsumerStatefulWidget {
  const BirthdayEgg({
    super.key,
    required this.onDone,
    this.scenes,
    this.breathSource,
  });

  /// 演完或跳过之后调用。**两条路同一个出口。**
  final VoidCallback onDone;

  /// 要放哪几幕。为 null 时用 [birthdayScenes] 算出来的那几幕。
  ///
  /// 显式接一个列表，是让这个组件退回成**纯粹的放映机**：它只管一幕演完
  /// 换下一幕、跳过就走人，至于「今年有几幕、缺了名字要不要跳过相册」
  /// 是 [birthdayScenes] 的事。顺带也让「一幕都没有」这条路能被真的测到，
  /// 而不是在测试里照抄一遍同样的逻辑——那种测试只证明我会复制粘贴。
  final List<BirthdayScene>? scenes;

  /// 麦克风来源，透传给蜡烛那一幕。为 null 时用真机实现。
  final BreathSource? breathSource;

  @override
  ConsumerState<BirthdayEgg> createState() => _BirthdayEggState();
}

class _BirthdayEggState extends ConsumerState<BirthdayEgg> {
  late final List<BirthdayScene> _scenes =
      widget.scenes ??
      birthdayScenes(
        library: ref.read(contentLibraryProvider),
        breathSource: widget.breathSource,
      );

  int _index = 0;

  /// 已经走过出口了。
  ///
  /// 跳过键和最后一幕的 `onFinished` 可能在同一拍里都触发（他正好在庆祝
  /// 那一下按了跳过），没有这个闩就会调用两次 [BirthdayEgg.onDone]——
  /// 表现是首页被弹掉两层。
  bool _left = false;

  void _finish() {
    if (_left) return;
    _left = true;
    widget.onDone();
  }

  void _nextScene() {
    if (_left) return;
    if (_index + 1 >= _scenes.length) {
      _finish();
      return;
    }
    setState(() => _index += 1);
  }

  @override
  Widget build(BuildContext context) {
    // 一幕都没有（内容全缺）→ 直接走完，不留一个空白页面。
    if (_scenes.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return const Scaffold(body: SizedBox.expand());
    }

    final scene = _scenes[_index];
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: scene.tapAnywhereSkips
                ? GestureDetector(
                    key: const ValueKey('skip-surface'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _finish,
                    child: scene.build(context, _nextScene),
                  )
                : scene.build(context, _nextScene),
          ),
          // 跳过键一直在。**它不是「关闭」而是「往下走」**——用的是他在
          // 别处见惯的那个向前箭头，不是一个叉。这个 App 里没有叉。
          Positioned(
            right: BlockMetrics.gap / 2,
            top: BlockMetrics.gap / 2,
            child: SafeArea(
              child: RoundActionButton(
                key: const ValueKey('skip'),
                icon: Icons.arrow_forward_rounded,
                onPressed: _finish,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
