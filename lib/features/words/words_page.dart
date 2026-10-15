/// 单词本页面。
///
/// P1 阶段的可见成果：导入旧版备份后，真实词条在这里列出来。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';

/// 单词本页面。
class WordsPage extends ConsumerWidget {
  /// 创建单词本页面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(wordListProvider);
    final total = ref.watch(wordCountProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _WordsHeader(total: total.value),
            const _FilterBar(),
            Expanded(
              child: words.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorView(
                  message: error is AppError ? error.message : '加载词条失败：$error',
                  onRetry: () => ref.invalidate(wordListProvider),
                ),
                data: (entries) => entries.isEmpty
                    ? const _EmptyView()
                    : _WordList(entries: entries),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WordsHeader extends ConsumerWidget {
  const new({required this.total});

  final int? total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '单词本',
                  style: TextStyle(
                    color: colors.label,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == null ? '加载中…' : '共 $total 个词条',
                  style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
                ),
              ],
            ),
          ),
          const _ImportButton(),
        ],
      ),
    );
  }
}

class _ImportButton extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends ConsumerState<_ImportButton> {
  bool _busy = false;

  Future<void> _import() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(backupServiceProvider).pickAndImport();
      if (result == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：${result.rowCounts['words'] ?? 0} 个词条、'
            '${result.totalRows} 行，统计重算 ${result.recomputedStats} 条',
          ),
        ),
      );
      ref
        ..invalidate(wordListProvider)
        ..invalidate(wordCountProvider)
        ..invalidate(masterySummaryProvider);
    } on AppError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy ? null : _import,
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_file_rounded, size: 17),
      label: Text(_busy ? '导入中…' : '导入备份'),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(wordQueryProvider);
    final notifier = ref.read(wordQueryProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: <Widget>[
          TextField(
            onChanged: notifier.setSearch,
            decoration: const InputDecoration(
              hintText: '搜索词条…',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _FilterChip(
                  label: '全部',
                  selected: query.masteryLevel == null,
                  onTap: () => notifier.setMasteryLevel(null),
                ),
                for (final level in MasteryLevel.values)
                  _FilterChip(
                    label: _masteryLabel(level),
                    selected: query.masteryLevel == level,
                    onTap: () => notifier.setMasteryLevel(level),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _masteryLabel(MasteryLevel level) => switch (level) {
  MasteryLevel.newWord => '新词',
  MasteryLevel.learning => '学习中',
  MasteryLevel.familiar => '熟悉',
  MasteryLevel.proficient => '熟练',
  MasteryLevel.mastered => '已掌握',
};

class _FilterChip extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? colors.accent.withValues(alpha: 0.14) : colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(LexiRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? colors.accent : colors.secondaryLabel,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WordList extends StatelessWidget {
  const new({required this.entries});

  final List<WordListEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, index) => _WordTile(entry: entries[index]),
    );
  }
}

/// 词条详情页的路径前缀。
///
/// 集中一处：路由表与本页都引用它，改名时不会只改一边。
const String wordDetailPathPrefix = '/words/';

class _WordTile extends StatelessWidget {
  const new({required this.entry});

  final WordListEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return GestureDetector(
      onTap: () => context.go('$wordDetailPathPrefix${entry.id}'),
      behavior: HitTestBehavior.opaque,
      child: LiquidGlass(
        level: GlassLevel.elevated,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        showSpecular: true,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.term,
                    style: TextStyle(
                      color: colors.label,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.meaning != null) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      entry.meaning!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.secondaryLabel,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                MasteryBadge(
                  level: entry.masteryLevel,
                  score: entry.masteryScore,
                ),
                const SizedBox(height: 4),
                InitializationBadge(status: entry.initializationStatus),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.menu_book_rounded,
              size: 44,
              color: colors.tertiaryLabel,
            ),
            const SizedBox(height: 14),
            Text(
              '还没有词条',
              style: TextStyle(
                color: colors.label,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '点击右上角「导入备份」，选择从旧版导出的 JSON 文件',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const new({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 40, color: colors.danger),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
