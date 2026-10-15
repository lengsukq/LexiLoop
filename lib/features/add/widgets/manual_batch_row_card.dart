/// 批量预览的单行卡片与预览详情。
///
/// 拆成独立文件而不是塞进面板：面板要管输入、选项、进度与「全部确认」，
/// 行卡片自带可展开的详情（旧版 `manual-tab.tsx` 的 `BatchRowCard` +
/// `PreviewDetail` 共约 120 行），混在一起会让 `build()` 迅速超过 80 行。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/features/add/manual_batch_providers.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/services/manual_preview_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';

/// 一行在批量列表里的位置与内容。
class ManualBatchEntry {
  /// 以位置与行内容构造。
  const new({required this.index, required this.row});

  /// 从 0 开始的行下标。
  final int index;

  /// 该行的内容。
  final ManualBatchRow row;
}

/// 批量预览的单行卡片。
class ManualBatchRowCard extends StatelessWidget {
  /// 以行、展开状态与回调构造。
  const new({
    required this.entry,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onConfirm,
    super.key,
  });

  /// 行位置与内容。
  final ManualBatchEntry entry;

  /// 是否展开详情。
  final bool expanded;

  /// 是否有正在进行的异步操作（此时禁止重复确认）。
  final bool busy;

  /// 展开 / 收起详情。
  final VoidCallback onToggle;

  /// 确认该行。
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final preview = entry.row.preview;
    return Container(
      key: Key('manualBatchRow-${entry.index}'),
      margin: const EdgeInsets.only(bottom: rowCardGap),
      padding: const EdgeInsets.all(rowCardPadding),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _RowHeader(entry: entry),
          const SizedBox(height: rowActionGap),
          _RowActions(
            entry: entry,
            expanded: expanded,
            busy: busy,
            onToggle: onToggle,
            onConfirm: onConfirm,
          ),
          if (expanded && preview != null) ...<Widget>[
            const SizedBox(height: detailGap),
            _PreviewDetail(preview: preview),
          ],
        ],
      ),
    );
  }
}

/// 行的上半部分：序号、词条、状态徽标与一行摘要。
class _RowHeader extends StatelessWidget {
  const new({required this.entry});

  final ManualBatchEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final row = entry.row;
    final preview = row.preview;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: indexBadgeSize,
          height: indexBadgeSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: LexiTint.tint),
            shape: BoxShape.circle,
          ),
          child: Text(
            '${entry.index + 1}',
            style: LexiType.caption.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: LexiSpace.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    row.term,
                    style: LexiType.callout.copyWith(
                      color: colors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (preview != null)
                    _Badge(label: articleEntryTypeLabel(preview.contentType)),
                  if (preview?.existingWordId != null)
                    const _Badge(label: '已存在', tone: LexiBadgeTone.warning),
                  if (row.isConfirmed)
                    const _Badge(label: '已确认', tone: LexiBadgeTone.success),
                ],
              ),
              const SizedBox(height: LexiSpace.s2),
              Text(
                _summary(row),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LexiType.body.copyWith(
                  color: row.error.isEmpty
                      ? colors.secondaryLabel
                      : colors.danger,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 该行的摘要文案：失败原因 > 翻译摘要 > 生成中占位。
  String _summary(ManualBatchRow row) {
    if (row.error.isNotEmpty) return row.error;
    final summary = row.preview?.content.record('summary');
    final translation = _text(summary?['translation']);
    if (translation.isNotEmpty) return translation;
    final short = _text(summary?['shortDefinition']);
    if (short.isNotEmpty) return short;
    return row.preview == null ? '正在生成预览…' : '词典没有给出摘要。';
  }
}

/// 行的下半部分：确认、打开词条、展开详情。
class _RowActions extends StatelessWidget {
  const new({
    required this.entry,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onConfirm,
  });

  final ManualBatchEntry entry;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final row = entry.row;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (row.isPending)
          OutlinedButton.icon(
            key: Key('manualBatchConfirm-${entry.index}'),
            onPressed: busy ? null : onConfirm,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
            label: const Text('确认添加'),
          ),
        if (row.isConfirmed) ...<Widget>[
          Text(
            '词条 ID：${row.confirmedWordId}',
            style: LexiType.footnote.copyWith(
              color: colors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextButton(
            key: Key('manualBatchOpenWord-${entry.index}'),
            onPressed: () => context.go('/words/${row.confirmedWordId}'),
            child: const Text('打开词条'),
          ),
        ],
        if (row.preview != null)
          TextButton.icon(
            key: Key('manualBatchToggle-${entry.index}'),
            onPressed: onToggle,
            icon: Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 16,
            ),
            label: Text(expanded ? '收起' : '详情'),
          ),
      ],
    );
  }
}

/// 预览详情：翻译摘要、音标、释义、例句、短语搭配、词形变化。
///
/// **与旧版的一处差异**：旧版详情页还渲染句子分析、学习提示、近义词 /
/// 同根词、模型质量分与 token 用量。这里只保留**判定「这个词要不要加」**
/// 所需的内容——批量预览是逐行快速决策的场景，模型质量分属于排查工具，
/// 已经在词条详情页的「初始化质量」卡里。
class _PreviewDetail extends StatelessWidget {
  /// 以预览构造。
  const new({required this.preview});

  /// 待渲染的预览。
  final ManualPreview preview;

  @override
  Widget build(BuildContext context) {
    final content = preview.content;
    return Column(
      key: const Key('manualBatchDetail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SummaryBlock(preview: preview),
        _ChipsBlock(title: '音标', values: _phonetics(content)),
        _LinesBlock(
          title: '释义',
          lines: _definitions(content, preview.targetLanguage),
        ),
        _LinesBlock(title: '例句', lines: _examples(content)),
        _LinesBlock(title: '短语搭配', lines: _phrases(content)),
        _LinesBlock(title: '词形变化', lines: _forms(content)),
      ],
    );
  }
}

/// 翻译摘要与语言方向。
class _SummaryBlock extends StatelessWidget {
  const new({required this.preview});

  final ManualPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final summary = preview.content.record('summary');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _Badge(label: articleEntryTypeLabel(preview.contentType)),
            if (preview.existingWordId != null)
              const _Badge(label: '词库中已存在', tone: LexiBadgeTone.warning),
            Text(
              '${preview.sourceLanguageName} → ${preview.targetLanguageName}',
              style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
            ),
            Text(
              '预览有效至 ${articleExpiryText(preview.expiresAt)}',
              style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
            ),
          ],
        ),
        if (_text(summary['translation']).isNotEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s6),
          Text(
            _text(summary['translation']),
            style: LexiType.title.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_text(summary['shortDefinition']).isNotEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s4),
          Text(
            _text(summary['shortDefinition']),
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
        ],
      ],
    );
  }
}

/// 一组徽标。
class _ChipsBlock extends StatelessWidget {
  const new({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return _Block(
      title: title,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[for (final value in values) _Badge(label: value)],
      ),
    );
  }
}

/// 一组文本行。
class _LinesBlock extends StatelessWidget {
  const new({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final colors = context.lexiColors;
    return _Block(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: LexiSpace.s2),
              child: Text(
                line,
                style: LexiType.body.copyWith(color: colors.secondaryLabel),
              ),
            ),
        ],
      ),
    );
  }
}

/// 带小标题的详情分块。
class _Block extends StatelessWidget {
  const new({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: detailBlockGap),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: LexiType.caption.copyWith(
            color: context.lexiColors.tertiaryLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LexiSpace.s4),
        child,
      ],
    ),
  );
}

/// 小徽标。
class _Badge extends StatelessWidget {
  const new({required this.label, this.tone = LexiBadgeTone.accent});

  final String label;
  final LexiBadgeTone tone;

  @override
  Widget build(BuildContext context) => LexiBadge(label: label, tone: tone);
}

/// 徽标色调。
String _text(Object? value) => value is String ? value.trim() : '';

List<String> _phonetics(DictionaryContent content) => <String>[
  for (final item in content.records('pronunciations'))
    if (_text(item['phonetic']).isNotEmpty) _text(item['phonetic']),
];

/// 目标语言释义；一条都没有时退回全部释义。
///
/// 退回是**有意偏离旧版**（旧版只渲染 `language === targetLanguage` 的条目）：
/// 有道对某些词只返回源语言释义，严格过滤会让详情页只剩一个「释义」标题，
/// 用户以为预览坏了。
List<String> _definitions(DictionaryContent content, String targetLanguage) {
  final all = <String>[
    for (final item in content.records('definitions')) _joinDefinition(item),
  ]..removeWhere((line) => line.isEmpty);
  final targeted = <String>[
    for (final item in content.records('definitions'))
      if (item['language'] == targetLanguage) _joinDefinition(item),
  ]..removeWhere((line) => line.isEmpty);
  return targeted.isNotEmpty ? targeted : all;
}

String _joinDefinition(Map<String, Object?> item) {
  final partOfSpeech = _text(item['partOfSpeech']);
  final text = _text(item['text']);
  if (text.isEmpty) return '';
  return partOfSpeech.isEmpty ? text : '$partOfSpeech · $text';
}

List<String> _examples(DictionaryContent content) => <String>[
  for (final item in content.records('examples'))
    if (_text(item['sentence']).isNotEmpty) _exampleLine(item),
];

String _exampleLine(Map<String, Object?> item) {
  final sentence = _text(item['sentence']);
  final translation = _text(item['translation']);
  return translation.isEmpty ? sentence : '$sentence（$translation）';
}

List<String> _phrases(DictionaryContent content) => <String>[
  for (final item in content.records('phrases'))
    if (_text(item['phrase']).isNotEmpty)
      _pairLine(item['phrase'], item['translation']),
];

List<String> _forms(DictionaryContent content) => <String>[
  for (final item in content.records('forms'))
    if (_text(item['value']).isNotEmpty) _pairLine(item['value'], item['type']),
];

String _pairLine(Object? left, Object? right) {
  final value = _text(left);
  final extra = _text(right);
  return extra.isEmpty ? value : '$value · $extra';
}

/// 行卡片之间的间距。
const double rowCardGap = 8;

/// 行卡片内边距。
const double rowCardPadding = 12;

/// 序号徽标尺寸。
const double indexBadgeSize = 22;

/// 行标题与操作区之间的间距。
const double rowActionGap = 8;

/// 操作区与详情之间的间距。
const double detailGap = 10;

/// 详情分块之间的间距。
const double detailBlockGap = 10;
