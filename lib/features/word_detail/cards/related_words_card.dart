/// 相关词条卡片（同义词 / 反义词 / 词族 / 易混词共用）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/features/word_detail/dialogs/related_word_dialog.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 关系类型对应的卡片标题与图标。
///
/// 标题由关系推导而不是由调用方传入：详情页有四处同形状的卡片，
/// 让调用方各写一遍标题，改名时必然漏掉一处（旧版正是如此）。
/// 注意这里的「同义词 / 词族」与弹窗里的「近义词 / 同根词 / 词族」措辞
/// 不同——那是旧版就有的两套文案，分别服务于「分区标题」与「关系徽标」。
({String title, IconData icon}) relatedCardLook(RelationType relation) =>
    switch (relation) {
      RelationType.synonym => (title: '同义词', icon: LucideIcons.arrowLeftRight),
      RelationType.antonym => (
        title: '反义词',
        icon: LucideIcons.arrowsUpFromLine,
      ),
      RelationType.wordFamily => (title: '词族', icon: LucideIcons.network),
      RelationType.confusedWith => (title: '易混词', icon: LucideIcons.circleHelp),
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
      variant: SurfaceVariant.plain,
      tone: LexiTone.lavender,
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
    // a11y-ok: 行内由 _RelatedBody 渲染可见文字，读屏会念出词条内容；
    // 点击语义由 InkWell 自己提供，不需要额外标签。
    return InkWell(
      onTap: () => RelatedWordDialog.show(
        context,
        parentWordId: wordId,
        term: item.word,
        relation: relation,
      ),
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: LexiSpace.s6,
          horizontal: LexiSpace.s2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: _RelatedBody(item: item)),
            const SizedBox(width: LexiSpace.s6),
            Icon(LucideIcons.circlePlus, size: 16, color: colors.tertiaryLabel),
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
                style: LexiType.callout.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (item.partOfSpeech != null) ...<Widget>[
              const SizedBox(width: LexiSpace.s6),
              DetailChip(text: item.partOfSpeech!),
            ],
            if (item.relation != null) ...<Widget>[
              const SizedBox(width: LexiSpace.s6),
              DetailChip(text: item.relation!),
            ],
          ],
        ),
        if (item.translation != null)
          Text(
            item.translation!,
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
        // 易混词的区别说明是这一类的核心信息，有则必须显示。
        if (item.difference != null)
          Text(
            '区别：${item.difference}',
            style: LexiType.footnote.copyWith(color: colors.warningText),
          ),
      ],
    );
  }
}

/// 把四类关系收进**一张**卡：上方是关系切换，下方是当前关系的词条。
///
/// **为什么合并**：收敛前同一个词条会连着摞 4 张同形状的卡
/// （同义词 / 反义词 / 词族 / 易混词），每张自带标题、图标和一列行。
/// 一个有很多关联词的词条，光这一块就占掉整屏——而用户真正想看的往往
/// 只是其中一类。合并后：一次只展开一类，其余以「+N」的形式留在切换条上。
///
/// 切换用 `ChoiceChip` 而不是 `SegmentedButton`：360 宽下四个中文标签
/// 放不下一行，`Wrap` 会折行，而 `SegmentedButton` 会溢出。
class RelatedWordsGroup extends StatefulWidget {
  /// 以父词条与「关系 → 词条」的分组构造。
  const new({required this.wordId, required this.groups, super.key});

  /// 父词条 ID。
  final int wordId;

  /// 关系与对应词条；空列表的关系会被忽略。
  final Map<RelationType, List<RelatedWordView>> groups;

  @override
  State<RelatedWordsGroup> createState() => _RelatedWordsGroupState();
}

class _RelatedWordsGroupState extends State<RelatedWordsGroup> {
  RelationType? _selected;

  /// 有内容的关系，按枚举顺序（同义 → 反义 → 词族 → 易混）。
  List<RelationType> get _available => <RelationType>[
    for (final relation in RelationType.values)
      if ((widget.groups[relation] ?? const <RelatedWordView>[]).isNotEmpty)
        relation,
  ];

  @override
  Widget build(BuildContext context) {
    final available = _available;
    if (available.isEmpty) return const SizedBox.shrink();
    // 选中项失效时（例如切换词条导致某类清空）回落到第一类。
    final selected = available.contains(_selected)
        ? _selected!
        : available.first;

    // 只有一类时标题就用那类的名字（「同义词」），而不是笼统的「相关词」：
    // 一张只装同义词的卡片，标题说「同义词」比说「相关词」更准确，
    // 也省掉一行「只有一个选项」的切换条。
    final single = available.length == 1;
    final look = relatedCardLook(
      single ? available.first : RelationType.synonym,
    );
    return SectionCard(
      variant: SurfaceVariant.plain,
      tone: LexiTone.lavender,
      title: single ? look.title : '相关词',
      icon: single ? look.icon : LucideIcons.network,
      trailing: _RelationChips(
        available: available,
        groups: widget.groups,
        selected: selected,
        onSelect: (relation) => setState(() => _selected = relation),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final item in widget.groups[selected]!)
            _RelatedRow(wordId: widget.wordId, relation: selected, item: item),
        ],
      ),
    );
  }
}

/// 关系切换条。
class _RelationChips extends StatelessWidget {
  const new({
    required this.available,
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<RelationType> available;
  final Map<RelationType, List<RelatedWordView>> groups;
  final RelationType selected;
  final ValueChanged<RelationType> onSelect;

  @override
  Widget build(BuildContext context) {
    if (available.length == 1) {
      // 只有一类时不需要切换条：标题已经说了是哪一类。
      return const SizedBox.shrink();
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: LexiSpace.s6,
      runSpacing: LexiSpace.s6,
      children: <Widget>[
        for (final relation in available)
          ChoiceChip(
            label: Text(
              '${relatedCardLook(relation).title} '
              '${groups[relation]!.length}',
            ),
            selected: relation == selected,
            onSelected: (_) => onSelect(relation),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
