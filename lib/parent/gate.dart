import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design/tokens.dart';

/// 一道两位数乘法题。
///
/// 这道题唯一的作用是**挡住一个三岁的孩子**，不是防成年人。所以它不需要难，
/// 只需要不可能被乱按蒙对——两位数相乘的答案有三到四位，随机点中的概率
/// 低于千分之一，而他连「答案要填在哪」都不会知道。
@immutable
class ParentGateChallenge {
  const ParentGateChallenge(this.a, this.b);

  final int a;
  final int b;

  int get answer => a * b;

  /// 抽一道新题，**保证与 [previous] 不同**。
  ///
  /// 规格要求答错后重试时换题：同一道题反复出现，等于把「答错了」变成
  /// 「你刚才那个答案再输一遍试试」——那不是验证，是刁难。
  static ParentGateChallenge next(math.Random random, {
    ParentGateChallenge? previous,
  }) {
    for (var attempt = 0; attempt < 32; attempt++) {
      final candidate = ParentGateChallenge(
        11 + random.nextInt(19), // 11..29
        11 + random.nextInt(9), // 11..19
      );
      if (candidate != previous) return candidate;
    }
    // 连抽 32 次都撞上同一道题在实践中不会发生；真发生了也得给出一道题，
    // 于是把其中一个因数挪开一格——**绝不能返回 null 让家长区进不去**。
    final fallback = previous ?? const ParentGateChallenge(12, 13);
    return ParentGateChallenge(fallback.a == 29 ? 11 : fallback.a + 1, fallback.b);
  }

  @override
  bool operator ==(Object other) =>
      other is ParentGateChallenge && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => '$a × $b';
}

/// 家长区入口：长按 3 秒。
///
/// 见 parent-zone 规格「家长门」。两道关卡各挡一件事：
///
/// - **长按 3 秒**挡住误触。三岁的手指按住一个地方三秒不动是件很难的事，
///   而这一条同时也挡住了大人自己口袋里的误触。
/// - **乘法题**挡住「他真的按住了三秒」这种情况。
///
/// 入口本身刻意**又小又灰**：它不是给孩子看的东西，长得越不像可以按的地方
/// 越好。这也是这个 App 里唯一一处不遵守 90dp 抓取阈值的可按元素——那条
/// 红线是为了让孩子按得中，这里要的正好相反。
class ParentGateEntry extends StatefulWidget {
  const ParentGateEntry({
    super.key,
    required this.onUnlockRequested,
    this.holdDuration = const Duration(seconds: 3),
  });

  /// 长按满时长后调用。
  final VoidCallback onUnlockRequested;

  final Duration holdDuration;

  /// 入口的边长。刻意小于 [BlockMetrics.minGrabTarget]，见类文档。
  static const double size = 44.0;

  @override
  State<ParentGateEntry> createState() => _ParentGateEntryState();
}

class _ParentGateEntryState extends State<ParentGateEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _hold.value = 0;
    widget.onUnlockRequested();
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  /// 松手就归零，**不保留进度**。
  ///
  /// 攒进度会让孩子的反复乱按最终累积到 3 秒——那正是这道门要挡的事。
  void _release() => _hold.value = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _hold.forward(from: 0),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: SizedBox(
        width: ParentGateEntry.size,
        height: ParentGateEntry.size,
        child: AnimatedBuilder(
          animation: _hold,
          builder: (context, _) => CustomPaint(
            painter: _HoldRingPainter(progress: _hold.value),
          ),
        ),
      ),
    );
  }
}

/// 长按进度环。
///
/// 有进度反馈是给**大人**看的：没有它，按住的人不知道要按多久，
/// 三秒会长得像坏了。
class _HoldRingPainter extends CustomPainter {
  const _HoldRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.28;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = BlockColors.ink.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = BlockColors.ink.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) => old.progress != progress;
}

/// 乘法题页面。
///
/// 答对 → `Navigator.pop(true)`；答错 → 立刻 `pop(false)` 回儿童端。
/// **答错不给重试机会**，因为重试就是「多按几次总能过」；重新长按 3 秒
/// 才是这道门要收的代价，那时会换一道新题。
class ParentGatePage extends StatefulWidget {
  const ParentGatePage({super.key, required this.challenge});

  final ParentGateChallenge challenge;

  @override
  State<ParentGatePage> createState() => _ParentGatePageState();
}

class _ParentGatePageState extends State<ParentGatePage> {
  String _entered = '';

  /// 答案最多四位（29×19=551，三位；留一位余量）。
  static const int _maxDigits = 4;

  void _digit(int d) {
    if (_entered.length >= _maxDigits) return;
    setState(() => _entered += '$d');
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _submit() {
    final correct = int.tryParse(_entered) == widget.challenge.answer;
    Navigator.of(context).pop(correct);
  }

  @override
  Widget build(BuildContext context) {
    // 家长区是**唯一有文字的地方**，也是唯一按成人尺度排版的地方。
    return Scaffold(
      backgroundColor: BlockColors.skyBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BlockMetrics.gap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '家长验证',
                  style: TextStyle(
                    fontSize: 15,
                    color: BlockColors.ink,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: BlockMetrics.gap / 2),
                Text(
                  '${widget.challenge.a} × ${widget.challenge.b} = ?',
                  key: const ValueKey('question'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: BlockColors.ink,
                  ),
                ),
                const SizedBox(height: BlockMetrics.gap / 2),
                Container(
                  key: const ValueKey('answer'),
                  width: 180,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _entered,
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 4,
                      color: BlockColors.ink,
                    ),
                  ),
                ),
                const SizedBox(height: BlockMetrics.gap / 2),
                SizedBox(
                  width: 260,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var d = 1; d <= 9; d++)
                        _Key(label: '$d', onPressed: () => _digit(d)),
                      _Key(
                        label: '⌫',
                        onPressed: _backspace,
                        keyValue: 'backspace',
                      ),
                      _Key(label: '0', onPressed: () => _digit(0)),
                      _Key(
                        label: '✓',
                        onPressed: _submit,
                        keyValue: 'submit',
                        primary: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BlockMetrics.gap / 2),
                TextButton(
                  key: const ValueKey('cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onPressed,
    this.keyValue,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final String? keyValue;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 48,
      child: FilledButton(
        key: ValueKey('gate-key-${keyValue ?? label}'),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: primary ? BlockColors.forIndex(4) : Colors.white,
          foregroundColor: primary ? Colors.white : BlockColors.ink,
          padding: EdgeInsets.zero,
        ),
        child: Text(label, style: const TextStyle(fontSize: 19)),
      ),
    );
  }
}

/// 走一遍完整的家长门：出题 → 弹页 → 返回是否通过。
///
/// 抽成函数是为了让「长按之后发生什么」只有一处实现——首页、模块内、
/// 日后任何一个想进家长区的地方，走的都必须是同一道门。
Future<bool> runParentGate(
  BuildContext context, {
  math.Random? random,
  ParentGateChallenge? previous,
}) async {
  final challenge = ParentGateChallenge.next(
    random ?? math.Random(),
    previous: previous,
  );
  final passed = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => ParentGatePage(challenge: challenge)),
  );
  return passed ?? false;
}
