/// 词库列表的筛选与排序控件。
///
/// 宽屏内联显示、窄屏放进筛选弹层，两处共用同一个控件——
/// 复制一份的代价是「宽屏能筛错词、窄屏筛不了」这种只在手机复现的差异。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/widgets/queue_toolbar.dart'
    show chipGap, chipPaddingH, chipPaddingV, toolbarGap;
import 'package:lexiloop/features/words/words_format.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 筛选与排序控件组。
class WordFilterControls extends ConsumerWidget {
  /// 创建筛选与排序控件组。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InitializationStatusPicker(),
        SizedBox(height: toolbarGap),
        _MasteryChips(),
        SizedBox(height: toolbarGap),
        _SpecialChips(),
        SizedBox(height: toolbarGap),
        _SortPicker(),
      ],
    );
  }
}

/// 初始化状态下拉框。
///
/// 用下拉框而不是一排芯片：初始化状态有 7 个取值，横向排开会把筛选区
/// 撑成两行高，把列表挤到首屏之外。
class _InitializationStatusPicker extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wordQueryProvider);
    final notifier = ref.read(wordQueryProvider.notifier);
    return Row(
      children: <Widget>[
        const _FieldLabel('初始化状态'),
        const SizedBox(width: chipGap),
        Expanded(
          child: DropdownButton<InitializationStatus?>(
            value: query.initializationStatus,
            isDense: true,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: <DropdownMenuItem<InitializationStatus?>>[
              const DropdownMenuItem<InitializationStatus?>(
                child: Text('全部初始化状态'),
              ),
              for (final status in InitializationStatus.values)
                DropdownMenuItem<InitializationStatus?>(
                  value: status,
                  child: Text(initializationStatusLabel(status)),
                ),
            ],
            onChanged: notifier.setInitializationStatus,
          ),
        ),
      ],
    );
  }
}

/// 排序下拉框。
class _SortPicker extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wordQueryProvider);
    final notifier = ref.read(wordQueryProvider.notifier);
    return Row(
      children: <Widget>[
        const _FieldLabel('排序'),
        const SizedBox(width: chipGap),
        Expanded(
          child: DropdownButton<WordSort>(
            value: query.sort,
            isDense: true,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: <DropdownMenuItem<WordSort>>[
              for (final sort in WordSort.values)
                DropdownMenuItem<WordSort>(
                  value: sort,
                  child: Text(sort.label),
                ),
            ],
            onChanged: (sort) {
              if (sort != null) notifier.setSort(sort);
            },
          ),
        ),
      ],
    );
  }
}

/// 掌握等级筛选芯片。
class _MasteryChips extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wordQueryProvider);
    final notifier = ref.read(wordQueryProvider.notifier);
    return Wrap(
      spacing: chipGap,
      runSpacing: chipGap,
      children: <Widget>[
        _FilterChip(
          label: '全部掌握度',
          selected: query.masteryLevel == null,
          onTap: () => notifier.setMasteryLevel(null),
        ),
        for (final level in MasteryLevel.values)
          _FilterChip(
            label: masteryLabel(level),
            selected: query.masteryLevel == level,
            onTap: () => notifier.setMasteryLevel(level),
          ),
      ],
    );
  }
}

/// 错词 / 到期 / 暂停三个开关芯片。
///
/// 三个是**互相独立**的开关而不是旧版那样的单选下拉：它们描述的是词条的
/// 三个正交属性（「它在错词本里」「它今天到期」「它被暂停」），
/// 单选会逼用户放弃「既错词又到期」这种最该优先复习的那一批。
class _SpecialChips extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wordQueryProvider);
    final notifier = ref.read(wordQueryProvider.notifier);
    return Wrap(
      spacing: chipGap,
      runSpacing: chipGap,
      children: <Widget>[
        _FilterChip(
          label: '错词',
          selected: query.wrongOnly,
          onTap: () => notifier.setWrongOnly(enabled: !query.wrongOnly),
        ),
        _FilterChip(
          label: '到期',
          selected: query.dueOnly,
          onTap: () => notifier.setDueOnly(enabled: !query.dueOnly),
        ),
        _FilterChip(
          label: '已暂停',
          selected: query.suspendedOnly,
          onTap: () => notifier.setSuspendedOnly(enabled: !query.suspendedOnly),
        ),
      ],
    );
  }
}

/// 字段名。
class _FieldLabel extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: LexiType.footnote.copyWith(
        color: context.lexiColors.tertiaryLabel,
      ),
    );
  }
}

/// 筛选芯片。
class _FilterChip extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  /// 芯片文案。
  final String label;

  /// 是否处于选中态。
  final bool selected;

  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Material(
      color: selected ? colors.accent.withValues(alpha: 0.14) : colors.fill,
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: chipPaddingH,
            vertical: chipPaddingV,
          ),
          child: Text(
            label,
            style: LexiType.footnote.copyWith(
              color: selected ? colors.accent : colors.secondaryLabel,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
