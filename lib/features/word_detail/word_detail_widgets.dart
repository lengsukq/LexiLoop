/// 词条详情页共用的小组件。
///
/// 这些是纯展示件（玻璃底板、字段行、小标签），不含任何取数逻辑；
/// 取数全在 `word_detail_providers.dart`，页面组件只接收数据。
///
/// 注：卡片底板是共享的 [SectionCard]；这里只留详情页特有的字段行、
/// 要点行、小标签与异步占位。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 「标签 + 值」的一行。
///
/// 标签列固定宽度，使同一卡片内多行的值左对齐——旧版详情页用
/// 定义列表（`<dl>`）达到同一效果，Flutter 侧需要显式定宽。
class DetailField extends StatelessWidget {
  /// 以标签与值构造。
  const new({required this.label, required this.value, super.key});

  /// 字段名。
  final String label;

  /// 字段值（已格式化的文本）。
  final String value;

  /// 标签列宽度。
  static const double labelWidth = 88;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: LexiType.body.copyWith(color: colors.label),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行要点文本（前置圆点）。
class DetailBullet extends StatelessWidget {
  /// 以文本构造。
  const new(this.text, {this.note, super.key});

  /// 要点正文。
  final String text;

  /// 补充说明（灰色小字）。
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(text, style: LexiType.body.copyWith(color: colors.label)),
                if (note != null)
                  Text(
                    note!,
                    style: LexiType.footnote.copyWith(
                      color: colors.secondaryLabel,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 小标签（语种、内容类型、已暂停等）。
class DetailChip extends StatelessWidget {
  /// 以文本构造。
  const new({required this.text, this.color, super.key});

  /// 标签文本。
  final String text;

  /// 强调色；为空时用次级文本色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final tone = color ?? colors.secondaryLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        text,
        style: LexiType.caption.copyWith(
          color: tone,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 异步卡片的加载占位。
class DetailLoadingCard extends StatelessWidget {
  /// 以卡片标题构造。
  const new({required this.title, super.key});

  /// 卡片标题。
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return SectionCard(
      title: title,
      child: Row(
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
      ),
    );
  }
}

/// 异步卡片的失败提示（含重试）。
class DetailErrorCard extends StatelessWidget {
  /// 以标题、提示与重试回调构造。
  const new({
    required this.title,
    required this.message,
    this.onRetry,
    super.key,
  });

  /// 卡片标题。
  final String title;

  /// 失败提示。
  final String message;

  /// 重试回调；为空时不显示按钮。
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return SectionCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(message, style: LexiType.body.copyWith(color: colors.danger)),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 8),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}

/// 卡片内的空态提示。
class DetailEmptyHint extends StatelessWidget {
  /// 以提示文本构造。
  const new({required this.text, super.key});

  /// 提示文本。
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Text(
      text,
      style: LexiType.body.copyWith(color: colors.tertiaryLabel),
    );
  }
}
