/// 数据管理设置分组。
///
/// 采用清晰的分组卡片层次：本地备份与词库导入（分组操作行）、局域网直连增量同步、
/// WebDAV 远程云备份与克制的危险区。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/settings/audio_cache_providers.dart';
import 'package:lexiloop/features/settings/backup_size_label.dart';
import 'package:lexiloop/features/settings/cloud_sync_section.dart';
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
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/lexi_confirm_sheet.dart';
import 'package:lexiloop/ui/widgets/lexi_pressable.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 清空全部数据确认按钮的稳定 Key。
const Key clearAllDataConfirmButtonKey = Key('clearAllDataConfirmButton');

/// 分组操作行图标底块边长。
const double _actionIconBoxSize = 36;

/// 分组操作行之间的缩进分隔线起点。
const double _actionDividerIndent = 60;

/// 危险区切换横/竖布局的宽度阈值。
const double _dangerWideThreshold = 460;

/// 危险按钮紧凑高度。
const double _dangerButtonHeight = 38;

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
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      LexiSpace.s4,
      LexiSpace.s12,
      LexiSpace.s4,
      LexiSpace.s24,
    ),
    children: <Widget>[
      _localBackupCard(),
      const SizedBox(height: LexiSpace.s16),
      const LanSyncSection(),
      const SizedBox(height: LexiSpace.s16),
      const CloudSyncSection(),
      const SizedBox(height: LexiSpace.s16),
      const RemoteBackupSection(),
      const SizedBox(height: LexiSpace.s16),
      _DangerZoneCard(onClearAll: _clearAll),
    ],
  );

  Widget _localBackupCard() => SectionCard(
    title: '备份与导入',
    icon: LucideIcons.hardDrive,
    tone: LexiTone.sky,
    subtitle: '导出离线 JSON 留底，或导入旧版备份与 EasyDict CSV 词库。',
    child: Surface(
      variant: SurfaceVariant.inset,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _GroupedActionRow(
            rowKey: const Key('exportBackup'),
            icon: LucideIcons.download,
            tone: LexiTone.mint,
            title: '导出 JSON 备份',
            subtitle: _exporting ? '正在打包词条与学习记录…' : '包含全部词条、释义与 FSRS 复习历史',
            trailing: LexiBadge(
              label: _exporting ? '导出中…' : '导出',
              tone: LexiBadgeTone.accent,
            ),
            onTap: _exporting ? null : _exportBackup,
          ),
          const Divider(height: 1, indent: _actionDividerIndent),
          _GroupedActionRow(
            icon: LucideIcons.fileUp,
            tone: LexiTone.sky,
            title: '导入旧版 JSON 备份',
            subtitle: _importing ? '正在校验并恢复…' : '从备份文件整体替换恢复当前词库',
            onTap: _importing ? null : _importBackup,
          ),
          const Divider(height: 1, indent: _actionDividerIndent),
          _GroupedActionRow(
            rowKey: const Key('openCsvImport'),
            icon: LucideIcons.table2,
            tone: LexiTone.peach,
            title: '导入 EasyDict CSV 词库',
            subtitle: '批量导入生词本、音标、释义与个人笔记',
            onTap: () => context.go('/import'),
          ),
        ],
      ),
    ),
  );

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
    await clearSpeechCache(ref);
    ref.read(settingsServiceProvider).invalidate();
    invalidateLocalData(ref);
    messenger.showSnackBar(const SnackBar(content: Text('本地数据与语音缓存已清空。')));
  }
}

class _GroupedActionRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.rowKey,
    this.trailing,
  });

  final Key? rowKey;
  final IconData icon;
  final LexiTone tone;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final style = context.lexiTones.styleOf(tone);
    return LexiPressable(
      key: rowKey,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s12,
          vertical: LexiSpace.s12,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: _actionIconBoxSize,
              height: _actionIconBoxSize,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(LexiRadius.sm),
              ),
              child: Icon(icon, size: 17, color: style.foreground),
            ),
            const SizedBox(width: LexiSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: LexiType.body.copyWith(
                      color: colors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: LexiSpace.s2),
                  Text(
                    subtitle,
                    style: LexiType.caption.copyWith(
                      color: colors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: LexiSpace.s8),
            trailing ??
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: colors.tertiaryLabel,
                ),
          ],
        ),
      ),
    );
  }
}

class _DangerZoneCard extends StatelessWidget {
  const new({required this.onClearAll});

  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      padding: const EdgeInsets.all(LexiSpace.s16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(LexiRadius.lg),
        border: Border.all(
          color: colors.danger.withValues(alpha: LexiTint.border),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = _dangerInfo(colors);
          final button = _dangerButton(colors);
          if (constraints.maxWidth >= _dangerWideThreshold) {
            return Row(
              children: <Widget>[
                Expanded(child: info),
                const SizedBox(width: LexiSpace.s16),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              info,
              const SizedBox(height: LexiSpace.s12),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          );
        },
      ),
    );
  }

  Widget _dangerInfo(LexiColors colors) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Container(
        width: _actionIconBoxSize,
        height: _actionIconBoxSize,
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: LexiTint.tint),
          borderRadius: BorderRadius.circular(LexiRadius.sm),
        ),
        child: Icon(
          LucideIcons.triangleAlert,
          size: 17,
          color: colors.dangerText,
        ),
      ),
      const SizedBox(width: LexiSpace.s12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '危险区',
              style: LexiType.callout.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: LexiSpace.s2),
            Text(
              '清空全部词条、学习记录、导入历史与设置并回到初始状态，不可撤销。',
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _dangerButton(LexiColors colors) => OutlinedButton.icon(
    key: const Key('clearAllData'),
    style: OutlinedButton.styleFrom(
      foregroundColor: colors.dangerText,
      backgroundColor: colors.danger.withValues(alpha: LexiTint.tint),
      side: BorderSide(color: colors.danger.withValues(alpha: LexiTint.border)),
      minimumSize: const Size(0, _dangerButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s14),
      textStyle: LexiType.footnote.copyWith(fontWeight: FontWeight.w600),
    ),
    onPressed: onClearAll,
    icon: const Icon(LucideIcons.trash2, size: 15),
    label: const Text('清空全部数据'),
  );
}
