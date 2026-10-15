/// 预览面板：本次会处理多少词条、跳过哪些、为什么。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_controls.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';

/// 预览面板。
///
/// 三个数字（范围内 / 处理 / 跳过）刻意与摘要里的「范围」分开：
/// 摘要回答「我配了什么」，这里回答「这么配会动多少数据」。
class ConfiguratorPreviewCard extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(configuratorPreviewProvider);
    return ConfiguratorCard(
      title: '本次任务预览',
      child: preview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          '预览失败：$error',
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: context.lexiColors.danger),
        ),
        data: (data) => _PreviewBody(preview: data),
      ),
    );
  }
}

/// 预览内容。
class _PreviewBody extends StatelessWidget {
  /// 以预览结果构造。
  const new({required this.preview});

  /// 预览结果。
  final InitializationPreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            PreviewMetric(label: '范围内', value: preview.existingWords),
            PreviewMetric(
              label: '处理',
              value: preview.selectedWords,
              highlight: true,
            ),
            PreviewMetric(label: '跳过', value: preview.skippedWords),
          ],
        ),
        const SizedBox(height: inlineGap),
        Text(
          '其中 ${preview.mergedWords} 个会并入已在排队的任务',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.tertiaryLabel),
        ),
        if (preview.samples.isNotEmpty) ...<Widget>[
          const SizedBox(height: inlineGap),
          Text(
            '示例：${preview.samples.map((item) => item.term).join('、')}',
            maxLines: sampleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.secondaryLabel),
          ),
        ],
        if (preview.skips.isNotEmpty) ...<Widget>[
          const SizedBox(height: inlineGap),
          Text(
            '跳过明细',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.label),
          ),
          const SizedBox(height: LexiSpace.s2),
          for (final skip in preview.skips)
            Text(
              '${skip.term}：${skip.reason}',
              maxLines: skipMaxLines,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colors.tertiaryLabel),
            ),
        ],
      ],
    );
  }
}

/// 一个计数字。
class PreviewMetric extends StatelessWidget {
  /// 以名称、数值与是否强调构造。
  const new({
    required this.label,
    required this.value,
    this.highlight = false,
    super.key,
  });

  /// 名称。
  final String label;

  /// 数值。
  final int value;

  /// 是否强调（用主色）。
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: highlight ? colors.accent : colors.label,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.tertiaryLabel),
          ),
        ],
      ),
    );
  }
}

/// 示例词条最多展示的行数。
const int sampleMaxLines = 2;

/// 单条跳过明细最多展示的行数。
const int skipMaxLines = 1;
