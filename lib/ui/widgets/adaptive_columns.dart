/// 按实际内容宽度排列主内容与辅助信息。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';

/// 辅助信息保持可见，空间不足或大字号时顺序排列。
class AdaptiveColumns extends StatelessWidget {
  /// 默认用于表单与资料工作区。
  const new({
    required this.primary,
    required this.secondary,
    this.breakpoint = LexiLayout.wideBreakpoint,
    this.secondaryWidth = 280,
    super.key,
  });

  /// 当前任务。
  final Widget primary;

  /// 概况、来源或操作说明。
  final Widget secondary;

  /// 内容宽度断点。
  final double breakpoint;

  /// 宽屏辅助栏宽度。
  final double secondaryWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < breakpoint ||
          MediaQuery.textScalerOf(context).scale(14) >= 24) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            primary,
            const SizedBox(height: LexiSpace.s24),
            secondary,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: primary),
          const SizedBox(width: LexiSpace.s24),
          SizedBox(width: secondaryWidth, child: secondary),
        ],
      );
    },
  );
}
