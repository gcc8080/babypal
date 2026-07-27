import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_bus.dart';
import '../../core/audio/audio_providers.dart';
import '../../core/audio/sfx.dart';
import '../../core/block/block_model.dart';
import '../../core/content/content_providers.dart';
import '../../core/content/models.dart';
import '../../core/design/controls.dart';
import '../../core/design/tokens.dart';
import 'letter_tile.dart';
import 'letters.dart';
import 'letters_page.dart';

/// 托盘里的一块字母积木。
///
/// 带自己的 id 而不是只带字母：Emmett 里有两个 M、两个 T，只按字母认的话
/// 拿起哪一块都分不清，托盘会少掉不该少的那块。
@immutable
class NameTile {
  const NameTile(this.id, this.letter);

  final int id;
  final String letter;

  @override
  String toString() => 'NameTile($id, $letter)';
}

/// 放错位置后的演示停留时长。
const Duration kNameDemoHold = Duration(milliseconds: 1200);

/// 拼自己的名字——字母模块的终关。
///
/// 见 letters 规格「拼自己的名字」：目标名字 MUST 来自可配置数据；字母顺序
/// 放错时 **MUST NOT 呈现失败状态**，而是吸附到它正确的位置并演示正确顺序。
///
/// 后面这条把整关的规则简化成了一句话：**他放下的每一块，都会去到它该去的
/// 地方。** 没有「放错了」这个分支，只有「它自己知道该站哪儿」。放对时是
/// 干脆的一声吸附；放歪时那块积木会先亮一下再滑过去，让他看见它去了哪里。
///
/// 空槽显示目标字母的淡色影子。三岁孩子拼名字本来就是**照着描**，不是默写；
/// 藏起影子只会把一件他做得到的事变成猜谜。
class NamePage extends ConsumerStatefulWidget {
  const NamePage({super.key});

  @override
  ConsumerState<NamePage> createState() => _NamePageState();
}

class _NamePageState extends ConsumerState<NamePage> {
  int _targetIndex = 0;

  /// 每个槽位里的积木，null 表示还空着。
  List<NameTile?> _slots = const [];

  /// 还在托盘里的积木。
  List<NameTile> _tray = const [];

  /// 刚刚被「送回正确位置」的槽位，短暂高亮。
  int? _demoSlot;

  bool _solved = false;
  Timer? _demoTimer;

  AudioBus get _audio => ref.read(audioBusProvider);

  List<SpellingTarget> get _targets =>
      ref.read(contentLibraryProvider).spellingTargets;

  SpellingTarget? get _target {
    final all = _targets;
    if (all.isEmpty) return null;
    return all[_targetIndex % all.length];
  }

  @override
  void initState() {
    super.initState();
    // **槽位必须在这里就建好，不能等到 postFrameCallback**：`_slots` 的长度和
    // 目标名字的长度是同一个事实的两种表示，中间隔一帧就会有一帧两者不一致，
    // 而那一帧的 `build` 会拿 `_slots` 的下标去索引目标字母——名字变短时直接
    // 越界。`ref.read` 在 initState 里是允许的（只有 `watch` 不行）。
    _reset();
    // 播报仍然留到首帧之后：音频总线要等界面立起来才有意义。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announce(interrupt: true);
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    super.dispose();
  }

  // ─── 状态 ──────────────────────────────────────────────────────────

  /// 重排托盘与槽位。**必须在 `setState` 里调**。
  void _reset() {
    final target = _target;
    if (target == null) {
      _slots = const [];
      _tray = const [];
      return;
    }
    _slots = List<NameTile?>.filled(target.letters.length, null);
    _tray = [
      for (var i = 0; i < target.letters.length; i++)
        NameTile(i, target.letters[i]),
      // 打乱顺序，否则托盘本身就是答案，他照着从左往右搬一遍就完了。
      // 用固定种子：同一关反复进来顺序一致，不会看见字母自己在跳。
    ]..shuffle(math.Random(_targetIndex * 17 + 3));
    _solved = false;
    _demoSlot = null;
  }

  /// [tile] 该去的槽位：第一个还空着、且目标字母与它相同的槽。
  ///
  /// 重复字母（Emmett 的两个 M）就靠「第一个空着的」来分配——他先放哪个 M
  /// 都对，因为两个 M 本来就没有区别。
  int? _homeSlot(NameTile tile) {
    final target = _target;
    if (target == null) return null;
    for (var i = 0; i < _slots.length; i++) {
      if (_slots[i] == null && target.letters[i] == tile.letter) return i;
    }
    return null;
  }

  // ─── 操作 ──────────────────────────────────────────────────────────

  /// 把 [tile] 放到第 [slot] 号槽位。[slot] 为 null 表示点选通道（他没指定
  /// 位置，那就直接送到该去的地方）。
  void _place(NameTile tile, {int? slot}) {
    final home = _homeSlot(tile);
    if (home == null) return;

    // 放对了地方 → 干脆的一声吸附。放歪了 → 它照样去 home，只是先亮一下，
    // 让他看清它去了哪里。**两条路径的终点相同，因为没有「放错」这回事。**
    final onTarget = slot == null || slot == home;

    setState(() {
      _slots[home] = tile;
      _tray = _tray.where((t) => t.id != tile.id).toList();
      _demoSlot = onTarget ? null : home;
      _solved = _slots.every((s) => s != null);
    });

    _audio.playSfx(onTarget ? Sfx.snap : Sfx.pickup);

    if (!onTarget) {
      _demoTimer?.cancel();
      _demoTimer = Timer(kNameDemoHold, () {
        if (mounted) setState(() => _demoSlot = null);
      });
    }

    if (_solved) {
      _celebrate();
    } else {
      _speakLetter(tile.letter);
    }
  }

  /// 把槽里的积木拿回托盘。点一下就好——与其他模块「点已放置的积木 = 收回」
  /// 是同一个动作。
  void _takeBack(int slot) {
    final tile = _slots[slot];
    if (tile == null) return;
    setState(() {
      _slots[slot] = null;
      _tray = [..._tray, tile];
      _solved = false;
      _demoSlot = null;
    });
    _audio.playSfx(Sfx.returned);
  }

  void _celebrate() {
    _audio.playSfx(Sfx.merge);
    _announce(interrupt: true);
  }

  void _speakLetter(String letter) {
    final item = ref.read(contentLibraryProvider).letterByChar(letter);
    if (item == null) return;
    unawaited(
      _audio.speakSequence(
        LetterNarration.letterAndPhoneme(item),
        policy: VoicePolicy.interrupt,
      ),
    );
  }

  /// 念出这个名字。这是终关的奖励本身——他听见的是自己的名字。
  void _announce({bool interrupt = false}) {
    final target = _target;
    if (target == null) return;
    unawaited(
      _audio.speak(
        target.voiceKey,
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  void _clear() {
    if (_tray.length == _slots.length) return;
    setState(_reset);
    _audio.playSfx(Sfx.returned);
  }

  void _nextTarget() {
    final count = _targets.length;
    if (count == 0) return;
    _demoTimer?.cancel();
    _audio.playSfx(Sfx.pickup);
    setState(() {
      _targetIndex = (_targetIndex + 1) % count;
      _reset();
    });
    _announce(interrupt: true);
  }

  void _goToLetters() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const LettersPage()),
    );
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final gap = BlockMetrics.gap / 2;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: target == null
              // 内容包里没有拼字目标时静默留白，绝不弹文字。
              ? const SizedBox.expand()
              : Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < _slots.length; i++) ...[
                            if (i > 0) SizedBox(width: gap),
                            Expanded(
                              child: _Slot(
                                key: ValueKey('slot-$i'),
                                targetLetter: target.letters[i],
                                tile: _slots[i],
                                demonstrating: _demoSlot == i,
                                solved: _solved,
                                onAccept: (tile) => _place(tile, slot: i),
                                onTap: () => _takeBack(i),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(height: gap),
                    // **字母积木单独占一行，不和按钮挤在一起。**
                    // Emmett 是 6 块 ×90dp = 540dp，再加三个 90dp 的按钮就是
                    // 874dp——交付机横屏只有 738dp，直接溢出 152dp。而这三样
                    // 都不能让步：90dp 是抓取红线，按钮一个都不能少。
                    //
                    // 横向滚动只是兜底：7 个字母以内都排得满满当当不用滑，
                    // 更长的名字（内容包可配）才会需要滑一下。首页的大陆
                    // 长条用的是同一套。
                    SizedBox(
                      height: BlockMetrics.minGrabTarget,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final tile in _tray) ...[
                              SizedBox(
                                width: BlockMetrics.minGrabTarget,
                                child: _TrayTile(
                                  key: ValueKey('tile-${tile.id}'),
                                  tile: tile,
                                  onTap: () => _place(tile),
                                ),
                              ),
                              SizedBox(width: gap),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: BlockMetrics.minGrabTarget,
                      child: Row(
                        children: [
                          const Spacer(),
                          RoundActionButton(
                            key: const ValueKey('mode'),
                            icon: Icons.image_rounded,
                            onPressed: _goToLetters,
                          ),
                          SizedBox(width: gap),
                          RoundActionButton(
                            key: const ValueKey('clear'),
                            icon: Icons.refresh_rounded,
                            onPressed: _clear,
                          ),
                          SizedBox(width: gap),
                          RoundActionButton(
                            key: const ValueKey('next'),
                            icon: Icons.chevron_right_rounded,
                            highlighted: _solved,
                            onPressed: _nextTarget,
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

/// 一个名字槽位。空着时显示目标字母的淡影子。
class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.targetLetter,
    required this.tile,
    required this.demonstrating,
    required this.solved,
    required this.onAccept,
    required this.onTap,
  });

  final String targetLetter;
  final NameTile? tile;

  /// 刚接住一块「本来放歪了」的积木，短暂高亮。**不是错误标记**。
  final bool demonstrating;

  final bool solved;
  final void Function(NameTile tile) onAccept;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DragTarget<NameTile>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, _) {
        final filled = tile != null;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            scale: candidate.isNotEmpty || demonstrating ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 160),
            child: filled
                ? LetterTile(
                    letter: targetLetter,
                    color: solved
                        ? RoundActionButton.doneColor
                        : letterColor(targetLetter),
                    expression: solved
                        ? BlockExpression.happy
                        : BlockExpression.idle,
                  )
                : LetterTile(
                    letter: targetLetter,
                    // 影子槽：底色很淡，字形反而用该字母**自己的颜色**加深。
                    // 白字画在淡底上几乎看不见，而这个字形就是「这一格要哪个
                    // 字母」的全部提示。托盘里那块的颜色也是同一个，
                    // 「找一样颜色的」本身就是他用得上的抓手。
                    color: letterColor(targetLetter).withValues(alpha: 0.12),
                    glyphColor: letterColor(
                      targetLetter,
                    ).withValues(alpha: 0.6),
                    showFace: false,
                  ),
          ),
        );
      },
    );
  }
}

/// 托盘里的字母积木。可拖、可点。
class _TrayTile extends StatelessWidget {
  const _TrayTile({super.key, required this.tile, required this.onTap});

  final NameTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final view = LetterTile(
      letter: tile.letter,
      color: letterColor(tile.letter),
      showFace: false,
    );

    return GestureDetector(
      onTap: onTap,
      child: Draggable<NameTile>(
        data: tile,
        feedback: SizedBox(
          width: BlockMetrics.minGrabTarget,
          height: BlockMetrics.minGrabTarget,
          child: Opacity(opacity: 0.9, child: view),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: view),
        child: view,
      ),
    );
  }
}
