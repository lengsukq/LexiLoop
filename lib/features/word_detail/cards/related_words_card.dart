/// 相关词条卡片（同义词 / 反义词 / 词族 / 易混词共用）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 相关词条卡片。
///
/// 四类关系的元素形态完全一致，因此共用同一组件、由调用方给标题与图标——
/// 旧版为 summary / learning / sentenceAnalysis 各写一段结构相同的渲染，
/// 是「同一形状重复三遍」的典型。
///
/// 调用方保证 [items] 非空，否则整卡不显示。
class RelatedWordsCard extends StatelessWidget {
  /// 以标题、图标与词条列表构造。
  const new({
    required this.title,
    required this.icon,
    required this.items,
    super.key,
  });

  /// 卡片标题。
  final String title;

  /// 标题图标。
  final IconData icon;

  /// 相关词条列表。
  final List<RelatedWordView> items;

  @override
  Widget build(BuildContext context) {
    return DetailSectionCard(
      title: title,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[for (final item in items) _RelatedRow(item: item)],
      ),
    );
  }
}

class _RelatedRow extends StatelessWidget {
  const new({required this.item});

  final RelatedWordView item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(
                child: Text(
                  item.word,
                  style: TextStyle(
                    color: colors.label,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (item.partOfSpeech != null) ...<Widget>[
                const SizedBox(width: 6),
                DetailChip(text: item.partOfSpeech!),
              ],
              if (item.relation != null) ...<Widget>[
                const SizedBox(width: 6),
                DetailChip(text: item.relation!),
              ],
            ],
          ),
          if (item.translation != null)
            Text(
              item.translation!,
              style: TextStyle(
                color: colors.secondaryLabel,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          // 易混词的区别说明是这一类的核心信息，有则必须显示。
          if (item.difference != null)
            Text(
              '区别：${item.difference}',
              style: TextStyle(
                color: colors.warning,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}
