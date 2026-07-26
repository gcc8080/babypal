import 'package:flutter/material.dart';

import '../../core/block/block_face.dart';
import '../../core/block/block_model.dart';
import '../../core/design/tokens.dart';
import 'module_emblem.dart';
import 'module_id.dart';

/// 首页「方块星球」。
///
/// 五块大陆对应五个模块，**纯图形、零文字**（child-safety-ux 规格）。
/// 每块大陆都是一块有脸的积木——会眨眼、会挤压回弹，点下去必有回应。
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    this.enabledModules = ModuleId.values,
    this.onModuleSelected,
  });

  /// 启用的模块。家长区可关闭某个模块，关掉后首页不再显示其入口。
  final List<ModuleId> enabledModules;

  final void Function(ModuleId module)? onModuleSelected;

  @override
  Widget build(BuildContext context) {
    final scale = BlockScale.of(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 大陆尺寸按可用宽度分配，但**下限锁死在抓取阈值**上——
            // 屏幕再窄也不能让入口小到 3 岁的手指按不准。
            final count = enabledModules.length;
            final gap = BlockMetrics.gap * scale;
            final available = constraints.maxWidth - gap * (count + 1);
            final byWidth = count == 0 ? 0.0 : available / count;
            final byHeight = constraints.maxHeight * 0.52;
            // 下限是**绝对的 90dp**，不乘缩放因子。dp 已经是密度无关单位，
            // 90dp 对应的是手指的物理尺寸；小屏上再乘 0.85 就成了 76dp，
            // 恰好击穿这条红线本身要守的东西。缩放只能把入口放大。
            final tileSize = [
              byWidth,
              byHeight,
            ].reduce((a, b) => a < b ? a : b).clamp(
                  BlockMetrics.minGrabTarget,
                  double.infinity,
                );

            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: PlanetArcPainter(
                      color: BlockColors.forIndex(4).withValues(alpha: 0.18),
                    ),
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: gap),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (final module in enabledModules) ...[
                          _ContinentTile(
                            // 稳定 Key：既让 Flutter 在模块开关变化时正确复用
                            // 状态，也让测试能精确定位到入口本身。
                            key: ValueKey(module),
                            module: module,
                            size: tileSize,
                            onTap: () => onModuleSelected?.call(module),
                          ),
                          if (module != enabledModules.last)
                            SizedBox(width: gap),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 一块大陆 = 一个模块入口。
///
/// 复用积木的触摸语汇：按下挤压、松手弹回、脸会变表情。首页和玩法里的手感
/// 必须是同一套，否则孩子要学两次「怎么按」。
class _ContinentTile extends StatefulWidget {
  const _ContinentTile({
    super.key,
    required this.module,
    required this.size,
    required this.onTap,
  });

  final ModuleId module;
  final double size;
  final VoidCallback onTap;

  @override
  State<_ContinentTile> createState() => _ContinentTileState();
}

class _ContinentTileState extends State<_ContinentTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _squash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 320),
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 1.0,
    end: BlockMetrics.squashScale,
  ).animate(
    CurvedAnimation(
      parent: _squash,
      curve: Curves.easeOut,
      reverseCurve: Curves.elasticOut.flipped,
    ),
  );

  bool _pressed = false;

  /// 按下点，用于区分「点击」与「横向滑动列表」。
  Offset? _downPosition;

  /// 与积木引擎同一个阈值：3 岁的手指按下必然带位移。
  static const double _tapSlop = 14.0;

  @override
  void dispose() {
    _squash.dispose();
    super.dispose();
  }

  // 用原始 [Listener] 而非 GestureDetector：`onTapDown` 要等手势竞技场裁决，
  // 而外层的横向滚动识别器会参与竞争，导致**按下去要等一下才有形变**——
  // 这直接违反「每一次触摸都必须立刻有可感知反馈」这条红线。
  // 原始指针事件不经过竞技场，按下即响应。
  void _onPointerDown(PointerDownEvent event) {
    _downPosition = event.position;
    setState(() => _pressed = true);
    _squash.forward();
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _downPosition;
    _downPosition = null;
    _release();
    // 位移在阈值内才算点击；超出则是在滑动列表，不触发进入模块。
    if (start != null && (event.position - start).distance <= _tapSlop) {
      widget.onTap();
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _downPosition = null;
    _release();
  }

  void _release() {
    if (!mounted) return;
    setState(() => _pressed = false);
    _squash.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final color = BlockColors.forIndex(widget.module.colorIndex);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          final s = _scale.value;
          return Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..scaleByDouble(1.0 + (1.0 - s) * 0.5, s, 1.0, 1.0),
            child: child,
          );
        },
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(size * 0.22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: size * 0.06,
                      offset: Offset(0, size * 0.035),
                    ),
                  ],
                ),
              ),
              // 徽记在上半部，脸在下半部——像一块印着图案的积木小伙伴。
              Align(
                alignment: const Alignment(0, -0.42),
                child: ModuleEmblem(module: widget.module, size: size * 0.44),
              ),
              Align(
                alignment: const Alignment(0, 0.62),
                child: SizedBox(
                  width: size * 0.5,
                  height: size * 0.3,
                  child: BlockFace(
                    expression: _pressed
                        ? BlockExpression.surprised
                        : BlockExpression.idle,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
