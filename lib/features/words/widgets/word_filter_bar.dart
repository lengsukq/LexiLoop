/// 词库页的搜索框与筛选入口。
///
/// 宽屏把筛选控件直接铺在搜索框下方，窄屏收进筛选弹层；
/// 断点与 [sidebarBreakpoint] 一致。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/features/words/widgets/word_filter_controls.dart';
import 'package:lexiloop/features/words/widgets/word_filter_sheet.dart';
import 'package:lexiloop/features/words/words_providers.dart';

/// 词库页的搜索框与筛选入口。
class WordFilterBar extends StatelessWidget {
  /// 创建搜索框与筛选入口。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= sidebarBreakpoint;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(child: _SearchField()),
                  if (!wide) ...<Widget>[
                    const SizedBox(width: 8),
                    const _FilterButton(),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              if (wide) const WordFilterControls(),
            ],
          );
        },
      ),
    );
  }
}

/// 关键词搜索框，带清除按钮。
class _SearchField extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  /// 自己持有控制器：清除按钮要把输入框本身也清空，
  /// 只改查询状态的话输入框里会留下旧词，看起来像清除失败。
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = ref.watch(
      wordQueryProvider.select((query) => query.search.isNotEmpty),
    );
    return TextField(
      controller: _controller,
      onChanged: ref.read(wordQueryProvider.notifier).setSearch,
      decoration: InputDecoration(
        hintText: '搜索词条或备注…',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        suffixIcon: hasText
            ? IconButton(
                tooltip: '清除搜索',
                onPressed: _clear,
                icon: const Icon(Icons.close_rounded, size: 16),
              )
            : null,
      ),
    );
  }

  void _clear() {
    _controller.clear();
    ref.read(wordQueryProvider.notifier).setSearch('');
  }
}

/// 窄屏上的「筛选」入口，标签带生效中的筛选数。
class _FilterButton extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      wordQueryProvider.select((query) => query.activeFilterCount),
    );
    return OutlinedButton.icon(
      onPressed: () => unawaited(showWordFilterSheet(context)),
      icon: const Icon(Icons.tune_rounded, size: 16),
      label: Text(active == 0 ? '筛选' : '筛选 $active'),
    );
  }
}
