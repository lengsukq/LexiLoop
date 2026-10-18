/// 配置器里的通用小控件。
///
/// 单列一个文件是因为它们要被四个分区共用：分段选择器与分区标题一旦
/// 各写一份，四个分区的圆角、内边距与字号就会慢慢长得不一样。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 一段式选择器的一个选项。
///
/// 只做「选中 / 未选中」两态：配置器里的范围与写入方式都是互斥的，
/// 用下拉或弹层只会多一次点击。
class ConfiguratorSegment extends StatelessWidget {
  /// 以文案、选中态与点击回调构造。
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// 选项文案。
  final String label;

  /// 是否选中。
  final bool selected;

  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Expanded(
      child: GestureDetector(
        // 整块可点：分段控件的命中区只有三十几像素高，
        // 只让文字响应点击会让用户反复瞄。
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: segmentPaddingH,
            vertical: segmentPaddingV,
          ),
          decoration: BoxDecoration(
            color: selected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(LexiRadius.sm),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? colors.label : colors.tertiaryLabel,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 分段选择器的外框。
class ConfiguratorSegmentBar extends StatelessWidget {
  /// 以子项构造。
  const new({required this.children, super.key});

  /// 互斥的选项（每项都必须是 [ConfiguratorSegment]）。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(segmentBarInset),
    decoration: BoxDecoration(
      color: context.lexiColors.fill,
      borderRadius: BorderRadius.circular(LexiRadius.md),
    ),
    child: Row(children: children),
  );
}

/// 一个分区的标题。
class ConfiguratorSectionHeader extends StatelessWidget {
  /// 以标题与右侧说明构造。
  const new({required this.title, this.trailing, super.key});

  /// 标题。
  final String title;

  /// 右侧的补充说明（通常是计数）。
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: context.lexiColors.label,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: context.lexiColors.tertiaryLabel),
        ),
    ],
  );
}

/// 一块玻璃卡片（配置器内所有分区的统一外壳）。
class ConfiguratorCard extends StatelessWidget {
  /// 以标题与内容构造。
  const new({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  /// 分区标题。
  final String title;

  /// 右侧补充说明。
  final String? trailing;

  /// 分区内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Surface(
      tone: LexiTone.lavender,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      padding: const EdgeInsets.all(cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ConfiguratorSectionHeader(title: title, trailing: trailing),
          const SizedBox(height: headerGap),
          child,
        ],
      ),
    );
  }
}

/// 分段选项的水平内边距。
const double segmentPaddingH = 12;

/// 分段选项的垂直内边距。
const double segmentPaddingV = 8;

/// 分段外框的内缩。
const double segmentBarInset = 3;

/// 分区卡片的内边距。
const double cardPadding = 14;

/// 标题与内容之间的间距。
const double headerGap = 10;

/// 分区之间的垂直间距。
const double sectionGap = 12;

/// 同层元素之间的水平间距。
const double inlineGap = 8;

/// 可折叠的细节区。
///
/// 配置器打开时有预设、作用范围、字段、数据源、预览、摘要六块，除预设外
/// 全部默认展开——一屏塞不下，用户的第一印象是「这个对话框好复杂」，
/// 而绝大多数情况下他只需要「选个方案 → 创建任务」。
///
/// 收起时保留一行**当前状态摘要**（例如「8 个字段 · 缺什么补什么」），
/// 折叠不等于隐藏：不展开也能确认自己选了什么。
class ConfiguratorDisclosure extends StatelessWidget {
  /// 以标题、摘要与内容构造。
  const new({
    required this.title,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.child,
    super.key,
  });

  /// 分区标题。
  final String title;

  /// 收起时显示的当前状态摘要。
  final String summary;

  /// 是否展开。
  final bool expanded;

  /// 切换展开状态。
  final VoidCallback onToggle;

  /// 展开后的内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(LexiRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LexiSpace.s6),
            child: Row(
              children: <Widget>[
                Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                  color: colors.secondaryLabel,
                ),
                const SizedBox(width: LexiSpace.s6),
                Text(
                  title,
                  style: LexiType.callout.copyWith(
                    color: colors.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: LexiSpace.s8),
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LexiType.footnote.copyWith(
                      color: colors.tertiaryLabel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: LexiSpace.s6),
            child: child,
          ),
      ],
    );
  }
}
