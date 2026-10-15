/// 学习会话的顶部进度与计数。
///
/// 学习页在沉浸模式下运行，外壳不提供导航，因此「跳过 / 结束」必须由这里
/// 自带；进度条也在这里，让用户随时知道还剩多少。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 顶部进度与计数。
class StudyProgressHeader extends StatelessWidget {
  /// 以会话、跳过回调（为空表示禁用）与结束回调构造。
  const new({
    required this.session,
    required this.onSkip,
    required this.onExit,
    super.key,
  });

  /// 当前会话。
  final StudySessionView session;

  /// 跳过回调；提交后为 `null`，此时按钮禁用。
  final VoidCallback? onSkip;

  /// 结束回调。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _CountsRow(session: session),
              const Spacer(),
              _HeaderAction(
                label: '跳过',
                enabled: onSkip != null,
                onTap: onSkip,
              ),
              _HeaderAction(label: '结束', enabled: true, onTap: onExit),
            ],
          ),
          const SizedBox(height: 10),
          _ProgressTrack(
            value: session.plannedCount <= 0
                ? 0
                : session.completedCount / session.plannedCount,
          ),
        ],
      ),
    );
  }
}

/// 已完成 / 计划 与正确 / 错误计数。
class _CountsRow extends StatelessWidget {
  const new({required this.session});

  final StudySessionView session;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Text(
          '${session.completedCount} / ${session.plannedCount}',
          style: TextStyle(
            color: colors.label,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        _CountChip(
          label: '正确',
          value: session.correctCount,
          color: colors.success,
        ),
        const SizedBox(width: 6),
        _CountChip(
          label: '错误',
          value: session.wrongCount,
          color: colors.danger,
        ),
      ],
    );
  }
}

/// 单个计数胶囊。
class _CountChip extends StatelessWidget {
  const new({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 进度条。
class _ProgressTrack extends StatelessWidget {
  const new({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 6,
        backgroundColor: colors.fill,
        valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
      ),
    );
  }
}

/// 顶部的小动作按钮（跳过 / 结束）。
class _HeaderAction extends StatelessWidget {
  const new({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: studyMinTapTarget,
        minWidth: 56,
      ),
      child: TextButton(
        onPressed: enabled ? onTap : null,
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? colors.accent : colors.tertiaryLabel,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
