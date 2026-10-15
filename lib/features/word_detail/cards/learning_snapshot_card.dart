/// 学习情况卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/word_detail/word_detail_format.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_widgets.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
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
      data: (value) => SectionCard(
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
        const SizedBox(height: LexiSpace.s10),
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
        const SizedBox(height: LexiSpace.s6),
        _WrongWordBlock(snapshot: snapshot),
      ],
    );
  }
}

/// 错词状态：错误次数、困难次数、连续答对。
///
/// `wrong_word_states` 之前完全没被详情页读过，于是「为什么这个词老记不住」
/// 在界面上没有任何答案——用户只能看到 63% 的正确率，不知道错在哪几次。
class _WrongWordBlock extends StatelessWidget {
  const new({required this.snapshot});

  final WordLearningSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isUntouched) {
      return const DetailEmptyHint(text: '没有错词记录，这个词一直答得不错。');
    }
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            DetailChip(
              text: snapshot.isWrongWord ? '活跃错词' : '错词已解除',
              color: snapshot.isWrongWord ? colors.danger : colors.success,
            ),
            DetailChip(text: '错误 ${snapshot.wrongCount} 次'),
            DetailChip(text: '困难 ${snapshot.hardCount} 次'),
            DetailChip(text: '连续答对 ${snapshot.consecutiveCorrect} 次'),
          ],
        ),
        const SizedBox(height: LexiSpace.s6),
        DetailField(
          label: '最近答错',
          value: formatOptionalTimestamp(snapshot.lastWrongAt),
        ),
        DetailField(
          label: '最近答对',
          value: formatOptionalTimestamp(snapshot.lastCorrectAt),
        ),
      ],
    );
  }
}
