/// 任务摘要侧栏。
///
/// 五行分别回答「补什么、对谁、怎么写、从哪来、怎么调」——
/// 这五个问题正好对应任务表里的五列，因此摘要不是装饰：
/// 它的每一行都能在入队请求里找到同名字段。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_fields.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 任务摘要。
class ConfiguratorSummarySidebar extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(configuratorProvider.select((s) => s.draft));
    final selected = ref.watch(queueSelectionProvider).length;
    final preset = activeConfiguratorPreset(
      draft.fields,
      youdaoOnly: draft.youdaoOnly,
    );
    final rows = <(String, String)>[
      ('内容', preset?.label ?? _fieldSummary(draft.fields)),
      (
        '范围',
        draft.scope == ConfiguratorScope.all
            ? ConfiguratorScope.all.label
            : '${ConfiguratorScope.selection.label} $selected 个',
      ),
      ('写入方式', writeModeLabel(draft.mode)),
      ('来源', _sourceSummary(draft)),
      ('策略', strategyLabel(draft)),
    ];
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(sidebarPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '任务摘要',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: context.lexiColors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: summaryHeaderGap),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: rowSpacing),
              child: SummaryRow(label: row.$1, value: row.$2),
            ),
        ],
      ),
    );
  }

  /// 自定义字段时的内容摘要。
  String _fieldSummary(List<String> fields) {
    if (fields.isEmpty) return '未选择字段';
    final labels = fields
        .take(fieldSummaryLimit)
        .map(initializationFieldLabel)
        .join('、');
    return fields.length > fieldSummaryLimit
        ? '$labels 等 ${fields.length} 项'
        : labels;
  }

  /// 来源摘要：有道锁定时说明只有这一个来源，否则报个数。
  String _sourceSummary(ConfiguratorDraft draft) {
    if (draft.youdaoOnly) return '有道词典（仅此来源）';
    if (draft.providers.isEmpty) return '尚未选择来源';
    return '${draft.providers.length} 个来源';
  }
}

/// 摘要里的一行。
class SummaryRow extends StatelessWidget {
  /// 以名称与取值构造。
  const new({required this.label, required this.value, super.key});

  /// 行名。
  final String label;

  /// 取值。
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colors.tertiaryLabel),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.label, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// 写入方式的中文名。
String writeModeLabel(InitializationMode mode) => switch (mode) {
  InitializationMode.fillMissingFields => '仅补充缺失',
  InitializationMode.forceOverwrite => '刷新所选字段',
  InitializationMode.skipInitialized => '跳过已补全',
};

/// 调用策略的中文名。
String strategyLabel(ConfiguratorDraft draft) {
  if (draft.youdaoOnly) return '严格仅有道';
  return switch (draft.strategy) {
    ProviderStrategy.priorityFallback => '按优先级回退',
    ProviderStrategy.parallelMerge => '全部查询并合并',
  };
}

/// 侧栏内边距。
const double sidebarPadding = 16;

/// 行间距。
const double rowSpacing = 6;

/// 标题与行之间的间距。
const double summaryHeaderGap = 10;

/// 行名列宽。
const double labelWidth = 56;

/// 摘要里最多列出的字段个数。
const int fieldSummaryLimit = 4;
