/// 词库页的搜索框与筛选入口。
///
/// 宽屏把筛选控件直接铺在搜索框下方，窄屏收进筛选弹层；
/// 断点用 `600`，**不是**侧边栏断点。
///
/// 这两个断点量的不是同一件事：侧边栏断点比的是**窗口宽度**（决定导航形态），
/// 这里比的是**内容宽度**（决定筛选控件铺开还是收进面板）。正文列被限宽到
/// `LexiLayout.pageMaxWidth` 之后，内容宽度永远小于 1024——继续沿用侧边栏
/// 断点，这个分支就永远不会走到，宽屏用户会一直看到「筛选」按钮。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/words/widgets/word_filter_controls.dart';
import 'package:lexiloop/features/words/widgets/word_filter_sheet.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词库页的搜索框与筛选入口。
class WordFilterBar extends StatelessWidget {
  /// 创建搜索框与筛选入口。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 20;
    return Padding(
      padding: const EdgeInsets.only(top: LexiSpace.s2, bottom: LexiSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _SearchField(),
          const SizedBox(height: LexiSpace.s8),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < LexiLayout.wideBreakpoint) {
                if (largeText) {
                  return const Wrap(
                    spacing: LexiSpace.s8,
                    runSpacing: LexiSpace.s8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[WordSortPicker(), _FilterButton()],
                  );
                }
                return const Row(
                  children: <Widget>[
                    Expanded(child: WordSortPicker()),
                    SizedBox(width: LexiSpace.s8),
                    _FilterButton(),
                  ],
                );
              }
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  WordSortPicker(),
                  DisclosureSection(title: '高级筛选', child: WordFilterControls()),
                ],
              );
            },
          ),
        ],
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
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final delay = ref.read(wordsSearchDebounceProvider);
    if (delay <= Duration.zero) {
      ref.read(wordQueryProvider.notifier).setSearch(value);
      return;
    }
    _debounce = Timer(delay, () {
      if (!mounted) return;
      ref.read(wordQueryProvider.notifier).setSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(wordQueryProvider.select((query) => query.search), (
      _,
      next,
    ) {
      if (next.isEmpty && _controller.text.isNotEmpty) {
        _debounce?.cancel();
        _controller.clear();
      }
    });
    final hasText =
        _controller.text.isNotEmpty ||
        ref.watch(wordQueryProvider.select((query) => query.search.isNotEmpty));
    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      decoration: InputDecoration(
        hintText: '搜索词条、中文释义、标签或备注…',
        prefixIcon: const Icon(LucideIcons.search, size: 18),
        suffixIcon: hasText
            ? IconButton(
                tooltip: '清除搜索',
                onPressed: _clear,
                icon: const Icon(LucideIcons.x, size: 16),
              )
            : null,
      ),
    );
  }

  void _clear() {
    _debounce?.cancel();
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
      icon: const Icon(LucideIcons.slidersHorizontal, size: 16),
      label: Text(active == 0 ? '筛选' : '筛选 $active'),
    );
  }
}
