/// 词书包中心的状态与数据提供者。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/data/word_packs/word_pack_downloader.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/services/word_packs/word_pack_install_service.dart';

/// 词书包传输/入库阶段。
enum WordPackTransferStage {
  /// 正在从云端通道下载压缩包。
  downloading,

  /// 正在后台解压并分批写入 SQLite。
  importing,
}

/// 单本词书当前的下载或入库进度状态。
class WordPackTransferState {
  /// 构造进度快照。
  const new({
    required this.stage,
    this.received = 0,
    this.total = 0,
    this.processedWords = 0,
    this.totalWords = 0,
  });

  /// 当前阶段。
  final WordPackTransferStage stage;

  /// 已下载字节数。
  final int received;

  /// 总字节数（未知时 `<= 0`）。
  final int total;

  /// 已入库词数。
  final int processedWords;

  /// 词书总词数。
  final int totalWords;

  /// 归一化进度（0–1）；未知总长时为 `null`。
  double? get progress {
    if (stage == WordPackTransferStage.importing) {
      return totalWords > 0 ? (processedWords / totalWords).clamp(0, 1) : null;
    }
    return total > 0 ? (received / total).clamp(0, 1) : null;
  }

  /// 面向用户的实时进度文案。
  String get label {
    if (stage == WordPackTransferStage.importing) {
      return totalWords > 0
          ? '正在入库 $processedWords / $totalWords 词…'
          : '正在解压并写入词库…';
    }
    if (total > 0) {
      return '正在下载 ${formatPackBytes(received)} / ${formatPackBytes(total)}';
    }
    return received > 0 ? '已下载 ${formatPackBytes(received)}…' : '正在连接下载通道…';
  }
}

/// 词书目录加载结果（区分远端最新与内置离线目录）。
class WordPackCatalogView {
  /// 以目录对象与是否来自远端构造。
  const new({required this.catalog, required this.fromRemote});

  /// 词书目录。
  final WordPackCatalog catalog;

  /// 是否成功从远端刷新。
  final bool fromRemote;
}

/// 内置词书目录读取器（测试可覆写，避免依赖真实资源包）。
final Provider<Future<String> Function()> bundledWordPackCatalogLoaderProvider =
    Provider<Future<String> Function()>(
      (ref) =>
          () => rootBundle.loadString(wordPackBundledCatalogAsset),
    );

/// 下载通道配置控制器。
class WordPackDownloadConfigNotifier
    extends AsyncNotifier<WordPackDownloadConfig> {
  @override
  Future<WordPackDownloadConfig> build() async {
    final raw = await ref.watch(settingsDaoProvider).loadRaw();
    return WordPackDownloadConfig.fromJson(raw[wordPackDownloadSettingsKey]);
  }

  /// 保存新的下载通道配置并刷新远端目录。
  Future<void> save(WordPackDownloadConfig next) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(settingsDaoProvider).saveAll(<String, Object?>{
      wordPackDownloadSettingsKey: next.toJson(),
    }, now);
    state = AsyncValue<WordPackDownloadConfig>.data(next);
  }
}

/// 下载通道配置提供者。
final AsyncNotifierProvider<
  WordPackDownloadConfigNotifier,
  WordPackDownloadConfig
>
wordPackDownloadConfigProvider =
    AsyncNotifierProvider<
      WordPackDownloadConfigNotifier,
      WordPackDownloadConfig
    >(WordPackDownloadConfigNotifier.new);

/// 词书目录提供者：优先拉取远端最新清单，离线时无感兜底至内置清单。
final FutureProvider<WordPackCatalogView> wordPackCatalogProvider =
    FutureProvider<WordPackCatalogView>((ref) async {
      final config = await ref.watch(wordPackDownloadConfigProvider.future);
      final remote = await ref
          .read(wordPackDownloaderProvider)
          .fetchRemoteCatalog(config);
      if (remote != null && remote.packs.isNotEmpty) {
        return WordPackCatalogView(catalog: remote, fromRemote: true);
      }
      final bundledRaw = await ref.read(bundledWordPackCatalogLoaderProvider)();
      return WordPackCatalogView(
        catalog: WordPackCatalog.parse(bundledRaw),
        fromRemote: false,
      );
    });

/// 已安装词书包列表及学习进度统计。
final FutureProvider<List<InstalledWordPackSummary>>
installedWordPacksProvider = FutureProvider<List<InstalledWordPackSummary>>(
  (ref) => ref.watch(wordPackDaoProvider).listInstalled(),
);

/// 词书下载/安装/卸载操作编排控制器。
class WordPackTransferNotifier
    extends Notifier<Map<String, WordPackTransferState>> {
  final Map<String, WordPackCancelSignal> _signals =
      <String, WordPackCancelSignal>{};

  @override
  Map<String, WordPackTransferState> build() =>
      const <String, WordPackTransferState>{};

  /// 从云端通道下载并安装指定词书。
  Future<WordPackInstallResult> downloadAndInstall(
    WordPackCatalogItem item, {
    required bool includeInDailyStudy,
    String? repo,
    String? refName,
  }) async {
    final signal = WordPackCancelSignal();
    _signals[item.id] = signal;
    _setTransfer(
      item.id,
      const WordPackTransferState(stage: WordPackTransferStage.downloading),
    );
    try {
      final config = await ref.read(wordPackDownloadConfigProvider.future);
      final downloaded = await ref
          .read(wordPackDownloaderProvider)
          .downloadPack(
            item: item,
            config: config,
            repo: repo,
            ref: refName,
            cancel: signal,
            onProgress: (received, total) => _setTransfer(
              item.id,
              WordPackTransferState(
                stage: WordPackTransferStage.downloading,
                received: received,
                total: total > 0 ? total : item.compressedBytes,
              ),
            ),
          );
      _setTransfer(
        item.id,
        WordPackTransferState(
          stage: WordPackTransferStage.importing,
          totalWords: item.wordCount,
        ),
      );
      final result = await ref
          .read(wordPackInstallServiceProvider)
          .installFromBytes(
            bytes: downloaded.bytes,
            now: DateTime.now().millisecondsSinceEpoch,
            includeInDailyStudy: includeInDailyStudy,
            sourceUrl: downloaded.resolvedUrl,
            onProgress: (processed, total) => _setTransfer(
              item.id,
              WordPackTransferState(
                stage: WordPackTransferStage.importing,
                processedWords: processed,
                totalWords: total,
              ),
            ),
          );
      _invalidateWordAndPackState();
      return result;
    } finally {
      _signals.remove(item.id);
      _clearTransfer(item.id);
    }
  }

  /// 从本地 `.lexipack.json.gz` / `.json` 文件字节离线安装词书。
  Future<WordPackInstallResult> importLocalBytes(
    Uint8List bytes, {
    bool includeInDailyStudy = false,
  }) async {
    final result = await ref
        .read(wordPackInstallServiceProvider)
        .installFromBytes(
          bytes: bytes,
          now: DateTime.now().millisecondsSinceEpoch,
          includeInDailyStudy: includeInDailyStudy,
        );
    _invalidateWordAndPackState();
    return result;
  }

  /// 取消指定词书的下载。
  void cancelDownload(String packId) {
    _signals[packId]?.cancel();
  }

  /// 切换词书是否纳入每日学习计划。
  Future<void> setIncludeInDailyStudy(
    String packId, {
    required bool enabled,
  }) async {
    await ref
        .read(wordPackDaoProvider)
        .setIncludeInDailyStudy(
          packId,
          enabled: enabled,
          now: DateTime.now().millisecondsSinceEpoch,
        );
    _invalidateWordAndPackState();
  }

  /// 安全卸载词书包。
  Future<WordPackUninstallResult> uninstallPack(
    String packId, {
    required bool keepLearnedAsPersonal,
  }) async {
    final result = await ref
        .read(wordPackInstallServiceProvider)
        .uninstallPack(
          packId: packId,
          now: DateTime.now().millisecondsSinceEpoch,
          keepLearnedAsPersonal: keepLearnedAsPersonal,
        );
    final currentQuery = ref.read(wordQueryProvider);
    if (currentQuery.packId == packId) {
      ref.read(wordQueryProvider.notifier).setPackId(null);
    }
    _invalidateWordAndPackState();
    return result;
  }

  /// 手动为整本词书触发后台有道全量补全。
  Future<int> enqueueFullYoudaoEnrich(String packId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final enqueued = await ref
        .read(wordPackInstallServiceProvider)
        .enqueueFullYoudaoEnrichment(packId: packId, now: now);
    if (enqueued > 0) {
      unawaited(ref.read(initializationMaintenanceProvider).pumpOnce(now: now));
    }
    ref
      ..invalidate(installedWordPacksProvider)
      ..invalidate(queueProgressProvider)
      ..invalidate(queuePageProvider);
    return enqueued;
  }

  /// 将单个词书词条收入个人词库。
  Future<void> promoteWordToPersonal(int wordId) async {
    await ref
        .read(wordPackDaoProvider)
        .promoteToPersonal(wordId, now: DateTime.now().millisecondsSinceEpoch);
    _invalidateWordAndPackState();
  }

  void _setTransfer(String packId, WordPackTransferState next) {
    state = <String, WordPackTransferState>{...state, packId: next};
  }

  void _clearTransfer(String packId) {
    final copy = <String, WordPackTransferState>{...state}..remove(packId);
    state = copy;
  }

  void _invalidateWordAndPackState() {
    ref
      ..invalidate(installedWordPacksProvider)
      ..invalidate(wordListProvider)
      ..invalidate(wordCountProvider)
      ..invalidate(masterySummaryProvider)
      ..invalidate(dashboardOverviewProvider)
      ..invalidate(dailyPlanProvider);
  }
}

/// 词书包操作控制器提供者。
final NotifierProvider<
  WordPackTransferNotifier,
  Map<String, WordPackTransferState>
>
wordPackTransferProvider =
    NotifierProvider<
      WordPackTransferNotifier,
      Map<String, WordPackTransferState>
    >(WordPackTransferNotifier.new);

/// 把词书包错误转换为面向用户的提示文案。
String wordPackErrorMessage(Object error) {
  if (error is AppError) return error.message;
  return '操作失败：$error';
}
