/// 最近作答的迷你趋势条。
///
/// 用一排小方块而不是折线：单次作答只有「对/错」两个状态，
/// 折线会暗示不存在的中间值。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/stat_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 最近作答正误条。
class RecentResultsCard extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(recentResultsProvider);
    return StatCard(
      title: '最近作答',
      child: results.when(
        data: (data) => _Strip(results: data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          '加载失败：$error',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.lexiColors.danger),
        ),
      ),
    );
  }
}

/// 一排方块，从左到右由旧到新。
class _Strip extends StatelessWidget {
  const new({required this.results});

  /// 由新到旧的作答正误（数据源是倒序的，这里翻过来显示）。
  final List<bool> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const EmptyHint(message: '还没有作答记录');
    final colors = context.lexiColors;
    final ordered = results.reversed.toList(growable: false);
    return Wrap(
      spacing: cellGap,
      runSpacing: cellGap,
      children: <Widget>[
        for (final correct in ordered)
          Container(
            width: cellSize,
            height: cellSize,
            decoration: BoxDecoration(
              color: correct ? colors.success : colors.danger,
              borderRadius: BorderRadius.circular(cellRadius),
            ),
          ),
      ],
    );
  }
}

/// 方块边长。
const double cellSize = 12;

/// 方块间距。
const double cellGap = 4;

/// 方块圆角。
const double cellRadius = LexiRadius.xxs;
