/// 通用表单行与分组卡片控件。
///
/// 由原 `features/settings/settings_controls.dart` 解耦提炼至 `lib/ui/widgets/`：
/// 分组卡片、带实时数值回显的滑条行、整行可点的开关行、语义提示横幅属于全应用
/// 通用的表单构件（设置页、复习配置抽屉、导入策略卡片均可复用）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 通用表单分组卡片。
class LexiSectionCard extends StatelessWidget {
  /// 以标题与内容构造。
  const new({
    required this.title,
    required this.child,
    this.subtitle,
    super.key,
  });

  /// 分组标题。
  final String title;

  /// 补充说明（解释「为什么」而不是复述标题）。
  final String? subtitle;

  /// 分组内容。
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: LexiSpace.s16),
    child: SectionCard(title: title, subtitle: subtitle, child: child),
  );
}

/// 兼容旧名：设置分组卡片。
typedef SettingsSectionCard = LexiSectionCard;

/// 带数值回显的通用滑条行。
///
/// **只在拖动结束时写库**：拖动过程中用本地状态实时回显，松手时触发触觉反馈
/// 并调用 [onChangeEnd]。
class LexiSliderRow extends StatefulWidget {
  /// 以标签、区间与回调构造。
  const new({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChangeEnd,
    this.valueText,
    this.description,
    this.divisions,
    super.key,
  });

  /// 标签。
  final String label;

  /// 当前值。
  final double value;

  /// 下限。
  final double min;

  /// 上限。
  final double max;

  /// 拖动结束（或点击轨道）后的回调。
  final ValueChanged<double> onChangeEnd;

  /// 数值回显文案；为空时显示当前数值。
  final String? valueText;

  /// 补充说明。
  final String? description;

  /// 刻度数；为空表示连续取值。
  final int? divisions;

  @override
  State<LexiSliderRow> createState() => _LexiSliderRowState();
}

/// 兼容旧名：设置滑条行。
typedef SettingsSliderRow = LexiSliderRow;

class _LexiSliderRowState extends State<LexiSliderRow> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(LexiSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  void _handleChangeEnd(double value) {
    LexiHaptics.selection();
    widget.onChangeEnd(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final description = widget.description;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LexiLayout.readingMaxWidth,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.label,
                      style: LexiType.body.copyWith(color: colors.label),
                    ),
                  ),
                  Text(
                    widget.valueText ?? _value.toStringAsFixed(2),
                    style: LexiType.body.copyWith(
                      color: colors.accentText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (description != null)
            Text(
              description,
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LexiLayout.readingMaxWidth,
              ),
              child: Slider(
                value: _value.clamp(widget.min, widget.max),
                min: widget.min,
                max: widget.max,
                divisions: widget.divisions,
                onChanged: (value) => setState(() => _value = value),
                onChangeEnd: _handleChangeEnd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用开关行。
class LexiSwitchRow extends StatelessWidget {
  /// 以标签与回调构造。
  const new({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.switchKey,
    super.key,
  });

  /// 标签。
  final String label;

  /// 当前开关状态。
  final bool value;

  /// 状态变化回调。
  final ValueChanged<bool> onChanged;

  /// 补充说明。
  final String? description;

  /// 开关本身的 Key。
  final Key? switchKey;

  void _handleChanged(bool next) {
    LexiHaptics.selection();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final description = this.description;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: LexiType.body.copyWith(color: colors.label)),
                if (description != null)
                  Text(
                    description,
                    style: LexiType.caption.copyWith(
                      color: colors.secondaryLabel,
                    ),
                  ),
              ],
            ),
          ),
          Switch(key: switchKey, value: value, onChanged: _handleChanged),
        ],
      ),
    );
  }
}

/// 兼容旧名：设置开关行。
typedef SettingsSwitchRow = LexiSwitchRow;

/// 通用内联提示横幅（用于警告、危险或规则说明）。
class LexiNoticeBanner extends StatelessWidget {
  /// 以文案与语义颜色构造。
  const new({
    required this.message,
    required this.color,
    this.icon = LucideIcons.info,
    super.key,
  });

  /// 提示文案。
  final String message;

  /// 提示主色。
  final Color color;

  /// 提示图标。
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LexiSpace.s10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: LexiTint.tint),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Text(
              message,
              style: LexiType.footnote.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// 兼容旧名：设置提示条。
typedef SettingsNotice = LexiNoticeBanner;
