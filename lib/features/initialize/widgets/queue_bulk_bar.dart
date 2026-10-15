/// 多选后浮在底部的批量操作条。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/features/initialize/configurator/configurator_state.dart';
import 'package:lexiloop/features/initialize/configurator/initialization_configurator.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 「已选 N 个词条」浮条。
///
/// 做成浮条而不是列表上方的一行：多选是为了在长列表里挑词条，
/// 挑完之后视线已经移到了列表底部，操作入口必须跟着出现在那里。
class QueueBulkBar extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(queueSelectionProvider);
    if (selected.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(queueSelectionProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: barInset),
      child: LiquidGlass(
        level: GlassLevel.elevated,
        borderRadius: BorderRadius.circular(LexiRadius.xl),
        padding: const EdgeInsets.symmetric(
          horizontal: barPadding,
          vertical: 10,
        ),
        child: Row(
          children: <Widget>[
            _SelectionCount(count: selected.length),
            const SizedBox(width: countGap),
            Text(
              '已选 ${selected.length} 个词条',
              style: TextStyle(
                color: context.lexiColors.label,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: barPadding),
            Expanded(
              child: Wrap(
                spacing: barPadding,
                alignment: WrapAlignment.end,
                children: <Widget>[
                  FilledButton(
                    onPressed: () => unawaited(
                      showInitializationConfigurator(
                        context,
                        initialScope: ConfiguratorScope.selection,
                      ),
                    ),
                    child: const Text('配置初始化'),
                  ),
                  FilledButton(
                    onPressed: () => _retry(context, ref),
                    child: const Text('重试这些词条的全部任务'),
                  ),
                  TextButton(
                    onPressed: notifier.clear,
                    child: const Text('取消选择'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retry(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final selection = ref.read(queueSelectionProvider);
    try {
      final retried = await ref
          .read(queueActionsProvider)
          .retryWords(selection.toList());
      messenger.showSnackBar(
        SnackBar(content: Text(retried == 0 ? '没有可重试的任务' : '已重试 $retried 个任务')),
      );
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// 选中数量的气泡计数。
class _SelectionCount extends StatelessWidget {
  const new({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: colors.surface,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 浮条离屏幕左右的距离。
const double barInset = 16;

/// 浮条内边距与元素间距。
const double barPadding = 12;

/// 计数气泡与文案之间的间距。
const double countGap = 6;
