/// 单词拼图的渲染层。
///
/// 只做两件事：把已选字母与字母池画出来、把点击翻译成动作。
/// 提交判定（忽略大小写、必须用完所有字母）全在状态机里。
///
/// **与旧版的差异**：旧版支持指针拖动字母块（全局 `pointermove` 监听 +
/// `elementFromPoint` 命中测试），这里只保留点按——拖动在 Flutter 里要
/// 自定义手势竞技场与命中测试，收益仅是手感，而旧版那套命令式 DOM 操作
/// 本身就是 `docs/CLEAN_CODE_BASELINE.md` 的反例。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/games/word_builder.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 单词拼图视图。
class WordBuilderView extends StatelessWidget {
  /// 以状态与派发回调构造。
  const new({required this.state, required this.onAction, super.key});

  /// 状态机状态。
  final WordBuilderState state;

  /// 动作派发。
  final ValueChanged<Object> onAction;

  @override
  Widget build(BuildContext context) {
    final question = state.current;
    if (question == null) return const SizedBox.shrink();
    if (state.revealed) return _Revealed(state: state, onAction: onAction);

    final letters = question.word.letters;
    final built = <LetterTile>[
      for (final id in state.selectedIds)
        for (final tile in letters)
          if (tile.id == id) tile,
    ];
    return Column(
      children: <Widget>[
        Text(
          '根据释义拼出英文',
          style: LexiType.footnote.copyWith(
            color: context.lexiColors.quaternaryLabel,
          ),
        ),
        const SizedBox(height: LexiSpace.s8),
        Text(
          question.word.definition,
          textAlign: TextAlign.center,
          style: LexiType.title2.copyWith(
            color: context.lexiColors.label,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: LexiSpace.s14),
        _BuiltRow(
          built: built,
          wrong: state.wrong,
          onTap: (id) => onAction(DeselectLetter(id)),
        ),
        const SizedBox(height: LexiSpace.s14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            for (final tile in letters)
              _LetterTileBox(
                label: tile.value,
                used: state.selectedIds.contains(tile.id),
                onTap: () => onAction(SelectLetter(tile.id)),
              ),
          ],
        ),
        const SizedBox(height: LexiSpace.s20),
        Row(
          children: <Widget>[
            OutlinedButton(
              onPressed: state.selectedIds.isEmpty
                  ? null
                  : () => onAction(const ClearLetters()),
              child: const Text('清空'),
            ),
            const SizedBox(width: LexiSpace.s8),
            OutlinedButton(
              onPressed: () => onAction(const RevealWord()),
              child: const Text('不认识'),
            ),
            const SizedBox(width: LexiSpace.s8),
            Expanded(
              child: FilledButton(
                onPressed: state.isComplete
                    ? () => onAction(const SubmitWord())
                    : null,
                child: const Text('提交答案'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BuiltRow extends StatelessWidget {
  const new({required this.built, required this.wrong, required this.onTap});

  final List<LetterTile> built;
  final bool wrong;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LexiRadius.lg),
        border: Border.all(
          color: wrong ? colors.danger : colors.accent.withValues(alpha: 0.3),
          width: 2,
        ),
        color: wrong
            ? colors.danger.withValues(alpha: 0.06)
            : colors.accent.withValues(alpha: 0.04),
      ),
      padding: const EdgeInsets.all(LexiSpace.s8),
      child: built.isEmpty
          ? Center(
              child: Text(
                '点按字母拼写',
                style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
              ),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: <Widget>[
                for (final tile in built)
                  _LetterTileBox(
                    label: tile.value,
                    used: false,
                    filled: true,
                    onTap: () => onTap(tile.id),
                  ),
              ],
            ),
    );
  }
}

class _LetterTileBox extends StatelessWidget {
  const new({
    required this.label,
    required this.used,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final bool used;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Opacity(
      opacity: used ? 0.25 : 1,
      child: Material(
        color: filled ? colors.accent : colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: InkWell(
          onTap: used ? null : onTap,
          borderRadius: BorderRadius.circular(LexiRadius.sm),
          child: SizedBox(
            width: LexiSpace.s40,
            height: LexiSpace.s40,
            child: Center(
              child: Text(
                label.toUpperCase(),
                style: LexiType.title.copyWith(
                  color: filled ? Colors.white : colors.label,
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

class _Revealed extends StatelessWidget {
  const new({required this.state, required this.onAction});

  final WordBuilderState state;
  final ValueChanged<Object> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final question = state.current!;
    return Column(
      children: <Widget>[
        Text(
          '正确答案 · 计时已暂停',
          style: LexiType.body.copyWith(
            color: colors.warningDeep,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LexiSpace.s12),
        Text(
          question.word.term,
          style: LexiType.display.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: LexiSpace.s10),
        Text(
          '记住它的拼写，然后继续下一题。该词已记入错词，之后会优先复习。',
          textAlign: TextAlign.center,
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: LexiSpace.s16),
        FilledButton.icon(
          onPressed: () => onAction(const ConfirmRevealed()),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: const Text('记住了，继续'),
        ),
      ],
    );
  }
}
