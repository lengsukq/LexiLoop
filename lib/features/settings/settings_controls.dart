/// 设置页的通用控件。
///
/// 抽出来的理由：6 个分组里的「卡片 + 滑条 + 开关」长得一样，
/// 旧版每个 tab 各写一遍 `FormField`，改一处间距要改六处。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 一个设置分组卡片。
class SettingsSectionCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final subtitle = this.subtitle;
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: colors.label,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// 带数值回显的滑条行。
///
/// **只在拖动结束时写库**：`onChanged` 每次移动都会触发，直接落库会在
/// 一次拖动里写上百次 `settings` 表。拖动过程中用本地状态回显，
/// 松手时才调用 [onChangeEnd]。
class SettingsSliderRow extends StatefulWidget {
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
  State<SettingsSliderRow> createState() => _SettingsSliderRowState();
}

class _SettingsSliderRowState extends State<SettingsSliderRow> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(SettingsSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化（例如备份导入）时同步；拖动中不打断用户。
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final description = widget.description;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(color: colors.label, fontSize: 13.5),
                ),
              ),
              Text(
                widget.valueText ?? _value.toStringAsFixed(2),
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (description != null)
            Text(
              description,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 11.5),
            ),
          Slider(
            value: _value.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (value) => setState(() => _value = value),
            onChangeEnd: widget.onChangeEnd,
          ),
        ],
      ),
    );
  }
}

/// 开关行。
class SettingsSwitchRow extends StatelessWidget {
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
  ///
  /// 行的中心是标签与开关之间的空白，点击不会命中任何手势；
  /// 测试与无障碍定位都要指向 [Switch] 本体。
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final description = this.description;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(color: colors.label, fontSize: 13.5),
                ),
                if (description != null)
                  Text(
                    description,
                    style: TextStyle(
                      color: colors.secondaryLabel,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          Switch(key: switchKey, value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 提示条（用于「至少启用一种题型」这类必须让用户看见的约束）。
class SettingsNotice extends StatelessWidget {
  /// 以文案与颜色构造。
  const new({required this.message, required this.color, super.key});

  /// 提示文案。
  final String message;

  /// 提示色（危险 / 警告）。
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
