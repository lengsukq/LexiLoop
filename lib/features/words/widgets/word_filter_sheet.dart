/// 窄屏的筛选弹层。
///
/// 断点沿用 [sidebarBreakpoint]（与 `AdaptiveShell` 的侧边栏/底部 Tab
/// 分界一致）：这个宽度以下放不下四个下拉框，横向排开会把搜索框挤没。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/features/words/widgets/word_filter_controls.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 打开筛选弹层。
Future<void> showWordFilterSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _WordFilterSheet(),
    );

/// 筛选弹层本体。
class _WordFilterSheet extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LiquidGlass(
          level: GlassLevel.elevated,
          borderRadius: BorderRadius.circular(LexiRadius.xxl),
          showSpecular: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.tune_rounded, size: 16, color: colors.accent),
                  const SizedBox(width: 6),
                  Text(
                    '筛选单词本',
                    style: TextStyle(
                      color: colors.label,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Flexible(
                child: SingleChildScrollView(child: WordFilterControls()),
              ),
              const SizedBox(height: 10),
              const _SheetActions(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹层底部的「清除筛选」与「完成」。
class _SheetActions extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        TextButton(
          onPressed: () => ref.read(wordQueryProvider.notifier).clearFilters(),
          child: const Text('清除筛选'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
