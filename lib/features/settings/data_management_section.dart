/// 数据管理设置分组。
///
/// 备份导出 / 导入（复用 `backupServiceProvider`）、CSV 导入入口、
/// WebDAV 远程备份、局域网同步与危险区。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/data_invalidation.dart';
import 'package:lexiloop/features/settings/import_backup_confirm.dart';
import 'package:lexiloop/features/settings/lan_sync_section.dart';
import 'package:lexiloop/features/settings/local_data_reset.dart';
import 'package:lexiloop/features/settings/remote_backup_section.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/services/backup/backup_export_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/lexi_confirm_sheet.dart';
import 'package:lexiloop/ui/widgets/lexi_form_rows.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 清空全部数据确认按钮的稳定 Key。
const Key clearAllDataConfirmButtonKey = Key('clearAllDataConfirmButton');

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
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s4,
        LexiSpace.s12,
        LexiSpace.s4,
        LexiSpace.s24,
      ),
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
                icon: const Icon(LucideIcons.download, size: 16),
                label: Text(_exporting ? '导出中…' : '导出 JSON 备份'),
              ),
              const SizedBox(height: LexiSpace.s8),
              OutlinedButton.icon(
                onPressed: _importing ? null : _importBackup,
                icon: const Icon(LucideIcons.fileUp, size: 16),
                label: Text(_importing ? '导入中…' : '导入旧版 JSON 备份'),
              ),
              const SizedBox(height: LexiSpace.s8),
              OutlinedButton.icon(
                key: const Key('openCsvImport'),
                onPressed: () => context.go('/import'),
                icon: const Icon(LucideIcons.table2, size: 16),
                label: const Text('导入 EasyDict CSV 词库'),
              ),
            ],
          ),
        ),
        const SizedBox(height: LexiSpace.s12),
        const RemoteBackupSection(),
        const SizedBox(height: LexiSpace.s12),
        const LanSyncSection(),
        const SizedBox(height: LexiSpace.s12),
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
              const SizedBox(height: LexiSpace.s10),
              FilledButton.icon(
                key: const Key('clearAllData'),
                style: FilledButton.styleFrom(backgroundColor: colors.danger),
                onPressed: _clearAll,
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: const Text('清空全部数据'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 导出备份：非破坏性只读动作，一键拉起系统分享/保存面板。
  Future<void> _exportBackup() async {
    LexiHaptics.light();
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
    final confirmed = await confirmBackupImport(context);
    if (!confirmed || !mounted) return;

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
    final confirmed = await showLexiConfirmSheet(
      context,
      title: '清空全部数据？',
      body: '此操作不可撤销，所有词条、学习记录、导入历史与设置都将被彻底清除。',
      confirmLabel: '清空',
      destructive: true,
      confirmButtonKey: clearAllDataConfirmButtonKey,
    );
    if (!confirmed || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    await clearAllData(ref.read(databaseProvider));
    ref.read(settingsServiceProvider).invalidate();
    invalidateLocalData(ref);
    messenger.showSnackBar(const SnackBar(content: Text('本地数据已清空。')));
  }
}
