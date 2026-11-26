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
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/lexi_progress_bar.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: Surface(
        borderRadius: BorderRadius.circular(LexiRadius.lg),
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s16,
          vertical: LexiSpace.s8,
        ),
        // 窄屏收紧纵向高度：把「详细统计」并入标题行右侧，为下方词表留出更多首屏空间。
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= LexiLayout.compactStripWidth;
            return Row(
              children: <Widget>[
                if (wide) _IconPlate(colors: colors),
                if (wide) const SizedBox(width: LexiSpace.s14),
                Expanded(
                  child: _OverviewText(
                    overview: overview,
                    showInlineStatsLink: !wide,
                  ),
                ),
                if (wide) _StatsLink(colors: colors),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 左侧的图标块。
class _IconPlate extends StatelessWidget {
  const new({required this.colors});

  final LexiColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: LexiTint.tint),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Icon(LucideIcons.bookOpen, size: 20, color: colors.accent),
    );
  }
}

/// 「详细统计」入口。
class _StatsLink extends StatelessWidget {
  const new({required this.colors, this.compact = false});

  final LexiColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) => TextButton(
    style: compact
        ? TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s6,
              vertical: LexiSpace.s2,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          )
        : null,
    onPressed: () => context.go(statisticsPath),
    child: Text(
      '详细统计',
      style: compact
          ? LexiType.footnote.copyWith(
              color: colors.accentText,
              fontWeight: FontWeight.w600,
            )
          : null,
    ),
  );
}

/// 标题、计数与进度条。
class _OverviewText extends StatelessWidget {
  const new({required this.overview, this.showInlineStatsLink = false});

  final MasteryOverview overview;
  final bool showInlineStatsLink;

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
                '掌握概览',
                style: LexiType.callout.copyWith(
                  color: colors.label,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: LexiType.callout.copyWith(
                color: colors.accentText,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showInlineStatsLink) ...<Widget>[
              const SizedBox(width: LexiSpace.s6),
              _StatsLink(colors: colors, compact: true),
            ],
          ],
        ),
        const SizedBox(height: LexiSpace.s4),
        Text(
          '已掌握 ${overview.mastered} · 待学习 ${overview.remaining}',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: LexiSpace.s6),
        LexiProgressBar(value: percent / percentScale),
      ],
    );
  }
}
