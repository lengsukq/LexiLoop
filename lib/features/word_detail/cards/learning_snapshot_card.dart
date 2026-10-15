/// 学习情况卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';

/// 学习情况卡片：熟练度、FSRS 卡片状态与累计正确率。
///
/// 自己 `watch` 数据提供者，页面只需给出 `wordId`——异步卡片把加载与失败
/// 状态收在卡片内部，页面不必为每张卡各写一遍 `when`。
class LearningSnapshotCard extends ConsumerWidget {
  /// 以词条 ID 构造。
  const new({required this.wordId, super.key});

  /// 词条 ID。
  final int wordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(wordLearningSnapshotProvider(wordId));
    return snapshot.when(
      loading: () => const DetailLoadingCard(title: '学习情况'),
      error: (error, _) => DetailErrorCard(
        title: '学习情况',
        message: '学习情况加载失败：$error',
        onRetry: () => ref.invalidate(wordLearningSnapshotProvider(wordId)),
      ),
      data: (value) => DetailSectionCard(
        title: '学习情况',
        icon: Icons.insights_rounded,
        child: _SnapshotBody(snapshot: value),
      ),
    );
  }
}

class _SnapshotBody extends StatelessWidget {
  const new({required this.snapshot});

  final WordLearningSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final accuracy = formatAccuracy(
      snapshot.accuracy,
      correct: snapshot.correctReviews,
      total: snapshot.totalReviews,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MasteryBadge(
          level: snapshot.masteryLevel,
          score: snapshot.masteryScore,
        ),
        const SizedBox(height: 10),
        if (snapshot.hasCard) ...<Widget>[
          DetailField(
            label: 'FSRS 阶段',
            value: fsrsStateLabel(snapshot.fsrsState),
          ),
          DetailField(label: '下次到期', value: formatTimestamp(snapshot.dueAt!)),
          DetailField(label: '间隔', value: formatDays(snapshot.scheduledDays)),
          DetailField(label: '稳定性', value: formatStability(snapshot.stability)),
          DetailField(
            label: '难度',
            value: formatDifficulty(snapshot.difficulty),
          ),
          DetailField(label: '复习次数', value: '${snapshot.reps ?? 0}'),
          DetailField(label: '遗忘次数', value: '${snapshot.lapses ?? 0}'),
        ] else
          const DetailEmptyHint(text: '还没有复习记录，学一次之后这里会显示 FSRS 卡片状态。'),
        DetailField(label: '累计正确率', value: accuracy ?? '暂无作答记录'),
      ],
    );
  }
}
