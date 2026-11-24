/// 单词本批量操作工具条（多选模式下展示）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/add/add_providers.dart'
    show wordEditServiceProvider;
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/features/words/word_csv_export.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 批量选择与操作条：加标签、暂停/恢复、有道查词补全、删除无记录词、导出 CSV。
class WordBulkBar extends ConsumerStatefulWidget {
  /// 以当前列表中的词条构造（用于一键全选当前页）。
  const new({required this.visibleEntries, super.key});

  /// 当前已加载的词条。
  final List<WordListEntry> visibleEntries;

  @override
  ConsumerState<WordBulkBar> createState() => _WordBulkBarState();
}

class _WordBulkBarState extends ConsumerState<WordBulkBar> {
  bool _busy = false;

  void _invalidateWords() {
    ref
      ..invalidate(wordListProvider)
      ..invalidate(wordCountProvider)
      ..invalidate(wordTagsProvider)
      ..invalidate(masterySummaryProvider)
      ..invalidate(queueProgressProvider);
  }

  Future<void> _run(Future<String> Function(List<int> ids) action) async {
    final ids = ref.read(wordSelectionProvider).selectedIds.toList();
    if (ids.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final notice = await action(ids);
      _invalidateWords();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notice)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('批量操作失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addTag() async {
    final tag = await showDialog<String>(
      context: context,
      builder: (_) => const _TagPromptDialog(),
    );
    if (tag == null || tag.isEmpty) return;
    await _run((ids) async {
      final updated = await ref
          .read(wordEditServiceProvider)
          .bulkAddTag(
            wordIds: ids,
            tag: tag,
            now: DateTime.now().millisecondsSinceEpoch,
          );
      return '已为 $updated 个词条添加标签 #$tag';
    });
  }

  Future<void> _toggleSuspend({required bool suspended}) => _run((ids) async {
    await ref
        .read(wordEditServiceProvider)
        .bulkSetSuspended(
          wordIds: ids,
          suspended: suspended,
          now: DateTime.now().millisecondsSinceEpoch,
        );
    return suspended ? '已暂停 ${ids.length} 个词条' : '已恢复 ${ids.length} 个词条';
  });

  Future<void> _enqueueYoudao() => _run((ids) async {
    final count = await ref
        .read(queueActionsProvider)
        .enqueueBulk(wordIds: ids, mode: InitializationMode.fillMissingFields);
    return '已将 $count 个词条排入有道词典查词补全队列';
  });

  Future<void> _exportSelected() => _run((ids) async {
    final rows = await ref
        .read(wordDaoProvider)
        .exportRows(ref.read(wordQueryProvider), onlyIds: ids.toSet());
    final fileName = await shareWordsCsv(rows);
    return '已导出 ${rows.length} 个词条到 $fileName';
  });

  Future<void> _deleteUnreviewed() async {
    final count = ref.read(wordSelectionProvider).selectedIds.length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除所选未复习词条？'),
        content: Text('将删除所选 $count 个词条中尚无学习记录的词条；已有复习记录的词条会自动跳过以保留统计。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('wordsBulkDeleteConfirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run((ids) async {
      final report = await ref
          .read(wordEditServiceProvider)
          .bulkDeleteUnreviewed(ids);
      ref.read(wordSelectionProvider.notifier).clearSelected();
      if (report.skippedWithHistory > 0) {
        final skipped = report.skippedWithHistory;
        return '已删除 ${report.deleted} 个词条，跳过 $skipped 个有复习记录的词条';
      }
      return '已删除 ${report.deleted} 个词条';
    });
  }

  List<Widget> _buildActionButtons(
    int count,
    LexiColors colors,
    WordSelectionNotifier notifier,
  ) {
    final disabled = _busy || count == 0;
    return <Widget>[
      TextButton(
        onPressed: _busy
            ? null
            : () => notifier.selectAll(widget.visibleEntries.map((e) => e.id)),
        child: const Text('全选当前'),
      ),
      TextButton.icon(
        key: const Key('wordsBulkAddTag'),
        onPressed: disabled ? null : () => unawaited(_addTag()),
        icon: const Icon(LucideIcons.tag, size: 14),
        label: const Text('加标签'),
      ),
      _bulkBtn('暂停', disabled, () => _toggleSuspend(suspended: true)),
      _bulkBtn('恢复', disabled, () => _toggleSuspend(suspended: false)),
      _bulkBtn('有道补全', disabled, _enqueueYoudao),
      _bulkBtn('导出 CSV', disabled, _exportSelected),
      _bulkBtn(
        '删除无记录',
        disabled,
        _deleteUnreviewed,
        key: const Key('wordsBulkDelete'),
        color: colors.dangerText,
      ),
      TextButton(
        key: const Key('wordsBulkExit'),
        onPressed: notifier.exit,
        child: const Text('完成'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(wordSelectionProvider);
    final notifier = ref.read(wordSelectionProvider.notifier);
    final count = selection.selectedIds.length;
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: Surface(
        key: const Key('wordsBulkBar'),
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s12,
          vertical: LexiSpace.s8,
        ),
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: Wrap(
          spacing: LexiSpace.s6,
          runSpacing: LexiSpace.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '已选 $count 项',
              style: LexiType.footnote.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            ..._buildActionButtons(count, colors, notifier),
          ],
        ),
      ),
    );
  }
}

Widget _bulkBtn(
  String label,
  bool disabled,
  Future<void> Function() fn, {
  Key? key,
  Color? color,
}) => TextButton(
  key: key,
  onPressed: disabled ? null : () => unawaited(fn()),
  child: Text(
    label,
    style: color == null ? null : LexiType.footnote.copyWith(color: color),
  ),
);

class _TagPromptDialog extends StatefulWidget {
  const new();

  @override
  State<_TagPromptDialog> createState() => _TagPromptDialogState();
}

class _TagPromptDialogState extends State<_TagPromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('批量添加标签'),
    content: TextField(
      key: const Key('wordsBulkTagInput'),
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(hintText: '例如：雅思阅读、高频易错'),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const Key('wordsBulkTagConfirm'),
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('添加'),
      ),
    ],
  );
}
