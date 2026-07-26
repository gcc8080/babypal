import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_bus.dart';
import '../../core/audio/audio_providers.dart';
import '../../core/audio/narration.dart';
import '../../core/audio/sfx.dart';
import '../../core/block/block_board.dart';
import '../../core/block/block_board_controller.dart';
import '../../core/block/block_model.dart';
import '../../core/block/snap_grid.dart';
import '../../core/design/controls.dart';
import '../../core/design/tokens.dart';
import 'addition.dart';
import 'decompose_page.dart';

/// 合体求和。
///
/// 见 numbers-addition 规格「合体加法」：两组积木拼接后合体为总数积木，
/// 并同步播报算式。
///
/// 他已经会背 10 以内加法表，所以这里**不是教他算**，而是让他看见「三块加
/// 两块真的变成了五块」——把背下来的口诀接回实物。这也正是他对着电视用实体
/// 积木在做的事。
///
/// 合体有三条触发路径，**全部保留**，因为 3 岁的手不稳，多一条路就少一次
/// 挫败：
///
/// 1. **拼到一起**——把 A 放到 B 旁边（同一行、边挨着边）。最容易，也最
///    贴合规格里「拼接」这个词。
/// 2. **叠到一起**——把 A 拖到 B 身上松手。
/// 3. **点两下**——点 A 选中，再点 B。点选通道，规格里的全局不变量。
class AdditionPage extends ConsumerStatefulWidget {
  const AdditionPage({super.key});

  @override
  ConsumerState<AdditionPage> createState() => _AdditionPageState();
}

class _AdditionPageState extends ConsumerState<AdditionPage> {
  static const String _idA = 'addend-a';
  static const String _idB = 'addend-b';
  static const String _idSum = 'sum';

  static const int _colorA = 1; // 珊瑚
  static const int _colorB = 3; // 紫罗兰
  static const int _colorSum = 4; // 薄荷绿：五个模块共用的「成了」色

  int _problemIndex = 0;
  AdditionProblem get _problem => kAdditionProblems[_problemIndex];

  BlockBoardController? _controller;
  bool _merged = false;
  bool _mutating = false;

  AudioBus get _audio => ref.read(audioBusProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askQuestion());
  }

  @override
  void dispose() {
    _controller?.removeListener(_onBoardChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ─── 题目 ──────────────────────────────────────────────────────────

  /// 摆出两个加数。
  ///
  /// 两块分置首尾两行、都靠左——起始状态必须一眼看出「这是两块，还没合」。
  /// 放同一行会在凑十题（`6+4`）上一开局就自己贴住，等于替他做完了。
  ///
  /// 刻意不走 [_mutate]，也不自己 `setState`：首次布局发生在 `LayoutBuilder`
  /// 的 builder 里（那时控制器刚建好），在 build 期间 `setState` 会直接抛。
  /// 调用方要么本来就在 build 中，要么自己包了 `setState`。
  void _layOutProblem() {
    final controller = _controller;
    if (controller == null) return;

    _mutating = true;
    try {
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
            anchor: const GridCell(0, kAdditionRows - 1),
          ),
        );
    } finally {
      _mutating = false;
    }
    _merged = false;
  }

  void _askQuestion({bool interrupt = false}) {
    unawaited(
      _audio.speakSequence(
        Narration.bilingualAdditionQuestion(_problem.a, _problem.b),
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  void _retry() {
    setState(_layOutProblem);
    _audio.playSfx(Sfx.returned);
    _askQuestion(interrupt: true);
  }

  void _nextProblem() {
    setState(() {
      _problemIndex = (_problemIndex + 1) % kAdditionProblems.length;
      _layOutProblem();
    });
    _audio.playSfx(Sfx.pickup);
    _askQuestion(interrupt: true);
  }

  // ─── 合体 ──────────────────────────────────────────────────────────

  /// 合体规则。返回 null 表示这两块不能合——引擎据此让积木退回，
  /// 且**不播放任何错误提示**。
  BlockBody? _resolveMerge(BlockBody moving, BlockBody target) {
    if (_merged) return null;
    if (moving.heightUnits != target.heightUnits) return null;

    final width = moving.widthUnits + target.widthUnits;
    if (width > kAdditionColumns) return null;

    // 合体结果落在两块中靠左的那一块的位置上。拖拽路径下 moving 已经
    // 离开格位（anchor 为 null），此时交给引擎回落到 target 原处。
    final ma = moving.anchor;
    final ta = target.anchor;
    final GridCell? anchor;
    if (ma != null && ta != null) {
      anchor = ma.col <= ta.col ? ma : ta;
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

  /// 点选通道：点 A 选中，再点 B 就合体。
  ///
  /// 返回 true 表示这次点击已被消费；返回 false 则交回引擎走默认选中态。
  bool _onBlockTapped(BlockBody block, Offset _) {
    final controller = _controller;
    if (controller == null) return false;

    final selectedId = controller.selectedId;
    if (selectedId == null || selectedId == block.id) return false;

    var merged = false;
    _mutate((c) => merged = c.mergeBlocks(selectedId, block.id) != null);
    return merged;
  }

  void _onBoardChanged() {
    if (!mounted || _mutating) return;
    final controller = _controller;
    if (controller == null) return;

    final blocks = controller.blocks;

    // 拼到一起了（同一行、边挨着边）→ 合体。规格说的是「拼接」，
    // 不是「叠在一起」：放到旁边比放到正上方好操作得多。
    if (!_merged && blocks.length == 2) {
      if (blocksAreJoined(blocks[0], blocks[1])) {
        _mutate((c) => c.mergeBlocks(blocks[0].id, blocks[1].id));
        return;
      }
    }

    final merged = blocks.length == 1 && blocks.first.id == _idSum;
    if (merged != _merged) {
      setState(() => _merged = merged);
      if (merged) _celebrate();
    }
  }

  void _celebrate() {
    // 「三 加 二 等于 五」，中英各一遍。
    unawaited(
      _audio.speakSequence(
        Narration.bilingualAddition(_problem.a, _problem.b),
        policy: VoicePolicy.interrupt,
      ),
    );
  }

  void _mutate(void Function(BlockBoardController controller) action) {
    final controller = _controller;
    if (controller == null) return;
    _mutating = true;
    try {
      action(controller);
    } finally {
      _mutating = false;
    }
    _onBoardChanged();
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  SnapGrid _buildGrid(BoxConstraints constraints) {
    final gap = BlockMetrics.gap;
    final byWidth = (constraints.maxWidth - gap * 2) / kAdditionColumns;
    final byHeight = (constraints.maxHeight - gap) / kAdditionRows;
    final cell = math.min(byWidth, byHeight);

    return SnapGrid(
      columns: kAdditionColumns,
      rows: kAdditionRows,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - cell * kAdditionColumns) / 2).clamp(
          0,
          double.infinity,
        ),
        0,
      ),
    );
  }

  /// 三个玩法接成一个环：合体 → 分解 → 等式 → 合体。图标画的是**下一站**。
  void _goToDecompose() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DecomposePage()),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(BlockMetrics.gap / 2),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final grid = _buildGrid(constraints);
                    if (_controller == null) {
                      _controller = BlockBoardController(
                        grid: grid,
                        mergeResolver: _resolveMerge,
                        onSound: _playBoardSound,
                        onBlockTapped: _onBlockTapped,
                      )..addListener(_onBoardChanged);
                      _layOutProblem();
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
                    Expanded(
                      child: _EquationStrip(
                        key: const ValueKey('equation'),
                        problem: _problem,
                        solved: _merged,
                        onTap: () => _merged
                            ? _celebrate()
                            : _askQuestion(interrupt: true),
                      ),
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.call_split_rounded,
                      onPressed: _goToDecompose,
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('retry'),
                      icon: Icons.refresh_rounded,
                      onPressed: _retry,
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('next'),
                      icon: Icons.arrow_forward_rounded,
                      highlighted: _merged,
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

/// 等式条 `[3] + [2] = [?]`。
///
/// **只是台面的镜子，不能操作**——把积木拖进槽位是 4.7 的玩法。这里存在的
/// 理由是他看动画时早就认得这个排版，让他一眼知道「这题问的是什么」。
///
/// 数字块的颜色与台面上对应的积木一致，那条对应关系不用讲他就能看出来。
class _EquationStrip extends StatelessWidget {
  const _EquationStrip({
    super.key,
    required this.problem,
    required this.solved,
    required this.onTap,
  });

  final AdditionProblem problem;
  final bool solved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableTile(
      onPressed: onTap,
      color: Colors.white,
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: BlockMetrics.gap / 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Chip(label: '${problem.a}', colorIndex: 1),
                const _Operator('+'),
                _Chip(label: '${problem.b}', colorIndex: 3),
                const _Operator('='),
                _Chip(
                  label: solved ? '${problem.sum}' : '?',
                  colorIndex: solved ? 4 : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.colorIndex});

  final String label;

  /// 为 null 时画成空槽——还不知道得数是多少。
  final int? colorIndex;

  @override
  Widget build(BuildContext context) {
    const size = BlockMetrics.minGrabTarget * 0.62;
    final filled = colorIndex != null;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? BlockColors.forIndex(colorIndex!) : Colors.transparent,
        borderRadius: BorderRadius.circular(BlockMetrics.blockRadius * 0.8),
        border: filled
            ? null
            : Border.all(
                color: BlockColors.ink.withValues(alpha: 0.28),
                width: 2,
              ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: size * 0.58,
          fontWeight: FontWeight.w700,
          height: 1.0,
          color: filled ? Colors.white : BlockColors.ink.withValues(alpha: 0.4),
        ),
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
      padding: EdgeInsets.symmetric(horizontal: BlockMetrics.gap * 0.35),
      child: Text(
        symbol,
        style: TextStyle(
          fontSize: BlockMetrics.minGrabTarget * 0.34,
          fontWeight: FontWeight.w700,
          height: 1.0,
          color: BlockColors.ink,
        ),
      ),
    );
  }
}
