import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_bus.dart';
import '../../core/audio/audio_providers.dart';
import '../../core/settings/settings_providers.dart';
import '../../core/audio/sfx.dart';
import '../../core/design/controls.dart';
import '../../core/design/tokens.dart';
import 'hundred_board.dart';
import 'piece_glyph.dart';
import 'place_value.dart';
import 'place_value_page.dart';

/// 百格板。
///
/// 见 numbers-addition 规格「百格板」：10×10 网格渐进填充呈现 1–100，
/// 用户操作的对象 MUST 是 ≥90dp 的可拖拽积木，**MUST NOT 要求点中单个格子**。
///
/// 这条约束不是可用性建议，而是几何事实：手机横屏可用高度约 280dp，10 行
/// 就是每格 28dp，怎么排都不可能满足 90dp。结论**不是「百格板做不了」，
/// 而是「格子根本不是操作对象」**——他碰的是托盘里的十条与单块，格子只负责
/// 显示。所以这个页面里，网格是一张画，不接受任何触摸。
///
/// 两处设计：
///
/// 1. **整行与零散格上不同的颜色。** 34 看起来就是「三行十个」加「四个」，
///    位值不用讲，看一眼就在那儿——这是位值工作台（4.1）那一课的回音。
/// 2. **不提供「百板」。** 一步填完 100 会把这个模块变成一次点击，而它的
///    乐趣恰恰在于一行一行地爬上去、听着数字一个个报出来。
class HundredBoardPage extends ConsumerStatefulWidget {
  const HundredBoardPage({super.key});

  @override
  ConsumerState<HundredBoardPage> createState() => _HundredBoardPageState();
}

class _HundredBoardPageState extends ConsumerState<HundredBoardPage>
    with SingleTickerProviderStateMixin {
  HundredBoard _board = const HundredBoard();

  /// 正在放烟花的那一行，无烟花时为 null。
  int? _burstRow;

  /// 烟花动画。
  ///
  /// **必须在 `initState` 里建，不能用 `late final` 惰性初始化**：一行都没填满
  /// 就退出这个页面时，`dispose()` 里的 `_burst.dispose()` 会成为它的首次访问，
  /// 于是在 dispose 期间才去 `createTicker`——而那要查祖先节点，此时组件树已经
  /// 失活，直接抛「Looking up a deactivated widget's ancestor is unsafe」。
  late final AnimationController _burst;

  AudioBus get _audio => ref.read(audioBusProvider);

  /// 念一遍还是念两遍，由家长设置说了算。**每次现读**，因此设置页一关下一句就生效。
  NarrationStyle get _narration => ref.read(narrationProvider);

  @override
  void initState() {
    super.initState();
    _burst =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _burstRow = null);
          }
        });
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  // ─── 操作 ──────────────────────────────────────────────────────────

  /// 从托盘取一块填上去。按下即填，不等抬手判定。
  void _place(PlacePiece piece) {
    final before = _board;
    if (before.isFull) {
      // 满了：静默收手，只给一声柔和的回位音。规格要求不得提示错误。
      _audio.playSfx(Sfx.returned);
      return;
    }

    final after = before.add(piece);
    setState(() => _board = after);

    final completed = rowsCompletedBetween(before.filled, after.filled);
    if (completed.isEmpty) {
      _audio.playSfx(Sfx.snap);
    } else {
      _celebrateRow(completed.last);
    }

    _announceCount(interrupt: true);
  }

  /// 填满一行：烟花 + 音效。规格「填满一行」要求的庆祝反馈。
  void _celebrateRow(int row) {
    _audio.playSfx(Sfx.merge);
    setState(() => _burstRow = row);
    _burst.forward(from: 0);
  }

  void _clear() {
    if (_board.isEmpty) return;
    _burst.stop();
    setState(() {
      _board = _board.cleared;
      _burstRow = null;
    });
    _audio.playSfx(Sfx.returned);
    _announceCount(interrupt: true);
  }

  /// 报当前的数，中英各一遍。
  ///
  /// 一律 `interrupt`：他连着按的时候只该听见最新那个数，把中间的数排队
  /// 播完既拖沓又对不上画面。
  void _announceCount({bool interrupt = false}) {
    unawaited(
      _audio.speakSequence(
        _narration.number(_board.filled),
        policy: interrupt ? VoicePolicy.interrupt : VoicePolicy.queue,
      ),
    );
  }

  void _goToPlaceValue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const PlaceValuePage()),
    );
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

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
                    // 网格是正方形，边长由可用高度决定——宽度总是富余的，
                    // 剩下的横向空间给那个大数字。
                    final cell = constraints.maxHeight / HundredBoard.rows;
                    final side = cell * HundredBoard.columns;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          key: const ValueKey('board'),
                          width: side,
                          height: side,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _BoardPainter(
                                    board: _board,
                                    cellSize: cell,
                                  ),
                                ),
                              ),
                              if (_burstRow != null)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: AnimatedBuilder(
                                      animation: _burst,
                                      builder: (context, _) => CustomPaint(
                                        painter: _FireworksPainter(
                                          row: _burstRow!,
                                          cellSize: cell,
                                          progress: _burst.value,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: _CountDisplay(
                              key: const ValueKey('count'),
                              value: _board.filled,
                              onTap: () => _announceCount(interrupt: true),
                            ),
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
                    // 十条按可用宽度伸缩：它是 10 格宽的长条，固定宽度会溢出。
                    Expanded(
                      child: _PieceSource(
                        key: const ValueKey('source-rod'),
                        piece: PlacePiece.rod,
                        onPressed: () => _place(PlacePiece.rod),
                      ),
                    ),
                    SizedBox(width: BlockMetrics.gap / 2),
                    SizedBox(
                      width: BlockMetrics.minGrabTarget,
                      child: _PieceSource(
                        key: const ValueKey('source-unit'),
                        piece: PlacePiece.unit,
                        onPressed: () => _place(PlacePiece.unit),
                      ),
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
                      icon: Icons.view_module_rounded,
                      highlighted: _board.isFull,
                      onPressed: _goToPlaceValue,
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

/// 当前的数。点一下重听一遍中英播报。
class _CountDisplay extends StatelessWidget {
  const _CountDisplay({super.key, required this.value, required this.onTap});

  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: FittedBox(
        child: Text(
          '$value',
          style: TextStyle(
            fontSize: BlockMetrics.minGrabTarget * 1.6,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: BlockColors.ink,
          ),
        ),
      ),
    );
  }
}

/// 托盘里的「源」。按下即填，可以一直按。
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

/// 网格本身。
///
/// **一张画，不接受任何触摸**——见类文档：格子只有约 28dp，远低于抓取阈值，
/// 不得作为操作对象。
class _BoardPainter extends CustomPainter {
  const _BoardPainter({required this.board, required this.cellSize});

  final HundredBoard board;
  final double cellSize;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = cellSize * 0.08;
    final radius = Radius.circular(cellSize * 0.22);

    final empty = Paint()..color = BlockColors.ink.withValues(alpha: 0.07);
    final rowFill = Paint()..color = PieceColors.of(PlacePiece.rod);
    final looseFill = Paint()..color = PieceColors.of(PlacePiece.unit);

    for (var index = 0; index < HundredBoard.capacity; index++) {
      final cell = HundredBoard.cellAt(index);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cell.col * cellSize + inset,
          cell.row * cellSize + inset,
          cellSize - inset * 2,
          cellSize - inset * 2,
        ),
        radius,
      );

      if (index >= board.filled) {
        canvas.drawRRect(rect, empty);
        continue;
      }
      // 整行用十条的颜色、零散格用单块的颜色：34 一眼就是「三行十个」加
      // 「四个」，位值不用讲。
      canvas.drawRRect(
        rect,
        board.isInCompletedRow(index) ? rowFill : looseFill,
      );
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.board != board || old.cellSize != cellSize;
}

/// 填满一行时的烟花。
///
/// 与积木的脸、音效一样走程序化绘制：零素材、零依赖、参数可调，风格自洽。
class _FireworksPainter extends CustomPainter {
  const _FireworksPainter({
    required this.row,
    required this.cellSize,
    required this.progress,
  });

  final int row;
  final double cellSize;

  /// 0 → 1。
  final double progress;

  static const int _particles = 18;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final origin = Offset(
      HundredBoard.columns * cellSize / 2,
      (row + 0.5) * cellSize,
    );
    // 先快后慢地飞出去，同时淡出——爆开的手感来自这条曲线，不是粒子数量。
    final spread = Curves.easeOutCubic.transform(progress);
    final fade = (1.0 - progress) * (1.0 - progress);
    final maxRadius = HundredBoard.columns * cellSize * 0.55;

    // 每行用固定的抖动，同一行反复放烟花时形状一致，不会闪成两个样子。
    final jitter = math.Random(row);

    for (var i = 0; i < _particles; i++) {
      final angle = i / _particles * math.pi * 2 + jitter.nextDouble();
      final distance = maxRadius * spread * (0.6 + jitter.nextDouble() * 0.6);
      final center =
          origin + Offset(math.cos(angle), math.sin(angle) * 0.7) * distance;

      final paint = Paint()
        ..color = BlockColors.forIndex(i).withValues(alpha: fade);
      canvas.drawCircle(
        center,
        cellSize * 0.22 * (1.0 - progress * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FireworksPainter old) =>
      old.progress != progress || old.row != row || old.cellSize != cellSize;
}
