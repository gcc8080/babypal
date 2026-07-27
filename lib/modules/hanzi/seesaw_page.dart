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
import '../../core/content/pack_loader.dart';
import '../../core/design/controls.dart';
import '../../core/design/glyph_tile.dart';
import '../../core/design/tokens.dart';
import 'hanzi.dart';
import 'pictograph_page.dart';

/// 托盘里给几个候选字。
///
/// 三个：横屏放得下三块 ≥90dp 的积木加两个按钮，再多就得压缩尺寸而击穿抓取
/// 红线。三岁的他一次能同时端详的东西本来也就三四样。
const int kSeesawChoices = 3;

/// 反义词跷跷板。
///
/// 见 hanzi 规格「反义词跷跷板」：配对数据取自内容包的 `antonyms`；配错时
/// **演示正确答案然后允许重试，无红叉**。
///
/// 跷跷板是这一课唯一说得清的比喻：反义词不是「两个不一样的字」，而是**一对
/// 分不开的字**——一头空着就翘着，配上了才平。这个道理讲不明白，但他在小区
/// 里坐过跷跷板，一眼就懂。
///
/// 与大小写配对同一套「没有答错」的写法：放错了，跷跷板自己把正确的那个字请
/// 上来配好、停一下、再放开。他放的那块原样留在托盘里，次数不限，不留痕迹。
class SeesawPage extends ConsumerStatefulWidget {
  const SeesawPage({super.key});

  @override
  ConsumerState<SeesawPage> createState() => _SeesawPageState();
}

class _SeesawPageState extends ConsumerState<SeesawPage> {
  int _pairIndex = 0;

  /// 他放上去的那个字。null 表示还没配对成功。
  ///
  /// 存字而不是存 bool：一个题面可能有**多个都对的答案**（高—矮 与 高—低），
  /// 座位上该显示的是他自己放的那一个，不是内容包里排第一的那一个。
  String? _placed;

  /// 正在演示正确答案——**不是错误状态**。
  bool _demo = false;

  /// 点选通道里选中的候选字。
  String? _selected;

  Timer? _demoTimer;

  AudioBus get _audio => ref.read(audioBusProvider);
  ContentLibrary get _library => ref.read(contentLibraryProvider);

  List<AntonymPair> get _pairs => _library.antonyms;

  AntonymPair? get _pair {
    final all = _pairs;
    if (all.isEmpty) return null;
    return all[_pairIndex % all.length];
  }

  bool get _solved => _placed != null;

  /// 这一关**全部**说得通的答案。
  ///
  /// 内容包里「高」既配「矮」也配「低」，「生」既配「死」也配「熟」。这两个
  /// 都对，判定和干扰项都得按这个集合来。
  Set<String> get _answers {
    final pair = _pair;
    if (pair == null) return const {};
    return antonymsOf(pair.left, _library);
  }

  /// 托盘里的候选字：正确答案 + 两个来自别的反义词对的字。
  ///
  /// 干扰项**取自其他反义词对**而不是随便找几个字——他要做的判断因此是
  /// 「哪个跟『大』是一对」，而不是「哪个字我认识」。
  ///
  /// 干扰项里必须剔掉**这一关所有说得通的答案**：内容包里「高」既配「矮」
  /// 也配「低」，把「低」当干扰项摆出来，他放上去却被判成要演示，就是在教
  /// 他一件假事。
  ///
  /// 用 `Random(_pairIndex)` 而不是全局随机：同一关反复重建组件树时顺序必须
  /// 一样，否则他会看见候选字自己在跳。
  List<String> get _choices {
    final pair = _pair;
    if (pair == null) return const [];

    final answers = _answers;
    final others = <String>[];
    for (final other in _pairs) {
      if (other == pair) continue;
      others
        ..add(other.left)
        ..add(other.right);
    }
    others.removeWhere((c) => c == pair.left || answers.contains(c));

    final picked = <String>[pair.right];
    for (var i = 0; i < kSeesawChoices - 1 && i < others.length; i++) {
      picked.add(others[(_pairIndex * 3 + i) % others.length]);
    }
    return picked.toSet().toList()..shuffle(math.Random(_pairIndex * 17 + 3));
  }

  /// 当前压在右座上的字：配对成功是**他放的那个**，演示中是系统请上来的。
  String? get _seated => _placed ?? (_demo ? _pair?.right : null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announcePrompt();
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    super.dispose();
  }

  // ─── 操作 ──────────────────────────────────────────────────────────

  void _announcePrompt() {
    final item = _promptItem;
    if (item == null) return;
    unawaited(
      _audio.speakSequence(
        HanziNarration.character(item),
        policy: VoicePolicy.interrupt,
      ),
    );
  }

  HanziItem? get _promptItem {
    final pair = _pair;
    return pair == null ? null : _library.hanziByChar(pair.left);
  }

  /// 把 [char] 放到右座上。拖拽与点选两条通道都走这里。
  void _place(String char) {
    final pair = _pair;
    if (pair == null || _solved) return;

    // 说得通的答案都算数，不只是内容包里排第一的那个。
    if (_answers.contains(char)) {
      _audio.playSfx(Sfx.merge);
      _demoTimer?.cancel();
      setState(() {
        _placed = char;
        _demo = false;
        _selected = null;
      });
      _speak(pair.left, char);
      return;
    }

    _demonstrate();
  }

  /// 演示这一对**本来**是什么样。
  ///
  /// 刻意用 `snap` 而不是任何带挫败感的音：他听到的是「啪，配好了」，和配对
  /// 成功时同一族的声音，只是没有庆祝的那一下。他放错的那块留在托盘里没动。
  void _demonstrate() {
    final pair = _pair;
    if (pair == null) return;
    _audio.playSfx(Sfx.snap);
    setState(() {
      _demo = true;
      _selected = null;
    });
    // 演示用内容包里排第一的那个答案——多个都对时总得挑一个演。
    _speak(pair.left, pair.right);

    _demoTimer?.cancel();
    _demoTimer = Timer(kSeesawDemoHold, () {
      if (mounted) setState(() => _demo = false);
    });
  }

  /// 把这一对念出来。
  void _speak(String a, String b) {
    final left = _library.hanziByChar(a);
    final right = _library.hanziByChar(b);
    if (left == null || right == null) return;
    unawaited(
      _audio.speakSequence(
        HanziNarration.antonym(left, right),
        policy: VoicePolicy.interrupt,
      ),
    );
  }

  /// 点选通道：先点候选字选中，再点右座落位。
  void _tapChoice(String char) {
    _audio.playSfx(Sfx.tap);
    setState(() => _selected = _selected == char ? null : char);
  }

  void _tapSeat() {
    final selected = _selected;
    if (selected == null) {
      // 没选中任何候选时，点座位只是重听一遍题目——**不算一次尝试**。
      _audio.playSfx(Sfx.tap);
      _announcePrompt();
      return;
    }
    _place(selected);
  }

  void _tapPrompt() {
    _audio.playSfx(Sfx.tap);
    // 配好之后再点，念的是他配出来的那一对；还没配好就只念题面那个字。
    final pair = _pair;
    final placed = _placed;
    if (pair != null && placed != null) {
      _speak(pair.left, placed);
    } else {
      _announcePrompt();
    }
  }

  void _nextPair() {
    _demoTimer?.cancel();
    _audio.playSfx(Sfx.pickup);
    setState(() {
      _pairIndex = (_pairIndex + 1) % math.max(1, _pairs.length);
      _placed = null;
      _demo = false;
      _selected = null;
    });
    _announcePrompt();
  }

  void _goToPictograph() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const PictographPage()),
    );
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pair = _pair;
    final gap = BlockMetrics.gap / 2;
    final seated = _seated;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Column(
            children: [
              Expanded(
                child: pair == null
                    // 内容包读不到时静默留白：儿童端不能弹「暂无内容」。
                    ? const SizedBox.expand()
                    : _Seesaw(
                        prompt: pair.left,
                        seated: seated,
                        // 一头空着就翘着，配上了才平——这个玩法的全部道理。
                        balanced: seated != null,
                        demonstrating: _demo && !_solved,
                        onPromptTap: _tapPrompt,
                        onSeatTap: _tapSeat,
                        onAccept: _place,
                      ),
              ),
              SizedBox(height: gap),
              SizedBox(
                height: BlockMetrics.minGrabTarget,
                child: Row(
                  children: [
                    for (final char in _choices) ...[
                      if (_placed != char)
                        SizedBox(
                          width: BlockMetrics.minGrabTarget,
                          child: _ChoiceTile(
                            key: ValueKey('choice-$char'),
                            char: char,
                            selected: _selected == char,
                            onTap: () => _tapChoice(char),
                          ),
                        ),
                      SizedBox(width: gap),
                    ],
                    const Spacer(),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.landscape_rounded,
                      onPressed: _goToPictograph,
                    ),
                    SizedBox(width: gap),
                    RoundActionButton(
                      key: const ValueKey('next'),
                      icon: Icons.chevron_right_rounded,
                      highlighted: _solved,
                      onPressed: _nextPair,
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

/// 跷跷板本体：支点 + 横杆 + 两个座位。
class _Seesaw extends StatelessWidget {
  const _Seesaw({
    required this.prompt,
    required this.seated,
    required this.balanced,
    required this.demonstrating,
    required this.onPromptTap,
    required this.onSeatTap,
    required this.onAccept,
  });

  final String prompt;
  final String? seated;
  final bool balanced;
  final bool demonstrating;
  final VoidCallback onPromptTap;
  final VoidCallback onSeatTap;
  final void Function(String char) onAccept;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final beamWidth = math.min(constraints.maxWidth * 0.92, 620.0);
        // 上限跟着可用高度走，否则窄屏上座位会把横杆顶出画面。
        final seatLimit = math.max(
          BlockMetrics.minGrabTarget,
          constraints.maxHeight * 0.45,
        );
        final seat = (beamWidth * 0.24).clamp(
          BlockMetrics.minGrabTarget,
          seatLimit,
        );
        final barHeight = seat * 0.12;
        final fulcrum = seat * 0.34;
        // 翘起那一头比水平时高出多少：整套东西的实际高度要算上它，
        // 否则居中会按「水平的跷跷板」算，翘起的一角就顶到上面去了。
        final lift = beamWidth / 2 * math.sin(kSeesawTilt);
        final assembly = math.min(
          fulcrum * 0.72 + barHeight + seat + lift,
          constraints.maxHeight,
        );

        // 整套居中，而不是贴着底。贴底在平板那种高屏幕上会把跷跷板压在下缘，
        // 上面留出一大片空地——真机上一眼看出来「这页没做完」。
        return Center(
          child: SizedBox(
            width: constraints.maxWidth,
            height: assembly,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: 0,
                  child: CustomPaint(
                    size: Size(fulcrum * 1.6, fulcrum),
                    painter: const _FulcrumPainter(),
                  ),
                ),
                Positioned(
                  bottom: fulcrum * 0.72,
                  child: AnimatedRotation(
                    // 配上了就摆平。转场稍慢一点，那一下「落下来」才看得见。
                    turns: balanced ? 0 : kSeesawTilt / (2 * math.pi),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutBack,
                    child: SizedBox(
                      width: beamWidth,
                      height: seat + barHeight,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: barHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: BlockColors.ink.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(
                                  barHeight / 2,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            bottom: barHeight,
                            width: seat,
                            height: seat,
                            child: Listener(
                              onPointerDown: (_) => onPromptTap(),
                              child: GlyphTile(
                                key: const ValueKey('prompt'),
                                glyph: prompt,
                                color: hanziColor(prompt),
                                expression: balanced
                                    ? BlockExpression.happy
                                    : BlockExpression.idle,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: barHeight,
                            width: seat,
                            height: seat,
                            child: _AnswerSeat(
                              seated: seated,
                              demonstrating: demonstrating,
                              onTap: onSeatTap,
                              onAccept: onAccept,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 右座。既接受拖拽，也接受「先选中候选再点这里」。
class _AnswerSeat extends StatelessWidget {
  const _AnswerSeat({
    required this.seated,
    required this.demonstrating,
    required this.onTap,
    required this.onAccept,
  });

  final String? seated;
  final bool demonstrating;
  final VoidCallback onTap;
  final void Function(String char) onAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, _) {
        final char = seated;
        return GestureDetector(
          key: const ValueKey('seat'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            scale: candidate.isNotEmpty ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Opacity(
              // 演示态与配对成功长得几乎一样，只差一点透明度——他看到的是
              // 「本来该是这样」，不是「你错了」。
              opacity: demonstrating ? 0.75 : 1.0,
              child: char == null
                  ? _EmptySeat()
                  : GlyphTile(
                      glyph: char,
                      color: hanziColor(char),
                      expression: BlockExpression.happy,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// 空座位。画成一个虚位以待的浅框，**不画问号也不画叉**。
class _EmptySeat extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: BlockColors.ink.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(side * 0.18),
            border: Border.all(
              color: BlockColors.ink.withValues(alpha: 0.20),
              width: 3,
            ),
          ),
        );
      },
    );
  }
}

class _FulcrumPainter extends CustomPainter {
  const _FulcrumPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = BlockColors.ink.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(_FulcrumPainter oldDelegate) => false;
}

/// 托盘里的候选字。可拖、可点。
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.char,
    required this.selected,
    required this.onTap,
  });

  final String char;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = GlyphTile(
      glyph: char,
      color: hanziColor(char),
      showFace: false,
      expression: BlockExpression.idle,
    );

    return Listener(
      // 与托盘里其他可按的东西一样用原始 Listener 抢在手势竞技场前面——
      // 这里只负责「按下去有动静」，落位交给 Draggable / GestureDetector。
      onPointerDown: (_) => onTap(),
      child: Draggable<String>(
        data: char,
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
