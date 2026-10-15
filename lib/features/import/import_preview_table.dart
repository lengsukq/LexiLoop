/// 导入预览表格。
///
/// 一次最多渲染 [importPreviewDisplayLimit] 行：预览可能有上万行，
/// 全量塞进 `ListView` 会让首帧直接卡住，而用户真正关心的是
/// 「前几十行长什么样」与「有多少行有问题」。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/import/csv_parser.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 预览表格。
class ImportPreviewTable extends StatelessWidget {
  /// 以预览与「只看问题行」开关构造。
  const new({required this.preview, required this.onlyProblems, super.key});

  /// 预览结果。
  final ImportPreview preview;

  /// 是否只展示非法 / 重复 / 已存在的行。
  final bool onlyProblems;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final rows = _visibleRows();
    final hidden = preview.totalRows - rows.length;
    final summary = StringBuffer()
      ..write('预览（共 ${preview.totalRows} 行，')
      ..write('新增 ${preview.newRows} / 已存在 ${preview.existingRows} / ')
      ..write('重复 ${preview.duplicateRows} / 无效 ${preview.invalidRows}）');

    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary.toString(),
            style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
          ),
          if (preview.skippedCount > 0) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '已跳过 ${preview.skippedCount} 个空行',
              style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          const _TableHeader(),
          const Divider(height: 12),
          for (final row in rows) _PreviewRow(row: row),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '另有 $hidden 行未展示（可导入，只是不在此处渲染）',
                style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  List<ParsedCsvRow> _visibleRows() {
    final filtered = onlyProblems
        ? preview.rows.where((row) => row.needsAttention).toList()
        : preview.rows;
    if (filtered.length <= importPreviewDisplayLimit) return filtered;
    return filtered.sublist(0, importPreviewDisplayLimit);
  }
}

class _TableHeader extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final style = TextStyle(
      color: colors.tertiaryLabel,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
    );
    return Row(
      children: <Widget>[
        SizedBox(width: 44, child: Text('行号', style: style)),
        Expanded(flex: 3, child: Text('词条', style: style)),
        Expanded(flex: 2, child: Text('类型', style: style)),
        SizedBox(width: 68, child: Text('状态', style: style)),
        Expanded(flex: 3, child: Text('问题', style: style)),
      ],
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const new({required this.row});

  final ParsedCsvRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final label = TextStyle(color: colors.label, fontSize: 12.5);
    final muted = TextStyle(color: colors.secondaryLabel, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(width: 44, child: Text('${row.rowNumber}', style: muted)),
          Expanded(
            flex: 3,
            child: Text(
              row.term.isEmpty ? '（空）' : row.term,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: label,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(_contentTypeLabel(row.contentType), style: muted),
          ),
          SizedBox(width: 68, child: ImportRowStatusBadge(status: row.status)),
          Expanded(
            flex: 3,
            child: Text(
              row.errorMessage ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.danger, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 导入行状态徽章。
class ImportRowStatusBadge extends StatelessWidget {
  /// 以状态构造。
  const new({required this.status, super.key});

  /// 行状态。
  final ImportRowStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final (String label, Color color) = switch (status) {
      ImportRowStatus.newWord => ('新增', colors.success),
      ImportRowStatus.existing => ('已存在', colors.accent),
      ImportRowStatus.duplicate => ('重复', colors.warning),
      ImportRowStatus.invalid => ('无效', colors.danger),
      ImportRowStatus.imported => ('已导入', colors.success),
      ImportRowStatus.error => ('失败', colors.danger),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 内容类型的中文标签。
String _contentTypeLabel(LexicalContentType type) => switch (type) {
  LexicalContentType.word => '单词',
  LexicalContentType.phrase => '短语',
  LexicalContentType.sentence => '句子',
};
