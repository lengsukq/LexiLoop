/// 复习历史卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 复习历史卡片：最近 `reviewHistoryLimit` 条作答记录。
class ReviewHistoryCard extends ConsumerWidget {
  /// 以词条 ID 构造。
  const new({required this.wordId, super.key});

  /// 词条 ID。
  final int wordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(recentReviewLogsProvider(wordId));
    return logs.when(
      loading: () => const DetailLoadingCard(title: '复习历史'),
      error: (error, _) => DetailErrorCard(
        title: '复习历史',
        message: '复习历史加载失败：$error',
        onRetry: () => ref.invalidate(recentReviewLogsProvider(wordId)),
      ),
      data: (entries) => DetailSectionCard(
        title: '复习历史',
        icon: Icons.history_rounded,
        child: entries.isEmpty
            ? const DetailEmptyHint(text: '还没有复习记录。')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final entry in entries) _LogRow(entry: entry),
                ],
              ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const new({required this.entry});

  final ReviewLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 118,
            child: Text(
              formatTimestamp(entry.reviewedAt),
              style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
            ),
          ),
          DetailChip(
            text: ratingLabel(entry.rating),
            color: entry.isCorrect ? colors.success : colors.danger,
          ),
          const SizedBox(width: 6),
          Icon(
            entry.isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 14,
            color: entry.isCorrect ? colors.success : colors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              questionTypeLabel(entry.questionType),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.label, fontSize: 12.5),
            ),
          ),
          Text(
            formatDuration(entry.durationMs),
            style: TextStyle(color: colors.tertiaryLabel, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
