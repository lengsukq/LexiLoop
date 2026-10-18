/// 首页「练习」入口卡片。
///
/// 对应旧版 `app/(main)/page.tsx` 的「趣味训练」区块。
///
/// **为什么这些入口在首页而不是导航栏**：小游戏与音标训练是「独立模式，
/// 不占用今日复习队列」（旧版原文），放进主导航会让人误以为它们是日常
/// 必做项。放在首页作为可选项，语义更准确。
///
/// **为什么收成一张卡片**：此前练习区是一段没有容器的标题 + 瓷砖，后面再
/// 挂「专项练习」与「更多趣味训练」两条折叠行；它们既不在同一张卡片里，
/// 也读不出分组关系，像两行没收尾的列表项。现在首屏只留 4 个精选入口，
/// 其余入口统一进「全部练习」弹层，分组由 `practice_catalog.dart` 提供。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/dashboard/practice_catalog.dart';
import 'package:lexiloop/features/dashboard/widgets/practice_sheet.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 「查看全部」入口的 Key，供测试与截图定位。
const Key practiceAllButtonKey = Key('practice-all');

/// 宽屏下练习瓷砖的列数切换点。
const double _fourColumnBreakpoint = 880;

/// 首页练习卡。
class PracticeCard extends StatelessWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context) => const SectionCard(
    title: '练习',
    icon: LucideIcons.gamepad2,
    tone: LexiTone.lavender,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PracticeGrid(),
        SizedBox(height: LexiSpace.s8),
        _AllPracticeButton(),
      ],
    ),
  );
}

/// 精选入口的响应式网格。
class _PracticeGrid extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) >= 24;
        final columns = largeText
            ? 1
            : constraints.maxWidth >= _fourColumnBreakpoint
            ? 4
            : 2;
        final width =
            (constraints.maxWidth - (columns - 1) * LexiSpace.s8) / columns;
        return Wrap(
          spacing: LexiSpace.s8,
          runSpacing: LexiSpace.s8,
          children: <Widget>[
            for (final entry in featuredPracticeEntries)
              SizedBox(
                width: width,
                child: _PracticeTile(entry: entry),
              ),
          ],
        );
      },
    );
  }
}

/// 一个紧凑的练习入口。
class _PracticeTile extends StatelessWidget {
  const new({required this.entry});

  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final tone = context.lexiTones.styleOf(LexiTone.lavender);
    final radius = BorderRadius.circular(LexiRadius.md);
    return Surface(
      variant: SurfaceVariant.inset,
      padding: EdgeInsets.zero,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.go(entry.location),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s8,
            vertical: LexiSpace.s10,
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(LexiSpace.s6),
                decoration: BoxDecoration(
                  color: tone.background,
                  borderRadius: BorderRadius.circular(LexiRadius.sm),
                ),
                child: Icon(entry.icon, size: 16, color: tone.foreground),
              ),
              const SizedBox(width: LexiSpace.s6),
              Expanded(child: _PracticeTileText(entry: entry)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 瓷砖里的标题与一句话说明。
class _PracticeTileText extends StatelessWidget {
  const new({required this.entry});

  final PracticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          entry.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LexiType.callout.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LexiSpace.s2),
        Text(
          entry.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: LexiType.caption.copyWith(color: colors.secondaryLabel),
        ),
      ],
    );
  }
}

/// 卡片底部的「查看全部」入口。
class _AllPracticeButton extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final radius = BorderRadius.circular(LexiRadius.md);
    return Surface(
      variant: SurfaceVariant.inset,
      padding: EdgeInsets.zero,
      borderRadius: radius,
      child: InkWell(
        key: practiceAllButtonKey,
        borderRadius: radius,
        onTap: () => showPracticeSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s12,
            vertical: LexiSpace.s10,
          ),
          child: Row(
            children: <Widget>[
              Icon(LucideIcons.layoutGrid, size: 16, color: colors.accentText),
              const SizedBox(width: LexiSpace.s8),
              Expanded(
                child: Text(
                  '查看全部 ${practiceEntries.length} 项练习',
                  style: LexiType.callout.copyWith(
                    color: colors.accentText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: colors.accentText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
