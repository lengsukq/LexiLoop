/// 队列工具栏：状态筛选、搜索、批量重试、分页。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/configurator/initialization_configurator.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 队列工具栏。
class QueueToolbar extends ConsumerStatefulWidget {
  /// 以键构造。
  const new({super.key});

  @override
  ConsumerState<QueueToolbar> createState() => _QueueToolbarState();
}

class _QueueToolbarState extends ConsumerState<QueueToolbar> {
  late final TextEditingController _search;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(queueFilterProvider).search);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: '搜索词条',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          // 提交时才筛选：边打边查会让每敲一个字都打一次库，
          // 而词条表通常不大，用户不会为了一次查询改一次筛选条件。
          onSubmitted: _applySearch,
        ),
        const SizedBox(height: toolbarGap),
        _ToolbarActions(
          busy: _busy,
          onProcessNow: () => unawaited(processNow()),
          onRetryFailed: () => unawaited(retryFailed()),
          onRefresh: () => ref.read(queueActionsProvider).refresh(),
          onConfigure: () => showInitializationConfigurator(
            context,
            initialScope: ConfiguratorScope.all,
          ),
        ),
        const SizedBox(height: toolbarGap),
        const _StatusFilters(),
        const SizedBox(height: toolbarGap),
        const _Paginator(),
      ],
    );
  }

  void _applySearch(String value) {
    final filter = ref.read(queueFilterProvider);
    ref
        .read(queueFilterProvider.notifier)
        .replace(filter.copyWith(search: value));
  }

  /// 立即处理一批排队中的任务。
  ///
  /// 后台每 [maintenanceIntervalMs] 才会保活一次、上一批有产出时每
  /// [maintenanceBusyIntervalMs] 就推进一次；但用户刚导入完词条时
  /// 等下一轮仍然不干脆，所以给一个手动入口。返回 0 时提示「没有可处理的任务」
  /// ——不区分「队列为空」和「失败」，因为维护层已经吞掉了异常，
  /// 真实原因在任务的失败原因字段里。
  Future<void> processNow() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final processed = await ref.read(queueActionsProvider).processNow();
      messenger.showSnackBar(
        SnackBar(
          content: Text(processed == 0 ? '没有可处理的任务' : '已处理 $processed 个任务'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 重试当前页所有失败任务。
  ///
  /// 只扫屏幕上这一页而不是整张表：用户看到的失败就是这些，
  /// 弹出一条「已重试 3 个任务」的提示最能对上他的预期。
  /// 逐个重试而不是一条 SQL 批量改状态：每个任务的失败原因可能不同
  /// （鉴权、超时、数据源下线），重排时各自重置退避计数才是同一个语义。
  Future<void> retryFailed() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final retried = await _retryVisibleFailed();
      messenger.showSnackBar(
        SnackBar(content: Text(retried == 0 ? '没有可重试的任务' : '已重试 $retried 个任务')),
      );
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<int> _retryVisibleFailed() async {
    final visible =
        ref.read(queuePageProvider).asData?.value.items ??
        const <InitializationWordSummary>[];
    final actions = ref.read(queueActionsProvider);
    var retried = 0;
    for (final word in visible) {
      for (final task in word.tasks) {
        if (task.status != InitializationStatus.failed) continue;
        await actions.retry(task.id);
        retried += 1;
      }
    }
    return retried;
  }

  /// 当前是否正在执行批量操作。
  bool get isBusy => _busy;
}

/// 三个动作按钮。
///
/// 拆成独立控件而不是塞进 `build()`：守卫对 `build()` 有 80 行上限，
/// 而这一页的动作会随功能继续增长。用 `Wrap` 而不是 `Row`，
/// 窄屏上「刷新」会自动折到下一行而不是溢出。
class _ToolbarActions extends StatelessWidget {
  const new({
    required this.busy,
    required this.onProcessNow,
    required this.onRetryFailed,
    required this.onRefresh,
    required this.onConfigure,
  });

  /// 是否有批量操作在执行（执行期间禁用会改数据的按钮）。
  final bool busy;

  /// 「立即处理一批」。
  final VoidCallback onProcessNow;

  /// 「重试失败」。
  final VoidCallback onRetryFailed;

  /// 「刷新」。
  final VoidCallback onRefresh;

  /// 「创建任务」：打开初始化配置器。
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: toolbarGap,
      runSpacing: toolbarGap,
      children: <Widget>[
        FilledButton.icon(
          onPressed: busy ? null : onProcessNow,
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('立即处理一批'),
        ),
        TextButton.icon(
          onPressed: busy ? null : onRetryFailed,
          icon: const Icon(Icons.restart_alt, size: 16),
          label: const Text('重试失败'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : onConfigure,
          icon: const Icon(Icons.tune, size: 16),
          label: const Text('创建任务'),
        ),
        // 刷新不参与 busy：它只读不写，正在跑批处理时也需要它。
        TextButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('刷新'),
        ),
      ],
    );
  }
}

/// 状态筛选按钮组。
class _StatusFilters extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(queueFilterProvider);
    return Wrap(
      spacing: chipGap,
      runSpacing: chipGap,
      children: <Widget>[
        for (final status in queueStatusFilters)
          _StatusChip(
            status: status,
            selected: filter.status == status,
            onTap: () => _select(ref, filter, status),
          ),
      ],
    );
  }

  /// 切换筛选；[QueueFilter.copyWith] 会把页码复位到 1。
  void _select(
    WidgetRef ref,
    QueueFilter filter,
    InitializationStatus? status,
  ) {
    ref
        .read(queueFilterProvider.notifier)
        .replace(
          status == null
              ? filter.copyWith(clearStatus: true)
              : filter.copyWith(status: status),
        );
  }
}

/// 分页条。
///
/// 旧版把它做成吸顶条；这里放在筛选条下方，因为队列页整页可滚动，
/// 吸顶反而会一直占着高度、挤掉列表。
class _Paginator extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(queueFilterProvider).page;
    final total = ref.watch(queuePageProvider).asData?.value.total ?? 0;
    final totalPages = _pageCount(total);
    return Row(
      children: <Widget>[
        TextButton(
          onPressed: page > 1 ? () => _go(ref, page - 1) : null,
          child: const Text('上一页'),
        ),
        const SizedBox(width: toolbarGap),
        Expanded(
          child: Text(
            '第 $page / $totalPages 页 · 共 $total 个词条',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: context.lexiColors.tertiaryLabel),
          ),
        ),
        const SizedBox(width: toolbarGap),
        TextButton(
          onPressed: page < totalPages ? () => _go(ref, page + 1) : null,
          child: const Text('下一页'),
        ),
      ],
    );
  }

  /// 至少一页：空队列也要能显示「第 1 / 1 页」，而不是除以零或空行。
  int _pageCount(int total) {
    final pages = (total / initializationJobPageSize).ceil();
    return pages < 1 ? 1 : pages;
  }

  void _go(WidgetRef ref, int page) {
    ref
        .read(queueFilterProvider.notifier)
        .replace(ref.read(queueFilterProvider).copyWith(page: page));
  }
}

/// 状态筛选按钮。
class _StatusChip extends StatelessWidget {
  const new({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final InitializationStatus? status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return GestureDetector(
      onTap: onTap,
      child: LiquidGlass(
        level: GlassLevel.subtle,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: chipPaddingH,
          vertical: chipPaddingV,
        ),
        child: Text(
          status == null ? '全部' : queueStatusLabel(status!),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? colors.accent : colors.secondaryLabel,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// 搜索框与筛选条的间距。
const double toolbarGap = 10;

/// 筛选按钮间距。
const double chipGap = 6;

/// 筛选按钮水平内边距。
const double chipPaddingH = 10;

/// 筛选按钮垂直内边距。
const double chipPaddingV = 5;
