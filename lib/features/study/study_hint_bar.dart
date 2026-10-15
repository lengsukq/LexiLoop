/// 拼写题的提示区：字母模式 + 提示按钮。
///
/// 对应旧版 `src/app/(main)/study/study-client.tsx` 拼写分支里的那两行
/// （等宽字体的提示模式 + 灯泡按钮）。旧版把「能不能给提示」「还能点几次」
/// 全写在 JSX 的条件表达式里；这里收成一个组件加两个判定函数，界面与快捷键
/// 共用同一份条件。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/hint.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/features/study/study_speech.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 提示模式露出的首尾字母个数，同时也是最短词条长度。
///
/// 来源：旧版 `study-client.tsx` 的 `getHintPattern` 里 `term.length <= 2`
/// 与 `term.slice(1, -1)`——两端各留一个字母，再短就等于直接给答案。
const int _hintEdgeLetterCount = 2;

/// 超过此长度改用连续下划线。
///
/// 来源：旧版同处的 `term.length > 12`。逐字符留空会把长词的提示行撑出屏幕。
const int _hintLongTermLength = 12;

/// 会显示字母提示的题型。
///
/// 只有「要把词拼出来」的题目才需要提示：看词说义/看词选义已经把词条摆在
/// 题干上，给模式毫无意义。
const Set<QuestionType> _hintQuestionTypes = <QuestionType>{
  QuestionType.zhToEnSpelling,
  QuestionType.listeningSpelling,
  QuestionType.clozeSentence,
};

/// 当前词条在基础模式下的提示（未揭开任何字母）。
String? _basePattern(String term) => getHintPattern(
  term,
  edgeLetterCount: _hintEdgeLetterCount,
  longTermLength: _hintLongTermLength,
);

/// 当前词条在 [level] 层提示下的模式。
String? _patternFor(String term, int level) =>
    getProgressiveHint(
      term,
      level,
      edgeLetterCount: _hintEdgeLetterCount,
      longTermLength: _hintLongTermLength,
    ) ??
    _basePattern(term);

/// 这题是否显示字母提示区。
bool studyHintAvailable(StudyItemView item) =>
    _hintQuestionTypes.contains(item.questionType) &&
    item.word.contentType != LexicalContentType.sentence &&
    _basePattern(item.word.term) != null;

/// 这题是否显示「提示」按钮。
///
/// 填空题只给模式、不给按钮：它的答案就是那个词，露首尾已经是很强的提示，
/// 再逐字母揭开等于直接给答案。
bool studyHintButtonAvailable(StudyItemView item) =>
    studyHintAvailable(item) &&
    (item.questionType == QuestionType.zhToEnSpelling ||
        item.questionType == QuestionType.listeningSpelling);

/// 提示区的当前状态与回调。
class StudyHintState {
  /// 以等级、是否用过与「再来一次」回调构造。
  const new({required this.level, required this.used, required this.onHint});

  /// 已揭开的层数；0 表示只露首尾字母。
  final int level;

  /// 本题是否用过提示（决定降级与说明文案）。
  final bool used;

  /// 点「提示」时的回调；为 `null` 表示这题不显示按钮。
  final VoidCallback? onHint;
}

/// 拼写题的提示区。
class StudyHintBar extends ConsumerWidget {
  /// 以题目、口音与提示状态构造。
  const new({
    required this.item,
    required this.accent,
    required this.hint,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 设置中的默认发音口音，供重播使用。
  final Accent accent;

  /// 提示状态与回调。
  final StudyHintState hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = item.word.term;
    final pattern = _patternFor(term, hint.level);
    if (pattern == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          pattern,
          key: const Key('study.hint.pattern'),
          style: TextStyle(
            color: context.lexiColors.accent,
            fontFamily: 'monospace',
            fontSize: LexiType.title.fontSize,
            letterSpacing: 2,
          ),
        ),
        if (hint.onHint != null) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              if (_needsReplay(item)) ...<Widget>[
                _HintAction(
                  icon: Icons.volume_up_rounded,
                  label: '重播发音',
                  onTap: () => unawaited(
                    speakStudyWord(
                      context,
                      ref,
                      word: item.word,
                      accent: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _HintAction(
                icon: Icons.lightbulb_outline_rounded,
                label: hint.level > 0 ? '提示 (${hint.level})' : '提示',
                onTap:
                    isHintExhausted(
                      term,
                      hint.level,
                      edgeLetterCount: _hintEdgeLetterCount,
                    )
                    ? null
                    : hint.onHint,
              ),
            ],
          ),
        ],
        if (hint.used && hint.onHint != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            studyHintPendingText,
            style: LexiType.caption.copyWith(
              color: context.lexiColors.tertiaryLabel,
            ),
          ),
        ],
      ],
    );
  }
}

/// 听音题的题干卡片已经有朗读按钮，这里不再摆第二个。
bool _needsReplay(StudyItemView item) =>
    item.questionType != QuestionType.listeningSpelling;

/// 提示区里的胶囊小按钮。
class _HintAction extends StatelessWidget {
  const new({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final enabled = onTap != null;
    final foreground = enabled ? colors.accent : colors.tertiaryLabel;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: studyMinTapTarget),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: foreground),
        label: Text(label, style: LexiType.body.copyWith(color: foreground)),
      ),
    );
  }
}
