/// 助记与句子分析卡片。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 助记与句子分析卡片：助记法、发音提示、常见错误与句子分析。
///
/// 调用方保证 [learning] 与 [analysis] 至少一个非空，否则整卡不显示。
class MnemonicCard extends StatelessWidget {
  /// 以学习信息与句子分析构造。
  const new({required this.learning, required this.analysis, super.key});

  /// 学习辅助信息。
  final LearningView learning;

  /// 句子分析。
  final SentenceAnalysisView analysis;

  @override
  Widget build(BuildContext context) {
    return DetailSectionCard(
      title: '助记与句子分析',
      icon: Icons.lightbulb_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (learning.pronunciationTip != null)
            DetailField(label: '发音提示', value: learning.pronunciationTip!),
          if (learning.mnemonic != null)
            DetailField(label: '助记', value: learning.mnemonic!),
          if (learning.commonMistakes.isNotEmpty)
            _BulletGroup(
              title: '常见错误',
              items: <String>[for (final item in learning.commonMistakes) item],
            ),
          if (!analysis.isEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _AnalysisSection(analysis: analysis),
          ],
        ],
      ),
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  const new({required this.analysis});

  final SentenceAnalysisView analysis;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Divider(color: colors.separator, height: 18),
        if (analysis.grammarPattern != null)
          DetailField(label: '语法模式', value: analysis.grammarPattern!),
        if (analysis.grammarExplanation != null)
          DetailField(label: '语法解释', value: analysis.grammarExplanation!),
        _BulletGroup(title: '语法要点', items: analysis.grammarNotes),
        _BulletGroup(
          title: '关键表达',
          items: <String>[
            for (final item in analysis.keyExpressions) item.text,
          ],
        ),
        _BulletGroup(
          title: '相似例句',
          items: <String>[
            for (final item in analysis.similarExamples) item.text,
          ],
        ),
        _BulletGroup(
          title: '句式变换',
          items: <String>[
            for (final item in analysis.variations)
              if (item.label == null)
                item.text
              else
                '${item.label}：${item.text}',
          ],
        ),
      ],
    );
  }
}

class _BulletGroup extends StatelessWidget {
  const new({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.secondaryLabel,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          for (final item in items) DetailBullet(item),
        ],
      ),
    );
  }
}
