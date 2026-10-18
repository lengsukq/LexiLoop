/// 单词本页面。
///
/// 页面本身只做编排：头部、掌握概览、筛选区、结果区与分页条各自成控件。
/// 这一页的筛选与卡片字段曾经全部堆在一个 `build()` 里，
/// 守卫的 80 行上限正是为此而设。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/features/words/widgets/mastery_overview_strip.dart';
import 'package:lexiloop/features/words/widgets/word_card.dart';
import 'package:lexiloop/features/words/widgets/word_empty_view.dart';
import 'package:lexiloop/features/words/widgets/word_filter_bar.dart';
import 'package:lexiloop/features/words/widgets/word_paginator.dart';
import 'package:lexiloop/features/words/widgets/words_header.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/error_retry_view.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 单词本页面。
class WordsPage extends ConsumerWidget {
  /// 创建单词本页面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordListProvider);
    final total = ref.watch(wordCountProvider);
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 20;

    // `scrollable: false`：这一页是「固定筛选栏 + 只滚列表」，
    // 滚动必须由列表自己掌管，外壳只负责版心与页头。
    return PageShell(
      header: WordsHeader(total: total.value),
      scrollable: largeText,
      child: Column(
        children: <Widget>[
          if ((total.value ?? 0) > 0) const MasteryOverviewStrip(),
          const WordFilterBar(),
          if (largeText)
            _WordResults(
              words: words,
              shrinkWrap: true,
              onRetry: () => ref.invalidate(wordListProvider),
            )
          else
            Expanded(
              child: _WordResults(
                words: words,
                onRetry: () => ref.invalidate(wordListProvider),
              ),
            ),
          const WordPaginator(),
        ],
      ),
    );
  }
}

/// 结果区：加载中 / 出错 / 空 / 列表。
class _WordResults extends ConsumerWidget {
  const new({
    required this.words,
    required this.onRetry,
    this.shrinkWrap = false,
  });

  final bool shrinkWrap;

  final AsyncValue<List<WordListEntry>> words;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return words.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetryView(
        message: error is AppError ? error.message : '加载词条失败：$error',
        onRetry: onRetry,
      ),
      data: (entries) => entries.isEmpty
          ? _empty(context, ref)
          : _WordList(entries: entries, shrinkWrap: shrinkWrap),
    );
  }

  /// 空状态要区分「库是空的」与「被筛空了」。
  Widget _empty(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wordQueryProvider);
    return WordEmptyView(
      filtered: query.search.isNotEmpty || query.activeFilterCount > 0,
    );
  }
}

/// 当前页的词条卡片列表。
class _WordList extends StatelessWidget {
  const new({required this.entries, this.shrinkWrap = false});

  final bool shrinkWrap;

  final List<WordListEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Surface(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      child: ListView.separated(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.only(
          top: LexiSpace.s4,
          bottom: LexiSpace.s16,
        ),
        itemCount: entries.length,
        separatorBuilder: (_, _) =>
            const Divider(indent: LexiSpace.s16, endIndent: LexiSpace.s16),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return WordCard(
            entry: entry,
            onTap: () => context.go('$wordDetailPathPrefix${entry.id}'),
          );
        },
      ),
    );
  }
}
