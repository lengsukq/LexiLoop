/// 词条摘要与标签卡片。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 摘要卡片：简释、整句翻译、CEFR 等级、词频，以及词条标签。
///
/// 调用方保证 [summary] 与 [tags] 至少有一个非空，否则整卡不显示。
class SummaryCard extends StatelessWidget {
  /// 以摘要与标签构造。
  const new({required this.summary, required this.tags, super.key});

  /// 词条摘要。
  final SummaryView summary;

  /// 词条标签。
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '摘要',
      icon: Icons.auto_awesome_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (summary.shortDefinition != null)
            DetailField(label: '简释', value: summary.shortDefinition!),
          if (summary.translation != null)
            DetailField(label: '整句翻译', value: summary.translation!),
          if (summary.cefrLevel != null)
            DetailField(label: 'CEFR', value: summary.cefrLevel!),
          if (summary.frequency != null)
            DetailField(label: '词频', value: summary.frequency!),
          if (tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[for (final tag in tags) DetailChip(text: tag)],
            ),
          ],
        ],
      ),
    );
  }
}
