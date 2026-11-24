/// 单词本顶部的来源作用域切换条（全部 / 个人词库 / 词书包）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/features/packs/word_packs_providers.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 来源作用域分段条与已安装词书快捷筛选胶囊。
class WordSourceScopeBar extends ConsumerWidget {
  /// 创建来源作用域切换条。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installed =
        ref.watch(installedWordPacksProvider).value ??
        const <InstalledWordPackSummary>[];
    final scope = ref.watch(
      wordQueryProvider.select((query) => query.sourceScope),
    );
    final selectedPackId = ref.watch(
      wordQueryProvider.select((query) => query.packId),
    );

    if (installed.isEmpty && scope == WordSourceScope.all) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: SegmentedButton<WordSourceScope>(
                  showSelectedIcon: false,
                  segments: const <ButtonSegment<WordSourceScope>>[
                    ButtonSegment<WordSourceScope>(
                      value: WordSourceScope.all,
                      label: Text('全部'),
                    ),
                    ButtonSegment<WordSourceScope>(
                      value: WordSourceScope.personal,
                      label: Text('个人词库'),
                    ),
                    ButtonSegment<WordSourceScope>(
                      value: WordSourceScope.packs,
                      label: Text('词书包'),
                    ),
                  ],
                  selected: <WordSourceScope>{scope},
                  onSelectionChanged: (next) => ref
                      .read(wordQueryProvider.notifier)
                      .setSourceScope(next.first),
                ),
              ),
              const SizedBox(width: LexiSpace.s8),
              IconButton(
                tooltip: '管理词书包',
                onPressed: () => context.go(packsPath),
                icon: Icon(
                  LucideIcons.libraryBig,
                  size: 18,
                  color: context.lexiColors.accentText,
                ),
              ),
            ],
          ),
          if (scope == WordSourceScope.packs &&
              installed.isNotEmpty) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            _InstalledPackChips(
              packs: installed,
              selectedPackId: selectedPackId,
            ),
          ],
          if (scope == WordSourceScope.packs && installed.isEmpty) ...<Widget>[
            const SizedBox(height: LexiSpace.s8),
            _EmptyPackBanner(onBrowse: () => context.go(packsPath)),
          ],
        ],
      ),
    );
  }
}

class _InstalledPackChips extends ConsumerWidget {
  const new({required this.packs, required this.selectedPackId});

  final List<InstalledWordPackSummary> packs;
  final String? selectedPackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(wordQueryProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: const Text('全部词书'),
            selected: selectedPackId == null,
            onSelected: (_) => notifier.setPackId(null),
          ),
          for (final pack in packs) ...<Widget>[
            const SizedBox(width: LexiSpace.s6),
            ChoiceChip(
              label: Text('${pack.name} (${pack.totalWords})'),
              selected: selectedPackId == pack.id,
              onSelected: (_) => notifier.setPackId(
                selectedPackId == pack.id ? null : pack.id,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyPackBanner extends StatelessWidget {
  const new({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '尚未添加任何词书包。',
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ),
        TextButton.icon(
          onPressed: onBrowse,
          icon: const Icon(LucideIcons.cloudDownload, size: 15),
          label: const Text('去词书广场下载'),
        ),
      ],
    );
  }
}
