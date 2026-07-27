import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_bus.dart';
import '../../core/audio/audio_providers.dart';
import '../../core/audio/sfx.dart';
import '../../core/block/block_board.dart';
import '../../core/block/block_board_controller.dart';
import '../../core/block/block_model.dart';
import '../../core/block/snap_grid.dart';
import '../../core/content/content_providers.dart';
import '../../core/content/models.dart';
import '../../core/content/pack_loader.dart';
import '../../core/design/controls.dart';
import '../../core/design/tokens.dart';
import 'hanzi.dart';
import 'seesaw_page.dart';

/// 拼搭台的格数。
///
/// 五列两行：三个部件摆成「木 _ 木 _ 木」正好占满一行且两两不相邻——**起始
/// 状态绝不能有两块已经挨着**，否则一进页面它们就自己合了，等于替他做完了。
/// 第二行是给他停放用的：只有一行时，任何一次拖动都只能落回同一行。
const int kHanziColumns = 5;
const int kHanziRows = 2;

/// 部件加法。
///
/// 见 hanzi 规格「部件加法」：**MUST 复用加法模块的合体交互，MUST NOT 实现
/// 一套独立的合体手势。** 所以这一页没有自己的手势代码——`BlockBoard` 与
/// `BlockBoardController` 原样搬过来，本页只提供一条规则：这两块碰到一起该
/// 变成哪个字。加法模块提供的规则是 `3 + 2 = 5`，这里是 `木 + 木 = 林`，
/// 引擎那边一个字都不用改。
///
/// 对他而言这不是「又一个玩法」，而是同一个动作换了内容。合体的三条触发路径
/// 因此全部照单继承：拼到旁边、叠上去、点两下。
///
/// 三部件的字（森 = 木+木+木）不需要一次凑齐三块——那对三岁的手太难了。
/// [componentsOf] 把已经合成的字摊回部件，于是 `木+木` 先成「林」，「林」再
/// 碰上「木」就成「森」。他因此顺带看见了「森里面有林」。
class ComponentPage extends ConsumerStatefulWidget {
  const ComponentPage({super.key});

  @override
  ConsumerState<ComponentPage> createState() => _ComponentPageState();
}

class _ComponentPageState extends ConsumerState<ComponentPage> {
  int _problemIndex = 0;

  BlockBoardController? _controller;
  bool _mutating = false;

  /// 合体 id 的递增计数器。合体产生的积木必须拿到**没用过的** id，
  /// 否则 `AnimatedPositioned` 会把新块认成旧块，飞入动画会从错误的位置起飞。
  int _nextMergeId = 0;

  /// 刚发生的一次合体，等着被播报。
  ///
  /// 在 `mergeResolver` 里记下、在 `_onBoardChanged` 里念出来：合体规则该是
  /// 纯粹的「这两块能不能合」，让它顺手说话就意味着一个返回 null 的分支里
  /// 也随时可能冒出声音。
  ({List<HanziItem> parts, HanziItem result})? _pendingSpeech;

  AudioBus get _audio => ref.read(audioBusProvider);
  ContentLibrary get _library => ref.read(contentLibraryProvider);

  List<HanziItem> get _problems => [
    for (final item in _library.hanzi)
      if (item.isCompound) item,
  ];

  HanziItem? get _problem {
    final all = _problems;
    if (all.isEmpty) return null;
    return all[_problemIndex % all.length];
  }

  /// 拼成了没有：台面上只剩一块，且它就是目标字。
  ///
  /// 存成字段而不是每次从 `_controller.blocks` 现算，是为了让 [_onBoardChanged]
  /// **只在它真的翻转时**才 `setState`。控制器每次 `notifyListeners` 都会走到
  /// 那里，其中包括 `updateGrid`——而 `updateGrid` 发生在 `LayoutBuilder` 的
  /// builder 里，在那儿 `setState` 会直接抛「setState during build」。
  /// 棋盘自己是控制器的监听者，本来就会自行重建，页面只需要管这一个状态。
  bool _solved = false;

  bool _computeSolved() {
    final blocks = _controller?.blocks ?? const [];
    return blocks.length == 1 && blocks.first.label == _problem?.char;
  }

  @override
  void initState() {
    super.initState();
    // 第一帧之后再出题：那时 provider 才可读。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announce();
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onBoardChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ─── 题目 ──────────────────────────────────────────────────────────

  /// 把部件摆开，两两之间空一格。
  ///
  /// 刻意不走 `setState`：首次布局发生在 `LayoutBuilder` 的 builder 里
  /// （那时控制器刚建好），在 build 期间 `setState` 会直接抛。调用方要么本来
  /// 就在 build 中，要么自己包了 `setState`——与加法模块同一套写法。
  void _layOutProblem() {
    final controller = _controller;
    final problem = _problem;
    if (controller == null || problem == null) return;

    _mutating = true;
    try {
      for (final id in controller.blocks.map((b) => b.id).toList()) {
        controller.removeBlock(id);
      }
      final parts = problem.parts;
      // 隔一列摆一块，整体居中。
      final span = parts.length * 2 - 1;
      final start = math.max(0, (kHanziColumns - span) ~/ 2);
      for (var i = 0; i < parts.length; i++) {
        controller.addBlock(
          BlockBody(
            id: 'part-$i',
            colorIndex: hanziColorIndex(parts[i]),
            label: parts[i],
            anchor: GridCell(start + i * 2, 0),
          ),
        );
      }
    } finally {
      _mutating = false;
    }
    _pendingSpeech = null;
    _solved = false;
  }

  void _retry() {
    setState(_layOutProblem);
    _audio.playSfx(Sfx.returned);
  }

  void _nextProblem() {
    setState(() {
      _problemIndex = (_problemIndex + 1) % math.max(1, _problems.length);
      _layOutProblem();
    });
    _audio.playSfx(Sfx.pickup);
    _announce();
  }

  /// 出题时只念部件，**不念结果**——念了这一关就没了。
  void _announce() {
    final problem = _problem;
    if (problem == null) return;
    final parts = [for (final p in problem.parts) ?_library.hanziByChar(p)];
    if (parts.length != problem.parts.length) return;
    unawaited(
      _audio.speakSequence([
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) 'zh.word.plus',
          parts[i].voiceKey,
        ],
      ], policy: VoicePolicy.interrupt),
    );
  }

  // ─── 合体 ──────────────────────────────────────────────────────────

  /// 合体规则。返回 null 表示这两块合不出字——引擎据此让积木退回或就地落位，
  /// 且**不播放任何错误提示，也不留下任何标记**（规格「非法组合」）。
  BlockBody? _resolveMerge(BlockBody moving, BlockBody target) {
    if (_solved) return null;
    final movingLabel = moving.label;
    final targetLabel = target.label;
    if (movingLabel == null || targetLabel == null) return null;

    final library = _library;
    final components = [
      ...componentsOf(movingLabel, library),
      ...componentsOf(targetLabel, library),
    ];
    final compound = compoundFrom(components, library);
    if (compound == null) return null;

    final movingItem = library.hanziByChar(movingLabel);
    final targetItem = library.hanziByChar(targetLabel);
    if (movingItem != null && targetItem != null) {
      // 念的是**刚才那两块**，不是目标字的部件表：他把林和木合成森的时候，
      // 该听见「林加木等于森」，而不是「木加木加木等于森」。
      _pendingSpeech = (parts: [movingItem, targetItem], result: compound);
    }

    // 合体结果落在两块中靠左的那一块的位置上。拖拽路径下 moving 已经离开
    // 格位（anchor 为 null），此时交给引擎回落到 target 原处。
    final ma = moving.anchor;
    final ta = target.anchor;
    final GridCell? anchor = (ma != null && ta != null)
        ? (ma.col <= ta.col ? ma : ta)
        : null;

    return BlockBody(
      id: 'merged-${_nextMergeId++}',
      colorIndex: hanziColorIndex(compound.char),
      label: compound.char,
      expression: BlockExpression.happy,
      anchor: anchor,
    );
  }

  /// 点选通道：点 A 选中，再点 B 就合体。
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

    // 拼到一起了（同一行、边挨着边）→ 合体。规格说的是「拼接」，不是
    // 「叠在一起」：放到旁边比放到正上方好操作得多。
    if (blocks.length >= 2) {
      for (var i = 0; i < blocks.length; i++) {
        for (var j = i + 1; j < blocks.length; j++) {
          if (blocksAreJoined(blocks[i], blocks[j])) {
            _mutate((c) => c.mergeBlocks(blocks[i].id, blocks[j].id));
            return;
          }
        }
      }
    }

    final speech = _pendingSpeech;
    if (speech != null) {
      _pendingSpeech = null;
      unawaited(
        _audio.speakSequence(
          HanziNarration.composition(speech.parts, speech.result),
          policy: VoicePolicy.interrupt,
        ),
      );
    }

    final solved = _computeSolved();
    if (solved != _solved) setState(() => _solved = solved);
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
    final byWidth = (constraints.maxWidth - gap * 2) / kHanziColumns;
    final byHeight = (constraints.maxHeight - gap) / kHanziRows;
    final cell = math.min(byWidth, byHeight);

    return SnapGrid(
      columns: kHanziColumns,
      rows: kHanziRows,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - cell * kHanziColumns) / 2).clamp(
          0,
          double.infinity,
        ),
        ((constraints.maxHeight - cell * kHanziRows) / 2).clamp(
          0,
          double.infinity,
        ),
      ),
    );
  }

  void _goToSeesaw() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SeesawPage()),
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
    final problem = _problem;
    final gap = BlockMetrics.gap / 2;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Column(
            children: [
              Expanded(
                child: problem == null
                    // 内容包读不到时静默留白：儿童端不能弹「暂无内容」。
                    ? const SizedBox.expand()
                    : LayoutBuilder(
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
              SizedBox(height: gap),
              SizedBox(
                height: BlockMetrics.minGrabTarget,
                child: Row(
                  children: [
                    Expanded(
                      child: _CompositionStrip(
                        key: const ValueKey('composition'),
                        problem: problem,
                        solved: _solved,
                        onTap: _announce,
                      ),
                    ),
                    SizedBox(width: gap),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.balance_rounded,
                      onPressed: _goToSeesaw,
                    ),
                    SizedBox(width: gap),
                    RoundActionButton(
                      key: const ValueKey('retry'),
                      icon: Icons.refresh_rounded,
                      onPressed: _retry,
                    ),
                    SizedBox(width: gap),
                    RoundActionButton(
                      key: const ValueKey('next'),
                      icon: Icons.arrow_forward_rounded,
                      highlighted: _solved,
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

/// 造字式 `[木] + [木] = [?]`。
///
/// **和加法模块的等式条是同一个排版**，这是故意的：他在加法那边已经认得这条
/// 「左边两个、右边一个」的横条，走到汉字这边不用重新学怎么读题，同时也是
/// 「这两件事是同一件事」最直白的一句话。
///
/// 只是台面的镜子，不能操作。点一下重念一遍题目。
class _CompositionStrip extends StatelessWidget {
  const _CompositionStrip({
    super.key,
    required this.problem,
    required this.solved,
    required this.onTap,
  });

  final HanziItem? problem;
  final bool solved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = problem;
    return PressableTile(
      onPressed: onTap,
      color: Colors.white,
      child: item == null
          ? const SizedBox.expand()
          : Center(
              child: FittedBox(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: BlockMetrics.gap / 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < item.parts.length; i++) ...[
                        if (i > 0) const _Operator('+'),
                        _Chip(label: item.parts[i]),
                      ],
                      const _Operator('='),
                      _Chip(label: solved ? item.char : '?', done: solved),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.done = false});

  final String label;

  /// 还没拼出来时画成空槽——他要做的事就在这个空槽里。
  final bool done;

  @override
  Widget build(BuildContext context) {
    const size = BlockMetrics.minGrabTarget * 0.62;
    final filled = label != '?';

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? (done ? RoundActionButton.doneColor : hanziColor(label))
            : Colors.transparent,
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
          fontSize: size * 0.56,
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
      padding: EdgeInsets.symmetric(horizontal: BlockMetrics.gap * 0.3),
      child: Text(
        symbol,
        style: TextStyle(
          fontSize: BlockMetrics.minGrabTarget * 0.32,
          fontWeight: FontWeight.w700,
          height: 1.0,
          color: BlockColors.ink,
        ),
      ),
    );
  }
}
