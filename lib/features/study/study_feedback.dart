/// 学习会话的判定反馈与会话总结。
///
/// 反馈面板回答「刚才这题算对还是算错、期望答案是什么、这个词接下来
/// 什么时候再出现」；总结卡片回答「这一轮到底做了什么」。两者都是**只读**
/// 展示，不含任何提交逻辑——避免出现「总结页点一下又提交一次」的路径。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_answer_diff.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 主按钮高度下限（逻辑像素）。
const double _buttonHeight = 50;

/// 提交后的判定反馈。
class StudyFeedbackPanel extends StatelessWidget {
  /// 以判定结果、当前题目、用户作答与「是否用过提示」构造。
  const new({
    required this.outcome,
    required this.item,
    required this.answer,
    required this.usedHint,
    super.key,
  });

  /// 本次作答的完整结果。
  final ReviewOutcome outcome;

  /// 当前题目；答错时要拿它的词条与题型决定差异对比的形态。
  final StudyItemView item;

  /// 用户提交的答案文本。
  final String answer;

  /// 本题是否用过提示；用过就提示用户「建议选模糊」。
  final bool usedHint;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final accent = outcome.isCorrect ? colors.success : colors.danger;
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                outcome.isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              Text(
                outcome.isCorrect ? '回答正确' : '回答错误',
                style: TextStyle(
                  color: accent,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '自评：${studyRatingLabel(outcome.rating)}',
                style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
              ),
            ],
          ),
          if (!outcome.isCorrect) ...<Widget>[
            const SizedBox(height: 10),
            _WrongAnswerDetail(item: item, outcome: outcome, answer: answer),
          ],
          if (usedHint) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              studyHintRevealedText,
              style: TextStyle(color: colors.warning, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          _StatRow(
            label: '掌握度',
            value:
                '${studyMasteryLabel(outcome.masteryLevel)}'
                ' · ${outcome.masteryScore} 分',
          ),
          _StatRow(label: '下次复习', value: _nextReviewText(outcome)),
          if (outcome.adaptiveFollowUp != null) ...<Widget>[
            const SizedBox(height: 10),
            _Notice(
              icon: Icons.repeat_rounded,
              text: '这个词稍后会再出现一次',
              color: colors.accent,
            ),
          ],
          if (outcome.idempotent) ...<Widget>[
            const SizedBox(height: 10),
            _Notice(
              icon: Icons.info_rounded,
              text: '重复提交已忽略，排期未重复推进',
              color: colors.warning,
            ),
          ],
        ],
      ),
    );
  }

  String _nextReviewText(ReviewOutcome outcome) =>
      outcome.scheduledDays <= 0 ? '今天内' : '${outcome.scheduledDays} 天后';
}

/// 答错时的详情：期望答案 + 逐字/逐词差异。
///
/// 期望答案那行始终保留（旧版也保留）：差异对比在「完全没写」或「答对但有
/// 容错」时不会渲染，用户至少要知道正确答案是什么。
class _WrongAnswerDetail extends StatelessWidget {
  const new({required this.item, required this.outcome, required this.answer});

  final StudyItemView item;
  final ReviewOutcome outcome;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '期望答案：${outcome.expectedAnswer}',
          style: TextStyle(color: colors.danger, fontSize: 14),
        ),
        const SizedBox(height: 8),
        StudyAnswerDiff(item: item, outcome: outcome, answer: answer),
      ],
    );
  }
}

/// 会话总结。
class StudySummaryView extends StatelessWidget {
  /// 以会话、再来一轮与返回首页的回调构造。
  const new({
    required this.session,
    required this.onRestart,
    required this.onHome,
    super.key,
  });

  /// 已结束的会话。
  final StudySessionView session;

  /// 「再来一轮」回调。
  final VoidCallback onRestart;

  /// 「返回首页」回调。
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    // 标题按「有没有题目」区分，照旧版 `study-client.tsx:548`：
    // `data.items.length === 0` 时是「暂时没有更多可学习词条」，否则
    // 「本轮学习完成」。两者共用同一个结算视图——对用户来说「今天没词可学」
    // 与「刚做完一轮」是同一件事：现在没得学了，只能再来一轮或回首页。
    final title = session.items.isEmpty ? '暂时没有更多可学习词条' : '这一轮完成了';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: <Widget>[
        Icon(Icons.celebration_rounded, size: 40, color: colors.accent),
        const SizedBox(height: 12),
        Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.label,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 20),
        LiquidGlass(
          level: GlassLevel.elevated,
          borderRadius: BorderRadius.circular(LexiRadius.lg),
          showSpecular: true,
          padding: const EdgeInsets.all(18),
          child: Column(
            children: <Widget>[
              _StatRow(label: '计划题数', value: '${session.plannedCount}'),
              _StatRow(label: '已完成', value: '${session.completedCount}'),
              _StatRow(label: '正确', value: '${session.correctCount}'),
              _StatRow(label: '错误', value: '${session.wrongCount}'),
              _StatRow(label: '跳过', value: '${session.skippedCount}'),
              _StatRow(
                label: '正确率',
                value: studyAccuracyText(
                  session.correctCount,
                  session.completedCount,
                ),
              ),
              _StatRow(
                label: '有效时长',
                value: studyDurationText(session.durationMs),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _buttonHeight),
          child: FilledButton(onPressed: onRestart, child: const Text('再来一轮')),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _buttonHeight),
          child: OutlinedButton(onPressed: onHome, child: const Text('返回首页')),
        ),
      ],
    );
  }
}

/// 反馈面板里的一行统计。
class _StatRow extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colors.label,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 反馈面板里的一条提示。
class _Notice extends StatelessWidget {
  const new({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 12.5)),
        ),
      ],
    );
  }
}
