/// 学习会话的总结。
///
/// 从 `study_feedback.dart` 拆出来：旧文件同时承载「单题判定反馈」与
/// 「会话总结」，而重做后单题反馈变成揭示面板（`study_reveal.dart`），
/// 这里只剩结算。总结是**只读**的，不含任何提交逻辑——避免出现
/// 「总结页点一下又提交一次」的路径。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 总结页里两个动作按钮的宽度上限。
///
/// 沉浸页有 840 可用，铺满会变成两条横幅；按内容取宽、居中。
const double _actionMaxWidth = 360;

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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: LexiLayout.readingMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SummaryHeader(empty: session.items.isEmpty),
            const SizedBox(height: LexiSpace.s20),
            _SummaryStats(session: session),
            const SizedBox(height: LexiSpace.s20),
            _SummaryActions(onRestart: onRestart, onHome: onHome),
          ],
        ),
      ),
    );
  }
}

/// 标题：图标 + 一句结论。
class _SummaryHeader extends StatelessWidget {
  const new({required this.empty});

  /// 本轮是否根本没有题目（「今天没词可学」）。
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    // 标题按「有没有题目」区分，照旧版 `study-client.tsx:548`：
    // `data.items.length === 0` 时是「暂时没有更多可学习词条」，否则
    // 「本轮学习完成」。两者共用同一个结算视图——对用户来说「今天没词可学」
    // 与「刚做完一轮」是同一件事：现在没得学了，只能再来一轮或回首页。
    final title = empty ? '暂时没有更多可学习词条' : '这一轮完成了';
    return Column(
      children: <Widget>[
        Icon(LucideIcons.partyPopper, size: 40, color: colors.accent),
        const SizedBox(height: LexiSpace.s12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: LexiType.title2.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 本轮统计。
class _SummaryStats extends StatelessWidget {
  const new({required this.session});

  final StudySessionView session;

  @override
  Widget build(BuildContext context) {
    return Surface(
      padding: const EdgeInsets.all(LexiSpace.s20),
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
          _StatRow(label: '有效时长', value: studyDurationText(session.durationMs)),
        ],
      ),
    );
  }
}

/// 两个出口：再来一轮 / 返回首页。
class _SummaryActions extends StatelessWidget {
  const new({required this.onRestart, required this.onHome});

  final VoidCallback onRestart;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _actionMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: LexiLayout.buttonHeight,
              ),
              child: FilledButton(
                onPressed: onRestart,
                child: const Text('再来一轮'),
              ),
            ),
            const SizedBox(height: LexiSpace.s10),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: LexiLayout.buttonHeight,
              ),
              child: OutlinedButton(
                onPressed: onHome,
                child: const Text('返回首页'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 总结里的一行统计。
class _StatRow extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(width: LexiSpace.s12),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: LexiType.callout.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
