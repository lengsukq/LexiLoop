/// 仪表盘共用的小组件。
///
/// 卡片底板本身是共享的 `SectionCard`（`lib/ui/widgets/section_card.dart`）；
/// 这里只留仪表盘特有的加载/失败/统计行——它们的文案与结构与其他页确实
/// 不同，强行统一只会把差异塞进参数里。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

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
          style: LexiType.body.copyWith(color: colors.secondaryLabel),
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
        Text(message, style: LexiType.body.copyWith(color: colors.danger)),
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
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
          ),
          Text(
            value,
            key: valueKey,
            style: LexiType.callout.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: LexiType.footnote.copyWith(color: colors.tertiaryLabel),
            ),
        ],
      ),
    );
  }
}
