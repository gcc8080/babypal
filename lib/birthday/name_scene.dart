import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_bus.dart';
import '../core/audio/audio_providers.dart';
import '../core/audio/sfx.dart';
import '../core/block/block_model.dart';
import '../core/content/content_providers.dart';
import '../core/content/models.dart';
import '../core/design/glyph_tile.dart';
import '../core/design/tokens.dart';
import '../modules/letters/letters.dart';

/// 彩蛋里那个名字的 id。
///
/// 内容包 `letters.json` 的 `spellingTargets` 里还有 Mama / Baba——那是字母
/// 模块终关的备选目标。**彩蛋只认这一个**：这一幕的全部意义就是他看见
/// 自己的名字。
const String kChildSpellingId = 'child';

/// 每个字母之间隔多久落地。
///
/// 与名词卡飞入（`kWordStagger` 220ms）取同一个量级但更慢一点：那边是三张
/// 卡扫一眼，这边他要**一个一个认出来**。太快就变成一团字母同时砸下来。
const Duration kNameLetterStagger = Duration(milliseconds: 300);

/// 单个字母飞进来用多久。
const Duration kNameLetterFlyIn = Duration(milliseconds: 420);

/// 名字拼完之后停留多久再交给下一幕。
///
/// 这段时间里要放完「（名字）· 生日快乐」两条播报，而且**得让他把整个名字
/// 看一会儿**——这一幕没有任何可操作的东西，唯一的内容就是那几个字母站在
/// 那里。撤得太快，他还没反应过来发生了什么。
const Duration kNameHold = Duration(milliseconds: 2600);

/// 拼名字动画——彩蛋的第一幕。
///
/// 见 birthday 规格「首启一次性生日彩蛋」：以孩子姓名字母**逐个飞入**的
/// 拼字动画开场；以及「彩蛋数据与资源可缺失」：姓名未配置时优雅省略。
///
/// **姓名来自内容包，不硬编码**（`spellingTargets`，与字母模块终关同一份
/// 数据）。换个孩子、改个拼法都是改 JSON，不是改 Dart——这条在字母模块那边
/// 已经立过一次，这里没有理由破例。
///
/// 这是一幕**被动画面**：他不需要做任何事。所以在 [BirthdayEgg] 那边它是
/// `tapAnywhereSkips: true` 的——他一碰就说明想往下走了。互动幕（蜡烛）
/// 不能这样，那边伸手是在玩。
class NameScene extends ConsumerStatefulWidget {
  const NameScene({super.key, required this.target, this.onFinished});

  /// 要拼的名字。由 [birthdayScenes] 从内容包里取好传进来——
  /// 「今年有没有这一幕」是那边的判断，这里只管演。
  final SpellingTarget target;

  final VoidCallback? onFinished;

  @override
  ConsumerState<NameScene> createState() => _NameSceneState();
}

class _NameSceneState extends ConsumerState<NameScene> {
  /// 已经落地几个字母。
  int _landed = 0;

  Timer? _ticker;
  Timer? _holdTimer;

  AudioBus get _audio => ref.read(audioBusProvider);

  List<String> get _letters => widget.target.letters;

  bool get _complete => _landed >= _letters.length;

  @override
  void initState() {
    super.initState();
    // 第一个字母也走定时器，不在 initState 里直接落：这样「每个字母之间隔
    // 300ms」这件事只有一处实现，第一个和后面几个的节奏天然一致。
    _ticker = Timer.periodic(kNameLetterStagger, (_) => _dropNext());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  void _dropNext() {
    if (!mounted || _complete) return;
    final index = _landed;
    setState(() => _landed += 1);

    _audio.playSfx(Sfx.snap);
    // 落一个念一个字母名。这正是他在字母模块听熟的那条播报——名字不是
    // 一串图案，是**他认识的那些字母**排在一起。
    final letter = ref
        .read(contentLibraryProvider)
        .letterByChar(_letters[index]);
    if (letter != null) {
      unawaited(_audio.speak(letter.voiceKey));
    }

    if (_complete) {
      _ticker?.cancel();
      _finishSoon();
    }
  }

  void _finishSoon() {
    // 整个名字念一遍，再说生日快乐。`target.voiceKey` 是家长最该录的那一条
    // ——他自己的名字，用爸爸妈妈的声音（见 6.6 录音顺序，名字排第一）。
    // 没录也无妨，覆盖层会回落到 TTS。
    unawaited(
      _audio.speakSequence([
        widget.target.voiceKey,
        'zh.birthday.happyBirthday',
      ]),
    );
    _holdTimer = Timer(kNameHold, () {
      if (mounted) widget.onFinished?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(BlockMetrics.gap),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = _tileSide(constraints);
              return Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _letters.length; i++) ...[
                      if (i > 0) SizedBox(width: BlockMetrics.gap / 2),
                      _FlyingLetter(
                        key: ValueKey('name-letter-$i'),
                        letter: _letters[i],
                        side: side,
                        landed: i < _landed,
                        // 落定之后整排一起笑——不是逐个笑，那样最后一个
                        // 落地时前面几个已经笑完了，看上去像各演各的。
                        celebrating: _complete,
                        // 单数从左边飞、双数从右边飞：全从同一侧过来，
                        // 后面几个会一直穿过前面已经站好的字母。
                        fromLeft: i.isEven,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 一块字母积木多大。
  ///
  /// **不套 `minGrabTarget`**：那条 90dp 是**可抓取目标**的下限，而这一幕
  /// 一个字母都点不了。名字长起来（比如四个汉字拼音）时硬守 90dp 只会让
  /// 整排溢出屏幕——那才是真的看不见。上限给 160dp，否则「Bo」两个字母
  /// 会撑成两块巨砖。
  double _tileSide(BoxConstraints constraints) {
    final n = _letters.length;
    final gaps = BlockMetrics.gap / 2 * (n - 1);
    final byWidth = (constraints.maxWidth - gaps) / n;
    return byWidth.clamp(24.0, 160.0).clamp(0.0, constraints.maxHeight);
  }
}

/// 一个飞进来的字母。
///
/// 用隐式动画而不是 `AnimationController`：这一幕的状态只有「落了没有」，
/// 没有需要逐帧读取的中间值。
class _FlyingLetter extends StatelessWidget {
  const _FlyingLetter({
    super.key,
    required this.letter,
    required this.side,
    required this.landed,
    required this.celebrating,
    required this.fromLeft,
  });

  final String letter;
  final double side;
  final bool landed;
  final bool celebrating;
  final bool fromLeft;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      // 6 倍宽度足够飞出屏幕外——`AnimatedSlide` 只改绘制位置，不影响布局，
      // 因此不会把 `Row` 撑开，也不会有 overflow 告警。
      offset: landed ? Offset.zero : Offset(fromLeft ? -6 : 6, 0),
      duration: kNameLetterFlyIn,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: landed ? 1 : 0,
        duration: kNameLetterFlyIn,
        child: SizedBox(
          width: side,
          height: side,
          child: GlyphTile(
            glyph: letter,
            color: letterColor(letter),
            expression: celebrating
                ? BlockExpression.happy
                : BlockExpression.idle,
          ),
        ),
      ),
    );
  }
}
