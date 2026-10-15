/// 仪表盘共用的小组件。
///
/// 与详情页的 `DetailSectionCard` 是同类底板；两者各自保留一份以免
/// feature 之间互相依赖，待 `lib/ui/widgets/` 开放编辑后应合并过去。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 仪表盘卡片底板：玻璃面板 + 标题行 + 内容。
class DashboardCard extends StatelessWidget {
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
    return LiquidGlass(
      level: GlassLevel.elevated,
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      showSpecular: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: colors.accent),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: TextStyle(
                  color: colors.label,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 卡片内的加载占位。
class DashboardLoading extends StatelessWidget {
  /// 创建加载占位。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(
          '加载中…',
          style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
        ),
      ],
    );
  }
}

/// 卡片内的失败提示（含重试）。
class DashboardError extends StatelessWidget {
  /// 以提示与重试回调构造。
  const new({required this.message, required this.onRetry, super.key});

  /// 失败提示。
  final String message;

  /// 重试回调。
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(message, style: TextStyle(color: colors.danger, fontSize: 13)),
        const SizedBox(height: 8),
        FilledButton(onPressed: onRetry, child: const Text('重试')),
      ],
    );
  }
}

/// 「标签 + 数值」的一行。
class DashboardStatRow extends StatelessWidget {
  /// 以标签、数值与可选说明构造。
  const new({
    required this.label,
    required this.value,
    this.note,
    this.valueKey,
    super.key,
  });

  /// 指标名称。
  final String label;

  /// 指标数值（已格式化的文本）。
  final String value;

  /// 数值后的补充说明。
  final String? note;

  /// 数值文本的 Key，供测试定位。
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
          ),
          Text(
            value,
            key: valueKey,
            style: TextStyle(
              color: colors.label,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: TextStyle(color: colors.tertiaryLabel, fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}
