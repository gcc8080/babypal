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
import '../../core/block/block_widget.dart';
import '../../core/block/snap_grid.dart';
import '../../core/content/content_providers.dart';
import '../../core/content/pack_loader.dart';
import '../../core/design/controls.dart';
import '../../core/design/tokens.dart';
import '../hanzi/hanzi.dart';
import 'sandbox_kit.dart';
import 'sandbox_providers.dart';
import 'sandbox_reader.dart';
import 'sandbox_store.dart';

/// 自由沙盒。
///
/// 见 sandbox 规格：**无关卡、无目标、无计分、无正误判定**。孩子把积木放哪
/// 都对，系统不给提示也不催促。这是决定这个 App 能玩两周还是两年的模块——
/// 关卡总会被玩通，空白拼搭台不会。
///
/// 三件事让它成为「沙盒」而不是「第六个玩法」：
///
/// 1. **货架横跨四个内容域**（[SandboxKit]）。数字、字母、汉字部件、纯色块
///    在台面上不是四种东西，就是积木——这正是整个 App 的内核：他在数字模块
///    学会的拖拽与吸附，走到这里一个字都不用重学。
/// 2. **只发现，不要求**（[SandboxReader]）。他自己摆出 `7+8=15` 会被认出来
///    并庆祝；没摆出任何东西时这里是安静的。没有「再试试」，没有目标。
/// 3. **作品留着**（[SandboxStore]）。离开再回来，台面原样。
class SandboxPage extends ConsumerStatefulWidget {
  const SandboxPage({super.key});

  @override
  ConsumerState<SandboxPage> createState() => _SandboxPageState();
}

class _SandboxPageState extends ConsumerState<SandboxPage> {
  /// 清空键的二次确认时长。
  ///
  /// 清空是这一页唯一不可撤销的动作，而他花十分钟堆的塔一按就没这件事，
  /// 比任何一次操作失误都伤人。二次确认用「再按一下」而不是长按或对话框：
  /// 对话框要认字，长按对三岁的手不稳，连按两下他每天都在做。
  static const Duration _confirmWindow = Duration(seconds: 3);

  BlockBoardController? _controller;
  SandboxKit? _kit;
  SandboxReader? _reader;
  SandboxStore? _store;

  int _categoryIndex = 0;
  int _pageIndex = 0;
  int _nextBlockId = 0;
  int _trayCapacity = 0;

  /// 正在改动台面，别把自己的改动当成他的动作。
  bool _mutating = false;

  bool _confirmingClear = false;
  Timer? _confirmTimer;

  /// 当前**still 摆在台面上**的组合签名。
  ///
  /// 存的是集合而不是「上次庆祝的那个」：他可以同时摆着一条算式和一个名字，
  /// 两个都该各自只庆祝一次。签名从这个集合里消失（拆掉了）之后再出现，
  /// 会重新庆祝——那确实是他又做成了一次。
  Set<String> _celebrated = {};

  AudioBus get _audio => ref.read(audioBusProvider);
  ContentLibrary get _library => ref.read(contentLibraryProvider);

  SandboxCategory get _category => _kit!.categories[_categoryIndex];

  @override
  void initState() {
    super.initState();
    _kit = null; // provider 要等到有 ref 才可读，真正的初始化在首帧布局里
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restore();
    });
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    _persist();
    _controller?.removeListener(_onBoardChanged);
    _controller?.dispose();
    super.dispose();
  }

  // ─── 存档 ──────────────────────────────────────────────────────────

  Future<void> _restore() async {
    final store = await ref.read(sandboxStoreProvider.future);
    if (!mounted) return;
    _store = store;
    final saved = store.load();
    if (saved.isEmpty) return;

    final controller = _controller;
    if (controller == null) return;

    _mutate((c) {
      for (final block in saved) {
        c.addBlock(block);
      }
    });
    // 还原的现场里可能本来就摆着一条算式——**不庆祝**。
    // 他刚进页面还没做任何事，此刻出声等于替他邀功。
    _celebrated = {for (final f in _reader!.read(controller.blocks)) f.signature};
  }

  void _persist() {
    final controller = _controller;
    final store = _store;
    if (controller == null || store == null) return;
    unawaited(store.save(controller.blocks));
  }

  // ─── 托盘 ──────────────────────────────────────────────────────────

  /// 把托盘换成当前类别当前页的货。
  ///
  /// 台面上已落位的积木**一块都不动**：换货架不是清场，他正在拼的东西必须
  /// 留在那儿。这也是「跨内容域混搭」真正发生的地方——切到汉字类之后，
  /// 台面上原有的数字块还在，两者就混在一起了。
  void _stockTray() {
    final controller = _controller;
    final kit = _kit;
    if (controller == null || kit == null || _trayCapacity <= 0) return;

    _mutate((c) {
      for (final block in c.blocks) {
        if (block.anchor == null && !c.isDragging(block.id)) {
          c.removeBlock(block.id);
        }
      }
      for (final piece in _category.page(_pageIndex, _trayCapacity)) {
        c.addBlock(piece.spawn('b${_nextBlockId++}'));
      }
    });
  }

  void _nextCategory() {
    setState(() {
      _categoryIndex = (_categoryIndex + 1) % _kit!.categories.length;
      _pageIndex = 0;
    });
    _stockTray();
    _audio.playSfx(Sfx.pickup);
  }

  void _nextPage() {
    setState(() {
      _pageIndex =
          (_pageIndex + 1) % _category.pageCount(math.max(1, _trayCapacity));
    });
    _stockTray();
    _audio.playSfx(Sfx.tap);
  }

  // ─── 清空 ──────────────────────────────────────────────────────────

  void _onClearPressed() {
    if (!_confirmingClear) {
      setState(() => _confirmingClear = true);
      _audio.playSfx(Sfx.tap);
      _confirmTimer?.cancel();
      _confirmTimer = Timer(_confirmWindow, () {
        if (mounted) setState(() => _confirmingClear = false);
      });
      return;
    }
    _confirmTimer?.cancel();
    setState(() => _confirmingClear = false);
    _clear();
  }

  /// 清空：台面上的积木**退回托盘再消失**，不是凭空蒸发。
  ///
  /// 先解锚点，`AnimatedPositioned` 会把它们一块块送回托盘位置（那是引擎
  /// 现成的退回动画）；一拍之后再真正移除。他因此看得见「东西回去了」，
  /// 而不是眼前一花什么都没了。
  void _clear() {
    final controller = _controller;
    if (controller == null) return;

    _mutate((c) {
      for (final block in c.blocks) {
        if (block.anchor != null) {
          c.updateBlocks([block.copyWith(clearAnchor: true)]);
        }
      }
    });
    _audio.playSfx(Sfx.split);
    _celebrated = {};

    Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _stockTray();
      unawaited(_store?.clear() ?? Future<void>.value());
    });
  }

  // ─── 识别 ──────────────────────────────────────────────────────────

  void _onBoardChanged() {
    if (!mounted || _mutating) return;
    final controller = _controller;
    final reader = _reader;
    if (controller == null || reader == null) return;

    // 汉字部件拼到一起就合体，与部件加法完全一样的判定。**沙盒里合体没有
    // 「拼对了」的含义**，只是一件可以做的事——所以合了之后没有下一题，
    // 也没有任何完成态。
    if (_mergeAdjacentHanzi(controller)) return;

    final findings = reader.read(controller.blocks);
    final present = {for (final f in findings) f.signature};
    for (final finding in findings) {
      if (_celebrated.contains(finding.signature)) continue;
      _audio.playSfx(Sfx.merge);
      unawaited(
        _audio.speakSequence(finding.speech, policy: VoicePolicy.interrupt),
      );
    }
    _celebrated = present;

    _refillTray();
    // 拖动过程中每移动一个像素都会走到这里——那时落盘就是每帧一次磁盘写。
    // 手松了再存，反正中途的位置本来也不值得记。
    if (controller.drags.isEmpty) _persist();
  }

  /// 台面上有两块汉字能合成一个字 → 合体并播报「木 加 木 等于 林」。
  ///
  /// 返回 true 表示这一轮已经改动了台面，调用方该让出去等下一次通知。
  bool _mergeAdjacentHanzi(BlockBoardController controller) {
    final blocks = controller.blocks;
    for (var i = 0; i < blocks.length; i++) {
      for (var j = i + 1; j < blocks.length; j++) {
        if (!blocksAreJoined(blocks[i], blocks[j])) continue;
        if (_hanziMerge(blocks[i], blocks[j]) == null) continue;
        _mutate((c) => c.mergeBlocks(blocks[i].id, blocks[j].id));
        return true;
      }
    }
    return false;
  }

  /// 合体规则。和部件加法用的是同一对函数（[componentsOf] / [compoundFrom]），
  /// 不是照抄一遍——两处对「木+木 是不是林」的答案永远一致。
  BlockBody? _hanziMerge(BlockBody moving, BlockBody target) {
    final a = moving.label;
    final b = target.label;
    if (a == null || b == null) return null;

    final library = _library;
    final compound = compoundFrom([
      ...componentsOf(a, library),
      ...componentsOf(b, library),
    ], library);
    if (compound == null) return null;

    final itemA = library.hanziByChar(a);
    final itemB = library.hanziByChar(b);
    if (itemA != null && itemB != null) {
      unawaited(
        _audio.speakSequence(
          HanziNarration.composition([itemA, itemB], compound),
          policy: VoicePolicy.interrupt,
        ),
      );
    }

    final ma = moving.anchor;
    final ta = target.anchor;
    return BlockBody(
      id: 'm${_nextBlockId++}',
      colorIndex: hanziColorIndex(compound.char),
      label: compound.char,
      expression: BlockExpression.happy,
      anchor: (ma != null && ta != null) ? (ma.col <= ta.col ? ma : ta) : null,
    );
  }

  /// 托盘里被拿走的货随手补上——**他永远不会「用完」**。
  ///
  /// 沙盒里「没积木了」是一种失败状态，而这一页不该有任何失败状态。
  void _refillTray() {
    final controller = _controller;
    final kit = _kit;
    if (controller == null || kit == null || _trayCapacity <= 0) return;

    final inTray = controller.blocks.where((b) => b.anchor == null).length;
    if (inTray >= _trayCapacity) return;

    final wanted = _category.page(_pageIndex, _trayCapacity);
    final present = {
      for (final b in controller.blocks)
        if (b.anchor == null) b.label,
    };
    _mutate((c) {
      for (final piece in wanted) {
        if (present.contains(piece.label)) continue;
        c.addBlock(piece.spawn('b${_nextBlockId++}'));
        present.add(piece.label);
      }
    });
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
  }

  void _playSound(BlockSoundEvent event) {
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

  /// 格位边长锁死在抓取阈值上，**列数与行数随屏幕变**。
  ///
  /// 别的模块是反过来的（格数固定、格位随屏幕缩放），因为那里格数由题目决定。
  /// 沙盒没有题目，屏幕大就该能多摆几块——平板上给他一片更大的地板，而不是
  /// 几块更大的积木。
  SnapGrid _buildGrid(BoxConstraints constraints) {
    const min = BlockMetrics.minGrabTarget;
    final gap = BlockMetrics.gap;

    final columns = math.max(3, (constraints.maxWidth / min).floor());
    final cell = math.max(min, constraints.maxWidth / columns);
    // 最后一行留给托盘。
    final rows = math.max(1, ((constraints.maxHeight - gap) / cell).floor() - 1);

    return SnapGrid(
      columns: columns,
      rows: rows,
      cellSize: cell,
      origin: Offset(
        ((constraints.maxWidth - cell * columns) / 2).clamp(0, double.infinity),
        0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _kit ??= SandboxKit(_library);
    _reader ??= SandboxReader(_library);
    final gap = BlockMetrics.gap / 2;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final grid = _buildGrid(constraints);
                    final capacityChanged = _trayCapacity != grid.columns;
                    _trayCapacity = grid.columns;

                    if (_controller == null) {
                      _controller = BlockBoardController(
                        grid: grid,
                        mergeResolver: _hanziMerge,
                        onSound: _playSound,
                      )..addListener(_onBoardChanged);
                      _stockTray();
                    } else {
                      _controller!.updateGrid(grid);
                      // 屏幕变宽/变窄会改变托盘能放几块，这时才需要重新上货。
                      if (capacityChanged) _stockTray();
                    }
                    return BlockBoard(controller: _controller!);
                  },
                ),
              ),
              SizedBox(width: gap),
              _Toolbar(
                sample: _kit!.categories[_categoryIndex].sample,
                confirmingClear: _confirmingClear,
                onCategory: _nextCategory,
                onPage: _nextPage,
                onClear: _onClearPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右侧竖排的三个键：换一类 / 换一批 / 清空。
///
/// 竖排在右侧而不是横排在托盘旁：横排会把托盘挤到只剩三四格，而托盘的宽度
/// 直接决定他一次能看见多少种货。
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.sample,
    required this.confirmingClear,
    required this.onCategory,
    required this.onPage,
    required this.onClear,
  });

  final SandboxPiece sample;
  final bool confirmingClear;
  final VoidCallback onCategory;
  final VoidCallback onPage;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final gap = BlockMetrics.gap / 2;
    return SizedBox(
      width: BlockMetrics.minGrabTarget,
      child: Column(
        children: [
          // 类别键上画的**就是那一类货的样子**，不是一个抽象图标：
          // 他不认识「数字」这个概念的图示，但认识一块写着 3 的积木。
          PressableTile(
            key: const ValueKey('category'),
            width: BlockMetrics.minGrabTarget,
            onPressed: onCategory,
            color: Colors.white,
            child: Center(
              child: SizedBox(
                width: BlockMetrics.minGrabTarget * 0.62,
                height: BlockMetrics.minGrabTarget * 0.62,
                child: BlockWidget(
                  body: sample.spawn('sample'),
                  cellSize: BlockMetrics.minGrabTarget * 0.62,
                ),
              ),
            ),
          ),
          SizedBox(height: gap),
          RoundActionButton(
            key: const ValueKey('page'),
            icon: Icons.more_horiz_rounded,
            onPressed: onPage,
          ),
          const Spacer(),
          // 按一下变绿等着，再按一下才真清。绿色在别处是「成了」，这里是
          // 「就等你这一下」——同一个意思：接下来会发生一件确定的事。
          RoundActionButton(
            key: const ValueKey('clear'),
            icon: confirmingClear
                ? Icons.check_rounded
                : Icons.delete_sweep_rounded,
            highlighted: confirmingClear,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
