/// 文章导入的候选列表：单词表、短语卡与句子卡。
///
/// 对应旧版 `article-tab.tsx` 的 `CandidateTables`：类型筛选、「仅看 AI 推荐」、
/// 选推荐 / 全选当前 / 清空，以及三块候选展示。已掌握（KNOWN）的候选
/// 不可勾选，但保留在列表里——用户需要看到「这个词我已经有了」。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/article_import/article_candidates.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/features/add/widgets/article_common.dart';
import 'package:lexiloop/features/add/widgets/article_youdao_preview_sheet.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 候选列表。
class ArticleCandidateList extends ConsumerWidget {
  /// 创建候选列表。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final preview = state.preview;
    if (preview == null) return const SizedBox.shrink();
    final visibleList = state.visibleCandidates;
    final words = <ArticleCandidate>[
      for (final candidate in visibleList)
        if (candidate.entryType == LexicalContentType.word) candidate,
    ];
    final phrases = <ArticleCandidate>[
      for (final candidate in visibleList)
        if (candidate.entryType == LexicalContentType.phrase) candidate,
    ];
    final sentences = <ArticleCandidate>[
      for (final candidate in visibleList)
        if (candidate.entryType == LexicalContentType.sentence) candidate,
    ];
    return ArticleSectionCard(
      title:
          '候选 · 已选 ${state.selection.selected.length} / ${state.candidateCount}',
      trailing: const _CandidateActions(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _FilterBar(),
          const SizedBox(height: articleTightGap),
          const _WordToolsBar(),
          if (state.selection.filter == ArticleCandidateFilter.all ||
              state.selection.filter == ArticleCandidateFilter.word)
            if (words.isNotEmpty) _WordTable(candidates: words),
          if (state.selection.filter == ArticleCandidateFilter.all ||
              state.selection.filter == ArticleCandidateFilter.phrase)
            _CardList(
              title: '短语 · ${_pending(phrases)} 待学（AI 精选固定搭配）',
              candidates: phrases,
            ),
          if (state.selection.filter == ArticleCandidateFilter.all ||
              state.selection.filter == ArticleCandidateFilter.sentence)
            _CardList(
              title: '句子 · ${_pending(sentences)} 待学（AI 句法卡片）',
              candidates: sentences,
            ),
          if (visibleList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: articleCardGap),
              child: Text(
                '当前筛选无候选。',
                style: LexiType.body.copyWith(
                  color: context.lexiColors.secondaryLabel,
                ),
              ),
            ),
          Text(
            '已按原形去重；点击右侧词典图标可即时通过有道预览释义与音标。',
            style: LexiType.caption.copyWith(
              color: context.lexiColors.tertiaryLabel,
            ),
          ),
        ],
      ),
    );
  }

  int _pending(List<ArticleCandidate> candidates) =>
      candidates.where((candidate) => candidate.isCandidate).length;
}

class _CandidateActions extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final recommended = state.preview?.recommendedTerms.isNotEmpty ?? false;
    return Wrap(
      spacing: 6,
      children: <Widget>[
        TextButton(
          key: const Key('articleSelectRecommended'),
          onPressed: recommended ? notifier.selectRecommended : null,
          child: const Text('选推荐'),
        ),
        TextButton(
          key: const Key('articleSelectAll'),
          onPressed: notifier.selectAllVisible,
          child: const Text('全选当前'),
        ),
        TextButton(
          key: const Key('articleClearSelection'),
          onPressed: notifier.clearSelection,
          child: const Text('清空'),
        ),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final preview = state.preview;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final filter in ArticleCandidateFilter.values)
          ChoiceChip(
            key: Key('articleFilter${filter.name}'),
            label: Text(_filterLabel(filter)),
            selected: state.selection.filter == filter,
            onSelected: (_) => notifier.setFilter(filter),
          ),
        if ((preview?.aiApplied ?? false) &&
            (preview?.recommendedTerms.isNotEmpty ?? false))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Checkbox(
                key: const Key('articleRecommendedOnly'),
                value: state.selection.showRecommendedOnly,
                onChanged: (value) =>
                    notifier.setShowRecommendedOnly(value: value ?? false),
              ),
              Text(
                '仅看 AI 推荐',
                style: LexiType.footnote.copyWith(
                  color: context.lexiColors.secondaryLabel,
                ),
              ),
            ],
          ),
      ],
    );
  }

  String _filterLabel(ArticleCandidateFilter filter) => switch (filter) {
    ArticleCandidateFilter.all => '全部',
    ArticleCandidateFilter.word => '单词',
    ArticleCandidateFilter.phrase => '短语',
    ArticleCandidateFilter.sentence => '句子',
  };
}

/// CEFR 筛选、排序与关键词过滤工具条。
class _WordToolsBar extends ConsumerWidget {
  const new();

  static const List<String> _cefrOptions = <String>['B1', 'B2', 'C1', 'C2'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final state = ref.watch(articleWizardProvider);
    final notifier = ref.read(articleWizardProvider.notifier);
    final hasCefr =
        state.preview?.candidates.any((item) => item.cefrLevel != null) ??
        false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          key: const Key('articleCandidateSearch'),
          onChanged: notifier.setSearchQuery,
          style: LexiType.body.copyWith(color: colors.label),
          decoration: InputDecoration(
            isDense: true,
            hintText: '筛选单词、变形词或语境提示…',
            hintStyle: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
            prefixIcon: const Icon(LucideIcons.search, size: 16),
            filled: true,
            fillColor: colors.fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LexiRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: articleTightGap),
        Wrap(
          spacing: LexiSpace.s6,
          runSpacing: LexiSpace.s6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (hasCefr) ...<Widget>[
              ChoiceChip(
                key: const Key('articleCefrAll'),
                label: const Text('全部等级'),
                selected: state.selection.cefrFilter == null,
                onSelected: (_) => notifier.setCefrFilter(null),
              ),
              for (final level in _cefrOptions)
                ChoiceChip(
                  key: Key('articleCefr$level'),
                  label: Text(level),
                  selected: state.selection.cefrFilter == level,
                  onSelected: (_) => notifier.setCefrFilter(level),
                ),
            ],
            for (final sort in ArticleCandidateSort.values)
              ChoiceChip(
                key: Key('articleSort${sort.name}'),
                label: Text(_sortLabel(sort)),
                selected: state.selection.sort == sort,
                onSelected: (_) => notifier.setSort(sort),
              ),
          ],
        ),
      ],
    );
  }

  String _sortLabel(ArticleCandidateSort sort) => switch (sort) {
    ArticleCandidateSort.difficulty => '按推荐/难度',
    ArticleCandidateSort.occurrences => '按频次',
    ArticleCandidateSort.appearance => '按原序',
  };
}

class _WordTable extends ConsumerWidget {
  const new({required this.candidates});

  final List<ArticleCandidate> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (candidates.isEmpty) return const SizedBox.shrink();
    final state = ref.watch(articleWizardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: articleCardGap),
        Text(
          '单词 · ${candidates.where((c) => c.isCandidate).length} 待学',
          style: LexiType.footnote.copyWith(
            color: context.lexiColors.secondaryLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: articleTightGap),
        for (final candidate in candidates)
          _WordRow(
            candidate: candidate,
            selected: state.selection.selected.contains(
              articleSelectionKey(candidate).toLowerCase(),
            ),
          ),
      ],
    );
  }
}

class _WordRow extends ConsumerWidget {
  const new({required this.candidate, required this.selected});

  final ArticleCandidate candidate;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final notifier = ref.read(articleWizardProvider.notifier);
    final key = articleSelectionKey(candidate).toLowerCase();
    return CheckboxListTile(
      key: Key('articleCandidate$key'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: !candidate.isKnown && selected,
      onChanged: candidate.isKnown ? null : (_) => notifier.toggleKey(key),
      secondary: IconButton(
        key: Key('articleYoudaoPreview$key'),
        tooltip: '有道查词预览',
        icon: Icon(LucideIcons.bookOpen, size: 17, color: colors.accent),
        onPressed: () => unawaited(
          showArticleYoudaoPreview(
            context,
            term: candidate.term,
            surfaceForm: candidate.surfaceForm,
          ),
        ),
      ),
      title: Wrap(
        spacing: LexiSpace.s6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            candidate.term,
            style: LexiType.callout.copyWith(
              color: candidate.isKnown ? colors.tertiaryLabel : colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (candidate.surfaceForm != null)
            Text(
              '← ${candidate.surfaceForm}',
              style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
            ),
        ],
      ),
      subtitle: _WordSubtitle(candidate: candidate, selected: selected),
    );
  }
}

class _WordSubtitle extends StatelessWidget {
  const new({required this.candidate, required this.selected});

  final ArticleCandidate candidate;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: LexiSpace.s6,
          runSpacing: LexiSpace.s4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (candidate.cefrLevel != null)
              ArticleBadge(
                label: candidate.cefrLevel!,
                tone: LexiBadgeTone.purple,
              ),
            for (final tag in candidate.examTags)
              ArticleBadge(label: tag, tone: LexiBadgeTone.neutral),
            if (candidate.difficulty != null)
              Text(
                '难度 ${candidate.difficulty}/5',
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
            Text('出现 ${candidate.occurrences} 次', style: LexiType.caption),
            _StateBadge(candidate: candidate, selected: selected),
          ],
        ),
        if (candidate.aiReason != null)
          Text(
            candidate.aiReason!,
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        if (candidate.sourceSentence != null)
          Padding(
            padding: const EdgeInsets.only(top: LexiSpace.s2),
            child: Text(
              '“${candidate.sourceSentence!}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
            ),
          ),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  const new({required this.candidate, required this.selected});

  final ArticleCandidate candidate;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (candidate.isKnown) {
      return const ArticleBadge(label: '已掌握', tone: LexiBadgeTone.accent);
    }
    return ArticleBadge(
      label: selected ? '待导入' : '未选',
      tone: selected ? LexiBadgeTone.success : LexiBadgeTone.neutral,
    );
  }
}

class _CardList extends ConsumerWidget {
  const new({required this.title, required this.candidates});

  final String title;
  final List<ArticleCandidate> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (candidates.isEmpty) return const SizedBox.shrink();
    final state = ref.watch(articleWizardProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: articleCardGap),
        Text(
          title,
          style: LexiType.footnote.copyWith(
            color: context.lexiColors.secondaryLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: articleTightGap),
        for (final candidate in candidates)
          _CandidateCard(
            candidate: candidate,
            selected: state.selection.selected.contains(
              articleSelectionKey(candidate).toLowerCase(),
            ),
          ),
      ],
    );
  }
}

class _CandidateCard extends ConsumerWidget {
  const new({required this.candidate, required this.selected});

  final ArticleCandidate candidate;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    final notifier = ref.read(articleWizardProvider.notifier);
    final key = articleSelectionKey(candidate).toLowerCase();
    final card = candidate.aiCard;
    return Container(
      margin: const EdgeInsets.only(bottom: articleTightGap),
      padding: const EdgeInsets.all(LexiSpace.s10),
      decoration: BoxDecoration(
        color: selected
            ? colors.accent.withValues(alpha: LexiTint.subtle)
            : colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(
          color: selected
              ? colors.accent.withValues(alpha: LexiTint.border)
              : colors.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Checkbox(
            key: Key('articleCandidate$key'),
            value: !candidate.isKnown && selected,
            onChanged: candidate.isKnown
                ? null
                : (_) => notifier.toggleKey(key),
          ),
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
                      candidate.term,
                      style: LexiType.body.copyWith(
                        color: colors.label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ArticleBadge(
                      label: articleEntryTypeLabel(candidate.entryType),
                      tone: candidate.entryType == LexicalContentType.sentence
                          ? LexiBadgeTone.purple
                          : LexiBadgeTone.accent,
                    ),
                    _StateBadge(candidate: candidate, selected: selected),
                  ],
                ),
                if (candidate.aiReason != null)
                  Text(
                    candidate.aiReason!,
                    style: LexiType.caption.copyWith(
                      color: colors.secondaryLabel,
                    ),
                  ),
                if (card != null)
                  DisclosureSection(
                    key: ValueKey<String>(key),
                    title: '查看解析 · ${candidate.term}',
                    child: _AiCardBody(card: card),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCardBody extends StatelessWidget {
  const new({required this.card});

  final ArticleAiCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final grammar = <String>[
      if (card.grammarPattern != null) card.grammarPattern!,
      ...card.grammarNotes,
    ].join('；');
    return Container(
      margin: const EdgeInsets.only(top: articleTightGap),
      padding: const EdgeInsets.all(LexiSpace.s8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: LexiTint.half),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _LabeledText(label: '直译：', text: card.literalTranslation),
          _LabeledText(label: '意译：', text: card.freeTranslation),
          if (card.keyVocab.isNotEmpty)
            _LabeledText(
              label: '重点词汇：',
              text: card.keyVocab.map(_keyVocabLine).join('； '),
            ),
          if (grammar.isNotEmpty) _LabeledText(label: '语法：', text: grammar),
          if (card.nuance != null)
            _LabeledText(label: '辨析：', text: card.nuance!),
        ],
      ),
    );
  }
}

/// 一条重点词汇的展示文本：`term pos. meaning`。
String _keyVocabLine(ArticleAiKeyVocab item) {
  final pos = item.pos == null ? '' : ' ${item.pos}.';
  return '${item.term}$pos ${item.meaning}';
}

class _LabeledText extends StatelessWidget {
  const new({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s2),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: label,
              style: LexiType.caption.copyWith(
                color: colors.accentText,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: text,
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「AI 理由 / 状态」列宽——固定宽度让每行的说明文字左端对齐。
