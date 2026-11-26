/// 渐进展示低频内容；折叠时保持表单和交互状态。
///
/// **头行为什么是一块淡底圆角**：折叠分区以前只有一行标题加箭头，放在卡片、
/// 统计页与设置分类里都像「没收尾的列表项」。现在头行使用 `fill` 淡底与
/// `md` 圆角，展开后内容接在同一块分区里，既看得出可点，也不会和正文抢层级。
/// 具体颜色与形状由 `lexi_theme.dart` 的 `ExpansionTileThemeData` 统一提供。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 头行的最小点击高度。
const double _headerMinHeight = 48;

/// 无额外卡片底板的可展开分区。
class DisclosureSection extends StatefulWidget {
  /// 创建可展开分区。
  const new({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
    this.titleStyle,
    super.key,
  });

  /// 始终可见的入口名称。
  final String title;

  /// 展开后的内容。
  final Widget child;

  /// 首次显示时是否展开。
  final bool initiallyExpanded;

  /// 标题样式；为空时使用 `callout` + w600。
  final TextStyle? titleStyle;

  @override
  State<DisclosureSection> createState() => _DisclosureSectionState();
}

class _DisclosureSectionState extends State<DisclosureSection> {
  // 展开状态(bool)与内部滚动位置(double)必须使用不同的存储域。
  final PageStorageBucket _contentStorage = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final titleStyle =
        widget.titleStyle ??
        LexiType.callout.copyWith(
          color: colors.label,
          fontWeight: FontWeight.w600,
        );
    return ExpansionTile(
      key: PageStorageKey<String>('disclosure-${widget.title}'),
      title: Text(widget.title, style: titleStyle),
      initiallyExpanded: widget.initiallyExpanded,
      maintainState: true,
      minTileHeight: _headerMinHeight,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      expansionAnimationStyle: AnimationStyle(
        duration: LexiMotion.of(context, LexiMotion.standard),
        curve: LexiMotion.spring,
      ),
      children: <Widget>[
        PageStorage(bucket: _contentStorage, child: widget.child),
      ],
    );
  }
}
