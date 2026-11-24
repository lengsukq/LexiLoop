/// 词书包中心页面：浏览/下载云端词书、切换国内加速通道、管理已安装词书。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/features/packs/widgets/word_pack_card.dart';
import 'package:lexiloop/features/packs/widgets/word_pack_channel_sheet.dart';
import 'package:lexiloop/features/packs/widgets/word_pack_dialogs.dart';
import 'package:lexiloop/features/packs/word_packs_providers.dart';
import 'package:lexiloop/features/settings/audio_precache_sheet.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/error_retry_view.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 词书包中心页面。
class WordPacksPage extends ConsumerStatefulWidget {
  /// 创建词书包中心页面。
  const new({super.key});

  @override
  ConsumerState<WordPacksPage> createState() => _WordPacksPageState();
}

class _WordPacksPageState extends ConsumerState<WordPacksPage> {
  bool _installedOnly = false;
  WordPackCategory? _category;

  Future<void> _importLocalFile() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final files = await FilePickerPlatform.instance.pickFiles(
      dialogTitle: '选择 LexiLoop 词书包（.lexipack.json.gz / .json）',
      type: FileType.custom,
      allowedExtensions: const <String>['gz', 'json'],
    );
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    if (bytes.isEmpty) return;
    try {
      final result = await ref
          .read(wordPackTransferProvider.notifier)
          .importLocalBytes(bytes);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '已导入「${result.packName}」：新增 ${result.createdWords} 词， '
            '复用 ${result.linkedExistingWords} 词。',
          ),
        ),
      );
    } on Object catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text(wordPackErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(wordPackCatalogProvider);
    final installed = ref.watch(installedWordPacksProvider);
    final installedCount = installed.value?.length ?? 0;

    return PageShell(
      header: PageHeader(
        title: '词书包',
        subtitle: '按需下载权威词表，与个人词库共存互不干扰。',
        leading: backButton(context, fallbackLocation: wordsPath),
        actions: <PageHeaderAction>[
          PageHeaderAction(
            label: '本地导入包',
            icon: LucideIcons.folderInput,
            onPressed: () => unawaited(_importLocalFile()),
          ),
          PageHeaderAction(
            label: '刷新目录',
            icon: LucideIcons.refreshCw,
            onPressed: () => ref.invalidate(wordPackCatalogProvider),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _ChannelStatusStrip(),
          const SizedBox(height: LexiSpace.s10),
          _FilterStrip(
            installedOnly: _installedOnly,
            installedCount: installedCount,
            selectedCategory: _category,
            onToggleInstalledOnly: (value) =>
                setState(() => _installedOnly = value),
            onSelectCategory: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: LexiSpace.s12),
          Expanded(
            child: _PacksBody(
              catalog: catalog,
              installed: installed,
              installedOnly: _installedOnly,
              category: _category,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelStatusStrip extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config =
        ref.watch(wordPackDownloadConfigProvider).value ??
        const WordPackDownloadConfig();
    final fromRemote = ref.watch(wordPackCatalogProvider).value?.fromRemote;
    final colors = context.lexiColors;
    return Surface(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s12,
        vertical: LexiSpace.s10,
      ),
      child: Row(
        children: <Widget>[
          Icon(LucideIcons.globe, size: 16, color: colors.accentText),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Wrap(
              spacing: LexiSpace.s6,
              runSpacing: LexiSpace.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  config.channel.label,
                  style: LexiType.callout.copyWith(color: colors.label),
                ),
                if (fromRemote != null)
                  LexiBadge(
                    label: fromRemote ? '云端最新目录' : '内置离线目录',
                    tone: fromRemote
                        ? LexiBadgeTone.success
                        : LexiBadgeTone.neutral,
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => unawaited(showWordPackChannelSheet(context)),
            icon: const Icon(LucideIcons.slidersHorizontal, size: 15),
            label: const Text('切换通道 / 测速'),
          ),
        ],
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const new({
    required this.installedOnly,
    required this.installedCount,
    required this.selectedCategory,
    required this.onToggleInstalledOnly,
    required this.onSelectCategory,
  });

  final bool installedOnly;
  final int installedCount;
  final WordPackCategory? selectedCategory;
  final ValueChanged<bool> onToggleInstalledOnly;
  final ValueChanged<WordPackCategory?> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LexiSpace.s8,
      runSpacing: LexiSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SegmentedButton<bool>(
          segments: <ButtonSegment<bool>>[
            const ButtonSegment<bool>(value: false, label: Text('全部词书')),
            ButtonSegment<bool>(
              value: true,
              label: Text('已添加 ($installedCount)'),
            ),
          ],
          selected: <bool>{installedOnly},
          onSelectionChanged: (set) => onToggleInstalledOnly(set.first),
        ),
        ChoiceChip(
          label: const Text('全部分类'),
          selected: selectedCategory == null,
          onSelected: (_) => onSelectCategory(null),
        ),
        for (final cat in const <WordPackCategory>[
          WordPackCategory.foundation,
          WordPackCategory.examCn,
          WordPackCategory.examIntl,
        ])
          ChoiceChip(
            label: Text(cat.label),
            selected: selectedCategory == cat,
            onSelected: (_) =>
                onSelectCategory(selectedCategory == cat ? null : cat),
          ),
      ],
    );
  }
}

class _PacksBody extends ConsumerWidget {
  const new({
    required this.catalog,
    required this.installed,
    required this.installedOnly,
    required this.category,
  });

  final AsyncValue<WordPackCatalogView> catalog;
  final AsyncValue<List<InstalledWordPackSummary>> installed;
  final bool installedOnly;
  final WordPackCategory? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(wordPackTransferProvider);
    if (catalog.isLoading && !catalog.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.hasError && !catalog.hasValue) {
      return ErrorRetryView(
        message: wordPackErrorMessage(catalog.error!),
        onRetry: () => ref.invalidate(wordPackCatalogProvider),
      );
    }
    final catalogView = catalog.value!;
    final installedList = installed.value ?? const <InstalledWordPackSummary>[];
    final entries = _mergeEntries(catalogView.catalog.packs, installedList);
    if (entries.isEmpty) {
      return Center(
        child: Text(
          installedOnly ? '还没有添加词书包，切换到「全部词书」挑选下载吧。' : '当前分类暂无词书。',
          style: LexiType.body.copyWith(
            color: context.lexiColors.secondaryLabel,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: LexiSpace.s24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: LexiSpace.s12),
      itemBuilder: (context, index) {
        final item = entries[index];
        final id = item.id;
        return WordPackCard(
          catalogItem: item.catalogItem,
          installed: item.installed,
          transfer: transfers[id],
          actions: _actionsFor(
            context: context,
            ref: ref,
            entry: item,
            catalog: catalogView.catalog,
          ),
        );
      },
    );
  }

  List<_CombinedPack> _mergeEntries(
    List<WordPackCatalogItem> catalogPacks,
    List<InstalledWordPackSummary> installedList,
  ) {
    final installedById = <String, InstalledWordPackSummary>{
      for (final item in installedList) item.id: item,
    };
    final result = <_CombinedPack>[];
    final seen = <String>{};
    for (final pack in catalogPacks) {
      seen.add(pack.id);
      result.add(_CombinedPack(pack.id, pack, installedById[pack.id]));
    }
    for (final local in installedList) {
      if (seen.add(local.id)) {
        result.add(_CombinedPack(local.id, null, local));
      }
    }
    return result
        .where((entry) {
          if (installedOnly && entry.installed == null) return false;
          if (category != null && entry.category != category) return false;
          return true;
        })
        .toList(growable: false);
  }

  WordPackCardActions _actionsFor({
    required BuildContext context,
    required WidgetRef ref,
    required _CombinedPack entry,
    required WordPackCatalog catalog,
  }) {
    final notifier = ref.read(wordPackTransferProvider.notifier);
    return WordPackCardActions(
      onDownload: () => unawaited(_downloadPack(context, ref, entry, catalog)),
      onCancel: () => notifier.cancelDownload(entry.id),
      onStudy: () => context.go('$studyPath?mode=DAILY&pack=${entry.id}'),
      onBrowseWords: () {
        ref
            .read(wordQueryProvider.notifier)
            .setSourceScope(WordSourceScope.packs, packId: entry.id);
        context.go(wordsPath);
      },
      onToggleDaily: (enabled) => unawaited(
        notifier.setIncludeInDailyStudy(entry.id, enabled: enabled),
      ),
      onEnrichYoudao: () => unawaited(_enrichPack(context, ref, entry.id)),
      onUninstall: () => unawaited(_uninstallPack(context, ref, entry.id)),
      onPrecacheAudio: () => unawaited(_precachePackAudio(context, ref, entry)),
    );
  }

  Future<void> _precachePackAudio(
    BuildContext context,
    WidgetRef ref,
    _CombinedPack entry,
  ) async {
    final name = entry.installed?.name ?? entry.catalogItem?.name ?? entry.id;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final started = await showAudioPrecacheSheet(
      context,
      ref,
      initialPackId: entry.id,
      initialPackName: name,
    );
    if (started) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('已开始后台缓存「$name」离线发音，可在「设置 → 播放」查看进度'),
          action: SnackBarAction(
            label: '查看进度',
            onPressed: () => context.go('$settingsPath?tab=playback'),
          ),
        ),
      );
    }
  }

  Future<void> _downloadPack(
    BuildContext context,
    WidgetRef ref,
    _CombinedPack entry,
    WordPackCatalog catalog,
  ) async {
    final item = entry.catalogItem;
    if (item == null) return;
    final choice = await showWordPackInstallDialog(
      context,
      item: item,
      isUpdate: entry.installed != null,
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final result = await ref
          .read(wordPackTransferProvider.notifier)
          .downloadAndInstall(
            item,
            includeInDailyStudy: choice.includeInDailyStudy,
            repo: catalog.repo,
            refName: catalog.ref,
          );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '已添加「${result.packName}」：新增 ${result.createdWords} 词， '
            '关联已有 ${result.linkedExistingWords} 词。',
          ),
        ),
      );
    } on AppError catch (error) {
      if (error.code == AppErrorCode.wordPackCancelled) return;
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    } on Object catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text(wordPackErrorMessage(error))),
      );
    }
  }

  Future<void> _enrichPack(
    BuildContext context,
    WidgetRef ref,
    String packId,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final count = await ref
        .read(wordPackTransferProvider.notifier)
        .enqueueFullYoudaoEnrich(packId);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          count == 0 ? '本词书词条均已完整，无需补全。' : '已将 $count 个词条排入有道后台补全队列。',
        ),
      ),
    );
  }

  Future<void> _uninstallPack(
    BuildContext context,
    WidgetRef ref,
    String packId,
  ) async {
    final impact = await ref
        .read(wordPackDaoProvider)
        .inspectUninstallImpact(packId);
    if (impact == null || !context.mounted) return;
    final choice = await showWordPackUninstallDialog(context, impact: impact);
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(wordPackTransferProvider.notifier)
        .uninstallPack(
          packId,
          keepLearnedAsPersonal: choice.keepLearnedAsPersonal,
        );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          '已卸载词书：清理 ${result.removedWords} 词， '
          '已学转个人 ${result.promotedToPersonalWords} 词， '
          '保留个人/共享 ${result.keptPersonalOrSharedWords} 词。',
        ),
      ),
    );
  }
}

class _CombinedPack {
  const new(this.id, this.catalogItem, this.installed);

  final String id;
  final WordPackCatalogItem? catalogItem;
  final InstalledWordPackSummary? installed;

  WordPackCategory get category =>
      installed?.category ?? catalogItem?.category ?? WordPackCategory.custom;
}
