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
import 'hundred_board_page.dart';
import 'piece_glyph.dart';
import 'place_value.dart';

/// 位值工作台。
///
/// 见 numbers-addition 规格「位值拆解」：他已经会读 0–100，这个模块的台阶
/// **不是数得更远，而是理解 23 由 2 个十和 3 个一组成**。
///
/// 三条设计取舍，都是为了 3 岁：
///
/// 1. **位置不参与判定**。只看总数。所以点一下托盘里的「源」，积木自己飞到
///    合适的位置——没有任何理由让他去瞄准落点。拖拽保留给「我想把它挪到
///    那儿」这种自发行为。
/// 2. **点已放置的积木 = 收回**。位置既然不判定，选中态在这里没有意义；
///    点一下就拿走比「先选中再决定」少一步。点选通道由托盘源承担。
/// 3. **10 个单块摆在台上不算错**，系统接受后再演示它可以换成 1 个十条。
///    这一条就是位值这一课的全部内容。
class PlaceValuePage extends ConsumerStatefulWidget {
  const PlaceValuePage({super.key});

  @override
  ConsumerState<PlaceValuePage> createState() => _PlaceValuePageState();
}

class _PlaceValuePageState extends ConsumerState<PlaceValuePage> {
  /// 攒够 10 个单块后，隔这么久再演示换十。
  ///
  /// 不能立刻换：他刚放下第 10 块，手还在那儿，画面立刻变会让他以为
  /// 是自己弄坏了。留一拍让他先看见「十个」，再看见它们合成一条。
  static const Duration _compactDelay = Duration(milliseconds: 700);

  int _targetIndex = 0;
  int get _target => kPlaceValueTargets[_targetIndex];

  BlockBoardController? _controller;
  int _nextId = 0;

  bool _solved = false;

  /// 自身正在改动积木时挂起监听，避免递归。
  bool _mutating = false;

  Timer? _compactTimer;

  AudioBus get _audio => ref.read(audioBusProvider);

  @override
  void initState() {
    super.initState();
    // 首帧之后再播报：initState 里 provider 还没准备好被读。
    WidgetsBinding.instance.addPostFrameCallback((_) => _announceTarget());
  }

  @override
  void dispose() {
    _compactTimer?.cancel();
    _controller?.removeListener(_onBoardChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ─── 台面状态 ───────────────────────────────────────────────────────

  PlaceValueAttempt _attempt() {
    final blocks = _controller?.blocks ?? const <BlockBody>[];
    return PlaceValueAttempt.fromPieces(
      blocks.map(
        (b) => b.widthUnits == PlacePiece.rod.widthUnits
            ? PlacePiece.rod
            : PlacePiece.unit,
      ),
    );
  }

  void _onBoardChanged() {
    if (!mounted || _mutating) return;

    final attempt = _attempt();

    if (attempt.canCompact) {
      _compactTimer?.cancel();
      _compactTimer = Timer(_compactDelay, _compact);
    }

    final solved = attempt.matches(_target);
    if (solved != _solved) {
      setState(() => _solved = solved);
      if (solved) _celebrate();
    }
  }

  /// 在挂起监听的前提下改动积木。
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

  // ─── 操作 ──────────────────────────────────────────────────────────

  /// 从托盘取一块。按下即出块——**不等抬手判定**，否则手感慢半拍；
  /// 而且孩子想「拖出来一块」时同样能立刻拿到东西。
  void _dispense(PlacePiece piece) {
    final controller = _controller;
    if (controller == null) return;

    final anchor = nextFreeAnchor(
      piece: piece,
      occupied: controller.occupiedCells(),
      columns: controller.grid.columns,
      rows: controller.grid.rows,
    );

    // 台面满了：静默收手，只给一声柔和的回位音。规格明确要求不得提示错误。
    if (anchor == null) {
      _audio.playSfx(Sfx.returned);
      return;
    }

    _mutate((c) {
      c.addBlock(
        BlockBody(
          id: 'p${_nextId++}',
          colorIndex: PieceColors.indexOf(piece),
          widthUnits: piece.widthUnits,
          anchor: anchor,
        ),
      );
    });
    _audio.playSfx(Sfx.snap);
  }

  /// 点已放置的积木 = 收回。返回 true 告诉引擎这次点击已被消费。
  bool _takeBack(BlockBody block, Offset _) {
    _mutate((c) => c.removeBlock(block.id));
    _audio.playSfx(Sfx.returned);
    return true;
  }

  void _clearBoard() {
    final controller = _controller;
    if (controller == null || controller.blocks.isEmpty) return;
    _mutate(_removeAll);
    _audio.playSfx(Sfx.returned);
  }

  /// `blocks` 是活的视图，边遍历边删会抛并发修改——先取快照。
  static void _removeAll(BlockBoardController controller) {
    for (final id in controller.blocks.map((b) => b.id).toList()) {
      controller.removeBlock(id);
    }
  }

  /// 演示换十：10 个单块合成 1 个十条。
  void _compact() {
    final controller = _controller;
    if (!mounted || controller == null) return;

    final units = controller.blocks
        .where((b) => b.widthUnits == PlacePiece.unit.widthUnits)
        .take(10)
        .toList();
    if (units.length < 10) return;

    _mutate((c) {
      for (final block in units) {
        c.removeBlock(block.id);
      }
      final anchor = nextFreeAnchor(
        piece: PlacePiece.rod,
        occupied: c.occupiedCells(),
        columns: c.grid.columns,
        rows: c.grid.rows,
      );
      // 刚腾空 10 格，正常一定放得下；真放不下就把单块留在原处，
      // 什么都不做也比闪一下再变回去好。
      if (anchor == null) {
        for (final block in units) {
          c.addBlock(block);
        }
        return;
      }
      c.addBlock(
        BlockBody(
          id: 'p${_nextId++}',
          colorIndex: PieceColors.rodIndex,
          widthUnits: PlacePiece.rod.widthUnits,
          expression: BlockExpression.happy,
          anchor: anchor,
        ),
      );
    });

    _audio.playSfx(Sfx.merge);
    // 「十个一，是一个十」——这一课要说的就是这一句。
    unawaited(
      _audio.speakSequence(
        Narration.tenOnesMakeATen,
        policy: VoicePolicy.interrupt,
      ),
    );
  }

  void _celebrate() {
    _audio.playSfx(Sfx.merge);
    _announceTarget(interrupt: true);
    // 台面上的积木一起笑。
    _mutate((c) {
      c.updateBlocks(
        c.blocks
            .map((b) => b.copyWith(expression: BlockExpression.happy))
            .toList(),
      );
    });
  }

  void _nextTarget() {
    _compactTimer?.cancel();
    _mutate(_removeAll);
    setState(() {
      _targetIndex = (_targetIndex + 1) % kPlaceValueTargets.length;
      _solved = false;
    });
    _audio.playSfx(Sfx.pickup);
    _announceTarget(interrupt: true);
  }

  /// 中英双声道：同一个数依次用中文、英文报一遍。
  ///
  /// 见规格「中英双声道」——双语是同一内容的两个声道，不是两套课程，
  /// 所以没有语言开关，也没有两个入口。
  void _announceTarget({bool interrupt = false}) {
    unawaited(
      _audio.speakSequence(
        Narration.bilingualNumber(_target),
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  /// 工作台几何。
  ///
  /// 格边长由**十条必须完整摆下**决定：10 格宽的长条一旦超出屏幕，位值
  /// 这一课就不成立了。因此宽度优先，高度次之。
  ///
  /// MI 8 SE（738×393dp）实测得到约 68dp/格——高于放置区下限 60dp。短边
  /// 360dp 的机型会降到约 60dp，仍在下限上；再小的屏幕由 1.5 倍吸附半径
  /// 兜底（≈90dp 的落点宽容度），不会因为格子小而变得难放。
  SnapGrid _buildGrid(BoxConstraints constraints) {
    final gap = BlockMetrics.gap;
    final byWidth = (constraints.maxWidth - gap * 2) / kPlaceValueColumns;
    final byHeight = (constraints.maxHeight - gap) / kPlaceValueRows;
    final cell = math.min(byWidth, byHeight);

    final boardWidth = cell * kPlaceValueColumns;
    return SnapGrid(
      columns: kPlaceValueColumns,
      rows: kPlaceValueRows,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - boardWidth) / 2).clamp(0, double.infinity),
        ((constraints.maxHeight - cell * kPlaceValueRows) / 2).clamp(
          0,
          double.infinity,
        ),
      ),
    );
  }

  /// 数字模块的两个玩法：位值工作台 ↔ 百格板。一律 `pushReplacement`，
  /// 返回键始终直接回星球地图，不会越按越深。
  void _goToHundredBoard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HundredBoardPage()),
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
                        onSound: _playBoardSound,
                        onBlockTapped: _takeBack,
                      )..addListener(_onBoardChanged);
                    } else {
                      _controller!.updateGrid(grid);
                    }
                    return BlockBoard(controller: _controller!);
                  },
                ),
              ),
              SizedBox(height: BlockMetrics.gap / 2),
              _Tray(
                target: _target,
                solved: _solved,
                onReplayTarget: () => _announceTarget(interrupt: true),
                onDispense: _dispense,
                onClear: _clearBoard,
                onNext: _nextTarget,
                onSwitchMode: _goToHundredBoard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部托盘。
///
/// 这一条里的每个元素都是**主动操作对象**，因此一律不低于 90dp——
/// 台面上的积木可以小到 60dp（它们是放置区，由吸附兜底），托盘不行。
class _Tray extends StatelessWidget {
  const _Tray({
    required this.target,
    required this.solved,
    required this.onReplayTarget,
    required this.onDispense,
    required this.onClear,
    required this.onNext,
    required this.onSwitchMode,
  });

  final int target;
  final bool solved;
  final VoidCallback onReplayTarget;
  final void Function(PlacePiece piece) onDispense;
  final VoidCallback onClear;
  final VoidCallback onNext;

  /// 去百格板。数字模块的两个玩法互相替换，返回键始终直接回星球地图。
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    const height = BlockMetrics.minGrabTarget;
    final gap = BlockMetrics.gap / 2;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          _TargetCard(
            key: const ValueKey('target'),
            target: target,
            solved: solved,
            onTap: onReplayTarget,
          ),
          SizedBox(width: gap),
          // 十条按可用宽度伸缩：它是 10 格宽的长条，固定宽度会在窄屏溢出。
          Expanded(
            child: _PieceSource(
              key: const ValueKey('source-rod'),
              piece: PlacePiece.rod,
              onPressed: () => onDispense(PlacePiece.rod),
            ),
          ),
          SizedBox(width: gap),
          SizedBox(
            width: height,
            child: _PieceSource(
              key: const ValueKey('source-unit'),
              piece: PlacePiece.unit,
              onPressed: () => onDispense(PlacePiece.unit),
            ),
          ),
          SizedBox(width: gap),
          RoundActionButton(
            key: const ValueKey('mode'),
            icon: Icons.grid_on_rounded,
            onPressed: onSwitchMode,
          ),
          SizedBox(width: gap),
          RoundActionButton(
            key: const ValueKey('clear'),
            icon: Icons.refresh_rounded,
            onPressed: onClear,
          ),
          SizedBox(width: gap),
          RoundActionButton(
            key: const ValueKey('next'),
            icon: Icons.arrow_forward_rounded,
            // 答对后才点亮，但**任何时候都能点**——他想跳过就跳过。
            highlighted: solved,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

/// 目标数。点一下重听一遍中英播报。
class _TargetCard extends StatelessWidget {
  const _TargetCard({
    super.key,
    required this.target,
    required this.solved,
    required this.onTap,
  });

  final int target;
  final bool solved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableTile(
      width: BlockMetrics.minGrabTarget * 1.4,
      onPressed: onTap,
      color: solved
          ? BlockColors.forIndex(4) // 薄荷绿：答对了
          : Colors.white,
      child: Center(
        child: Text(
          '$target',
          style: TextStyle(
            fontSize: BlockMetrics.minGrabTarget * 0.62,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: solved ? Colors.white : BlockColors.ink,
          ),
        ),
      ),
    );
  }
}

/// 托盘里的「源」。按下即出一块，可以一直按。
class _PieceSource extends StatelessWidget {
  const _PieceSource({super.key, required this.piece, required this.onPressed});

  final PlacePiece piece;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableTile(
      onPressed: onPressed,
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(BlockMetrics.gap / 2),
        child: PieceGlyph(piece: piece),
      ),
    );
  }
}
