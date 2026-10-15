/// 数据管理设置分组。
///
/// 备份导出 / 导入（复用 `backupServiceProvider`）、CSV 导入入口与危险区。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/settings/data_invalidation.dart';
import 'package:lexiloop/features/settings/local_data_reset.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/services/backup/backup_export_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 二次确认时要求输入的词。
const String deleteConfirmKeyword = 'DELETE';

/// 导出备份的二次确认关键词。
///
/// 与 [deleteConfirmKeyword] 用同一套「敲一个词才放行」的模式：导出是危险区
/// 文案里点名推荐的动作（「建议先导出备份」），把它做成一键可达，
/// 等于把用户的注意力训练成「看到导出按钮就直接点」。
const String exportConfirmKeyword = 'EXPORT';

/// 备份字节数的展示单位。
const List<String> backupByteUnits = <String>['B', 'KB', 'MB', 'GB'];

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
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      children: <Widget>[
        SettingsSectionCard(
          title: '备份与导入',
          subtitle:
              '备份是包含全部词条与学习记录的 JSON 文件； '
              'CSV 是 EasyDict 导出的词库文件。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('exportBackup'),
                onPressed: _exporting ? null : _exportBackup,
                icon: const Icon(Icons.save_alt_rounded, size: 16),
                label: Text(_exporting ? '导出中…' : '导出 JSON 备份'),
              ),
              const SizedBox(height: 8),
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
                style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
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

  /// 导出备份：先敲关键字确认，再走系统分享面板。
  Future<void> _exportBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _ExportConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final exported = await ref
          .read(backupExportServiceProvider)
          .exportAndShare();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '已导出 ${exported.result.totalRows} 行 '
            '（${formatBackupBytes(exported.byteSize)}）：${exported.filename}',
          ),
        ),
      );
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
      invalidateLocalData(ref);
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
    invalidateLocalData(ref);
    messenger.showSnackBar(const SnackBar(content: Text('本地数据已清空。')));
  }
}

/// 要求输入 DELETE 的二次确认对话框。
class _DeleteConfirmDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const _TypedConfirmDialog(
      title: '清空全部数据？',
      body: '此操作不可撤销。请输入 DELETE 以确认。',
      keyword: deleteConfirmKeyword,
      confirmLabel: '清空',
      keyPrefix: 'clearAllDataConfirm',
    );
  }
}

/// 导出备份前的确认：说清楚「导出的是什么、不含什么」。
class _ExportConfirmDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const _TypedConfirmDialog(
      title: '导出 JSON 备份？',
      body:
          '备份包含全部词条、词典内容、学习记录、导入历史与设置，'
          '可用于换机迁移或回滚。\n\n'
          '不含小游戏最高分与累计答题统计：前者用的是新计分公式，'
          '后者会在导入时由复习日志重算。\n\n'
          '请输入 EXPORT 以确认。',
      keyword: exportConfirmKeyword,
      confirmLabel: '导出',
      keyPrefix: 'exportBackupConfirm',
    );
  }
}

/// 要求敲对一个关键字才放行的确认对话框。
///
/// 清空数据与导出备份共用它：两者的共同点是「一步误点就不可逆」，
/// 而确认成本只需要用户多打五个字母。
class _TypedConfirmDialog extends StatefulWidget {
  const new({
    required this.title,
    required this.body,
    required this.keyword,
    required this.confirmLabel,
    required this.keyPrefix,
  });

  final String title;
  final String body;
  final String keyword;
  final String confirmLabel;

  /// widget 测试用的 key 前缀，派生出 `…Field` 与 `…Button` 两个 key。
  ///
  /// 由前缀派生而不是各传一个 key：两个对话框的差别只有标题、正文与关键字，
  /// 让它们各自声明 key 只会多两处需要同步的名字。
  final String keyPrefix;

  /// 输入框的 key。
  Key get fieldKey => Key('${keyPrefix}Field');

  /// 确认按钮的 key。
  Key get buttonKey => Key('${keyPrefix}Button');

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
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
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.body),
          const SizedBox(height: 12),
          TextField(
            key: widget.fieldKey,
            controller: _controller,
            autocorrect: false,
            decoration: InputDecoration(hintText: widget.keyword),
            onChanged: (value) =>
                setState(() => _matched = value.trim() == widget.keyword),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: widget.buttonKey,
          onPressed: _matched ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// 把字节数写成人类可读的大小，例如 `27.1 MB`。
///
/// 沿用 [backupByteUnits] 的阶梯而不是现成的格式化库：备份文件通常落在
/// KB–MB，两级之内就够，不必为一次提示引入一个依赖。
String formatBackupBytes(int bytes) {
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < backupByteUnits.length - 1) {
    value /= 1024;
    unit += 1;
  }
  final text = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${backupByteUnits[unit]}';
}
