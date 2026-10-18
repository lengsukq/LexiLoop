/// 词库列表的分页条。
///
/// 形状与 `queue_toolbar.dart` 的分页条一致（上一页 / 「第 X / Y 页 ·
/// 共 N 个」/ 下一页），间距也复用同一批常量：两个列表页的分页控件长得
/// 不一样会让用户以为自己到了另一个模块。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/initialize/widgets/queue_toolbar.dart'
    show toolbarGap;
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 词库列表的分页条。
class WordPaginator extends ConsumerWidget {
  /// 创建分页条。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wordQueryProvider);
    final total = ref.watch(wordCountProvider).value ?? 0;
    // 结果为空时整条隐藏：此时「第 1 / 1 页 · 共 0 个词条」只是噪声，
    // 而空状态已经把「为什么是空的」说清楚了。
    if (total == 0) return const SizedBox.shrink();

    final pages = _pageCount(total, query.limit);
    final page = query.page;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s12),
      child: Surface(
        variant: SurfaceVariant.inset,
        borderRadius: BorderRadius.circular(LexiRadius.pill),
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s8,
          vertical: LexiSpace.s4,
        ),
        child: Row(
          children: <Widget>[
            TextButton(
              onPressed: page > 1 ? () => _go(ref, page - 1) : null,
              child: const Text('上一页'),
            ),
            const SizedBox(width: toolbarGap),
            Expanded(
              child: Text(
                '第 $page / $pages 页 · 共 $total 个词条',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: context.lexiColors.tertiaryLabel),
              ),
            ),
            const SizedBox(width: toolbarGap),
            TextButton(
              onPressed: page < pages ? () => _go(ref, page + 1) : null,
              child: const Text('下一页'),
            ),
          ],
        ),
      ),
    );
  }

  /// 至少一页：结果为空时也要能显示「第 1 / 1 页」，而不是除以零。
  int _pageCount(int total, int limit) {
    final pages = limit < 1 ? 1 : (total / limit).ceil();
    return pages < 1 ? 1 : pages;
  }

  void _go(WidgetRef ref, int page) {
    ref.read(wordQueryProvider.notifier).goToPage(page);
  }
}
