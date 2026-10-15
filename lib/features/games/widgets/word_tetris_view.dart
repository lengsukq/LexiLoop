/// 词汇俄罗斯方块的渲染层。
///
/// 方块位置由 [TetrisBlock.progress]（已下落比例）换算——旧版用 CSS
/// `tetris-fall` 关键帧让浏览器自己做插值，Flutter 侧改由状态机提供
/// 剩余下落时间，界面按比例摆放，规则（落地时间、堆叠上限）完全一致。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/games/word_tetris.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 词汇俄罗斯方块视图。
class WordTetrisView extends StatelessWidget {
  /// 以状态与派发回调构造。
  const new({required this.state, required this.onAction, super.key});

  /// 状态机状态。
  final WordTetrisState state;

  /// 动作派发。
  final ValueChanged<Object> onAction;

  /// 轨道区域高度。
  static const double fieldHeight = 340;

  /// 方块高度。
  static const double blockHeight = 44;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final question = state.current;
    if (question == null) return const SizedBox.shrink();
    final full = state.isStackFull;

    return Column(
      children: <Widget>[
        Text(
          '看释义，点中正在下落的正确单词',
          style: LexiType.footnote.copyWith(color: colors.quaternaryLabel),
        ),
        const SizedBox(height: LexiSpace.s8),
        Text(
          question.word.definition,
          textAlign: TextAlign.center,
          style: LexiType.title2.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: LexiSpace.s12),
        SizedBox(
          height: fieldHeight,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.purple.withValues(alpha: LexiTint.subtle),
                    borderRadius: BorderRadius.circular(LexiRadius.lg),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                ),
              ),
              for (final block in state.board.blocks)
                if (!block.resolved)
                  Positioned(
                    left: 8 + block.column * 78,
                    top: block.progress * (fieldHeight - blockHeight),
                    child: _Block(
                      word: block.word,
                      shaking: state.shakingWord == block.word,
                      onTap: () => onAction(TapTetrisBlock(block.word)),
                    ),
                  ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _StackGauge(danger: state.danger),
              ),
            ],
          ),
        ),
        const SizedBox(height: LexiSpace.s8),
        Text(
          '堆叠 ${state.danger}/$wordTetrisDangerCap · 点错会记一次失误 · 堆满结束本轮',
          style: LexiType.caption.copyWith(
            color: full ? colors.danger : colors.tertiaryLabel,
            fontWeight: full ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const new({required this.word, required this.shaking, required this.onTap});

  final String word;
  final bool shaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _blockWidth,
      height: WordTetrisView.blockHeight,
      child: Material(
        color: shaking ? context.lexiColors.danger : const Color(0xFF5856D6),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.sm),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s4),
              child: Text(
                word,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: LexiType.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StackGauge extends StatelessWidget {
  const new({required this.danger});

  final int danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    if (danger <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(LexiSpace.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var index = 0; index < danger; index += 1)
            Padding(
              padding: const EdgeInsets.only(top: LexiSpace.s2),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: colors.purple.withValues(alpha: LexiTint.strong),
                  borderRadius: BorderRadius.circular(LexiRadius.pill),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 下落方块宽度。
const double _blockWidth = 70;
