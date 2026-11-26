/// 各题型正确率卡片。
///
/// **为什么值得单独一张卡**：题型正确率是唯一能指出「哪种练法没效果」的
/// 指标。例如「看汉选英」正确率远低于「看英选中」，说明识别能力够但产出
/// 能力弱，应当调高拼写类题型的权重。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/statistics_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/stat_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 题型正确率列表。
class QuestionTypeCard extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accuracy = ref.watch(questionTypeAccuracyProvider);
    return StatCard(
      title: '题型正确率',
      child: accuracy.when(
        data: _buildList,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          '加载失败：$error',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.lexiColors.dangerText),
        ),
      ),
    );
  }

  Widget _buildList(List<QuestionTypeAccuracy> items) {
    if (items.isEmpty) return const EmptyHint(message: '还没有作答记录');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final item in items.take(maxRows))
          Padding(
            padding: const EdgeInsets.only(bottom: rowGap),
            child: _Row(item: item),
          ),
      ],
    );
  }
}

/// 单行：题型名 + 正确率 + 占比条。
class _Row extends StatelessWidget {
  const new({required this.item});

  final QuestionTypeAccuracy item;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final ratio = item.accuracy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                questionTypeLabel(item.questionType),
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.secondaryLabel),
              ),
            ),
            Text(
              '${item.correct}/${item.attempts}',
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colors.tertiaryLabel),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: percentWidth,
              child: Text(
                '${formatPercent(ratio)}%',
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: accuracyColor(ratio, colors),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: labelGap),
        ProportionBar(ratio: ratio, color: accuracyColor(ratio, colors)),
      ],
    );
  }
}

/// 题型的中文名。
String questionTypeLabel(QuestionType type) => switch (type) {
  QuestionType.enToZh => '看英说义',
  QuestionType.enToZhChoice => '看英选义',
  QuestionType.zhToEnChoice => '看义选英',
  QuestionType.zhToEnSpelling => '看义拼写',
  QuestionType.listeningSpelling => '听音拼写',
  QuestionType.clozeSentence => '例句填空',
  QuestionType.listeningChoice => '听音选词',
  QuestionType.letterBank => '字母拼图',
};

/// 按正确率给颜色：低正确率标红以引起注意。
Color accuracyColor(double ratio, LexiColors colors) {
  if (ratio < lowAccuracy) return colors.danger;
  if (ratio < mediumAccuracy) return colors.warning;
  return colors.success;
}

/// 最多展示的题型行数。
const int maxRows = 8;

/// 行间距。
const double rowGap = 12;

/// 标签与条的间距。
const double labelGap = 5;

/// 计数与百分比之间的间距。
const double gap = 8;

/// 百分比文本区宽度。
const double percentWidth = 44;

/// 低正确率阈值。
const double lowAccuracy = 0.6;

/// 中等正确率阈值。
const double mediumAccuracy = 0.8;
