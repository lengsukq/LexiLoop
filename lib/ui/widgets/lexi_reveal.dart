/// 分区入场：淡入 + 轻微上移。
///
/// **为什么不用 `Future.delayed` 做错峰**：测试里的 `pumpAndSettle` 不会等
/// 一个没有安排帧的定时器，容易留下「动画还没开始」的假象。这里用
/// `AnimationController` 的 `Interval` 表达延迟：延迟与动画共用一条时间线，
/// 既没有悬挂定时器，也能在 `pumpAndSettle` 里自然走完。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';

/// 一个延迟入场的区块。
class LexiReveal extends StatefulWidget {
  /// 以子组件与序号构造。
  const new({required this.child, this.index = 0, super.key});

  /// 区块内容。
  final Widget child;

  /// 同一屏内的序号；越大入场越晚（封顶见 [LexiMotion.staggerMax]）。
  final int index;

  @override
  State<LexiReveal> createState() => _LexiRevealState();
}

class _LexiRevealState extends State<LexiReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: LexiMotion.standard + LexiMotion.stagger(widget.index),
    );
    _fade = CurvedAnimation(parent: _controller, curve: LexiMotion.spring);
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `MediaQuery` 只能在 initState 之后读；开启减弱动态效果时直接落到终态。
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.duration = Duration.zero;
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(_fade),
        child: widget.child,
      ),
    );
  }
}
