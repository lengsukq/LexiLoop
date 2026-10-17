/// 「导入备份」按钮。
///
/// 从词库页头部挪成独立控件：空状态也要给出同一个入口，
/// 否则「一个词条都没有」的用户只能在空页面里猜该去哪里导入。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/features/settings/import_backup_confirm.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';

/// 导入旧版 JSON 备份的按钮。
class ImportBackupButton extends ConsumerStatefulWidget {
  /// 以强调样式构造（空状态里它是主按钮）。
  const new({this.emphasized = false, super.key});

  /// 是否用实心主按钮样式。
  final bool emphasized;

  @override
  ConsumerState<ImportBackupButton> createState() => _ImportBackupButtonState();
}

class _ImportBackupButtonState extends ConsumerState<ImportBackupButton> {
  bool _busy = false;

  Future<void> _import() async {
    // **与设置页同一个确认框**：这个动作整份替换 12 张表，
    // 而此前这里是零确认——入口越显眼（就贴在「手动添加」旁边），
    // 门槛反而越低，正好反了。
    if (!await confirmBackupImport(context) || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(backupServiceProvider).pickAndImport();
      if (result == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：${result.rowCounts['words'] ?? 0} 个词条、'
            '${result.totalRows} 行，统计重算 ${result.recomputedStats} 条',
          ),
        ),
      );
      ref
        ..invalidate(wordListProvider)
        ..invalidate(wordCountProvider)
        ..invalidate(masterySummaryProvider);
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox(
            width: LexiSpace.s14,
            height: LexiSpace.s14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.upload_file_rounded, size: 17);
    final label = Text(_busy ? '导入中…' : '导入备份');
    if (widget.emphasized) {
      return FilledButton.icon(
        onPressed: _busy ? null : _import,
        icon: icon,
        label: label,
      );
    }
    return TextButton.icon(
      onPressed: _busy ? null : _import,
      icon: icon,
      label: label,
    );
  }
}
