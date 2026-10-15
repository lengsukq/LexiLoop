/// 队列列表与行内操作。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/features/initialize/widgets/queue_progress_card.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 队列列表。
class QueueList extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(queuePageProvider);
    return page.when(
      data: (data) => data.items.isEmpty
          ? const _EmptyView()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final word in data.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: rowGap),
                    child: _WordTile(word: word),
                  ),
              ],
            ),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: loadingPadding),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(
        '加载失败：$error',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.lexiColors.danger),
      ),
    );
  }
}

/// 单个词条的任务行。
class _WordTile extends ConsumerWidget {
  const new({required this.word});

  final InitializationWordSummary word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  word.term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.label,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(status: word.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _summaryText(word),
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
          ),
          if (word.errorSummary != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              word.errorSummary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          _TaskActions(tasks: word.tasks),
        ],
      ),
    );
  }

  /// 「3 个任务 · 2 已完成 · 1 失败」这类摘要。
  String _summaryText(InitializationWordSummary word) {
    final parts = <String>['${word.taskCount} 个任务'];
    if (word.completedTaskCount > 0) {
      parts.add('${word.completedTaskCount} 已完成');
    }
    if (word.activeTaskCount > 0) parts.add('${word.activeTaskCount} 进行中');
    if (word.failedTaskCount > 0) parts.add('${word.failedTaskCount} 失败');
    return parts.join(' · ');
  }
}

/// 每个任务一个小按钮：进行中的可取消，失败的或已停用的可重试。
class _TaskActions extends ConsumerWidget {
  const new({required this.tasks});

  final List<InitializationTaskSummary> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: actionGap,
      runSpacing: actionGap,
      children: <Widget>[
        for (final task in tasks)
          _TaskChip(
            task: task,
            onCancel: () => _run(
              context,
              ref,
              () => ref.read(queueActionsProvider).cancel(task.id),
            ),
            onRetry: () => _run(
              context,
              ref,
              () => ref.read(queueActionsProvider).retry(task.id),
            ),
          ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// 单个任务的操作芯片。
class _TaskChip extends StatelessWidget {
  const new({
    required this.task,
    required this.onCancel,
    required this.onRetry,
  });

  final InitializationTaskSummary task;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final actionable = switch (task.status) {
      InitializationStatus.queued ||
      InitializationStatus.pending => (label: '取消', action: onCancel),
      InitializationStatus.failed ||
      InitializationStatus.disabled => (label: '重试', action: onRetry),
      _ => null,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          taskTypeLabel(task.taskType),
          style: TextStyle(color: colors.secondaryLabel, fontSize: 12),
        ),
        if (task.attemptCount > 0) ...<Widget>[
          const SizedBox(width: 4),
          Text(
            '${task.attemptCount}/${task.maxAttempts}',
            style: TextStyle(color: colors.quaternaryLabel, fontSize: 11),
          ),
        ],
        if (actionable != null) ...<Widget>[
          const SizedBox(width: 4),
          TextButton(
            onPressed: actionable.action,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, tapTarget),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(actionable.label),
          ),
        ],
      ],
    );
  }
}

/// 状态徽标。
class _StatusBadge extends StatelessWidget {
  const new({required this.status});

  final InitializationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final tint = statusColor(status, colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Text(
        queueStatusLabel(status),
        style: TextStyle(color: tint, fontSize: 11.5),
      ),
    );
  }
}

/// 空态。
class _EmptyView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: emptyPadding),
    child: Center(
      child: Text(
        '没有符合条件的任务',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.lexiColors.tertiaryLabel),
      ),
    ),
  );
}

/// 任务类型的中文名。
String taskTypeLabel(JobTaskType type) => switch (type) {
  JobTaskType.initialize => '内容初始化',
  JobTaskType.mnemonic => '助记词',
  JobTaskType.exampleTranslations => '例句翻译',
};

/// 行间距。
const double rowGap = 10;

/// 操作芯片间距。
const double actionGap = 8;

/// 加载占位的内边距。
const double loadingPadding = 24;

/// 空态的垂直内边距。
const double emptyPadding = 32;

/// 按钮最小高度（无障碍热区下限）。
const double tapTarget = 32;
