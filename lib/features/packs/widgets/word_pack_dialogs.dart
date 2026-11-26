/// 词书包安装确认与安全卸载影响确认弹窗。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 安装确认弹窗返回结果。
class WordPackInstallChoice {
  /// 以是否纳入每日计划构造。
  const new({required this.includeInDailyStudy});

  /// 是否在安装后同步纳入每日计划。
  final bool includeInDailyStudy;
}

/// 卸载确认弹窗返回结果。
class WordPackUninstallChoice {
  /// 以是否将已学词条保留到个人词库构造。
  const new({required this.keepLearnedAsPersonal});

  /// 是否自动将有学习记录的词条转为个人词库。
  final bool keepLearnedAsPersonal;
}

/// 弹出词书下载安装确认框。
Future<WordPackInstallChoice?> showWordPackInstallDialog(
  BuildContext context, {
  required WordPackCatalogItem item,
  bool isUpdate = false,
}) => showDialog<WordPackInstallChoice>(
  context: context,
  builder: (context) => _InstallConfirmDialog(item: item, isUpdate: isUpdate),
);

/// 弹出卸载词书前的影响明细确认框。
Future<WordPackUninstallChoice?> showWordPackUninstallDialog(
  BuildContext context, {
  required WordPackUninstallImpact impact,
}) => showDialog<WordPackUninstallChoice>(
  context: context,
  builder: (context) => _UninstallConfirmDialog(impact: impact),
);

class _InstallConfirmDialog extends StatefulWidget {
  const new({required this.item, required this.isUpdate});

  final WordPackCatalogItem item;
  final bool isUpdate;

  @override
  State<_InstallConfirmDialog> createState() => _InstallConfirmDialogState();
}

class _InstallConfirmDialogState extends State<_InstallConfirmDialog> {
  bool _includeInDaily = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final item = widget.item;
    return AlertDialog(
      title: Text(widget.isUpdate ? '更新「${item.name}」' : '添加「${item.name}」'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '约 ${item.wordCount} 词 · '
            '${formatPackBytes(item.compressedBytes)} · '
            '${item.contentMode.label}',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s12),
          Text(
            '词书词条与个人词库共用唯一词形与 FSRS 进度，绝不覆盖你手动编辑过的内容。',
            style: LexiType.body.copyWith(color: colors.label),
          ),
          const SizedBox(height: LexiSpace.s12),
          CheckboxListTile(
            value: _includeInDaily,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('纳入「今日每日学习计划」', style: LexiType.callout),
            subtitle: Text(
              '默认关闭，推荐在词书卡片点「专项学习」单独背诵，避免打乱个人生词节奏。',
              style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
            ),
            onChanged: (value) =>
                setState(() => _includeInDaily = value ?? false),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(WordPackInstallChoice(includeInDailyStudy: _includeInDaily)),
          child: Text(widget.isUpdate ? '开始更新' : '下载并添加'),
        ),
      ],
    );
  }
}

class _UninstallConfirmDialog extends StatefulWidget {
  const new({required this.impact});

  final WordPackUninstallImpact impact;

  @override
  State<_UninstallConfirmDialog> createState() =>
      _UninstallConfirmDialogState();
}

class _UninstallConfirmDialogState extends State<_UninstallConfirmDialog> {
  bool _keepLearned = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final impact = widget.impact;
    return AlertDialog(
      title: Text('卸载「${impact.packName}」'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ImpactLine(label: '个人词库词条（原样保留）', count: impact.personalKeptCount),
          _ImpactLine(
            label: '其他词书共享词条（保留）',
            count: impact.sharedOtherPackCount,
          ),
          _ImpactLine(
            label: '仅本词书且未学习（将清理释放空间）',
            count: impact.removableUnlearnedCount,
          ),
          if (impact.learnedOnlyInPackCount > 0) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            CheckboxListTile(
              value: _keepLearned,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '将已学过的 ${impact.learnedOnlyInPackCount} 词保留到个人词库',
                style: LexiType.callout,
              ),
              subtitle: Text(
                '推荐勾选，保留这些词条的全部 FSRS 记忆曲线与统计记录。',
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
              onChanged: (value) =>
                  setState(() => _keepLearned = value ?? true),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.danger),
          onPressed: () => Navigator.of(
            context,
          ).pop(WordPackUninstallChoice(keepLearnedAsPersonal: _keepLearned)),
          child: const Text('确认卸载'),
        ),
      ],
    );
  }
}

class _ImpactLine extends StatelessWidget {
  const new({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
          ),
          const SizedBox(width: LexiSpace.s8),
          Text(
            '$count 词',
            style: LexiType.callout.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
