/// 数据管理设置分组。
///
/// 备份导入（复用 `backupServiceProvider`）、CSV 导入入口与危险区。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/import/import_providers.dart';
import 'package:lexiloop/features/settings/local_data_reset.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 二次确认时要求输入的词。
const String deleteConfirmKeyword = 'DELETE';

/// 数据管理分组。
class DataManagementSection extends ConsumerStatefulWidget {
  /// 创建数据管理分组。
  const new({super.key});

  @override
  ConsumerState<DataManagementSection> createState() =>
      _DataManagementSectionState();
}

class _DataManagementSectionState extends ConsumerState<DataManagementSection> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      children: <Widget>[
        SettingsSectionCard(
          title: '导入数据',
          subtitle: '备份是旧版导出的 JSON；CSV 是 EasyDict 导出的词库文件。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _importing ? null : _importBackup,
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: Text(_importing ? '导入中…' : '导入旧版 JSON 备份'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('openCsvImport'),
                onPressed: () => context.go('/import'),
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text('导入 EasyDict CSV 词库'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SettingsSectionCard(
          title: '危险区',
          subtitle: '以下操作不可撤销，建议先导出备份。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '清空全部数据会删除所有词条、学习记录、导入历史与设置，'
                '应用回到首次启动的状态。',
                style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('clearAllData'),
                style: FilledButton.styleFrom(backgroundColor: colors.danger),
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_forever_rounded, size: 16),
                label: const Text('清空全部数据'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _importBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      final result = await ref.read(backupServiceProvider).pickAndImport();
      if (result == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：${result.rowCounts['words'] ?? 0} 个词条、'
            '${result.totalRows} 行',
          ),
        ),
      );
      _invalidateData();
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _DeleteConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await clearAllData(ref.read(databaseProvider));
    ref.read(settingsServiceProvider).invalidate();
    _invalidateData();
    messenger.showSnackBar(const SnackBar(content: Text('本地数据已清空。')));
  }

  void _invalidateData() {
    ref
      ..invalidate(appSettingsProvider)
      ..invalidate(importHistoryProvider)
      ..invalidate(wordListProvider)
      ..invalidate(wordCountProvider);
  }
}

/// 要求输入 DELETE 的二次确认对话框。
class _DeleteConfirmDialog extends StatefulWidget {
  const new();

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _matched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('清空全部数据？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('此操作不可撤销。请输入 DELETE 以确认。'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('clearAllDataConfirmField'),
            controller: _controller,
            autocorrect: false,
            decoration: const InputDecoration(hintText: deleteConfirmKeyword),
            onChanged: (value) =>
                setState(() => _matched = value.trim() == deleteConfirmKeyword),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('clearAllDataConfirmButton'),
          onPressed: _matched ? () => Navigator.of(context).pop(true) : null,
          child: const Text('清空'),
        ),
      ],
    );
  }
}
