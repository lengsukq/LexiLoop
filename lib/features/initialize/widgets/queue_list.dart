/// 队列列表与行内操作。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/features/initialize/widgets/queue_progress_card.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 队列列表。
class QueueList extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(queuePageProvider);
    // 翻页时保留上一页的列表：整屏换成转圈会让用户以为队列空了，
    // 而实际只是这一页还没查完（旧版 `load()` 也是直接换列表，不闪 loading）。
    return page.when(
      skipLoadingOnReload: true,
      data: (data) =>
          data.items.isEmpty ? const _EmptyView() : _Loaded(page: data),
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

/// 已加载的队列：全选条 + 词条行。
class _Loaded extends StatelessWidget {
  const new({required this.page});

  final InitializationJobPage page;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SelectAllRow(page: page),
        for (final word in page.items)
          Padding(
            padding: const EdgeInsets.only(bottom: rowGap),
            child: _WordTile(word: word),
          ),
      ],
    );
  }
}

/// 「选择本页」全选条。
///
/// 只作用于当前页：批量操作要能对上用户眼前看到的东西，
/// 跨页累积会让「已选 N 个」在翻页后指向看不见的词条。
class _SelectAllRow extends ConsumerWidget {
  const new({required this.page});

  final InitializationJobPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(queueSelectionProvider);
    final ids = <int>[for (final word in page.items) word.wordId];
    final allSelected = ids.isNotEmpty && ids.every(selected.contains);
    void toggleRow() => ref
        .read(queueSelectionProvider.notifier)
        .setVisible(ids, selected: !allSelected);
    return Padding(
      padding: const EdgeInsets.only(bottom: rowGap),
      // 整行可点：只让 40px 的复选框响应点击，用户为了全选得先精确瞄准它，
      // 而标签本来就是复选框的自然延伸。
      child: InkWell(
        onTap: toggleRow,
        child: Row(
          children: <Widget>[
            Checkbox(
              value: allSelected,
              onChanged: (value) => ref
                  .read(queueSelectionProvider.notifier)
                  .setVisible(ids, selected: value ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Text(
              allSelected ? '取消选择本页' : '选择本页',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: context.lexiColors.secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个词条的任务行。
///
/// 展开状态放在本地而不是全局：同时展开十几个词条只会把列表刷成一屏
/// 任务编号，而用户一次只会关心一两个词条为什么没补全。
class _WordTile extends ConsumerStatefulWidget {
  const new({required this.word});

  final InitializationWordSummary word;

  @override
  ConsumerState<_WordTile> createState() => _WordTileState();
}

class _WordTileState extends ConsumerState<_WordTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final word = widget.word;
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _WordHeader(word: word),
          const SizedBox(height: 4),
          Text(
            _summaryText(word),
            style: TextStyle(
              color: context.lexiColors.tertiaryLabel,
              fontSize: 12,
            ),
          ),
          if (word.errorSummary != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              word.errorSummary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.lexiColors.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          _WordActions(
            word: word,
            toggleLabel: _expanded ? '收起任务' : '展开 ${word.tasks.length} 个任务',
            onToggle: _toggleTasks,
          ),
          if (_expanded) _TaskPanel(tasks: word.tasks),
        ],
      ),
    );
  }

  void _toggleTasks() => setState(() => _expanded = !_expanded);

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

/// 词条行的头部：勾选框、词条文本、状态徽标。
class _WordHeader extends ConsumerWidget {
  const new({required this.word});

  final InitializationWordSummary word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final selected = ref.watch(queueSelectionProvider).contains(word.wordId);
    return Row(
      children: <Widget>[
        Checkbox(
          value: selected,
          onChanged: (_) =>
              ref.read(queueSelectionProvider.notifier).toggle(word.wordId),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => context.go('$wordDetailPathPrefix${word.wordId}'),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    word.term,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new, size: 12),
              ],
            ),
          ),
        ),
        _StatusBadge(status: word.status),
      ],
    );
  }
}

/// 词条行的操作区：展开/收起、整词条重试。
class _WordActions extends ConsumerWidget {
  const new({
    required this.word,
    required this.toggleLabel,
    required this.onToggle,
  });

  final InitializationWordSummary word;

  /// 展开按钮的文案。
  final String toggleLabel;

  /// 展开 / 收起回调。
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: <Widget>[
        if (word.tasks.isNotEmpty)
          TextButton(onPressed: onToggle, child: Text(toggleLabel)),
        const Spacer(),
        if (_canRetryWord(word))
          TextButton.icon(
            onPressed: () => _retryWord(context, ref),
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('重试'),
          ),
      ],
    );
  }

  Future<void> _retryWord(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final retried = await ref
          .read(queueActionsProvider)
          .retryWord(word.wordId);
      messenger.showSnackBar(SnackBar(content: Text(_retriedText(retried))));
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// 展开后的任务明细面板。
class _TaskPanel extends ConsumerWidget {
  const new({required this.tasks});

  final List<InitializationTaskSummary> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: detailGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final task in tasks) _TaskDetailRow(task: task),
        ],
      ),
    );
  }
}

/// 单条任务的明细：编号、重试次数、更新时间、失败原因与行内操作。
///
/// 这一层以前是压扁的芯片，`lastError` 与尝试次数永远看不到，
/// 用户判断不了「重试还有没有用」只能靠猜。
class _TaskDetailRow extends ConsumerWidget {
  const new({required this.task});

  final InitializationTaskSummary task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final actions = ref.read(queueActionsProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: detailGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${taskTypeLabel(task.taskType)} · 任务 #${task.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.label,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusBadge(status: task.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '重试 ${task.attemptCount}/${task.maxAttempts}'
            ' · 更新时间 ${formatTaskStamp(task.updatedAt)}',
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 11.5),
          ),
          if (task.lastError != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              task.lastError!,
              style: TextStyle(color: colors.danger, fontSize: 11.5),
            ),
          ],
          if (_actionable(task.status) != null) ...<Widget>[
            const SizedBox(height: 2),
            _TaskActionButton(
              status: task.status,
              jobId: task.id,
              actions: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// 单条任务的行内按钮（取消 / 重试）。
class _TaskActionButton extends StatelessWidget {
  const new({required this.status, required this.jobId, required this.actions});

  final InitializationStatus status;
  final int jobId;
  final QueueActions actions;

  @override
  Widget build(BuildContext context) {
    final label = _actionable(status)!.label;
    return TextButton(
      onPressed: () => _run(context, actions),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, tapTarget),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label),
    );
  }

  Future<void> _run(BuildContext context, QueueActions actions) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_actionable(status)!.isCancel) {
        await actions.cancel(jobId);
      } else {
        await actions.retry(jobId);
      }
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
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

/// 单个任务的动作。
typedef _TaskAction = ({String label, bool isCancel});

/// 哪些状态有行内动作，以及动作是什么。
///
/// 只有排队中可取消、失败/停用可重试：运行中取消会被服务端拒绝
/// （worker 已经持有锁），完成的任务重试等于让用户手动重跑一次补全。
_TaskAction? _actionable(InitializationStatus status) => switch (status) {
  InitializationStatus.queued ||
  InitializationStatus.pending => (label: '取消', isCancel: true),
  InitializationStatus.failed ||
  InitializationStatus.disabled => (label: '重试', isCancel: false),
  _ => null,
};

/// 这个词条是否值得给一个「重试」按钮。
///
/// 只在有失败/停用任务时出现：排队中的任务本来就在队列里，
/// 给它一个重试按钮只会诱导用户养成「没事点一下」的习惯。
/// 底层 [QueueActions.retryWord] 仍然连排队中的任务一起重排，
/// 因为批量入口（「已选 N 个词条」）的口径是「这个词条上所有可重试的任务」。
bool _canRetryWord(InitializationWordSummary word) => word.tasks.any(
  (task) =>
      task.status == InitializationStatus.failed ||
      task.status == InitializationStatus.disabled,
);

/// 「已重试 N 个任务」/「没有可重试的任务」。
///
/// 两句都保留：批量操作点下去之后用户需要一个可证伪的回执，
/// 否则分不清是操作生效了还是这条路径本来就没有可重试的东西。
String _retriedText(int retried) =>
    retried == 0 ? '没有可重试的任务' : '已重试 $retried 个任务';

/// 任务时间戳的展示格式。
///
/// 手动补零：直接用 `padLeft` 会给负数或超长年份留出怪异宽度，
/// 而且这里只需要「哪一天」这一层精度，不需要时区转换的完整语义。
String formatTaskStamp(int epochMs) {
  final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${at.year}-${_two(at.month)}-${_two(at.day)} '
      '${_two(at.hour)}:${_two(at.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 任务类型的中文名。
String taskTypeLabel(JobTaskType type) => switch (type) {
  JobTaskType.initialize => '内容初始化',
  JobTaskType.mnemonic => '助记词',
  JobTaskType.exampleTranslations => '例句翻译',
};

/// 行间距。
const double rowGap = 10;

/// 任务明细行间距。
const double detailGap = 8;

/// 加载占位的内边距。
const double loadingPadding = 24;

/// 空态的垂直内边距。
const double emptyPadding = 32;

/// 按钮最小高度（无障碍热区下限）。
const double tapTarget = 32;
