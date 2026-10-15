/// 释义卡片。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 释义卡片：按语言分组，标注词性与来源。
///
/// 调用方保证 [definitions] 非空，否则整卡不显示。
class DefinitionsCard extends StatelessWidget {
  /// 以释义列表构造。
  const new({required this.definitions, super.key});

  /// 释义列表。
  final List<DefinitionValue> definitions;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByLanguage(definitions);
    return DetailSectionCard(
      title: '释义',
      icon: Icons.menu_book_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final entry in groups.entries) ...<Widget>[
            _LanguageGroup(language: entry.key, items: entry.value),
            if (entry.key != groups.keys.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// 按语言分组，保留首次出现的顺序。
///
/// 刻意不按 key 排序：释义顺序应与词典返回顺序一致，
/// 排序会把英文释义挪到中文前面，与词条的目标语言不符。
Map<String, List<DefinitionValue>> _groupByLanguage(
  List<DefinitionValue> items,
) {
  final groups = <String, List<DefinitionValue>>{};
  for (final item in items) {
    groups.putIfAbsent(item.language, () => <DefinitionValue>[]).add(item);
  }
  return groups;
}

class _LanguageGroup extends StatelessWidget {
  const new({required this.language, required this.items});

  final String language;
  final List<DefinitionValue> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          language.isEmpty ? '未标注语言' : languageLabel(language),
          style: TextStyle(
            color: colors.secondaryLabel,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in items)
          DetailBullet(item.text, note: _annotation(item)),
      ],
    );
  }

  /// 「词性 · 来源 · 已编辑」标注；三者都缺时返回 `null`。
  String? _annotation(DefinitionValue item) {
    final parts = <String>[
      if (item.partOfSpeech != null) item.partOfSpeech!,
      if (item.source != null) item.source!,
      if (item.isUserEdited) '已编辑',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
