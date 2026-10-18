/// 卡片底板：内容层的一张分区卡片 + 标题行。
///
/// **为什么只有这一份**：收敛前「带标题的卡片」有五套实现——`SectionCard`
/// （内边距 18）、`SettingsSectionCard`（14）、`StatCard`（16）、
/// `ArticleSectionCard`（14）、`ConfiguratorCard`（14）。它们的标题样式
/// 完全一样（`LexiType.callout` + w600），差别只在内边距一两像素和
/// 「有没有副标题 / 右侧内容 / 图标」这些**开关**上。
///
/// 差一两像素单看每一处都「合理」，叠在一起就是「看起来不统一」：眼睛读不出
/// 18 与 16 的差别，只觉得哪里不对。所以这里把差异收成参数：
///
/// | 参数 | 用来表达 |
/// |---|---|
/// | `icon` | 标题前的语义图标（今日页的卡片） |
/// | `subtitle` | 标题下的一句「为什么」（设置页） |
/// | `trailing` | 标题右侧的附加内容（文章流程的计数） |
///
/// 内边距统一取 `LexiSpace.s16`、标题间距取 `LexiSpace.s12`——两者都在
/// 间距音阶上，不再是「刚好合适的 18」。
///
/// 卡片内的加载/失败/空态**没有**一并合并：它们在各页的文案与结构确实不同
/// （详情页按分区说「正在加载释义」，仪表盘按卡片说「正在加载」），
/// 强行统一会把差异塞进参数里，反而更难读。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 卡片内边距。
const double sectionCardPadding = LexiSpace.s16;

/// 标题与内容之间的间距。
const double sectionCardTitleGap = LexiSpace.s12;

/// 标题图标尺寸。
const double _sectionCardIconSize = 16;

/// 图标与标题之间的间距。
const double _sectionCardIconGap = LexiSpace.s8;

/// 标题与副标题之间的间距。
const double _sectionCardSubtitleGap = LexiSpace.s4;

/// 玻璃底板上的一张分区卡片。
class SectionCard extends StatelessWidget {
  /// 以标题与内容构造。
  const new({
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.trailing,
    this.tone,
    this.variant = SurfaceVariant.card,
    super.key,
  });

  /// 卡片标题。
  final String title;

  /// 标题左侧图标。
  final IconData? icon;

  /// 标题下的一句补充说明（「为什么」而不是复述标题）。
  final String? subtitle;

  /// 标题右侧的附加内容。
  final Widget? trailing;

  /// 卡片内容。
  final Widget child;

  /// 内容角色的柔和彩色分区。
  final LexiTone? tone;

  /// 按内容用途选择表面层级。
  final SurfaceVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      tone: tone,
      variant: variant,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(sectionCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _titleRow(context, colors),
          const SizedBox(height: sectionCardTitleGap),
          child,
        ],
      ),
    );
  }

  Widget _titleRow(BuildContext context, LexiColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      LayoutBuilder(
        builder: (context, constraints) {
          final heading = _heading(context, colors);
          final accessory = trailing;
          if (accessory == null) return heading;
          if (constraints.maxWidth < 480 ||
              MediaQuery.textScalerOf(context).scale(13) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                heading,
                const SizedBox(height: LexiSpace.s12),
                accessory,
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: heading),
              accessory,
            ],
          );
        },
      ),
      if (subtitle != null) ...<Widget>[
        const SizedBox(height: _sectionCardSubtitleGap),
        Text(
          subtitle!,
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
      ],
    ],
  );

  Widget _heading(BuildContext context, LexiColors colors) => Row(
    children: <Widget>[
      if (icon != null) ...<Widget>[
        Icon(
          icon,
          size: _sectionCardIconSize,
          color: tone == null
              ? colors.secondaryLabel
              : context.lexiTones.styleOf(tone!).foreground,
        ),
        const SizedBox(width: _sectionCardIconGap),
      ],
      Expanded(
        child: Text(
          title,
          style: LexiType.callout.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
