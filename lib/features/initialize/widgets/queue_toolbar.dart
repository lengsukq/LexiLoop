/// 队列工具栏：状态筛选、搜索、批量重试。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
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
    final filter = ref.watch(queueFilterProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            hintText: '搜索词条',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          onSubmitted: _applySearch,
        ),
        const SizedBox(height: toolbarGap),
        _actions(),
        const SizedBox(height: toolbarGap),
        Wrap(
          spacing: chipGap,
          runSpacing: chipGap,
          children: <Widget>[
            for (final status in queueStatusFilters)
              _StatusChip(
                status: status,
                selected: filter.status == status,
                onTap: () => ref
                    .read(queueFilterProvider.notifier)
                    .replace(
                      status == null
                          ? filter.copyWith(clearStatus: true)
                          : filter.copyWith(status: status),
                    ),
              ),
          ],
        ),
      ],
    );
  }

  /// 「立即处理一批」与「重试失败」两个动作。
  ///
  /// 放成独立控件而不是塞进 `build()`：守卫对 `build()` 有 80 行上限，
  /// 而这一页的动作会随功能继续增长。
  Widget _actions() {
    return Row(
      children: <Widget>[
        FilledButton.icon(
          onPressed: _busy ? null : () => unawaited(processNow()),
          icon: const Icon(Icons.play_arrow, size: 16),
          label: const Text('立即处理一批'),
        ),
        const SizedBox(width: toolbarGap),
        TextButton.icon(
          onPressed: _busy ? null : () => unawaited(retryFailed()),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重试失败'),
        ),
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

  /// 重试当前所有失败任务。
  ///
  /// 逐个重试而不是一条 SQL 批量改状态：每个任务的失败原因可能不同
  /// （鉴权、超时、数据源下线），逐个走 `retryJob` 才能各自重置退避计数。
  Future<void> retryFailed() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final page = await ref
          .read(initializationQueriesProvider)
          .listJobs(status: InitializationStatus.failed);
      var retried = 0;
      for (final word in page.items) {
        for (final task in word.tasks) {
          if (task.status != InitializationStatus.failed) continue;
          await ref.read(queueActionsProvider).retry(task.id);
          retried += 1;
        }
      }
      messenger.showSnackBar(
        SnackBar(content: Text(retried == 0 ? '没有可重试的任务' : '已重试 $retried 个任务')),
      );
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 当前是否正在执行批量操作。
  bool get isBusy => _busy;
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
