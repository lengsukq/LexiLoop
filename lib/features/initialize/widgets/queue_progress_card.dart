/// 队列进度概览卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 各状态任务计数。
class QueueProgressCard extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(queueProgressProvider);
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(cardPadding),
      child: progress.when(
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Completion(progress: data.completion),
            if (data.total > 0) ...<Widget>[
              const SizedBox(height: cardGap),
              _Counts(progress: data),
            ] else
              Text(
                '队列为空。导入词条后任务会出现在这里。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.lexiColors.tertiaryLabel),
              ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          '加载失败：$error',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.lexiColors.danger),
        ),
      ),
    );
  }
}

/// 词条级完成百分比与进度条。
///
/// 放在计数行之上：用户想知道的是「还剩多少词条没补全」，
/// 而不是队列里 QUEUED 和 RUNNING 各堆了多少条。
class _Completion extends StatelessWidget {
  const new({required this.progress});

  final InitializationWordCompletion progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Text(
                '已完成 ${progress.completedWords} / ${progress.totalWords} 个词条',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.secondaryLabel,
                ),
              ),
            ),
            Text(
              '${progress.percent}%',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: barGap),
        ClipRRect(
          borderRadius: BorderRadius.circular(LexiRadius.sm),
          child: LinearProgressIndicator(
            value: progress.totalWords == 0
                ? 0
                : progress.percent / percentScale,
            minHeight: barHeight,
            backgroundColor: colors.fill,
            color: colors.accent,
          ),
        ),
      ],
    );
  }
}

/// 计数行。
class _Counts extends StatelessWidget {
  const new({required this.progress});

  final InitializationProgress progress;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: columnGap,
      runSpacing: rowGap,
      children: <Widget>[
        for (final status in countedStatuses)
          SizedBox(
            width: cellWidth,
            child: _Cell(status: status, count: progress.countOf(status)),
          ),
      ],
    );
  }
}

/// 单个计数单元。
class _Cell extends StatelessWidget {
  const new({required this.status, required this.count});

  final InitializationStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          queueStatusLabel(status),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.tertiaryLabel),
        ),
        const SizedBox(height: labelGap),
        Text(
          '$count',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: statusColor(status, colors),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// 概览中展示的状态（按处理流程排序）。
const List<InitializationStatus> countedStatuses = <InitializationStatus>[
  InitializationStatus.queued,
  InitializationStatus.running,
  InitializationStatus.ready,
  InitializationStatus.partial,
  InitializationStatus.failed,
];

/// 状态对应的强调色。
Color statusColor(InitializationStatus status, LexiColors colors) =>
    switch (status) {
      InitializationStatus.failed => colors.danger,
      InitializationStatus.running => colors.accent,
      InitializationStatus.queued => colors.warning,
      InitializationStatus.ready => colors.success,
      InitializationStatus.partial => colors.purple,
      _ => colors.secondaryLabel,
    };

/// 卡片内边距。
const double cardPadding = 16;

/// 完成度与计数行之间的间距。
const double cardGap = 14;

/// 标题与进度条之间的间距。
const double barGap = 8;

/// 进度条高度。
const double barHeight = 6;

/// 计数单元宽度。
const double cellWidth = 84;

/// 单元之间的水平间距。
const double columnGap = 10;

/// 单元之间的垂直间距。
const double rowGap = 14;

/// 标签与数值的间距。
const double labelGap = 2;
