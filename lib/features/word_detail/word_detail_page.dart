/// 词条详情页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/features/word_detail/cards/definitions_card.dart';
import 'package:lexiloop/features/word_detail/cards/examples_card.dart';
import 'package:lexiloop/features/word_detail/cards/forms_card.dart';
import 'package:lexiloop/features/word_detail/cards/initialization_quality_card.dart';
import 'package:lexiloop/features/word_detail/cards/learning_snapshot_card.dart';
import 'package:lexiloop/features/word_detail/cards/mnemonic_card.dart';
import 'package:lexiloop/features/word_detail/cards/morphology_card.dart';
import 'package:lexiloop/features/word_detail/cards/note_card.dart';
import 'package:lexiloop/features/word_detail/cards/phrases_card.dart';
import 'package:lexiloop/features/word_detail/cards/related_words_card.dart';
import 'package:lexiloop/features/word_detail/cards/review_history_card.dart';
import 'package:lexiloop/features/word_detail/cards/summary_card.dart';
import 'package:lexiloop/features/word_detail/cards/word_detail_header_card.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/error_retry_view.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 词条详情页。
///
/// 只负责「取数 → 组装分区」：每个分区都是独立组件文件，
/// 组件只接收数据，写操作走 [wordDetailActionsProvider]。
class WordDetailPage extends ConsumerWidget {
  /// 以词条 ID 创建详情页。
  const new({required this.wordId, super.key});

  /// 词条 ID。
  final int wordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(wordDetailProvider(wordId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorRetryView(
            message: '词条加载失败：$error',
            onRetry: () => ref.invalidate(wordDetailProvider(wordId)),
          ),
          data: (word) => word == null
              ? const _MissingView()
              : _WordDetailBody(detail: word),
        ),
      ),
    );
  }
}

/// 详情页正文：按固定顺序堆叠各分区。
class _WordDetailBody extends StatelessWidget {
  const new({required this.detail});

  final WordDetail detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: _spaced(<Widget>[
        WordDetailHeaderCard(detail: detail),
        ..._contentSections(),
        ..._activitySections(),
      ]),
    );
  }

  /// 内容类分区；对应数据为空的分区整块不出现，而不是留一张空卡片。
  List<Widget> _contentSections() => <Widget>[
    if (!detail.summary.isEmpty || detail.tags.isNotEmpty)
      SummaryCard(summary: detail.summary, tags: detail.tags),
    if (detail.definitions.isNotEmpty)
      DefinitionsCard(wordId: detail.id, definitions: detail.definitions),
    if (detail.examples.isNotEmpty)
      ExamplesCard(wordId: detail.id, examples: detail.examples),
    if (detail.phrases.isNotEmpty) PhrasesCard(phrases: detail.phrases),
    if (detail.forms.isNotEmpty) FormsCard(forms: detail.forms),
    if (detail.synonyms.isNotEmpty)
      RelatedWordsCard(
        wordId: detail.id,
        relation: RelationType.synonym,
        items: detail.synonyms,
      ),
    if (detail.antonyms.isNotEmpty)
      RelatedWordsCard(
        wordId: detail.id,
        relation: RelationType.antonym,
        items: detail.antonyms,
      ),
    if (detail.wordFamily.isNotEmpty)
      RelatedWordsCard(
        wordId: detail.id,
        relation: RelationType.wordFamily,
        items: detail.wordFamily,
      ),
    if (detail.confusedWords.isNotEmpty)
      RelatedWordsCard(
        wordId: detail.id,
        relation: RelationType.confusedWith,
        items: detail.confusedWords,
      ),
    if (detail.roots.isNotEmpty || detail.affixes.isNotEmpty)
      MorphologyCard(roots: detail.roots, affixes: detail.affixes),
    // 助记卡**始终出现**：它同时是「生成助记」的入口，早期初始化完成的
    // 词条 `learning` 与 `sentenceAnalysis` 都是空的，卡片跟着消失的话，
    // 用户连去生成助记的地方都没有。
    MnemonicCard(
      wordId: detail.id,
      learning: detail.learning,
      analysis: detail.sentenceAnalysis,
    ),
    if (detail.hasNoContent) const _NoContentCard(),
  ];

  /// 学习情况类分区；它们自己处理空态，因此始终出现。
  List<Widget> _activitySections() => <Widget>[
    LearningSnapshotCard(wordId: detail.id),
    ReviewHistoryCard(wordId: detail.id),
    InitializationQualityCard(wordId: detail.id),
    NoteCard(wordId: detail.id, initialNote: detail.userNote),
  ];

  /// 在分区之间插入固定间距。
  List<Widget> _spaced(List<Widget> sections) {
    final result = <Widget>[];
    for (final section in sections) {
      if (result.isNotEmpty) result.add(const SizedBox(height: 10));
      result.add(section);
    }
    return result;
  }
}

/// 词条存在但没有任何内容的提示。
///
/// 没有这张卡时页面只剩头部，用户会以为加载失败。
class _NoContentCard extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      title: '内容',
      icon: Icons.hourglass_empty_rounded,
      child: DetailEmptyHint(text: '该词条还没有内容。它可能正在等待初始化，或数据源没有返回结果。'),
    );
  }
}

/// 词条不存在（或已被删除）时的空态。
class _MissingView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.search_off_rounded,
              size: 44,
              color: colors.tertiaryLabel,
            ),
            const SizedBox(height: 14),
            Text(
              '词条不存在或已被删除',
              style: LexiType.title.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '它可能刚被删除，或来自一个尚未导入的 ID。',
              textAlign: TextAlign.center,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
