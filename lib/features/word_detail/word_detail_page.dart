/// 词条详情页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/adaptive_columns.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lexiloop/ui/widgets/page_states.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

    return PageShell(
      child: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // **失败态必须能走出去**：本页是 `/words` 分支的子路由，
        // 但它是从列表 `context.go` 进来的，返回栈里未必有上一页。
        error: (error, _) => PageErrorState(
          message: '词条加载失败：$error',
          onRetry: () => ref.invalidate(wordDetailProvider(wordId)),
          secondaryLabel: '返回单词本',
          onSecondary: () => leaveWordDetail(context),
        ),
        data: (word) => word == null
            ? _MissingView(onBack: () => leaveWordDetail(context))
            : _WordDetailBody(detail: word),
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
      padding: const EdgeInsets.only(top: LexiSpace.s16, bottom: LexiSpace.s32),
      children: <Widget>[
        WordDetailHeaderCard(detail: detail),
        const SizedBox(height: LexiSpace.s24),
        AdaptiveColumns(
          breakpoint: 920,
          primary: Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _spaced(_contentSections()),
            ),
          ),
          secondary: _personalRecords(),
        ),
      ],
    );
  }

  Widget _personalRecords() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: _spaced(<Widget>[
      const _ZoneLabel(label: '我的记录'),
      NoteCard(wordId: detail.id, initialNote: detail.userNote),
      LearningSnapshotCard(wordId: detail.id),
      DisclosureSection(
        title: '复习记录',
        child: ReviewHistoryCard(wordId: detail.id),
      ),
      InitializationQualityCard(wordId: detail.id),
    ]),
  );

  /// 内容类分区；对应数据为空的分区整块不出现，而不是留一张空卡片。
  List<Widget> _contentSections() => <Widget>[
    if (detail.definitions.isNotEmpty)
      DefinitionsCard(wordId: detail.id, definitions: detail.definitions),
    if (detail.examples.isNotEmpty)
      ExamplesCard(wordId: detail.id, examples: detail.examples),
    if (!detail.summary.isEmpty || detail.tags.isNotEmpty)
      SummaryCard(summary: detail.summary, tags: detail.tags),
    DisclosureSection(
      title: '扩展知识与助记',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _spaced(_extendedSections()),
      ),
    ),
    if (detail.hasNoContent) const _NoContentCard(),
  ];

  List<Widget> _extendedSections() => <Widget>[
    if (detail.phrases.isNotEmpty) PhrasesCard(phrases: detail.phrases),
    if (detail.forms.isNotEmpty) FormsCard(forms: detail.forms),
    // 四类关联词合成一张卡：一次只展开一类，其余以计数留在切换条上。
    // 此前它们是四张独立的卡片，词条关联多时这一块就占掉整屏。
    if (_relatedGroups(detail).isNotEmpty)
      RelatedWordsGroup(wordId: detail.id, groups: _relatedGroups(detail)),
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
  ];

  /// 四类关联词按关系分组；空的分组不参与渲染。
  Map<RelationType, List<RelatedWordView>> _relatedGroups(WordDetail detail) =>
      <RelationType, List<RelatedWordView>>{
        RelationType.synonym: detail.synonyms,
        RelationType.antonym: detail.antonyms,
        RelationType.wordFamily: detail.wordFamily,
        RelationType.confusedWith: detail.confusedWords,
      };

  /// 在分区之间插入固定间距。
  List<Widget> _spaced(List<Widget> sections) {
    final result = <Widget>[];
    for (final section in sections) {
      if (result.isNotEmpty) result.add(const SizedBox(height: LexiSpace.s10));
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
      icon: LucideIcons.hourglass,
      child: DetailEmptyHint(text: '该词条还没有内容。它可能正在等待补全，或数据源没有返回结果。'),
    );
  }
}

/// 词条不存在（或已被删除）时的空态。
class _MissingView extends StatelessWidget {
  const new({required this.onBack});

  /// 离开本页；由页面提供，保证「能出栈就出栈、否则回单词本」。
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => PageEmptyState(
    icon: LucideIcons.searchX,
    title: '词条不存在或已被删除',
    message: '它可能刚被删除，或来自一个尚未导入的 ID。',
    primaryLabel: '返回单词本',
    onPrimary: onBack,
  );
}

/// 离开词条详情：能出栈就出栈，否则回单词本。
///
/// `Navigator.maybePop()` 在这里不可靠——本页常常是用 `context.go` 直接
/// 进入的，栈里没有上一页，那个调用会静默地什么都不做，于是「返回」按钮
/// 变成一个按了没反应的装饰。
void leaveWordDetail(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(wordsPath);
  }
}

/// 分区标签：把「内容」与「我的记录」在视觉上分开。
class _ZoneLabel extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LexiSpace.s20),
    child: Text(
      label,
      style: LexiType.footnote.copyWith(
        color: context.lexiColors.tertiaryLabel,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    ),
  );
}
