/// 页首「掌握概览」进度带。
///
/// 对应旧版 `words/learning-overview.tsx`：一句话回答「这个词库我学得
/// 怎么样、还剩多少」，并把想去细看的人送去统计页。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 掌握概览进度带。
class MasteryOverviewStrip extends ConsumerWidget {
  /// 创建掌握概览进度带。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(masteryOverviewProvider);
    // 一个词条都没有时不显示：此时进度条只能是 0%，占了位置却不传递信息，
    // 而空状态已经把「先去导入」说得更清楚。
    return overview.maybeWhen(
      data: (data) => data.total == 0
          ? const SizedBox.shrink()
          : _OverviewBody(overview: data),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// 进度带本体。
class _OverviewBody extends StatelessWidget {
  const new({required this.overview});

  final MasteryOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s20,
        0,
        LexiSpace.s20,
        LexiSpace.s8,
      ),
      child: Surface(
        borderRadius: BorderRadius.circular(LexiRadius.lg),
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s16,
          vertical: LexiSpace.s14,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: LexiTint.tint),
                borderRadius: BorderRadius.circular(LexiRadius.md),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                size: 20,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: LexiSpace.s14),
            Expanded(child: _OverviewText(overview: overview)),
            TextButton(
              onPressed: () => context.go(statisticsPath),
              child: const Text('详细统计'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标题、计数与进度条。
class _OverviewText extends StatelessWidget {
  const new({required this.overview});

  final MasteryOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final percent = overview.percent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '当前词条掌握程度',
                style: LexiType.callout.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: LexiType.title2.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: LexiSpace.s4),
        Text(
          '已掌握 ${overview.mastered} / ${overview.total} 个词条 · '
          '还有 ${overview.remaining} 个待继续学习',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: LexiSpace.s8),
        ClipRRect(
          borderRadius: BorderRadius.circular(LexiRadius.sm),
          child: LinearProgressIndicator(
            value: percent / percentScale,
            minHeight: 6,
            backgroundColor: colors.fill,
            color: colors.accent,
          ),
        ),
      ],
    );
  }
}
