/// 统一的「可选卡片」。
///
/// 小游戏准备页、配对预设、音标模式、导入模式、配置器选项此前各写一套
/// 选中描边与底色；描边宽度在 1 与 2 之间摇摆，选中底色有的用分区色、
/// 有的用主色淡底。这里把差异收成参数，选中态只保留一种表达：
/// 主色描边 + 分区色底 + 勾选图标 + 120ms 过渡。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 一张可选卡片。
///
/// 参数克制到「内容 + 选中状态 + 一个动作」：再多就会退化成每个调用方
/// 各传一套样式。
class SelectionCard extends StatelessWidget {
  /// 以标题、说明与选中状态构造。
  const new({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.tone,
    this.trailing,
    this.compact = false,
    super.key,
  });

  /// 标题。
  final String title;

  /// 说明；为空时只渲染标题。
  final String? subtitle;

  /// 左侧图标。
  final IconData? icon;

  /// 分区色；为空时用中性卡片底。
  final LexiTone? tone;

  /// 右侧附加内容（计数、耗时等）。
  final Widget? trailing;

  /// 是否选中。
  final bool selected;

  /// 点击回调；为 `null` 时禁用。
  final VoidCallback? onTap;

  /// 紧凑模式：减少纵向留白，用于导入模式这类列表项。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final toneStyle = tone == null ? null : context.lexiTones.styleOf(tone!);
    final radius = BorderRadius.circular(LexiRadius.lg);
    return Surface(
      variant: SurfaceVariant.raised,
      padding: EdgeInsets.zero,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: LexiMotion.quick,
          curve: LexiMotion.spring,
          padding: EdgeInsets.all(compact ? LexiSpace.s12 : LexiSpace.s16),
          decoration: BoxDecoration(
            color: selected
                ? toneStyle?.background ??
                      colors.accent.withValues(alpha: LexiTint.tint)
                : null,
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? colors.accent
                  : toneStyle?.border ?? Colors.transparent,
              width: selected ? 2 : 1,
            ),
          ),
          child: _SelectionRow(
            title: title,
            subtitle: subtitle,
            icon: icon,
            toneStyle: toneStyle,
            selected: selected,
            trailing: trailing,
          ),
        ),
      ),
    );
  }
}

/// 卡片内部的一行：图标 + 标题/说明 + 选中勾 + 右侧附加。
class _SelectionRow extends StatelessWidget {
  const new({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.toneStyle,
    required this.selected,
    required this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final LexiToneStyle? toneStyle;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(LexiSpace.s8),
            decoration: BoxDecoration(
              color: toneStyle?.background ?? colors.fill,
              borderRadius: BorderRadius.circular(LexiRadius.sm),
            ),
            child: Icon(
              icon,
              size: 22,
              color: toneStyle?.foreground ?? colors.secondaryLabel,
            ),
          ),
          const SizedBox(width: LexiSpace.s12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: LexiType.callout.copyWith(
                        color: colors.label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      LucideIcons.circleCheck,
                      size: 18,
                      color: colors.accentText,
                    ),
                ],
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: LexiSpace.s2),
                Text(
                  subtitle!,
                  style: LexiType.footnote.copyWith(
                    color: colors.secondaryLabel,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: LexiSpace.s12),
          trailing!,
        ],
      ],
    );
  }
}
