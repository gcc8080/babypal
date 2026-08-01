import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_bus.dart';
import '../../core/audio/audio_providers.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/audio/sfx.dart';
import '../../core/block/block_board.dart';
import '../../core/block/block_board_controller.dart';
import '../../core/block/block_model.dart';
import '../../core/block/snap_grid.dart';
import '../../core/design/controls.dart';
import '../../core/design/tokens.dart';
import 'addition.dart';
import 'addition_page.dart';

/// 等式槽 `[3][+][2][=][?]`。
///
/// 见 numbers-addition 规格「等式槽」。这是他看动画时**实际在做的事**——
/// 前面三个玩法讲的是数量，这一个讲的是数量与符号的对应。
///
/// 三条设计取舍：
///
/// 1. **积木区是一台随手可用的算盘，不是装饰。** 两个加数一直摆在那儿，他可以
///    直接把它们拖到一起合体、数出得数，再去选答案。这不算作弊——**用积木算
///    出来正是我们想要的行为**，只是没人逼他这么做。
/// 2. **答对答错走同一条路：都用积木演示一遍。** 见规格「填入错误答案」——
///    不出红叉、不扣分、不倒计时，而是把 3 和 2 真的合起来给他看，然后让他
///    再试。答对时也演示，于是「演示」不是错误的信号，只是答案的样子。
/// 3. **候选答案的位置每题轮换**，干扰项紧贴正确答案（±1）。固定位置他会
///    改记位置；干扰项差得远则一眼可排除，等于没考。
class EquationPage extends ConsumerStatefulWidget {
  const EquationPage({super.key});

  @override
  ConsumerState<EquationPage> createState() => _EquationPageState();
}

/// 一道题的三个阶段。
enum _Phase {
  /// 等他作答。
  asking,

  /// 正在用积木演示得数——答对答错都要走这一步。
  demonstrating,

  /// 答对了，停在这儿让他看着，「下一题」点亮。
  solved,
}

class _EquationPageState extends ConsumerState<EquationPage> {
  static const String _idA = 'addend-a';
  static const String _idB = 'addend-b';
  static const String _idSum = 'sum';

  static const int _colorA = 1; // 珊瑚
  static const int _colorB = 3; // 紫罗兰
  static const int _colorSum = 4; // 薄荷绿

  /// 演示完到复位之间的停顿。
  ///
  /// 双语播报「三加二等于五 / three plus two equals five」约 3 秒，留到 3.4 秒
  /// 让他把话听完、把积木看完，再把槽清空重来。清早了等于话没说完就翻页。
  static const Duration _demoHold = Duration(milliseconds: 3400);

  int _problemIndex = 0;
  AdditionProblem get _problem => kAdditionProblems[_problemIndex];

  BlockBoardController? _controller;
  _Phase _phase = _Phase.asking;

  /// 槽里当前填着的数，未作答时为 null。
  int? _answer;

  Timer? _demoTimer;

  AudioBus get _audio => ref.read(audioBusProvider);

  /// 念一遍还是念两遍，由家长设置说了算。**每次现读**，因此设置页一关下一句就生效。
  NarrationStyle get _narration => ref.read(narrationProvider);

  List<int> get _choices => equationChoices(_problem, _problemIndex);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askQuestion());
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // ─── 题目 ──────────────────────────────────────────────────────────

  /// 把两个加数摆回积木区，中间隔开。
  ///
  /// 见 [AdditionPage] 同名方法：首次布局在 build 期间发生，因此这里不自己
  /// `setState`——调用方要么本来就在 build 中，要么自己包了 `setState`。
  void _layOutAddends() {
    final controller = _controller;
    if (controller == null) return;

    for (final id in controller.blocks.map((b) => b.id).toList()) {
      controller.removeBlock(id);
    }
    controller
      ..addBlock(
        BlockBody(
          id: _idA,
          colorIndex: _colorA,
          widthUnits: _problem.a,
          anchor: const GridCell(0, 0),
        ),
      )
      ..addBlock(
        BlockBody(
          id: _idB,
          colorIndex: _colorB,
          widthUnits: _problem.b,
          anchor: GridCell(kAdditionColumns - _problem.b, 0),
        ),
      );
  }

  void _askQuestion({bool interrupt = false}) {
    unawaited(
      _audio.speakSequence(
        _narration.additionQuestion(_problem.a, _problem.b),
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  void _nextProblem() {
    _demoTimer?.cancel();
    setState(() {
      _problemIndex = (_problemIndex + 1) % kAdditionProblems.length;
      _answer = null;
      _phase = _Phase.asking;
      _layOutAddends();
    });
    _audio.playSfx(Sfx.pickup);
    _askQuestion(interrupt: true);
  }

  // ─── 作答 ──────────────────────────────────────────────────────────

  /// 把 [value] 填进结果槽。拖拽与点选两条通道都汇到这里。
  void _answerWith(int value) {
    if (_phase != _Phase.asking) return;

    setState(() {
      _answer = value;
      _phase = _Phase.demonstrating;
    });
    _audio.playSfx(Sfx.snap);
    _demonstrate(correct: value == _problem.sum);
  }

  /// 用积木演示得数：把两个加数真的合起来。
  ///
  /// **答对答错都走这一步**，规格要求填错时「用积木演示 3+2 实际合体为 5，
  /// 然后允许重试」。答对时也演示，这样「演示」就不是一个错误信号——
  /// 它只是「答案长什么样」，不带任何评判。
  void _demonstrate({required bool correct}) {
    _mutate((c) {
      // 他可能已经自己把积木合起来了，那就不用再合一次。
      if (c.blocks.length == 2) {
        c.mergeBlocks(c.blocks.first.id, c.blocks.last.id);
      }
    });

    unawaited(
      _audio.speakSequence(
        _narration.addition(_problem.a, _problem.b),
        policy: VoicePolicy.interrupt,
      ),
    );

    _demoTimer?.cancel();
    _demoTimer = Timer(_demoHold, () {
      if (!mounted) return;
      if (correct) {
        setState(() => _phase = _Phase.solved);
        return;
      }
      // 答错：把槽清空、积木摆回去，让他接着试。**没有任何惩罚**——
      // 不扣分、不记次数、不变红。
      setState(() {
        _answer = null;
        _phase = _Phase.asking;
        _layOutAddends();
      });
    });
  }

  /// 合体规则：两个加数拼成得数。他自己动手合也走这条。
  BlockBody? _resolveMerge(BlockBody moving, BlockBody target) {
    if (moving.heightUnits != target.heightUnits) return null;
    final width = moving.widthUnits + target.widthUnits;
    if (width > kAdditionColumns) return null;

    final ma = moving.anchor;
    final ta = target.anchor;
    final GridCell? anchor;
    if (ma != null && ta != null) {
      anchor = GridCell(math.min(ma.col, ta.col), ma.row);
    } else {
      anchor = null;
    }

    return BlockBody(
      id: _idSum,
      colorIndex: _colorSum,
      widthUnits: width,
      heightUnits: target.heightUnits,
      expression: BlockExpression.happy,
      anchor: anchor,
    );
  }

  /// 改动积木。
  ///
  /// 这个页面**刻意不监听控制器**：等式条与托盘都不依赖积木状态，`BlockBoard`
  /// 自己会重绘。加了监听反而会出事——`updateGrid` 是在 `LayoutBuilder` 的
  /// builder 里调的，监听里一 `setState` 就是「build 期间标记重建」。
  ///
  /// 由此也带来一条语义：**他自己把积木合起来不算作答**。那只是他在用算盘，
  /// 选哪个答案始终是他的决定。
  void _mutate(void Function(BlockBoardController controller) action) {
    final controller = _controller;
    if (controller != null) action(controller);
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  SnapGrid _buildGrid(BoxConstraints constraints) {
    final gap = BlockMetrics.gap;
    final cell = math.min(
      (constraints.maxWidth - gap * 2) / kAdditionColumns,
      constraints.maxHeight,
    );
    return SnapGrid(
      columns: kAdditionColumns,
      rows: 1,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - cell * kAdditionColumns) / 2).clamp(
          0,
          double.infinity,
        ),
        ((constraints.maxHeight - cell) / 2).clamp(0, double.infinity),
      ),
    );
  }

  void _playBoardSound(BlockSoundEvent event) {
    _audio.playSfx(switch (event) {
      BlockSoundEvent.tap => Sfx.tap,
      BlockSoundEvent.pickup => Sfx.pickup,
      BlockSoundEvent.snap => Sfx.snap,
      BlockSoundEvent.merge => Sfx.merge,
      BlockSoundEvent.split => Sfx.split,
      BlockSoundEvent.returned => Sfx.returned,
    });
  }

  void _goToMerge() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const AdditionPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(BlockMetrics.gap / 2),
          child: Column(
            children: [
              _EquationRow(
                problem: _problem,
                answer: _answer,
                solved: _phase == _Phase.solved,
                accepting: _phase == _Phase.asking,
                onDropped: _answerWith,
                onReplay: () => _phase == _Phase.asking
                    ? _askQuestion(interrupt: true)
                    : unawaited(
                        _audio.speakSequence(
                          _narration.addition(_problem.a, _problem.b),
                          policy: VoicePolicy.interrupt,
                        ),
                      ),
              ),
              SizedBox(height: BlockMetrics.gap / 2),
              // 积木区：随手可用的算盘。他可以自己把两块拖到一起数出得数。
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final grid = _buildGrid(constraints);
                    if (_controller == null) {
                      _controller = BlockBoardController(
                        grid: grid,
                        mergeResolver: _resolveMerge,
                        onSound: _playBoardSound,
                      );
                      _layOutAddends();
                    } else {
                      _controller!.updateGrid(grid);
                    }
                    return BlockBoard(controller: _controller!);
                  },
                ),
              ),
              SizedBox(height: BlockMetrics.gap / 2),
              SizedBox(
                height: BlockMetrics.minGrabTarget,
                child: Row(
                  children: [
                    for (final value in _choices) ...[
                      _ChoiceTile(
                        key: ValueKey('choice-$value'),
                        value: value,
                        enabled: _phase == _Phase.asking,
                        onPicked: () => _answerWith(value),
                      ),
                      SizedBox(width: BlockMetrics.gap / 2),
                    ],
                    const Spacer(),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.call_merge_rounded,
                      onPressed: _goToMerge,
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('next'),
                      icon: Icons.arrow_forward_rounded,
                      highlighted: _phase == _Phase.solved,
                      onPressed: _nextProblem,
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

/// `[3] + [2] = [?]`。结果槽是拖拽通道的落点。
class _EquationRow extends StatelessWidget {
  const _EquationRow({
    required this.problem,
    required this.answer,
    required this.solved,
    required this.accepting,
    required this.onDropped,
    required this.onReplay,
  });

  final AdditionProblem problem;
  final int? answer;
  final bool solved;
  final bool accepting;
  final void Function(int value) onDropped;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    const height = BlockMetrics.minGrabTarget * 1.15;

    return SizedBox(
      height: height,
      child: FittedBox(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NumberTile(label: '${problem.a}', colorIndex: 1, onTap: onReplay),
            const _Operator('+'),
            _NumberTile(label: '${problem.b}', colorIndex: 3, onTap: onReplay),
            const _Operator('='),
            _AnswerSlot(
              key: const ValueKey('slot'),
              answer: answer,
              solved: solved,
              accepting: accepting,
              onDropped: onDropped,
            ),
          ],
        ),
      ),
    );
  }
}

/// 结果槽。
///
/// 空着时是虚线框；填上后显示数字。**答错不变红**——见规格「填入错误答案」，
/// 界面上不出现任何否定信号，纠正完全靠积木演示。
class _AnswerSlot extends StatelessWidget {
  const _AnswerSlot({
    super.key,
    required this.answer,
    required this.solved,
    required this.accepting,
    required this.onDropped,
  });

  final int? answer;
  final bool solved;
  final bool accepting;
  final void Function(int value) onDropped;

  @override
  Widget build(BuildContext context) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => accepting,
      onAcceptWithDetails: (details) => onDropped(details.data),
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        return _TileShell(
          // 拖到上方时整个槽长大一圈——3 岁需要「就是这儿」的明确信号。
          scale: hovering ? 1.12 : 1.0,
          color: solved ? RoundActionButton.doneColor : Colors.white,
          border: answer == null
              ? Border.all(
                  color: BlockColors.ink.withValues(
                    alpha: hovering ? 0.6 : 0.3,
                  ),
                  width: 3,
                )
              : null,
          child: answer == null
              ? const SizedBox.shrink()
              : _Numeral(
                  '$answer',
                  color: solved ? Colors.white : BlockColors.ink,
                ),
        );
      },
    );
  }
}

/// 托盘里的候选答案。
///
/// 双通道：**点一下直接填进槽**（只有一个槽，没有歧义，比「先选中再点槽」
/// 少一步），**拖进槽**同样可以。按下即有挤压与音效，不等抬手判定。
class _ChoiceTile extends StatefulWidget {
  const _ChoiceTile({
    super.key,
    required this.value,
    required this.enabled,
    required this.onPicked,
  });

  final int value;
  final bool enabled;
  final VoidCallback onPicked;

  @override
  State<_ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<_ChoiceTile> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tile = _TileShell(
      scale: _pressed ? BlockMetrics.squashScale : 1.0,
      color: Colors.white,
      opacity: widget.enabled ? 1.0 : 0.4,
      child: _Numeral('${widget.value}', color: BlockColors.ink),
    );

    if (!widget.enabled) return tile;

    // Listener 只管「按下立刻有反应」，不消费事件；点击与拖拽的归属仍由
    // 下面的 GestureDetector / Draggable 在手势竞技场里正常裁决。
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: Draggable<int>(
        data: widget.value,
        onDragStarted: () => _setPressed(false),
        feedback: Material(
          color: Colors.transparent,
          child: _TileShell(
            scale: 1.1,
            color: Colors.white,
            child: _Numeral('${widget.value}', color: BlockColors.ink),
          ),
        ),
        childWhenDragging: _TileShell(
          scale: 1.0,
          color: Colors.white,
          opacity: 0.3,
          child: _Numeral('${widget.value}', color: BlockColors.ink),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPicked,
          child: tile,
        ),
      ),
    );
  }
}

/// 等式里的固定数字（两个加数）。
class _NumberTile extends StatelessWidget {
  const _NumberTile({
    required this.label,
    required this.colorIndex,
    required this.onTap,
  });

  final String label;
  final int colorIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _TileShell(
        scale: 1.0,
        color: BlockColors.forIndex(colorIndex),
        child: _Numeral(label, color: Colors.white),
      ),
    );
  }
}

/// 等式与托盘里所有方块格子的共同外壳，保证尺寸一致。
class _TileShell extends StatelessWidget {
  const _TileShell({
    required this.child,
    required this.scale,
    required this.color,
    this.border,
    this.opacity = 1.0,
  });

  final Widget child;
  final double scale;
  final Color color;
  final BoxBorder? border;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: Opacity(
        opacity: opacity,
        child: SizedBox(
          width: BlockMetrics.minGrabTarget,
          height: BlockMetrics.minGrabTarget,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(BlockMetrics.blockRadius),
              border: border,
              boxShadow: border != null
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _Numeral extends StatelessWidget {
  const _Numeral(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: BlockMetrics.minGrabTarget * 0.5,
        fontWeight: FontWeight.w700,
        height: 1.0,
        color: color,
      ),
    );
  }
}

class _Operator extends StatelessWidget {
  const _Operator(this.symbol);

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: BlockMetrics.gap * 0.4),
      child: Text(
        symbol,
        style: TextStyle(
          fontSize: BlockMetrics.minGrabTarget * 0.42,
          fontWeight: FontWeight.w700,
          height: 1.0,
          color: BlockColors.ink,
        ),
      ),
    );
  }
}
