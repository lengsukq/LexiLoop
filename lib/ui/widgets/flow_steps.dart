/// 多步导入的轻量阶段提示，不额外改变业务状态机。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 当前阶段具有文字、形状与颜色三种提示。
class FlowSteps extends StatelessWidget {
  /// [current] 为从零开始的阶段编号。
  const new({required this.labels, required this.current, super.key});

  /// 按操作顺序排列的阶段。
  final List<String> labels;

  /// 当前阶段。
  final int current;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: LexiSpace.s20),
    child: Wrap(
      spacing: LexiSpace.s8,
      runSpacing: LexiSpace.s8,
      children: <Widget>[
        for (var i = 0; i < labels.length; i++)
          Semantics(
            selected: i == current,
            label: '第 ${i + 1} 步',
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LexiSpace.s12,
                vertical: LexiSpace.s8,
              ),
              decoration: BoxDecoration(
                color: i == current
                    ? context.lexiColors.accent
                    : context.lexiColors.card,
                borderRadius: BorderRadius.circular(LexiRadius.pill),
              ),
              child: Text(
                '${i + 1}  ${labels[i]}',
                style: LexiType.caption.copyWith(
                  color: i == current
                      ? context.lexiColors.onAccent
                      : context.lexiColors.secondaryLabel,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
