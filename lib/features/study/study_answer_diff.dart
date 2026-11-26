/// 答案差异的展示。
///
/// 对应旧版 `src/components/answer-diff.tsx`。算法在
/// `domain/review/answer_diff.dart`，这里只负责上色：红色是「你写的多出来的
/// 部分」，绿色是「正确答案里你漏掉的部分」。
///
/// 判定由调用方给（揭示面板的本地预览），本组件不再依赖服务层的
/// `ReviewOutcome`——自评之前就要显示差异。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/answer_diff.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 会做答案差异对比的题型。
///
/// 只有「要把答案拼出来」的题目才有「差在哪」可言；选择题的错因是选错了项，
/// 界面上已经用颜色标出来了。
const Set<QuestionType> _diffQuestionTypes = <QuestionType>{
  QuestionType.zhToEnSpelling,
  QuestionType.listeningSpelling,
  QuestionType.clozeSentence,
  QuestionType.letterBank,
};

/// 这道题是否有「差在哪」可言。
///
/// 只有要把答案拼出来的题型才值得画差异；选择题的错因是选错了项，选项上已经
/// 标出来了。揭示面板用它决定要不要留出差异块的位置。
bool studyAnswerDiffApplies(StudyItemView item) =>
    _diffQuestionTypes.contains(item.questionType);

/// 答案差异：词条走字符级，句子走词级。
class StudyAnswerDiff extends StatelessWidget {
  /// 以题目、期望答案、用户作答与判定结果构造。
  const new({
    required this.item,
    required this.expectedAnswer,
    required this.answer,
    required this.isCorrect,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 服务层同源的期望答案。
  final String expectedAnswer;

  /// 用户实际提交的答案文本（字母拼词是拼出的字母串）。
  final String answer;

  /// 本地预览的判定结果。
  final bool isCorrect;

  @override
  Widget build(BuildContext context) => _diffView() ?? const SizedBox.shrink();

  /// 构造差异视图；无需展示时返回 `null`。
  ///
  /// 判对就不展示：差异是「你错在哪」的说明，答对了还列一堆红字只会让人
  /// 以为自己错了。
  Widget? _diffView() {
    if (isCorrect) return null;
    if (!_diffQuestionTypes.contains(item.questionType)) return null;
    final expected = expectedAnswer;
    if (item.word.contentType == LexicalContentType.sentence) {
      final diff = sentenceDiff(expected: expected, actual: answer);
      return diff == null ? null : _SentenceDiffView(diff: diff);
    }
    final diff = termDiff(expected: expected, actual: answer);
    return diff == null ? null : _TermDiffView(diff: diff);
  }
}

/// 词条的两行字符级差异。
class _TermDiffView extends StatelessWidget {
  const new({required this.diff});

  final ({List<DiffSegment> expected, List<DiffSegment> actual}) diff;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DiffLine(
          lineKey: const Key('study.diff.actual'),
          label: '你的输入：',
          segments: diff.actual,
          color: colors.danger,
        ),
        const SizedBox(height: LexiSpace.s4),
        _DiffLine(
          lineKey: const Key('study.diff.expected'),
          label: '正确答案：',
          segments: diff.expected,
          color: colors.success,
        ),
      ],
    );
  }
}

/// 一行带标签的差异文本。
class _DiffLine extends StatelessWidget {
  const new({
    required this.lineKey,
    required this.label,
    required this.segments,
    required this.color,
  });

  final Key lineKey;
  final String label;
  final List<DiffSegment> segments;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final base = LexiType.body.copyWith(color: colors.label);
    return Text.rich(
      key: lineKey,
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: label,
            style: LexiType.footnote.copyWith(
              color: colors.tertiaryLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final segment in segments)
            TextSpan(
              text: segment.text,
              style: segment.isDiff
                  ? base.copyWith(
                      color: color,
                      backgroundColor: color.withValues(alpha: LexiTint.tint),
                      decoration: TextDecoration.underline,
                      decorationColor: color.withValues(alpha: LexiTint.half),
                    )
                  : base,
            ),
        ],
      ),
    );
  }
}

/// 句子的词级差异。
class _SentenceDiffView extends StatelessWidget {
  const new({required this.diff});

  final ({List<SentenceDiffWord> words, int editDistance, String expectedText})
  diff;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '逐词对比（红=多写，绿=漏词）',
          style: LexiType.caption.copyWith(
            color: colors.tertiaryLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LexiSpace.s6),
        Wrap(
          key: const Key('study.diff.words'),
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            for (final word in diff.words) _WordChip(word: word),
          ],
        ),
        const SizedBox(height: LexiSpace.s6),
        Text(
          '编辑距离 ${diff.editDistance} · 参考：${diff.expectedText}',
          key: const Key('study.diff.meta'),
          style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
        ),
      ],
    );
  }
}

/// 词级差异里的一个词。
class _WordChip extends StatelessWidget {
  const new({required this.word});

  final SentenceDiffWord word;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final (
      Color foreground,
      Color? background,
      TextDecoration? decoration,
    ) = switch (word.kind) {
      SentenceDiffKind.equal => (colors.secondaryLabel, null, null),
      SentenceDiffKind.extra => (
        colors.danger,
        colors.danger.withValues(alpha: LexiTint.tint),
        null,
      ),
      SentenceDiffKind.missing => (
        colors.success,
        colors.success.withValues(alpha: LexiTint.tint),
        TextDecoration.lineThrough,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s4,
        vertical: LexiSpace.s2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(LexiRadius.xxs),
      ),
      child: Text(
        word.word,
        style: LexiType.footnote.copyWith(
          color: foreground,
          decoration: decoration,
          decorationColor: colors.success.withValues(alpha: LexiTint.half),
        ),
      ),
    );
  }
}
