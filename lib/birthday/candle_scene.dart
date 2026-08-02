import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_bus.dart';
import '../core/audio/audio_providers.dart';
import '../core/audio/sfx.dart';
import '../core/block/block_board.dart';
import '../core/block/block_board_controller.dart';
import '../core/block/block_model.dart';
import '../core/block/snap_grid.dart';
import '../core/design/tokens.dart';
import '../core/settings/settings_providers.dart';
import 'breath_detector.dart';
import 'breath_source.dart';
import 'candle_cake.dart';

/// 蜡烛数量。也是他今年的岁数，也是 `1+1+1` 的得数——**三处是同一个 3**。
const int kCandleCount = 3;

/// 拼搭台的格数。三块摆在 0 / 2 / 4 列，两两不相邻。
///
/// 与部件加法同一个道理：起始状态绝不能有两块已经挨着，否则一进画面它们
/// 就自己合了，等于替他把蜡烛点上了。
const int kCandleColumns = 5;

/// 吹着的时候，每灭一根要吸收多少块气流数据。
///
/// 不是一口气全灭：三根依次灭掉才看得出「是我在吹」，而一瞬间全黑更像
/// 画面卡了一下。
///
/// **按块数计，不按墙钟计。** 第一版用 `DateTime.now()` 掐间隔，结果是
/// 节奏取决于「过了多久」而不是「吹进来多少气」——麦克风卡一下、系统调度
/// 慢一拍，蜡烛照样灭。而且这样的东西在测试里根本验不了：`tester.pump`
/// 推的是假时钟，`DateTime.now()` 不跟着走。
///
/// 真机实测一块是 80ms（16kHz 单声道，每块 2560 字节），4 块 ≈ 0.32 秒。
const int kChunksPerCandle = 4;

/// 多久没进展就把「点一下也行」演出来。
///
/// 给得比较长，因为**吹才是他想做的事**——太早提示等于在说「你吹不灭的」。
/// 但也不能不给：三岁的孩子未必吹得准手机麦克风的位置。
const Duration kTapHintDelay = Duration(seconds: 8);

/// 生日彩蛋的蜡烛环节。
///
/// 见 birthday 规格「合体点燃蜡烛」与「蜡烛吹气检测」：
///
/// - 三块单块积木**复用积木引擎的合体交互**合成 3，然后点燃三根蜡烛，
///   播报「一加一加一等于三」。这一段没有一行新的手势代码。
/// - 吹气检测走麦克风 PCM 流算 RMS，不写任何临时文件。
/// - **点一下也能灭，而且一直都能。** 规格只要求没有麦克风时降级为点击，
///   但三岁的孩子未必吹得准麦克风的位置，而这是他的生日——这一关不允许
///   存在「过不去」这个状态。吹是他想做的事，点是兜底，两条同时开着。
class CandleScene extends ConsumerStatefulWidget {
  const CandleScene({super.key, this.breathSource, this.onFinished});

  /// 麦克风来源。为 null 时用真机实现。
  final BreathSource? breathSource;

  /// 三根都灭掉、庆祝放完之后调用。供 8.1 的彩蛋流程串场。
  final VoidCallback? onFinished;

  @override
  ConsumerState<CandleScene> createState() => _CandleSceneState();
}

class _CandleSceneState extends ConsumerState<CandleScene> {
  late final BreathSource _breath = widget.breathSource ?? MicBreathSource();
  final BreathDetector _detector = BreathDetector();

  BlockBoardController? _controller;
  StreamSubscription<Uint8List>? _micSub;
  Timer? _hintTimer;

  /// 已经点着了吗。三块合成 3 之后为真。
  bool _lit = false;

  /// 还剩几根亮着。
  int _remaining = kCandleCount;

  /// 正在吹（由 [BreathDetector] 判定）。只用于让火苗抖起来。
  bool _blowing = false;

  /// 从上一根灭掉之后，又吹进来多少块。见 [kChunksPerCandle]。
  int _blowChunks = 0;

  /// 该把「点一下也行」演出来了。
  bool _showTapHint = false;

  bool _mutating = false;

  AudioBus get _audio => ref.read(audioBusProvider);

  bool get _allOut => _remaining <= 0;

  @override
  void dispose() {
    _hintTimer?.cancel();
    unawaited(_micSub?.cancel());
    unawaited(_breath.stop());
    unawaited(_breath.dispose());
    _controller?.removeListener(_onBoardChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ─── 点燃 ──────────────────────────────────────────────────────────

  /// 三块摆开，隔一列一块。
  void _layOutBlocks() {
    final controller = _controller;
    if (controller == null) return;
    _mutating = true;
    try {
      for (final id in controller.blocks.map((b) => b.id).toList()) {
        controller.removeBlock(id);
      }
      for (var i = 0; i < kCandleCount; i++) {
        controller.addBlock(
          BlockBody(
            id: 'candle-block-$i',
            colorIndex: i * 3,
            anchor: GridCell(i * 2, 0),
          ),
        );
      }
    } finally {
      _mutating = false;
    }
  }

  /// 合体规则：同高就拼长。宽度封顶在 [kCandleCount]，因为这一关的
  /// 目标数就是 3——多出来的宽度没有任何意义。
  BlockBody? _resolveMerge(BlockBody moving, BlockBody target) {
    if (_lit) return null;
    if (moving.heightUnits != target.heightUnits) return null;
    final width = moving.widthUnits + target.widthUnits;
    if (width > kCandleCount) return null;

    final ma = moving.anchor;
    final ta = target.anchor;
    return BlockBody(
      id: 'candle-merged-$width',
      colorIndex: 4,
      widthUnits: width,
      heightUnits: target.heightUnits,
      expression: BlockExpression.happy,
      anchor: (ma != null && ta != null) ? (ma.col <= ta.col ? ma : ta) : null,
    );
  }

  /// 点选通道：点 A 再点 B 就合体。与加法、部件加法同一条路。
  bool _onBlockTapped(BlockBody block, Offset _) {
    final controller = _controller;
    if (controller == null) return false;
    final selectedId = controller.selectedId;
    if (selectedId == null || selectedId == block.id) return false;

    var merged = false;
    _mutating = true;
    try {
      merged = controller.mergeBlocks(selectedId, block.id) != null;
    } finally {
      _mutating = false;
    }
    if (merged) _onBoardChanged();
    return merged;
  }

  void _onBoardChanged() {
    if (!mounted || _mutating || _lit) return;
    final controller = _controller;
    if (controller == null) return;

    // 拼到一起了（同一行、边挨着边）→ 合体。与部件加法同一条判定。
    final blocks = controller.blocks;
    for (var i = 0; i < blocks.length; i++) {
      for (var j = i + 1; j < blocks.length; j++) {
        if (!blocksAreJoined(blocks[i], blocks[j])) continue;
        _mutating = true;
        try {
          controller.mergeBlocks(blocks[i].id, blocks[j].id);
        } finally {
          _mutating = false;
        }
        _onBoardChanged();
        return;
      }
    }

    final only = blocks.length == 1 ? blocks.single : null;
    if (only != null && only.widthUnits == kCandleCount) _light();
  }

  void _light() {
    setState(() => _lit = true);
    _audio.playSfx(Sfx.merge);

    // 「一加一加一等于三」——三块变成 3 这件事，得用他在加法模块听熟的
    // 那句话说出来，否则这里只是一块变长了的积木。
    final narration = ref.read(narrationProvider);
    unawaited(
      _audio.speakSequence([
        ...narration.sum(const [1, 1, 1]),
        'zh.birthday.blowTheCandles',
      ], policy: VoicePolicy.interrupt),
    );

    unawaited(_startListening());
    _restartHintTimer();
  }

  // ─── 吹灭 ──────────────────────────────────────────────────────────

  Future<void> _startListening() async {
    final available = await _breath.isAvailable();
    if (!mounted) return;
    if (!available) {
      // 没有麦克风就直接把「点一下」演出来——这时候再等 8 秒毫无意义。
      setState(() => _showTapHint = true);
      return;
    }

    try {
      final stream = await _breath.start();
      _micSub = stream.listen(_onAudioChunk, onError: (Object e) {
        debugPrint('蜡烛：麦克风流出错，改用点击 -> $e');
        if (mounted) setState(() => _showTapHint = true);
      });
    } on Exception catch (e) {
      debugPrint('蜡烛：麦克风起不来，改用点击 -> $e');
      if (mounted) setState(() => _showTapHint = true);
    }
  }

  void _onAudioChunk(Uint8List chunk) {
    if (!mounted || _allOut) return;
    final blowing = _detector.add(chunk);
    if (blowing != _blowing) setState(() => _blowing = blowing);
    if (!blowing) {
      // 停下来就不再累积。断续地哈几口不该攒够一根。
      _blowChunks = 0;
      return;
    }

    // 依次熄灭：每吹进来这么多块灭一根，而不是一口气全灭。
    _blowChunks++;
    if (_blowChunks < kChunksPerCandle) return;
    _blowChunks = 0;
    _blowOutOne();
  }

  /// 灭掉一根。吹和点走的是**同一条路**——两种输入，一种结果。
  void _blowOutOne() {
    if (_allOut) return;
    setState(() => _remaining -= 1);
    _audio.playSfx(Sfx.split);
    _restartHintTimer();
    if (_allOut) _celebrate();
  }

  void _onCakeTapped() {
    if (!_lit || _allOut) return;
    _blowChunks = 0;
    _blowOutOne();
  }

  void _restartHintTimer() {
    _hintTimer?.cancel();
    if (_allOut) return;
    if (_showTapHint) return; // 已经在演了，别重置
    _hintTimer = Timer(kTapHintDelay, () {
      if (mounted && !_allOut) setState(() => _showTapHint = true);
    });
  }

  void _celebrate() {
    _hintTimer?.cancel();
    unawaited(_micSub?.cancel());
    _micSub = null;
    unawaited(_breath.stop());
    setState(() {
      _blowing = false;
      _showTapHint = false;
    });
    _audio.playSfx(Sfx.merge);
    unawaited(
      _audio.speakSequence([
        'zh.birthday.happyBirthday',
      ], policy: VoicePolicy.interrupt),
    );
    widget.onFinished?.call();
  }

  // ─── 布局 ──────────────────────────────────────────────────────────

  SnapGrid _buildGrid(BoxConstraints constraints) {
    const cell = BlockMetrics.minGrabTarget;
    final width = cell * kCandleColumns;
    return SnapGrid(
      columns: kCandleColumns,
      rows: 1,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - width) / 2).clamp(0, double.infinity),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BlockMetrics.gap / 2),
          child: Column(
            children: [
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('cake'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _onCakeTapped,
                  child: CandleCake(
                    total: kCandleCount,
                    remaining: _remaining,
                    lit: _lit,
                    blowing: _blowing,
                    showTapHint: _showTapHint,
                  ),
                ),
              ),
              // 点着之后拼搭台就没用了，让位给蛋糕——他该看的是蜡烛。
              if (!_lit)
                SizedBox(
                  height: BlockMetrics.minGrabTarget,
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
                        _layOutBlocks();
                      } else {
                        _controller!.updateGrid(grid);
                      }
                      return BlockBoard(controller: _controller!);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
