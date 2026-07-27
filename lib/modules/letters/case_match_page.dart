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
import 'name_page.dart';

/// 一屏配几对。
///
/// 三对：横屏放得下三块 ≥90dp 的大写 + 三块小写，再多就得压缩尺寸。而且
/// 三岁的孩子一次能同时端详的东西本来也就三四样。
const int kCaseMatchPerRound = 3;

/// 配错时演示正确配对的停留时长。
///
/// 与等式槽的演示同一个道理：**必须留够他看清「哦，A 配的是 a」的时间**。
/// 太短就只是闪一下，跟错误提示没有区别；太长他会以为卡住了。
const Duration kCaseDemoHold = Duration(milliseconds: 1800);

/// 大小写配对。
///
/// 见 letters 规格「大小写配对」：**配错时 MUST NOT 出现错误标记，而是演示
/// 正确配对**。
///
/// 所以这里没有「答错」这个状态，只有「他还没找到，那就演示给他看」。把 b
/// 拖到 A 上，A 会自己把 a 请过来配好、停一下、再放开——他看见的是一次示范，
/// 不是一次判错。b 原样留在托盘里，随时可以再试，次数不限、不留痕迹。
class CaseMatchPage extends ConsumerStatefulWidget {
  const CaseMatchPage({super.key});

  @override
  ConsumerState<CaseMatchPage> createState() => _CaseMatchPageState();
}

class _CaseMatchPageState extends ConsumerState<CaseMatchPage> {
  int _round = 0;

  /// 已配好的字母。
  final Set<String> _matched = {};

  /// 点选通道里选中的小写字母。
  String? _selected;

  /// 正在被演示正确配对的大写字母。
  String? _demo;

  Timer? _demoTimer;

  AudioBus get _audio => ref.read(audioBusProvider);

  List<LetterItem> get _letters => ref.read(contentLibraryProvider).letters;

  /// 本轮的字母，按字母表顺序切段。
  List<LetterItem> get _round3 {
    final all = _letters;
    if (all.isEmpty) return const [];
    final start = (_round * kCaseMatchPerRound) % all.length;
    return [
      for (var i = 0; i < kCaseMatchPerRound && start + i < all.length; i++)
        all[start + i],
    ];
  }

  int get _roundCount {
    final n = _letters.length;
    return n == 0 ? 1 : (n + kCaseMatchPerRound - 1) ~/ kCaseMatchPerRound;
  }

  /// 托盘里的小写字母，本轮固定打乱一次。
  ///
  /// 用 `Random(_round)` 而不是全局随机：同一轮反复看到的顺序必须一样，
  /// 否则每次重建组件树他都会看见小写字母自己在跳。
  List<LetterItem> get _tray {
    final items = _round3.where((l) => !_matched.contains(l.letter)).toList();
    return items..shuffle(math.Random(_round * 31 + 7));
  }

  bool get _solved =>
      _round3.isNotEmpty && _round3.every((l) => _matched.contains(l.letter));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announceRound();
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    super.dispose();
  }

  // ─── 操作 ──────────────────────────────────────────────────────────

  /// 把小写 [lower] 放到大写 [upper] 上。拖拽与点选两条通道都走这里。
  void _place(LetterItem lower, LetterItem upper) {
    if (_matched.contains(upper.letter)) return;

    if (lower.letter == upper.letter) {
      _audio.playSfx(Sfx.merge);
      setState(() {
        _matched.add(upper.letter);
        _selected = null;
      });
      unawaited(
        _audio.speakSequence(
          LetterNarration.letterAndPhoneme(upper),
          policy: VoicePolicy.interrupt,
        ),
      );
      return;
    }

    _demonstrate(upper);
  }

  /// 演示 [upper] 正确的配对。
  ///
  /// 刻意用 `snap` 而不是任何带挫败感的音：他听到的是「啪，配好了」，
  /// 和配对成功时是同一族的声音，只是没有庆祝的那一声。
  void _demonstrate(LetterItem upper) {
    _audio.playSfx(Sfx.snap);
    setState(() {
      _demo = upper.letter;
      _selected = null;
    });
    unawaited(
      _audio.speakSequence(
        LetterNarration.letterAndPhoneme(upper),
        policy: VoicePolicy.interrupt,
      ),
    );

    _demoTimer?.cancel();
    _demoTimer = Timer(kCaseDemoHold, () {
      // 演示完原样退回：小写字母还在托盘里，没有任何痕迹留下。
      if (mounted) setState(() => _demo = null);
    });
  }

  /// 点选通道：先点小写选中，再点大写落位。
  void _tapLower(LetterItem lower) {
    _audio.playSfx(Sfx.tap);
    setState(() => _selected = _selected == lower.letter ? null : lower.letter);
  }

  void _tapUpper(LetterItem upper) {
    final selectedLetter = _selected;
    if (selectedLetter == null) {
      // 没选中任何小写时，点大写只是听一遍它的读音——**不算一次尝试**。
      _audio.playSfx(Sfx.tap);
      unawaited(
        _audio.speakSequence(
          LetterNarration.letterAndPhoneme(upper),
          policy: VoicePolicy.interrupt,
        ),
      );
      return;
    }
    final lower = _round3.firstWhere((l) => l.letter == selectedLetter);
    _place(lower, upper);
  }

  void _nextRound() {
    _demoTimer?.cancel();
    _audio.playSfx(Sfx.pickup);
    setState(() {
      _round = (_round + 1) % _roundCount;
      _matched.clear();
      _selected = null;
      _demo = null;
    });
    _announceRound();
  }

  void _announceRound() {
    final first = _round3.isEmpty ? null : _round3.first;
    if (first == null) return;
    unawaited(
      _audio.speakSequence(
        LetterNarration.letterAndPhoneme(first),
        policy: VoicePolicy.interrupt,
      ),
    );
  }

  void _goToName() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const NamePage()),
    );
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final round = _round3;
    final tray = _tray;
    final gap = BlockMetrics.gap / 2;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < round.length; i++) ...[
                      if (i > 0) SizedBox(width: BlockMetrics.gap),
                      Expanded(
                        child: _UpperSlot(
                          key: ValueKey('upper-${round[i].letter}'),
                          letter: round[i],
                          matched: _matched.contains(round[i].letter),
                          demonstrating: _demo == round[i].letter,
                          onAccept: (lower) => _place(lower, round[i]),
                          onTap: () => _tapUpper(round[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: gap),
              SizedBox(
                height: BlockMetrics.minGrabTarget,
                child: Row(
                  children: [
                    for (final item in tray) ...[
                      SizedBox(
                        width: BlockMetrics.minGrabTarget,
                        child: _LowerTile(
                          key: ValueKey('lower-${item.letter}'),
                          letter: item,
                          selected: _selected == item.letter,
                          onTap: () => _tapLower(item),
                        ),
                      ),
                      SizedBox(width: gap),
                    ],
                    const Spacer(),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.badge_rounded,
                      onPressed: _goToName,
                    ),
                    SizedBox(width: gap),
                    RoundActionButton(
                      key: const ValueKey('next'),
                      icon: Icons.chevron_right_rounded,
                      highlighted: _solved,
                      onPressed: _nextRound,
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

/// 大写字母的落位区。既接受拖拽，也接受「先选中小写再点这里」。
class _UpperSlot extends StatelessWidget {
  const _UpperSlot({
    super.key,
    required this.letter,
    required this.matched,
    required this.demonstrating,
    required this.onAccept,
    required this.onTap,
  });

  final LetterItem letter;
  final bool matched;

  /// 正在演示正确配对——**不是错误状态**，配色也刻意与「配对成功」同族。
  final bool demonstrating;

  final void Function(LetterItem lower) onAccept;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 配好了、或正在演示，都显示成「Aa」。演示态与完成态长得几乎一样，
    // 只差一点透明度——他看到的是「本来该是这样」，不是「你错了」。
    final paired = matched || demonstrating;

    return DragTarget<LetterItem>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            scale: candidate.isNotEmpty ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Opacity(
              opacity: demonstrating && !matched ? 0.75 : 1.0,
              child: LetterTile(
                letter: paired
                    ? '${letter.letter}${letter.lowercase}'
                    : letter.letter,
                color: matched
                    ? RoundActionButton.doneColor
                    : letterColor(letter.letter),
                expression: paired
                    ? BlockExpression.happy
                    : BlockExpression.idle,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 托盘里的小写字母。可拖、可点。
class _LowerTile extends StatelessWidget {
  const _LowerTile({
    super.key,
    required this.letter,
    required this.selected,
    required this.onTap,
  });

  final LetterItem letter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = LetterTile(
      letter: letter.lowercase,
      color: letterColor(letter.letter),
      showFace: false,
      expression: BlockExpression.idle,
    );

    return Listener(
      // 与托盘里其他可按的东西一样用原始 Listener 抢在手势竞技场前面——
      // 但这里只负责「按下去有动静」，落位交给 Draggable / GestureDetector。
      onPointerDown: (_) => onTap(),
      child: Draggable<LetterItem>(
        data: letter,
        feedback: SizedBox(
          width: BlockMetrics.minGrabTarget,
          height: BlockMetrics.minGrabTarget,
          child: Opacity(opacity: 0.9, child: tile),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: AnimatedScale(
          scale: selected ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 160),
          child: tile,
        ),
      ),
    );
  }
}
