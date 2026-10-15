/// 复习历史卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

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
      data: (entries) => SectionCard(
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
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _timestampColumnWidth,
            child: Text(
              formatTimestamp(entry.reviewedAt),
              style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
            ),
          ),
          DetailChip(
            text: ratingLabel(entry.rating),
            color: entry.isCorrect ? colors.success : colors.danger,
          ),
          const SizedBox(width: LexiSpace.s6),
          Icon(
            entry.isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 14,
            color: entry.isCorrect ? colors.success : colors.danger,
          ),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Text(
              questionTypeLabel(entry.questionType),
              overflow: TextOverflow.ellipsis,
              style: LexiType.footnote.copyWith(color: colors.label),
            ),
          ),
          Text(
            formatDuration(entry.durationMs),
            style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}

/// 复习时间列宽——时间戳等宽，固定宽度让右侧内容左端对齐。
const double _timestampColumnWidth = 118;
