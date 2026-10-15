/// 选择题的选项网格（小游戏与音标训练共用）。
///
/// 对应旧版 `games/page.tsx` 的 `ChoiceGrid` 与
/// `phonetics/phonetic-question.tsx` 的选项按钮。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 一个选项的三态。
enum ChoiceState {
  /// 未选中。
  idle,

  /// 选错了（红色抖动）。
  wrong,

  /// 是正确答案（绿色高亮）。
  correct,
}

/// 选项网格。
class GameChoiceGrid extends StatelessWidget {
  /// 以各字段构造。
  const new({
    required this.choices,
    required this.onChoose,
    this.stateOf,
    this.subtitleOf,
    this.promptStyle,
    this.enabled = true,
    super.key,
  });

  /// 选项文本。
  final List<String> choices;

  /// 点选回调。
  final ValueChanged<String> onChoose;

  /// 计算某个选项的状态；为空时全部按未选中渲染。
  final ChoiceState Function(String choice)? stateOf;

  /// 选项的副标题（听音选词题展示中文释义）。
  final String Function(String choice)? subtitleOf;

  /// 选项文本样式（音标用等宽字体）。
  final TextStyle? promptStyle;

  /// 是否可点。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: columns == 2 ? 3.4 : 4.4,
          children: <Widget>[
            for (final choice in choices)
              _ChoiceTile(
                label: choice,
                subtitle: subtitleOf?.call(choice),
                state: stateOf?.call(choice) ?? ChoiceState.idle,
                labelStyle: promptStyle,
                onTap: enabled ? () => onChoose(choice) : null,
              ),
          ],
        );
      },
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const new({
    required this.label,
    required this.state,
    required this.onTap,
    this.subtitle,
    this.labelStyle,
  });

  final String label;
  final String? subtitle;
  final ChoiceState state;
  final TextStyle? labelStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final border = switch (state) {
      ChoiceState.wrong => colors.danger,
      ChoiceState.correct => colors.success,
      ChoiceState.idle => colors.borderDefault,
    };
    final background = switch (state) {
      ChoiceState.wrong => colors.danger.withValues(alpha: 0.1),
      ChoiceState.correct => colors.success.withValues(alpha: 0.12),
      ChoiceState.idle => Colors.transparent,
    };
    return LiquidGlass(
      level: GlassLevel.subtle,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LexiRadius.md),
              border: Border.all(color: border),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s14,
              vertical: LexiSpace.s10,
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style:
                      labelStyle ??
                      LexiType.title.copyWith(
                        color: colors.label,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LexiType.caption.copyWith(
                      color: colors.quaternaryLabel,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
