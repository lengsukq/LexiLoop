/// 导入历史区域。
///
/// 支持展开看行明细与撤销。撤销按钮的可用性由
/// [ImportBatchSummary.canRollback] 决定（与 `CsvImportService` 的静态资格
/// 检查逐条对齐），真正的依赖检查（复习日志、错词、会话）在服务层；
/// 失败时用 [rollbackBlockedMessage] 把挡住的词条摆给用户看。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/import/import_preview_table.dart';
import 'package:lexiloop/features/import/import_providers.dart';
import 'package:lexiloop/features/import/rollback_blocked_message.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 撤销失败的提示停留时长。
///
/// 比默认的四秒长：撤销被拒的理由常常是一长串词条，用户需要时间读完
/// 才能判断「那我该怎么办」。
const Duration rollbackErrorDuration = Duration(seconds: 8);

/// 导入历史区域。
class ImportHistorySection extends ConsumerWidget {
  /// 创建导入历史区域。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final history = ref.watch(importHistoryProvider);

    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.history_rounded, size: 16, color: colors.accent),
              const SizedBox(width: 6),
              Text(
                '导入历史',
                style: TextStyle(
                  color: colors.label,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh_rounded, size: 16),
                onPressed: () => ref.invalidate(importHistoryProvider),
              ),
            ],
          ),
          const SizedBox(height: 6),
          history.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text(
              error is AppError ? error.message : '读取导入历史失败：$error',
              style: TextStyle(color: colors.danger, fontSize: 13),
            ),
            data: (batches) => batches.isEmpty
                ? Text(
                    '还没有导入记录。',
                    style: TextStyle(
                      color: colors.secondaryLabel,
                      fontSize: 13,
                    ),
                  )
                : Column(
                    children: <Widget>[
                      for (final batch in batches) _BatchTile(batch: batch),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BatchTile extends ConsumerStatefulWidget {
  const new({required this.batch});

  final ImportBatchSummary batch;

  @override
  ConsumerState<_BatchTile> createState() => _BatchTileState();
}

class _BatchTileState extends ConsumerState<_BatchTile> {
  bool _expanded = false;
  bool _busy = false;

  Future<void> _rollback() async {
    final confirmed = await _confirmRollback();
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(csvImportServiceProvider)
          .rollback(
            batchId: widget.batch.id,
            now: DateTime.now().millisecondsSinceEpoch,
          );
      _refresh();
      messenger.showSnackBar(const SnackBar(content: Text('已撤销该批次。')));
    } on AppError catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(rollbackBlockedMessage(error)),
          duration: rollbackErrorDuration,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 二次确认：撤销会删除词条，不能一键完成。
  Future<bool?> _confirmRollback() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('撤销这次导入？'),
        content: Text(
          '将删除本批次新增的 ${widget.batch.createdWords} 个词条及其内容。\n'
          '已经产生学习记录的词条不会被删除，届时会给出提示。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
  }

  /// 撤销会把行的 `word_id` 置空，历史与明细都要重新取。
  void _refresh() {
    ref
      ..invalidate(importHistoryProvider)
      ..invalidate(importBatchRowsProvider(widget.batch.id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _BatchSummaryRow(
            batch: widget.batch,
            expanded: _expanded,
            busy: _busy,
            onToggle: () => setState(() => _expanded = !_expanded),
            onRollback: _rollback,
          ),
          if (_expanded) _BatchRows(batchId: widget.batch.id),
        ],
      ),
    );
  }
}

class _BatchSummaryRow extends StatelessWidget {
  const new({
    required this.batch,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onRollback,
  });

  final ImportBatchSummary batch;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onRollback;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                batch.filename,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.label,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _batchMeta(batch),
                style: TextStyle(color: colors.secondaryLabel, fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _BatchStatusBadge(status: batch.status),
        IconButton(
          tooltip: expanded ? '收起明细' : '展开明细',
          icon: Icon(
            expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18,
          ),
          onPressed: onToggle,
        ),
        if (batch.canRollback)
          TextButton(
            onPressed: busy ? null : onRollback,
            child: Text(busy ? '撤销中…' : '撤销'),
          )
        else
          Tooltip(
            message: staticRollbackBlockedReason(batch) ?? '',
            child: const TextButton(
              key: Key('rollbackDisabled'),
              onPressed: null,
              child: Text('撤销'),
            ),
          ),
      ],
    );
  }
}

/// 批次的统计摘要文案。
String _batchMeta(ImportBatchSummary batch) {
  final buffer = StringBuffer()
    ..write('${_formatTimestamp(batch.createdAt)} · ${batch.totalRows} 行')
    ..write(' · 新增 ${batch.createdWords} / 跳过 ${batch.existingWords}');
  if (batch.duplicateRows > 0) buffer.write(' / 重复 ${batch.duplicateRows}');
  if (batch.invalidRows > 0) buffer.write(' / 无效 ${batch.invalidRows}');
  return buffer.toString();
}

class _BatchRows extends ConsumerWidget {
  const new({required this.batchId});

  final int batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final rows = ref.watch(importBatchRowsProvider(batchId));

    return rows.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Text(
        error is AppError ? error.message : '读取行明细失败：$error',
        style: TextStyle(color: colors.danger, fontSize: 12.5),
      ),
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 6),
          for (final row in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${row.rowNumber}',
                      style: TextStyle(
                        color: colors.tertiaryLabel,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.term.isEmpty ? '（空）' : row.term,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.label, fontSize: 12.5),
                    ),
                  ),
                  ImportRowStatusBadge(status: row.status),
                  if (row.errorMessage != null) ...<Widget>[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        row.errorMessage!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.danger, fontSize: 11.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BatchStatusBadge extends StatelessWidget {
  const new({required this.status});

  final ImportBatchStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final (String label, Color color) = switch (status) {
      ImportBatchStatus.pending => ('未提交', colors.warning),
      ImportBatchStatus.committed => ('已提交', colors.success),
      ImportBatchStatus.failed => ('失败', colors.danger),
      ImportBatchStatus.rolledBack => ('已撤销', colors.tertiaryLabel),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 本地时间 `2026-03-01 10:05`。
String _formatTimestamp(int millis) {
  final date = DateTime.fromMillisecondsSinceEpoch(millis);
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} '
      '${pad(date.hour)}:${pad(date.minute)}';
}
