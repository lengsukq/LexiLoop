/// 单词本页面。
///
/// 采用移动端优先（Mobile-First）的**触底无限加载 + 下拉刷新**交互，
/// 彻底取代桌面端「上一页 / 下一页」按钮式分页器。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/features/words/widgets/mastery_overview_strip.dart';
import 'package:lexiloop/features/words/widgets/word_bulk_bar.dart';
import 'package:lexiloop/features/words/widgets/word_card.dart';
import 'package:lexiloop/features/words/widgets/word_empty_view.dart';
import 'package:lexiloop/features/words/widgets/word_filter_bar.dart';
import 'package:lexiloop/features/words/widgets/word_source_scope_bar.dart';
import 'package:lexiloop/features/words/widgets/words_header.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/error_retry_view.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 触底自动加载更多的剩余滚动阈值（逻辑像素）。
const double _loadMoreScrollThreshold = 160;

/// 单词本页面。
class WordsPage extends ConsumerWidget {
  /// 创建单词本页面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordListProvider);
    final total = ref.watch(wordCountProvider);
    final selecting = ref.watch(wordSelectionProvider.select((s) => s.enabled));
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 20;

    return PageShell(
      header: WordsHeader(total: total.value),
      scrollable: largeText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if ((total.value ?? 0) > 0) const MasteryOverviewStrip(),
          const _QueueProgressStrip(),
          if (selecting)
            WordBulkBar(visibleEntries: words.value ?? const <WordListEntry>[]),
          const WordSourceScopeBar(),
          const WordFilterBar(),
          if (largeText)
            _WordResults(
              words: words,
              totalCount: total.value ?? 0,
              shrinkWrap: true,
              onRetry: () => ref.invalidate(wordListProvider),
            )
          else
            Expanded(
              child: _WordResults(
                words: words,
                totalCount: total.value ?? 0,
                onRetry: () => ref.invalidate(wordListProvider),
              ),
            ),
        ],
      ),
    );
  }
}

/// 结果区：加载中 / 出错 / 空 / 无限滚动列表。
class _WordResults extends ConsumerWidget {
  const new({
    required this.words,
    required this.totalCount,
    required this.onRetry,
    this.shrinkWrap = false,
  });

  final bool shrinkWrap;
  final AsyncValue<List<WordListEntry>> words;
  final int totalCount;
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
          : _WordList(
              entries: entries,
              totalCount: totalCount,
              shrinkWrap: shrinkWrap,
            ),
    );
  }

  Widget _empty(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wordQueryProvider);
    return WordEmptyView(
      filtered: query.search.isNotEmpty || query.activeFilterCount > 0,
    );
  }
}

/// 词条无限滚动列表 + 下拉刷新。
class _WordList extends ConsumerWidget {
  const new({
    required this.entries,
    required this.totalCount,
    this.shrinkWrap = false,
  });

  final bool shrinkWrap;
  final List<WordListEntry> entries;
  final int totalCount;

  bool get _hasMore => entries.length < totalCount;

  bool _onScroll(ScrollNotification notification, WidgetRef ref) {
    if (!_hasMore) return false;
    if (notification is ScrollEndNotification &&
        notification.metrics.extentAfter < _loadMoreScrollThreshold) {
      ref.read(wordQueryProvider.notifier).loadMore();
    }
    return false;
  }

  Future<void> _onRefresh(WidgetRef ref) async {
    LexiHaptics.light();
    ref
      ..invalidate(wordListProvider)
      ..invalidate(wordCountProvider)
      ..invalidate(masterySummaryProvider);
    await ref.read(wordListProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(wordSelectionProvider);
    final list = ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: LexiSpace.s4, bottom: LexiSpace.s8),
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          const Divider(indent: LexiSpace.s16, endIndent: LexiSpace.s16),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return WordCard(
          entry: entry,
          selectable: selection.enabled,
          selected: selection.selectedIds.contains(entry.id),
          onTap: selection.enabled
              ? () => ref.read(wordSelectionProvider.notifier).toggle(entry.id)
              : () => context.go('$wordDetailPathPrefix${entry.id}'),
        );
      },
    );

    final scrollableList = NotificationListener<ScrollNotification>(
      onNotification: (notification) => _onScroll(notification, ref),
      child: shrinkWrap
          ? list
          : RefreshIndicator(onRefresh: () => _onRefresh(ref), child: list),
    );

    return Surface(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      child: Column(
        mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        children: <Widget>[
          if (shrinkWrap) scrollableList else Expanded(child: scrollableList),
          _LoadMoreFooter(
            loadedCount: entries.length,
            totalCount: totalCount,
            onLoadMore: () => ref.read(wordQueryProvider.notifier).loadMore(),
          ),
        ],
      ),
    );
  }
}

/// 列表底部加载状态与加载更多提示条。
class _LoadMoreFooter extends StatelessWidget {
  const new({
    required this.loadedCount,
    required this.totalCount,
    required this.onLoadMore,
  });

  final int loadedCount;
  final int totalCount;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final hasMore = loadedCount < totalCount;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s16,
        vertical: LexiSpace.s6,
      ),
      child: Center(
        child: hasMore
            ? TextButton(
                key: const Key('wordsLoadMore'),
                onPressed: onLoadMore,
                child: Text(
                  '已显示 $loadedCount / $totalCount 个词条 · 加载更多',
                  style: LexiType.footnote.copyWith(
                    color: colors.accentText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : Text(
                '已加载全部 $totalCount 个词条',
                style: LexiType.caption.copyWith(color: colors.tertiaryLabel),
              ),
      ),
    );
  }
}

/// 词库页顶部的后台有道查词补全进度条（仅当队列有待处理或进行中任务时出现）。
class _QueueProgressStrip extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_QueueProgressStrip> createState() =>
      _QueueProgressStripState();
}

class _QueueProgressStripState extends ConsumerState<_QueueProgressStrip> {
  bool _pumping = false;

  Future<void> _pumpNow() async {
    if (_pumping) return;
    setState(() => _pumping = true);
    try {
      await ref.read(queueActionsProvider).processNow();
      ref
        ..invalidate(wordListProvider)
        ..invalidate(wordCountProvider);
    } finally {
      if (mounted) setState(() => _pumping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(queueProgressProvider).value;
    if (progress == null) return const SizedBox.shrink();
    final queued = progress.countOf(InitializationStatus.queued);
    final running = progress.countOf(InitializationStatus.running);
    if (queued + running == 0) return const SizedBox.shrink();
    final colors = context.lexiColors;
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 20;
    final label =
        '有道查词补全中：队列中 $queued'
        '${running > 0 ? ' · 进行中 $running' : ''}';
    final actions = _queueActions(colors);
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: Surface(
        key: const Key('wordsQueueProgressBanner'),
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s12,
          vertical: LexiSpace.s8,
        ),
        borderRadius: BorderRadius.circular(LexiRadius.lg),
        child: largeText
            ? Wrap(
                spacing: LexiSpace.s8,
                runSpacing: LexiSpace.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Icon(
                    LucideIcons.sparkles,
                    size: 15,
                    color: colors.accentText,
                  ),
                  Text(
                    label,
                    style: LexiType.footnote.copyWith(color: colors.label),
                  ),
                  ...actions,
                ],
              )
            : Row(
                children: <Widget>[
                  Icon(
                    LucideIcons.sparkles,
                    size: 15,
                    color: colors.accentText,
                  ),
                  const SizedBox(width: LexiSpace.s8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LexiType.footnote.copyWith(color: colors.label),
                    ),
                  ),
                  const SizedBox(width: LexiSpace.s4),
                  ...actions,
                ],
              ),
      ),
    );
  }

  List<Widget> _queueActions(LexiColors colors) {
    final compactStyle = TextButton.styleFrom(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s6,
        vertical: LexiSpace.s4,
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    return <Widget>[
      TextButton(
        key: const Key('wordsQueuePumpNow'),
        style: compactStyle,
        onPressed: _pumping ? null : () => unawaited(_pumpNow()),
        child: Text(
          _pumping ? '处理中' : '拉取',
          style: LexiType.footnote.copyWith(
            color: colors.accentText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      TextButton(
        key: const Key('wordsQueueOpen'),
        style: compactStyle,
        onPressed: () => context.go(initializePath),
        child: Text(
          '队列',
          style: LexiType.footnote.copyWith(
            color: colors.secondaryLabel,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ];
  }
}
