/// 相关词条卡片（同义词 / 反义词 / 词族 / 易混词共用）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/features/word_detail/dialogs/related_word_dialog.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 关系类型对应的卡片标题与图标。
///
/// 标题由关系推导而不是由调用方传入：详情页有四处同形状的卡片，
/// 让调用方各写一遍标题，改名时必然漏掉一处（旧版正是如此）。
/// 注意这里的「同义词 / 词族」与弹窗里的「近义词 / 同根词 / 词族」措辞
/// 不同——那是旧版就有的两套文案，分别服务于「分区标题」与「关系徽标」。
({String title, IconData icon}) relatedCardLook(
  RelationType relation,
) => switch (relation) {
  RelationType.synonym => (title: '同义词', icon: Icons.sync_alt_rounded),
  RelationType.antonym => (title: '反义词', icon: Icons.compare_arrows_rounded),
  RelationType.wordFamily => (title: '词族', icon: Icons.hub_rounded),
  RelationType.confusedWith => (title: '易混词', icon: Icons.help_outline_rounded),
};

/// 相关词条卡片。
///
/// 四类关系的元素形态完全一致，因此共用同一组件、由 [relation] 决定标题与
/// 图标——旧版为 summary / learning / sentenceAnalysis 各写一段结构相同的
/// 渲染，是「同一形状重复三遍」的典型。
///
/// **每一行都可点**：点开的是关联词弹窗，它先回答「这个词在不在词库里」，
/// 再决定能不能加入。只读列表等于告诉用户「这里有些词，但你什么都做不了」。
///
/// 调用方保证 [items] 非空，否则整卡不显示。
class RelatedWordsCard extends StatelessWidget {
  /// 以父词条 ID、关系与词条列表构造。
  const new({
    required this.wordId,
    required this.relation,
    required this.items,
    super.key,
  });

  /// 父词条 ID；加入关联词时要用它读父词条的关系信息。
  final int wordId;

  /// 本卡展示的关系类型。
  final RelationType relation;

  /// 相关词条列表。
  final List<RelatedWordView> items;

  @override
  Widget build(BuildContext context) {
    final look = relatedCardLook(relation);
    return SectionCard(
      title: look.title,
      icon: look.icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final item in items)
            _RelatedRow(wordId: wordId, relation: relation, item: item),
        ],
      ),
    );
  }
}

/// 一行关联词；点按打开加入弹窗。
class _RelatedRow extends StatelessWidget {
  const new({required this.wordId, required this.relation, required this.item});

  final int wordId;
  final RelationType relation;
  final RelatedWordView item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return InkWell(
      onTap: () => RelatedWordDialog.show(
        context,
        parentWordId: wordId,
        term: item.word,
        relation: relation,
      ),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _RelatedBody(item: item)),
            const SizedBox(width: 6),
            Icon(
              Icons.add_circle_outline_rounded,
              size: 16,
              color: colors.tertiaryLabel,
            ),
          ],
        ),
      ),
    );
  }
}

/// 关联词的正文：词形、词性、关系、译文与区别说明。
class _RelatedBody extends StatelessWidget {
  const new({required this.item});

  final RelatedWordView item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
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
    );
  }
}
