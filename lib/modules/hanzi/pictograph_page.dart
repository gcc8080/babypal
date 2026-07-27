import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_bus.dart';
import '../../core/audio/audio_providers.dart';
import '../../core/audio/sfx.dart';
import '../../core/block/block_model.dart';
import '../../core/content/content_providers.dart';
import '../../core/content/models.dart';
import '../../core/design/controls.dart';
import '../../core/design/glyph_tile.dart';
import '../../core/design/tokens.dart';
import 'component_page.dart';
import 'hanzi.dart';
import 'pictograph_view.dart';

/// 象形动画。
///
/// 见 hanzi 规格「象形字渐变动画」：图片渐变为字形，**动画 MUST 可重播**。
///
/// 覆盖的正是他已经认识的 山田土木/日月水火——这一关不教新字，教的是「这些
/// 字本来就是那样东西的画」。他认得「山」，但多半没想过为什么「山」长这样；
/// 三座山峰收拢成三竖的那一下，就是这个玩法的全部。
///
/// 左右两侧摆着前一个和后一个字，点一下直接跳过去。**不做 26 格长条**：
/// 长条要滑，滑要练，而这里统共只有九个字。
class PictographPage extends ConsumerStatefulWidget {
  const PictographPage({super.key});

  @override
  ConsumerState<PictographPage> createState() => _PictographPageState();
}

class _PictographPageState extends ConsumerState<PictographPage>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// 渐变动画。在 `initState` 里建而不是 `late final` 惰性初始化——惰性初始化
  /// 会让 `dispose()` 成为首次访问，那时组件树已失活，`createTicker` 查祖先
  /// 节点会直接抛（见百格板 4.3 与字母页的同名修复）。
  late final AnimationController _morph;

  AudioBus get _audio => ref.read(audioBusProvider);

  List<HanziItem> get _items => [
    for (final item in ref.read(contentLibraryProvider).hanzi)
      if (item.type == HanziType.pictograph) item,
  ];

  HanziItem? get _current {
    final items = _items;
    if (items.isEmpty) return null;
    return items[_index % items.length];
  }

  HanziItem? _neighbour(int step) {
    final items = _items;
    if (items.length < 2) return null;
    return items[(_index + step + items.length) % items.length];
  }

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(vsync: this, duration: kMorphDuration);
    // 进页面就演一遍：三岁的他不会先想「我该点哪里」，而是等着看会发生什么。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play(interrupt: true);
    });
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  // ─── 操作 ──────────────────────────────────────────────────────────

  /// 从头演一遍，并念出这个字。
  ///
  /// 规格的「重播」就是这一个方法：点画面、点重播键、切字，走的都是它，
  /// 因此**不存在「已经播过了所以不播」的状态**。
  void _play({bool interrupt = false}) {
    final item = _current;
    if (item == null) return;
    _morph.forward(from: 0);
    unawaited(
      _audio.speakSequence(
        HanziNarration.character(item),
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  void _tapPicture() {
    _audio.playSfx(Sfx.tap);
    _play(interrupt: true);
  }

  void _step(int delta) {
    final count = _items.length;
    if (count == 0) return;
    _audio.playSfx(Sfx.pickup);
    // 走到头绕回去，不禁用——一个按不动的东西对他就是「坏了」。
    setState(() => _index = (_index + delta + count) % count);
    _play(interrupt: true);
  }

  /// 三个玩法接成一个环：象形 → 部件加法 → 跷跷板 → 象形。图标画的是**下一站**。
  /// 一律 `pushReplacement`，返回键始终直接回星球地图，不会越按越深。
  void _goToComponent() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ComponentPage()),
    );
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final item = _current;
    final gap = BlockMetrics.gap / 2;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Column(
            children: [
              Expanded(
                child: item == null
                    // 内容包读不到时静默留白：儿童端不能弹「暂无内容」。
                    ? const SizedBox.expand()
                    : Row(
                        children: [
                          _NeighbourTile(
                            id: 'prev',
                            item: _neighbour(-1),
                            onTap: () => _step(-1),
                          ),
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('picture'),
                              behavior: HitTestBehavior.opaque,
                              onTap: _tapPicture,
                              child: AnimatedBuilder(
                                animation: _morph,
                                builder: (context, _) => PictographView(
                                  char: item.char,
                                  imageKey: item.imageKey,
                                  progress: _morph.value,
                                  color: hanziColor(item.char),
                                ),
                              ),
                            ),
                          ),
                          _NeighbourTile(
                            id: 'next',
                            item: _neighbour(1),
                            onTap: () => _step(1),
                          ),
                        ],
                      ),
              ),
              SizedBox(height: gap),
              SizedBox(
                height: BlockMetrics.minGrabTarget,
                child: Row(
                  children: [
                    RoundActionButton(
                      key: const ValueKey('replay'),
                      icon: Icons.replay_rounded,
                      onPressed: () => _play(interrupt: true),
                    ),
                    const Spacer(),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.add_circle_outline_rounded,
                      onPressed: _goToComponent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 左右两侧的邻居字。点一下直接跳过去。
///
/// 画得暗一些：他要看的是中间那个正在变的字，这两块只是「旁边还有」。
class _NeighbourTile extends StatelessWidget {
  const _NeighbourTile({
    required this.id,
    required this.item,
    required this.onTap,
  });

  final String id;
  final HanziItem? item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = item;
    if (value == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: BlockMetrics.gap / 2),
      child: Center(
        child: SizedBox(
          key: ValueKey(id),
          width: BlockMetrics.minGrabTarget,
          height: BlockMetrics.minGrabTarget,
          child: Listener(
            // 与托盘里其他可按的东西一样用原始 Listener 抢在手势竞技场前面：
            // 「触摸必有回应」要的是按下那一瞬间就有动静。
            onPointerDown: (_) => onTap(),
            child: GlyphTile(
              glyph: value.char,
              color: hanziColor(value.char),
              dimmed: true,
              expression: BlockExpression.idle,
            ),
          ),
        ),
      ),
    );
  }
}
