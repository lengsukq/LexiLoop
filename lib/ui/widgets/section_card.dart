/// 卡片底板：玻璃面板 + 标题行 + 内容。
///
/// **为什么合并**：仪表盘与词条详情页各有一份逐字相同的实现
/// （`SectionCard` 与 `SectionCard`），两份的文件头都写着
/// 「待 `lib/ui/widgets/` 开放编辑后应合并过去」——这里就是那个时机。
/// 两份拷贝的代价不是行数，而是「改一次内边距要改两个文件，漏掉的那个
/// 只有在用户恰好走进那条路径时才会被发现」。
///
/// 卡片内的加载/失败/空态**没有**一并合并：它们在各页的文案与结构确实不同
/// （详情页按分区说「正在加载释义」，仪表盘按卡片说「正在加载」），
/// 强行统一会把差异塞进参数里，反而更难读。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 卡片内边距。
const double sectionCardPadding = 18;

/// 标题与内容之间的间距。
const double sectionCardTitleGap = 12;

/// 标题图标尺寸。
const double _sectionCardIconSize = 16;

/// 图标与标题之间的间距。
const double _sectionCardIconGap = 8;

/// 玻璃底板上的一张分区卡片。
class SectionCard extends StatelessWidget {
  /// 以标题与内容构造。
  const new({required this.title, required this.child, this.icon, super.key});

  /// 卡片标题。
  final String title;

  /// 标题左侧图标。
  final IconData? icon;

  /// 卡片内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(sectionCardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: _sectionCardIconSize, color: colors.accent),
                const SizedBox(width: _sectionCardIconGap),
              ],
              Text(
                title,
                style: TextStyle(
                  color: colors.label,
                  fontSize: LexiType.callout.fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: sectionCardTitleGap),
          child,
        ],
      ),
    );
  }
}
