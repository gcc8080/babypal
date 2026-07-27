import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/audio/audio_bus.dart';
import '../../core/audio/audio_providers.dart';
import '../../core/audio/sfx.dart';
import '../../core/block/block_model.dart';
import '../../core/content/content_providers.dart';
import '../../core/content/models.dart';
import '../../core/design/controls.dart';
import '../../core/design/tokens.dart';
import '../../core/design/glyph_tile.dart';
import 'outline_page.dart';
import 'letters.dart';

/// 「A is for Apple」交互版。
///
/// 见 letters 规格的两条要求：
///
/// 1. **字母名与音素分开播报**，两次可区分，不得合并成一条音频。
/// 2. **飞入的名词图全部是正确答案**，点哪张都庆祝，不存在错误选项。
///
/// 第二条是这个玩法的全部设计。他看的那些字母视频就是这个格式——A、然后
/// 苹果蚂蚁飞机一个个出来。做成「三选一，选对了才夸你」会把一个他本来看得
/// 很开心的东西变成考试，而三岁的孩子没有考试这个概念，只有「我又做错了」。
///
/// 翻页只用上一个 / 下一个，不做 26 个字母的横向长条：长条要滑，滑要练，
/// 而字母表的顺序他早就会唱了。
class LettersPage extends ConsumerStatefulWidget {
  const LettersPage({super.key});

  @override
  ConsumerState<LettersPage> createState() => _LettersPageState();
}

class _LettersPageState extends ConsumerState<LettersPage>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  /// 被点过的那张卡（庆祝中），没有则为 null。
  String? _cheeredId;

  /// 名词卡飞入动画。在 `initState` 里建而不是 `late final` 惰性初始化——
  /// 惰性初始化会让 `dispose()` 成为首次访问，那时组件树已失活，
  /// `createTicker` 查祖先节点会直接抛异常（见百格板 4.3 的同名修复）。
  late final AnimationController _flyIn;

  Timer? _cheerTimer;

  AudioBus get _audio => ref.read(audioBusProvider);

  List<LetterItem> get _letters => ref.read(contentLibraryProvider).letters;

  @override
  void initState() {
    super.initState();
    _flyIn = AnimationController(
      vsync: this,
      duration: kWordFlyIn + kWordStagger * (kMaxWordCards - 1),
    );
    // 进页面就把第一个字母演一遍：三岁的他不会先想「我该点哪里」，
    // 而是等着看会发生什么。第一帧之后再放，此时 provider 才可读。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _present(interrupt: true);
    });
  }

  @override
  void dispose() {
    _cheerTimer?.cancel();
    _flyIn.dispose();
    super.dispose();
  }

  // ─── 操作 ──────────────────────────────────────────────────────────

  LetterItem? get _letter {
    final letters = _letters;
    if (letters.isEmpty) return null;
    return letters[_index % letters.length];
  }

  List<NounItem> get _words {
    final letter = _letter;
    if (letter == null) return const [];
    return ref
        .read(contentLibraryProvider)
        .wordsFor(letter)
        .take(kMaxWordCards)
        .toList();
  }

  /// 演一遍当前字母：字母名 → 音素 → 三张卡依次飞入并各报英文名。
  void _present({bool interrupt = false}) {
    final letter = _letter;
    if (letter == null) return;

    setState(() => _cheeredId = null);
    _cheerTimer?.cancel();
    _flyIn.forward(from: 0);

    unawaited(
      _audio.speakSequence(
        LetterNarration.letterIntro(letter, _words),
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  void _step({required bool forward}) {
    final count = _letters.length;
    if (count == 0) return;
    _audio.playSfx(Sfx.tap);
    setState(() => _index = nextLetterIndex(_index, count, forward: forward));
    _present(interrupt: true);
  }

  /// 点一张名词卡。
  ///
  /// **每一张都走同一条路径**——没有 `if (correct)`，因为没有不正确的那张。
  /// 规格「点击任意图片 → 三张图行为一致」在代码里就该长这样：连一个用来
  /// 判对错的分支都不存在，就没人能在以后不小心加回来。
  void _tapWord(NounItem noun) {
    _audio.playSfx(Sfx.merge);
    setState(() => _cheeredId = noun.id);
    unawaited(
      _audio.speakSequence(
        LetterNarration.wordTapped(noun),
        policy: VoicePolicy.interrupt,
      ),
    );
    _cheerTimer?.cancel();
    _cheerTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _cheeredId = null);
    });
  }

  /// 点字母积木本身：只重放字母名与音素，不重放卡片。
  ///
  /// 他反复点字母的时候要的是那个音，不是再看一遍三张图飞进来。
  void _tapLetter() {
    final letter = _letter;
    if (letter == null) return;
    _audio.playSfx(Sfx.tap);
    unawaited(
      _audio.speakSequence(
        LetterNarration.letterAndPhoneme(letter),
        policy: VoicePolicy.interrupt,
      ),
    );
  }

  /// 字母模块的玩法之间一律 `pushReplacement`，返回键始终直接回星球地图，
  /// 不会越按越深——与数字、加法两个模块的规矩一致。
  void _goToOutline() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const OutlinePage()),
    );
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final letter = _letter;
    final words = _words;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(BlockMetrics.gap / 2),
          child: Column(
            children: [
              Expanded(
                child: letter == null
                    // 内容包读不到时静默留白：儿童端不能弹「暂无内容」。
                    ? const SizedBox.expand()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final side = constraints.maxHeight.clamp(
                            BlockMetrics.minGrabTarget,
                            constraints.maxWidth * 0.34,
                          );
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                key: const ValueKey('letter'),
                                width: side,
                                height: side,
                                child: _PressableLetter(
                                  letter: letter,
                                  onPressed: _tapLetter,
                                ),
                              ),
                              SizedBox(width: BlockMetrics.gap),
                              Expanded(
                                child: _WordRow(
                                  words: words,
                                  flyIn: _flyIn,
                                  cheeredId: _cheeredId,
                                  onTap: _tapWord,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              SizedBox(height: BlockMetrics.gap / 2),
              SizedBox(
                height: BlockMetrics.minGrabTarget,
                child: Row(
                  children: [
                    RoundActionButton(
                      key: const ValueKey('prev'),
                      icon: Icons.chevron_left_rounded,
                      onPressed: () => _step(forward: false),
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('next'),
                      icon: Icons.chevron_right_rounded,
                      onPressed: () => _step(forward: true),
                    ),
                    const Spacer(),
                    RoundActionButton(
                      key: const ValueKey('replay'),
                      icon: Icons.replay_rounded,
                      onPressed: () => _present(interrupt: true),
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.grid_view_rounded,
                      onPressed: _goToOutline,
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

/// 字母积木：按下即挤压、即发声。
class _PressableLetter extends StatefulWidget {
  const _PressableLetter({required this.letter, required this.onPressed});

  final LetterItem letter;
  final VoidCallback onPressed;

  @override
  State<_PressableLetter> createState() => _PressableLetterState();
}

class _PressableLetterState extends State<_PressableLetter> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // 与 PressableTile 同样用原始 Listener：手势竞技场要等到抬手才出结果，
      // 而「触摸必有回应」要的是按下那一瞬间就有动静。
      onPointerDown: (_) {
        setState(() => _pressed = true);
        widget.onPressed();
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? BlockMetrics.squashScale : 1.0,
        duration: Duration(milliseconds: _pressed ? 90 : 320),
        curve: _pressed ? Curves.easeOut : Curves.elasticOut,
        child: GlyphTile(
          glyph: widget.letter.letter,
          color: letterColor(widget.letter.letter),
          expression: _pressed ? BlockExpression.happy : BlockExpression.idle,
        ),
      ),
    );
  }
}

/// 飞入的名词卡。
class _WordRow extends StatelessWidget {
  const _WordRow({
    required this.words,
    required this.flyIn,
    required this.cheeredId,
    required this.onTap,
  });

  final List<NounItem> words;
  final AnimationController flyIn;
  final String? cheeredId;
  final void Function(NounItem) onTap;

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) return const SizedBox.expand();

    final total = flyIn.duration ?? kWordFlyIn;
    return AnimatedBuilder(
      animation: flyIn,
      builder: (context, _) {
        return Row(
          // **必须 stretch**：卡片用 `expand` 撑满高度，靠的就是父级给的紧
          // 约束。默认的 `center` 会给松约束，卡片高度直接塌成 0。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < words.length; i++) ...[
              if (i > 0) SizedBox(width: BlockMetrics.gap / 2),
              Expanded(
                child: _WordCard(
                  key: ValueKey('word-${words[i].id}'),
                  noun: words[i],
                  progress: _progressFor(i, total),
                  cheering: cheeredId == words[i].id,
                  onTap: () => onTap(words[i]),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 第 i 张卡自己的 0→1 进度，由总时间轴切出来。
  double _progressFor(int index, Duration total) {
    final start = kWordStagger.inMilliseconds * index / total.inMilliseconds;
    final end = start + kWordFlyIn.inMilliseconds / total.inMilliseconds;
    return ((flyIn.value - start) / (end - start)).clamp(0.0, 1.0);
  }
}

class _WordCard extends StatelessWidget {
  const _WordCard({
    super.key,
    required this.noun,
    required this.progress,
    required this.cheering,
    required this.onTap,
  });

  final NounItem noun;
  final double progress;
  final bool cheering;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    return Opacity(
      // 用进度本身淡入，而不是 eased——easeOutBack 会冲过 1 再回落，
      // 拿它当透明度会先过曝再压回来。
      opacity: progress.clamp(0.0, 1.0),
      child: Transform.translate(
        // 从右侧飞进来。位移随卡片宽度走，平板上才不会显得只挪了一点点。
        offset: Offset((1 - eased) * 120, 0),
        child: Transform.scale(
          scale: cheering ? 1.12 : 1.0,
          child: PressableTile(
            onPressed: onTap,
            expand: true,
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(BlockMetrics.gap / 2),
              child: SvgPicture.asset(
                'assets/icons/${noun.iconKey}.svg',
                fit: BoxFit.contain,
                // 图标缺失时留白而不是显示错误占位图——一个红叉出现在
                // 「点哪张都对」的玩法里是最糟糕的画面。
                placeholderBuilder: (_) => const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
