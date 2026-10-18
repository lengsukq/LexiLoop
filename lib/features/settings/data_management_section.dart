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
import 'package:lexiloop/features/dashboard/cards/platform_card.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/data_invalidation.dart';
import 'package:lexiloop/features/settings/import_backup_confirm.dart';
import 'package:lexiloop/features/settings/lan_sync_section.dart';
import 'package:lexiloop/features/settings/local_data_reset.dart';
import 'package:lexiloop/features/settings/remote_backup_section.dart';
import 'package:lexiloop/features/settings/settings_controls.dart';
import 'package:lexiloop/features/settings/typed_confirm_dialog.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/services/backup/backup_export_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 二次确认时要求输入的词。
const String deleteConfirmKeyword = 'DELETE';

/// 导出备份的二次确认关键词。
///
/// 与 [deleteConfirmKeyword] 用同一套「敲一个词才放行」的模式：导出是危险区
/// 文案里点名推荐的动作（「建议先导出备份」），把它做成一键可达，
/// 等于把用户的注意力训练成「看到导出按钮就直接点」。
const String exportConfirmKeyword = 'EXPORT';

/// 导入备份的二次确认关键词。
///
/// **导入是这一组里最危险的动作，却曾经是唯一没有确认的**：它按父子序
/// 覆盖 12 张表（见 `data/backup/backup_import.dart`），点一下就把当前
/// 库整个换掉，而「清空全部数据」与「导出」都要求打字确认。
/// 确认强度必须按**后果**排，不是按动作的名字听起来危不危险：
/// 导出的后果是可再生的（大不了再导一次），导入的后果是不可逆的覆盖。

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
        // **自检卡从首页挪到这里**：它讲的是「TTS 能不能落盘、模糊会不会
        // 降级、当前是不是侧边栏布局」，属于排查信息而不是每日任务。
        // 摆在首页最末位时，它是整页唯一一块与「今天学什么」无关的内容，
        // 却占着最有价值的滚动终点。
        const DisclosureSection(
          title: '设备与运行信息',
          child: PlatformCapabilityCard(),
        ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _ImportConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

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
    return const TypedConfirmDialog(
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
    return const TypedConfirmDialog(
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

/// 导入备份前的确认：说清楚「会覆盖什么、什么会被丢掉」。
///
/// 文案必须点名**作用范围**：这个动作不是「合并」，而是全量替换。
/// 用户点它之前唯一需要知道的事，就是当前库里的东西还在不在。
class _ImportConfirmDialog extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const BackupImportConfirmDialog();
}
