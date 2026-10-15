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
import 'package:lexiloop/ui/widgets/error_retry_view.dart';

/// 单词本页面。
class WordsPage extends ConsumerWidget {
  /// 创建单词本页面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordListProvider);
    final total = ref.watch(wordCountProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            WordsHeader(total: total.value),
            const MasteryOverviewStrip(),
            const WordFilterBar(),
            Expanded(
              child: _WordResults(
                words: words,
                onRetry: () => ref.invalidate(wordListProvider),
              ),
            ),
            const WordPaginator(),
          ],
        ),
      ),
    );
  }
}

/// 结果区：加载中 / 出错 / 空 / 列表。
class _WordResults extends ConsumerWidget {
  const new({required this.words, required this.onRetry});

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
      data: (entries) =>
          entries.isEmpty ? _empty(context, ref) : _WordList(entries: entries),
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
  const new({required this.entries});

  final List<WordListEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return WordCard(
          entry: entry,
          onTap: () => context.go('$wordDetailPathPrefix${entry.id}'),
        );
      },
    );
  }
}
