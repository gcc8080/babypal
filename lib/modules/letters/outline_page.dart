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
import '../../core/design/controls.dart';
import '../../core/design/tokens.dart';
import 'letter_shapes.dart';
import 'letters.dart';
import 'case_match_page.dart';

/// 字母轮廓填充。
///
/// 见 letters 规格「字母轮廓填充」：小方块填进字母模板，MUST 使用引擎的吸附
/// 能力，MUST 支持拖拽与点选双通道。
///
/// **轮廓格只有 50 多 dp，因此它不是操作对象**——与百格板同一条推论（那里的
/// 格子只有 28dp）。他碰的是托盘里那块 90dp 的源：按一下，方块自己落到该去
/// 的位置，一次都不用瞄。拖拽留给「我想把这块挪到那儿」这种自发行为，由
/// 1.5 倍吸附半径（约 84dp 的落点宽容度）兜住。
///
/// 轮廓外的空白格全部标成不可落子，于是吸附**只可能**落进笔画里——不需要在
/// 引擎里新加一个「轮廓」的概念，也就不会有第二套判定跟着走偏。
class OutlinePage extends ConsumerStatefulWidget {
  const OutlinePage({super.key});

  @override
  ConsumerState<OutlinePage> createState() => _OutlinePageState();
}

class _OutlinePageState extends ConsumerState<OutlinePage> {
  int _index = 0;
  BlockBoardController? _controller;
  int _nextId = 0;
  bool _solved = false;
  bool _mutating = false;

  AudioBus get _audio => ref.read(audioBusProvider);

  List<LetterItem> get _letters => ref.read(contentLibraryProvider).letters;

  LetterItem? get _letter {
    final letters = _letters;
    if (letters.isEmpty) return null;
    return letters[_index % letters.length];
  }

  LetterShape? get _shape {
    final letter = _letter;
    return letter == null ? null : letterShapeOf(letter.letter);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _announce(interrupt: true);
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_onBoardChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ─── 台面状态 ───────────────────────────────────────────────────────

  Set<GridCell> _filledCells() {
    final blocks = _controller?.blocks ?? const <BlockBody>[];
    return {for (final b in blocks) ?b.anchor};
  }

  void _onBoardChanged() {
    if (!mounted || _mutating) return;
    final shape = _shape;
    if (shape == null) return;

    final solved = _filledCells().length >= shape.size;
    if (solved != _solved) {
      setState(() => _solved = solved);
      if (solved) _celebrate();
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

  // ─── 操作 ──────────────────────────────────────────────────────────

  /// 托盘出一块，落到轮廓里下一个空位。按下即出，不等抬手。
  void _dispense() {
    final shape = _shape;
    final controller = _controller;
    if (shape == null || controller == null) return;

    final cell = nextEmptyCell(shape, _filledCells());
    if (cell == null) {
      // 已经填满了：静默收手，只给一声柔和的回位音。不提示、不报错。
      _audio.playSfx(Sfx.returned);
      return;
    }

    _mutate(
      (c) => c.addBlock(
        BlockBody(id: 'o${_nextId++}', colorIndex: _colorIndex, anchor: cell),
      ),
    );
    _audio.playSfx(Sfx.snap);
  }

  /// 点已放置的方块 = 收回。与位值工作台同一个动作，他不用学第二次。
  bool _takeBack(BlockBody block, Offset _) {
    _mutate((c) => c.removeBlock(block.id));
    _audio.playSfx(Sfx.returned);
    return true;
  }

  void _clear() {
    final controller = _controller;
    if (controller == null || controller.blocks.isEmpty) return;
    _mutate(_removeAll);
    setState(() => _solved = false);
    _audio.playSfx(Sfx.returned);
  }

  /// `blocks` 是活视图，边遍历边删会抛并发修改——先取 id 快照。
  static void _removeAll(BlockBoardController controller) {
    for (final id in controller.blocks.map((b) => b.id).toList()) {
      controller.removeBlock(id);
    }
  }

  /// 填满：整个字母一起笑，报字母名与音素。
  void _celebrate() {
    _audio.playSfx(Sfx.merge);
    _mutate((c) {
      c.updateBlocks(
        c.blocks
            .map((b) => b.copyWith(expression: BlockExpression.happy))
            .toList(),
      );
    });
    _announce(interrupt: true);
  }

  void _announce({bool interrupt = false}) {
    final letter = _letter;
    if (letter == null) return;
    unawaited(
      _audio.speakSequence(
        LetterNarration.letterAndPhoneme(letter),
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  void _step({required bool forward}) {
    final count = _letters.length;
    if (count == 0) return;
    _mutate(_removeAll);
    setState(() {
      _index = nextLetterIndex(_index, count, forward: forward);
      _solved = false;
    });
    _audio.playSfx(Sfx.pickup);
    _announce(interrupt: true);
  }

  void _goToCaseMatch() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const CaseMatchPage()),
    );
  }

  int get _colorIndex {
    final letter = _letter;
    return letter == null ? 0 : letter.letter.codeUnitAt(0) - 0x41;
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

  // ─── 布局 ──────────────────────────────────────────────────────────

  SnapGrid _buildGrid(BoxConstraints constraints, LetterShape shape) {
    final cell = math.min(
      constraints.maxWidth / shape.columns,
      constraints.maxHeight / shape.rows,
    );
    final width = cell * shape.columns;
    final height = cell * shape.rows;
    return SnapGrid(
      columns: shape.columns,
      rows: shape.rows,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - width) / 2).clamp(0, double.infinity),
        ((constraints.maxHeight - height) / 2).clamp(0, double.infinity),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final letter = _letter;
    final shape = _shape;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(BlockMetrics.gap / 2),
          child: Column(
            children: [
              Expanded(
                child: shape == null
                    ? const SizedBox.expand()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final grid = _buildGrid(constraints, shape);
                          final blocked = blockedCellsFor(shape);
                          if (_controller == null) {
                            _controller =
                                BlockBoardController(
                                    grid: grid,
                                    onSound: _playBoardSound,
                                    onBlockTapped: _takeBack,
                                  )
                                  ..blockedCells = blocked
                                  ..addListener(_onBoardChanged);
                          } else {
                            _controller!
                              ..updateGrid(grid)
                              ..updateBlockedCells(blocked);
                          }
                          return Stack(
                            key: const ValueKey('outline'),
                            children: [
                              // 轮廓的「影子」。画在底下，让他一眼看见要填成
                              // 什么形状——没有这张影子，这个玩法就只是往
                              // 空白处随便放方块。
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _OutlinePainter(
                                    shape: shape,
                                    grid: grid,
                                    color: letterColor(shape.letter),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: BlockBoard(controller: _controller!),
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
                    if (letter != null)
                      SizedBox(
                        key: const ValueKey('target'),
                        width: BlockMetrics.minGrabTarget,
                        child: PressableTile(
                          onPressed: () => _announce(interrupt: true),
                          color: _solved
                              ? RoundActionButton.doneColor
                              : Colors.white,
                          child: Center(
                            child: Text(
                              letter.letter,
                              style: TextStyle(
                                fontSize: BlockMetrics.minGrabTarget * 0.6,
                                fontWeight: FontWeight.w800,
                                height: 1.0,
                                color: _solved
                                    ? Colors.white
                                    : letterColor(letter.letter),
                              ),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    Expanded(
                      child: PressableTile(
                        key: const ValueKey('source'),
                        onPressed: _dispense,
                        color: Colors.white,
                        child: Center(
                          child: SizedBox(
                            width: BlockMetrics.minGrabTarget * 0.5,
                            height: BlockMetrics.minGrabTarget * 0.5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: BlockColors.forIndex(_colorIndex),
                                borderRadius: BorderRadius.circular(
                                  BlockMetrics.blockRadius * 0.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('prev'),
                      icon: Icons.chevron_left_rounded,
                      onPressed: () => _step(forward: false),
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('clear'),
                      icon: Icons.refresh_rounded,
                      onPressed: _clear,
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('mode'),
                      icon: Icons.text_fields_rounded,
                      onPressed: _goToCaseMatch,
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    RoundActionButton(
                      key: const ValueKey('next'),
                      icon: Icons.chevron_right_rounded,
                      highlighted: _solved,
                      onPressed: () => _step(forward: true),
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

/// 轮廓影子：还没填的笔画格画成浅色虚位。
class _OutlinePainter extends CustomPainter {
  const _OutlinePainter({
    required this.shape,
    required this.grid,
    required this.color,
  });

  final LetterShape shape;
  final SnapGrid grid;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = grid.cellSize;
    final inset = cell * 0.08;
    final radius = Radius.circular(cell * 0.2);
    final paint = Paint()..color = color.withValues(alpha: 0.16);

    for (final c in shape.cells) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            grid.origin.dx + c.col * cell + inset,
            grid.origin.dy + c.row * cell + inset,
            cell - inset * 2,
            cell - inset * 2,
          ),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.shape.letter != shape.letter ||
      old.grid != grid ||
      old.color != color;
}
