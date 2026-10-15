/// 词汇地鼠的渲染层。
///
/// 只做两件事：按 [WhackAMoleState.isMoleUp] 决定哪几只地鼠露头，
/// 把点击翻译成 `WhackMole` 动作。判定与计分全在状态机里。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/games/whack_a_mole.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 词汇地鼠视图。
class WhackAMoleView extends StatelessWidget {
  /// 以状态与派发回调构造。
  const new({required this.state, required this.onAction, super.key});

  /// 状态机状态。
  final WhackAMoleState state;

  /// 动作派发。
  final ValueChanged<Object> onAction;

  @override
  Widget build(BuildContext context) {
    final question = state.current;
    final layout = state.layout;
    if (question == null || layout == null) return const SizedBox.shrink();

    return Column(
      children: <Widget>[
        Text(
          '看释义，锤出正确的单词地鼠',
          style: LexiType.footnote.copyWith(
            color: context.lexiColors.quaternaryLabel,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          question.word.definition,
          textAlign: TextAlign.center,
          style: LexiType.title2.copyWith(
            color: context.lexiColors.label,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: <Widget>[
            for (var hole = 0; hole < whackAMoleHoleCount; hole += 1)
              _Hole(
                word: _wordAtHole(layout, hole),
                up: _isUpAtHole(layout, hole),
                wrong: _isWrongAtHole(layout, hole),
                onTap: onAction,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '地鼠缩回前锤中正确单词 · 锤错会记一次失误',
          style: LexiType.caption.copyWith(
            color: context.lexiColors.tertiaryLabel,
          ),
        ),
      ],
    );
  }

  String? _wordAtHole(WhackAMoleLayout layout, int hole) {
    final index = layout.holes.indexOf(hole);
    final question = state.current;
    if (index < 0 || question == null) return null;
    if (index >= question.choices.options.length) return null;
    return question.choices.options[index];
  }

  bool _isUpAtHole(WhackAMoleLayout layout, int hole) {
    final index = layout.holes.indexOf(hole);
    return index >= 0 && state.isMoleUp(index);
  }

  bool _isWrongAtHole(WhackAMoleLayout layout, int hole) {
    final word = _wordAtHole(layout, hole);
    return word != null && state.whackedWrong.contains(word);
  }
}

class _Hole extends StatelessWidget {
  const new({
    required this.word,
    required this.up,
    required this.wrong,
    required this.onTap,
  });

  final String? word;
  final bool up;
  final bool wrong;
  final ValueChanged<Object> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final visible = word != null && up;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        SizedBox(
          height: 54,
          child: visible
              ? AnimatedScale(
                  scale: 1,
                  duration: const Duration(milliseconds: 160),
                  child: Material(
                    color: wrong
                        ? colors.danger.withValues(alpha: 0.85)
                        : colors.warning.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(LexiRadius.md),
                    child: InkWell(
                      onTap: () => onTap(WhackMole(word!)),
                      borderRadius: BorderRadius.circular(LexiRadius.md),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            word!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: LexiType.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 4),
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: colors.borderStrong,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ],
    );
  }
}
