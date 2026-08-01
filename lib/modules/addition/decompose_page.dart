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
import 'equation_page.dart';

/// 反向分解。
///
/// 见 numbers-addition 规格「反向分解」：**其权重 MUST NOT 低于合体求和**。
/// 他已经会背 `3+2=5`，倒过来拆才是明年凑十法与进位加法的地基——
/// 「5 可以分成 2 和 3」这句话说出来容易，看见 5 真的裂成 2 和 3 是另一回事。
///
/// 交互只有一条规则：**点哪儿切哪儿**。
///
/// 手指落在积木的哪个位置，就从最近的那道格缝切开。[cutIndexAt] 的 `clamp`
/// 保证结果永远合法——点在最左端切出 `1+4`，点在最右端切出 `4+1`，点到积木
/// 外面也照切。**反向分解里不存在「没切中」**：他点在积木上的任何位置都必须
/// 切出点什么来，否则就是「点了没反应」。
///
/// 切开之后**点任意一块就合回去**（拖一块到另一块上也行），于是「切开—合回—
/// 换个地方再切」成为一个可以一直转的循环。合回去时播报的是加法算式，分解与
/// 合体因此成了同一件事的两个方向，而不是两个玩法。
class DecomposePage extends ConsumerStatefulWidget {
  const DecomposePage({super.key});

  @override
  ConsumerState<DecomposePage> createState() => _DecomposePageState();
}

class _DecomposePageState extends ConsumerState<DecomposePage> {
  static const String _idWhole = 'whole';
  static const String _idLeft = 'part-left';
  static const String _idRight = 'part-right';

  /// 与合体求和共用同一套配色：绿 = 总数，珊瑚 / 紫罗兰 = 两个加数。
  /// 两个玩法之间不需要重新学配色。
  static const int _colorWhole = 4;
  static const int _colorLeft = 1;
  static const int _colorRight = 3;

  int _targetIndex = 0;
  int get _total => kDecompositionTargets[_targetIndex];

  BlockBoardController? _controller;
  bool _mutating = false;

  /// 已经发现过的分法，存左边那一份的大小。
  ///
  /// 记下来是为了让他**主动重复**——「5 还有一种分法没找到」是这个模块唯一
  /// 的驱动力，而且它不是关卡、不计分、找不齐也没有任何后果。
  final Set<int> _found = {};

  /// 当前切开的样子，未切时为 null。
  AdditionProblem? _cut;

  AudioBus get _audio => ref.read(audioBusProvider);

  /// 念一遍还是念两遍，由家长设置说了算。**每次现读**，因此设置页一关下一句就生效。
  NarrationStyle get _narration => ref.read(narrationProvider);

  bool get _allFound => _found.length == _total - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _announceTotal());
  }

  @override
  void dispose() {
    _controller?.removeListener(_onBoardChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ─── 题目 ──────────────────────────────────────────────────────────

  /// 整块积木的起始格位：横向居中。
  GridCell get _wholeAnchor =>
      GridCell((kAdditionColumns - _total) ~/ 2, kAdditionRows ~/ 2);

  /// 见 [AdditionPage] 里同名方法的说明：首次布局发生在 build 期间，
  /// 因此这里既不走 `_mutate` 也不自己 `setState`。
  void _layOutWhole() {
    final controller = _controller;
    if (controller == null) return;

    _mutating = true;
    try {
      for (final id in controller.blocks.map((b) => b.id).toList()) {
        controller.removeBlock(id);
      }
      controller.addBlock(
        BlockBody(
          id: _idWhole,
          colorIndex: _colorWhole,
          widthUnits: _total,
          anchor: _wholeAnchor,
        ),
      );
    } finally {
      _mutating = false;
    }
    _cut = null;
  }

  void _announceTotal({bool interrupt = false}) {
    unawaited(
      _audio.speakSequence(
        _narration.number(_total),
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  void _nextTarget() {
    setState(() {
      _targetIndex = (_targetIndex + 1) % kDecompositionTargets.length;
      _found.clear();
      _layOutWhole();
    });
    _audio.playSfx(Sfx.pickup);
    _announceTotal(interrupt: true);
  }

  // ─── 切 / 合 ───────────────────────────────────────────────────────

  bool _onBlockTapped(BlockBody block, Offset localPosition) {
    final controller = _controller;
    if (controller == null) return false;

    if (block.id == _idWhole) {
      _cutAt(localPosition.dx, controller.grid.cellSize);
      return true;
    }

    // 点任意一块碎片 → 合回去。切开、合回、换个地方再切，这个循环是这个
    // 模块全部的可玩性所在。
    _rejoin();
    return true;
  }

  void _cutAt(double localX, double cellSize) {
    final left = cutIndexAt(localX, cellSize, _total);
    final right = _total - left;

    _mutate((c) {
      c.split(_idWhole, [
        BlockBody(id: _idLeft, colorIndex: _colorLeft, widthUnits: left),
        BlockBody(id: _idRight, colorIndex: _colorRight, widthUnits: right),
      ]);
    });

    setState(() {
      _cut = AdditionProblem(left, right);
      _found.add(left);
    });

    // 「五 可以分成 二 和 三」，中英各一遍。
    unawaited(
      _audio.speakSequence(
        _narration.decomposition(_total, left, right),
        policy: VoicePolicy.interrupt,
      ),
    );
  }

  void _rejoin() {
    final controller = _controller;
    if (controller == null || controller.blocks.length != 2) return;

    final cut = _cut;
    _mutate((c) => c.mergeBlocks(c.blocks.first.id, c.blocks.last.id));

    // 合回去时报的是加法算式——分解与合体是同一件事的两个方向，
    // 不是两个玩法。
    if (cut != null) {
      unawaited(
        _audio.speakSequence(
          _narration.addition(cut.a, cut.b),
          policy: VoicePolicy.interrupt,
        ),
      );
    }
  }

  /// 合体规则：两块碎片拼回整块。
  BlockBody? _resolveMerge(BlockBody moving, BlockBody target) {
    if (moving.heightUnits != target.heightUnits) return null;
    if (moving.widthUnits + target.widthUnits != _total) return null;

    // 拖拽路径下 moving 已离开格位，此时锚点交回引擎（落在 target 原处）。
    final ma = moving.anchor;
    final ta = target.anchor;
    GridCell? anchor;
    if (ma != null && ta != null) {
      final col = math.min(ma.col, ta.col);
      // 别让合回来的整块伸到棋盘外面去。
      anchor = GridCell(
        math.min(col, kAdditionColumns - _total),
        ma.col <= ta.col ? ma.row : ta.row,
      );
    }

    return BlockBody(
      id: _idWhole,
      colorIndex: _colorWhole,
      widthUnits: _total,
      heightUnits: target.heightUnits,
      expression: BlockExpression.happy,
      anchor: anchor,
    );
  }

  void _onBoardChanged() {
    if (!mounted || _mutating) return;
    final controller = _controller;
    if (controller == null) return;

    // 拖拽合体走的是引擎路径，页面在这里补上状态同步。
    final whole = controller.blocks.length == 1;
    if (whole && _cut != null) {
      setState(() => _cut = null);
    }
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
    final cell = math.min(
      (constraints.maxWidth - gap * 2) / kAdditionColumns,
      (constraints.maxHeight - gap) / kAdditionRows,
    );

    return SnapGrid(
      columns: kAdditionColumns,
      rows: kAdditionRows,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - cell * kAdditionColumns) / 2).clamp(
          0,
          double.infinity,
        ),
        ((constraints.maxHeight - cell * kAdditionRows) / 2).clamp(
          0,
          double.infinity,
        ),
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

  /// 三个玩法接成一个环：合体 → 分解 → 等式 → 合体。图标画的是**下一站**。
  ///
  /// 一律 `pushReplacement` 而不是叠层——返回键始终直接回星球地图，
  /// 不会越按越深。
  void _goToEquation() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const EquationPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cut = _cut;

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
                      _layOutWhole();
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
                      child: _DecompositionStrip(
                        key: const ValueKey('decomposition'),
                        total: _total,
                        cut: cut,
                        found: _found,
                        onTap: () => cut == null
                            ? _announceTotal(interrupt: true)
                            : unawaited(
                                _audio.speakSequence(
                                  _narration.decomposition(
                                    _total,
                                    cut.a,
                                    cut.b,
                                  ),
                                  policy: VoicePolicy.interrupt,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.calculate_rounded,
                      onPressed: _goToEquation,
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('next'),
                      icon: Icons.arrow_forward_rounded,
                      highlighted: _allFound,
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

/// `5 = [2] + [3]`，下面一排小格记着哪几种分法已经找到过。
///
/// 只是台面的镜子，不能操作。那排小格是这个模块唯一的驱动力——
/// **不是关卡**：找不齐没有任何后果，下一题随时能走。
class _DecompositionStrip extends StatelessWidget {
  const _DecompositionStrip({
    super.key,
    required this.total,
    required this.cut,
    required this.found,
    required this.onTap,
  });

  final int total;
  final AdditionProblem? cut;
  final Set<int> found;
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Chip(label: '$total', colorIndex: 4),
                    const _Operator('='),
                    _Chip(
                      label: cut == null ? '?' : '${cut!.a}',
                      colorIndex: cut == null ? null : 1,
                    ),
                    const _Operator('+'),
                    _Chip(
                      label: cut == null ? '?' : '${cut!.b}',
                      colorIndex: cut == null ? null : 3,
                    ),
                  ],
                ),
                SizedBox(height: BlockMetrics.gap * 0.25),
                _FoundMarks(total: total, found: found),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 已找到的分法。第 i 格对应「左边 i 块」那一种。
class _FoundMarks extends StatelessWidget {
  const _FoundMarks({required this.total, required this.found});

  final int total;
  final Set<int> found;

  @override
  Widget build(BuildContext context) {
    const size = BlockMetrics.minGrabTarget * 0.14;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var a = 1; a < total; a++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.22),
            child: SizedBox(
              width: size,
              height: size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: found.contains(a)
                      ? BlockColors.forIndex(4)
                      : BlockColors.ink.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(size * 0.3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.colorIndex});

  final String label;
  final int? colorIndex;

  @override
  Widget build(BuildContext context) {
    const size = BlockMetrics.minGrabTarget * 0.5;
    final filled = colorIndex != null;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? BlockColors.forIndex(colorIndex!) : Colors.transparent,
        borderRadius: BorderRadius.circular(BlockMetrics.blockRadius * 0.7),
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
      padding: EdgeInsets.symmetric(horizontal: BlockMetrics.gap * 0.28),
      child: Text(
        symbol,
        style: TextStyle(
          fontSize: BlockMetrics.minGrabTarget * 0.28,
          fontWeight: FontWeight.w700,
          height: 1.0,
          color: BlockColors.ink,
        ),
      ),
    );
  }
}
