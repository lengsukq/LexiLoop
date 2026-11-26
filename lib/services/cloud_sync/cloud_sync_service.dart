/// Next.js 跨端云同步编排服务：握手、分页拉取、分批推送、本机增量合并与覆盖恢复。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/backup/incremental_sync_exporter.dart';
import 'package:lexiloop/data/backup/incremental_sync_payload.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_protocol.dart';
import 'package:lexiloop/domain/models/cloud_sync_progress.dart';
import 'package:lexiloop/domain/models/cloud_sync_settings.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/domain/sync/delta_batch_splitter.dart';
import 'package:lexiloop/services/cloud_sync/cloud_sync_state_store.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/incremental_merge_service.dart';

/// 云端同步依赖的本地数据读写引擎聚合（控制服务构造参数 ≤ 5）。
class CloudSyncLocalEngine {
  /// 以增量导出器、增量合并服务与全量导入器构造。
  const new({
    required this.deltaExporter,
    required this.incrementalMerger,
    required this.importer,
  });

  /// 本机增量导出器。
  final IncrementalSyncExporter deltaExporter;

  /// 本机单事务增量合并服务。
  final IncrementalMergeService incrementalMerger;

  /// 本机单事务全量覆盖导入器。
  final BackupImporter importer;
}

/// Next.js 云端跨端同步服务。
class CloudSyncService {
  /// 以客户端工厂、状态存储、设备身份存储、本地引擎与可选时钟构造。
  new(
    this._clientFactory,
    this._states,
    this._lanStates,
    this._engine, {
    int Function()? clock,
  }) : _clock = clock ?? _wallClockMs;

  final CloudSyncClientFactory _clientFactory;
  final CloudSyncStateStore _states;
  final LanSyncStateStore _lanStates;
  final CloudSyncLocalEngine _engine;
  final int Function() _clock;

  /// 测试与 Next.js 服务器的连通性、密码鉴权与协议兼容性。
  Future<CloudSyncHandshakeReply> testConnection({
    CloudSyncCredential? overrideCredential,
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final settings = await _states.load();
    final credential = _requireCredential(
      overrideCredential ?? settings.credential,
    );
    final identity = await _lanStates.ensureIdentity();
    return await _clientFactory(credential).handshake(
      _handshakeRequest(identity, settings),
      cancelSignal: cancelSignal,
    );
  }

  /// 执行一次完整的云端同步（双向增量 / 单向拉取合并 / 云端覆盖本机）。
  Future<CloudSyncResult> sync({
    CloudSyncMode? mode,
    void Function(CloudSyncProgress progress)? onProgress,
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final notify = onProgress ?? _ignoreProgress;
    try {
      final settings = await _states.load();
      final credential = _requireCredential(settings.credential);
      final identity = await _lanStates.ensureIdentity();
      return await _runMode(
        client: _clientFactory(credential),
        settings: settings,
        identity: identity,
        mode: mode ?? settings.mode,
        notify: notify,
        cancelSignal: cancelSignal,
      );
    } on AppError catch (error) {
      await _handleSyncError(error, notify);
      rethrow;
    }
  }

  Future<void> _handleSyncError(
    AppError error,
    void Function(CloudSyncProgress) notify,
  ) async {
    if (error.code == AppErrorCode.cloudSyncCancelled) {
      notify(
        const CloudSyncProgress(
          phase: CloudSyncPhase.cancelled,
          message: '已取消云端同步',
        ),
      );
      return;
    }
    await _states.recordFailure(error.code.code);
    notify(
      CloudSyncProgress(phase: CloudSyncPhase.failed, message: error.message),
    );
  }

  Future<CloudSyncResult> _runMode({
    required CloudSyncClient client,
    required CloudSyncSettings settings,
    required LanSyncSettings identity,
    required CloudSyncMode mode,
    required void Function(CloudSyncProgress) notify,
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    notify(
      const CloudSyncProgress(
        phase: CloudSyncPhase.connecting,
        message: '正在连接 Next.js 服务器并验证身份…',
      ),
    );
    final handshake = await client.handshake(
      _handshakeRequest(identity, settings),
      cancelSignal: cancelSignal,
    );
    if (mode == CloudSyncMode.pullReplace) {
      return await _executePullReplace(
        client: client,
        handshake: handshake,
        notify: notify,
        cancelSignal: cancelSignal,
      );
    }
    return await _executeMergeSync(
      client: client,
      settings: settings,
      identity: identity,
      handshake: handshake,
      bidirectional: mode == CloudSyncMode.bidirectional,
      notify: notify,
      cancelSignal: cancelSignal,
    );
  }

  Future<CloudSyncResult> _executeMergeSync({
    required CloudSyncClient client,
    required CloudSyncSettings settings,
    required LanSyncSettings identity,
    required CloudSyncHandshakeReply handshake,
    required bool bidirectional,
    required void Function(CloudSyncProgress) notify,
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    // 双向模式下先拍下本机增量，避免稍后把刚拉回来的数据重复推回云端。
    final localDelta = bidirectional
        ? await _engine.deltaExporter.exportDelta(
            datasetEpoch: identity.datasetEpoch,
            since: handshake.pushSince,
          )
        : null;
    final pulled = await _pullAllPages(
      client: client,
      mode: 'delta',
      since: _effectivePullSince(settings.watermark, handshake),
      notify: notify,
      cancelSignal: cancelSignal,
    );
    final pushed = localDelta == null
        ? null
        : await _pushAllBatches(
            client: client,
            delta: localDelta,
            identity: identity,
            pulledServerNow: pulled.serverNow,
            notify: notify,
            cancelSignal: cancelSignal,
          );
    return await _applyDeltaAndRecord(
      pulled: pulled,
      localDelta: localDelta,
      handshake: handshake,
      pushed: pushed,
      bidirectional: bidirectional,
      notify: notify,
    );
  }

  Future<CloudSyncResult> _applyDeltaAndRecord({
    required _PulledBundle pulled,
    required IncrementalSyncPayload? localDelta,
    required CloudSyncHandshakeReply handshake,
    required _PushedBundle? pushed,
    required bool bidirectional,
    required void Function(CloudSyncProgress) notify,
  }) async {
    final latestEpoch = _resolveLatestEpoch(pulled, handshake, pushed);
    final totalBytes = pulled.wireBytes + (pushed?.wireBytes ?? 0);
    notify(
      CloudSyncProgress(
        phase: CloudSyncPhase.merging,
        transferredBytes: totalBytes,
        message: '正在合入本机数据库并重排 FSRS…',
      ),
    );
    final summary = await _engine.incrementalMerger.apply(
      IncrementalSyncPayload(
        isIncremental: pulled.isIncremental,
        serverNow: pulled.serverNow,
        datasetEpoch: latestEpoch,
        wordRefs: pulled.wordRefs,
        tables: pulled.tables,
      ),
    );
    final result = _buildMergeResult(
      summary: summary,
      peerCounts: pushed?.summary ?? CloudSyncSideCounts.zero,
      totalBytes: totalBytes,
      isIncremental: pulled.isIncremental,
      bidirectional: bidirectional,
    );
    await _recordCompletion(
      result: result,
      handshake: handshake,
      latestEpoch: latestEpoch,
      serverCursorMs: pulled.serverNow,
      localCursorMs: localDelta?.serverNow ?? 0,
      notify: notify,
    );
    return result;
  }

  Future<CloudSyncResult> _executePullReplace({
    required CloudSyncClient client,
    required CloudSyncHandshakeReply handshake,
    required void Function(CloudSyncProgress) notify,
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final pulled = await _pullAllPages(
      client: client,
      mode: 'replace',
      since: null,
      notify: notify,
      cancelSignal: cancelSignal,
    );
    notify(
      CloudSyncProgress(
        phase: CloudSyncPhase.merging,
        transferredBytes: pulled.wireBytes,
        message: '正在用云端快照替换本机数据…',
      ),
    );
    final secretSnapshot = await _states.snapshotLocalSecrets();
    final lanSnapshot = await _lanStates.snapshot();
    final imported = await _engine.importer.replaceAll(pulled.tables);
    await _states.restoreAfterReplace(secretSnapshot);
    await _lanStates.restoreAfterReplace(lanSnapshot);

    final words = imported.rowCounts['words'] ?? 0;
    final result = CloudSyncResult(
      mode: CloudSyncMode.pullReplace,
      local: CloudSyncSideCounts(
        addedWords: words,
        addedLogs: imported.rowCounts['review_logs'] ?? 0,
        wordCount: words,
      ),
      transferredBytes: pulled.wireBytes,
    );
    final latestEpoch = pulled.datasetEpoch.isEmpty
        ? handshake.datasetEpoch
        : pulled.datasetEpoch;
    await _recordCompletion(
      result: result,
      handshake: handshake,
      latestEpoch: latestEpoch,
      serverCursorMs: pulled.serverNow,
      localCursorMs: 0,
      notify: notify,
    );
    return result;
  }

  Future<void> _recordCompletion({
    required CloudSyncResult result,
    required CloudSyncHandshakeReply handshake,
    required String latestEpoch,
    required int serverCursorMs,
    required int localCursorMs,
    required void Function(CloudSyncProgress) notify,
  }) async {
    final serverCount = result.peer.wordCount > 0
        ? result.peer.wordCount
        : (result.mode == CloudSyncMode.pullReplace
              ? result.local.wordCount
              : handshake.wordCount);
    await _states.recordSuccess(
      watermark: CloudSyncWatermark(
        serverDeviceId: handshake.deviceId,
        serverDatasetEpoch: latestEpoch,
        serverCursorMs: serverCursorMs > 0
            ? serverCursorMs
            : handshake.serverNow,
        localCursorMs: localCursorMs,
      ),
      serverWordCount: serverCount,
      summary: formatCloudSyncResultSummary(result),
    );
    notify(
      CloudSyncProgress(
        phase: CloudSyncPhase.completed,
        completedSteps: 1,
        totalSteps: 1,
        transferredBytes: result.transferredBytes,
        message: result.mode == CloudSyncMode.pullReplace ? '覆盖恢复完成' : '同步完成',
      ),
    );
  }

  Future<_PulledBundle> _pullAllPages({
    required CloudSyncClient client,
    required String mode,
    required int? since,
    required void Function(CloudSyncProgress) notify,
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final collector = _PullCollector(_clock());
    for (var pageNo = 1; pageNo <= cloudSyncMaxPullPages; pageNo += 1) {
      notify(
        CloudSyncProgress(
          phase: CloudSyncPhase.pulling,
          completedSteps: pageNo - 1,
          transferredBytes: collector.wireBytes,
          message: '正在拉取云端数据（第 $pageNo 页）…',
        ),
      );
      final page = await client.pullPage(
        CloudSyncPullRequest(
          mode: mode,
          since: since,
          snapshotAt: collector.snapshotAt,
          cursor: collector.cursor,
        ),
        cancelSignal: cancelSignal,
      );
      collector.absorb(page);
      if (!page.meta.hasMore || page.meta.nextCursor == null) break;
    }
    return collector.finish();
  }

  Future<_PushedBundle> _pushAllBatches({
    required CloudSyncClient client,
    required IncrementalSyncPayload delta,
    required LanSyncSettings identity,
    required int pulledServerNow,
    required void Function(CloudSyncProgress) notify,
    CloudSyncCancelSignal? cancelSignal,
  }) async {
    final batches = splitDeltaIntoPushBatches(delta);
    final meta = CloudSyncPushMeta(
      clientDeviceId: identity.deviceId,
      clientDeviceName: identity.deviceName,
      clientDatasetEpoch: identity.datasetEpoch,
      clientServerNow: delta.serverNow,
      pulledServerNow: pulledServerNow,
    );
    if (batches.isEmpty) {
      return await _pushEmptyCommit(client, meta, cancelSignal);
    }
    return await _pushBatchList(client, batches, meta, notify, cancelSignal);
  }

  Future<_PushedBundle> _pushEmptyCommit(
    CloudSyncClient client,
    CloudSyncPushMeta meta,
    CloudSyncCancelSignal? cancelSignal,
  ) async {
    final reply = await client.pushBatch(
      CloudSyncPushRequest(
        batch: const CloudSyncPushBatch(
          tables: <String, List<Map<String, Object?>>>{},
        ),
        meta: meta,
        commitWatermark: true,
      ),
      cancelSignal: cancelSignal,
    );
    return _PushedBundle(
      summary: reply.summary,
      datasetEpoch: reply.datasetEpoch,
      wireBytes: reply.wireBytes,
    );
  }

  Future<_PushedBundle> _pushBatchList(
    CloudSyncClient client,
    List<CloudSyncPushBatch> batches,
    CloudSyncPushMeta meta,
    void Function(CloudSyncProgress) notify,
    CloudSyncCancelSignal? cancelSignal,
  ) async {
    var totalSummary = CloudSyncSideCounts.zero;
    var latestEpoch = '';
    var totalWireBytes = 0;
    for (var i = 0; i < batches.length; i += 1) {
      final batchNo = i + 1;
      notify(
        CloudSyncProgress(
          phase: CloudSyncPhase.pushing,
          completedSteps: i,
          totalSteps: batches.length,
          transferredBytes: totalWireBytes,
          message: '正在压缩推送本机变更（$batchNo/${batches.length} 批）…',
        ),
      );
      final reply = await client.pushBatch(
        CloudSyncPushRequest(
          batch: batches[i],
          meta: meta,
          commitWatermark: batchNo == batches.length,
        ),
        cancelSignal: cancelSignal,
      );
      totalSummary = totalSummary.accumulate(reply.summary);
      totalWireBytes += reply.wireBytes;
      if (reply.datasetEpoch.isNotEmpty) latestEpoch = reply.datasetEpoch;
    }
    return _PushedBundle(
      summary: totalSummary,
      datasetEpoch: latestEpoch,
      wireBytes: totalWireBytes,
    );
  }

  CloudSyncHandshakeRequest _handshakeRequest(
    LanSyncSettings identity,
    CloudSyncSettings settings,
  ) => CloudSyncHandshakeRequest(
    deviceId: identity.deviceId,
    deviceName: identity.deviceName,
    datasetEpoch: identity.datasetEpoch,
    knownServerEpoch: settings.watermark?.serverDatasetEpoch ?? '',
  );

  int? _effectivePullSince(
    CloudSyncWatermark? watermark,
    CloudSyncHandshakeReply handshake,
  ) {
    if (watermark == null) return null;
    if (watermark.serverDeviceId != handshake.deviceId) return null;
    if (watermark.serverDatasetEpoch != handshake.datasetEpoch) return null;
    return watermark.serverCursorMs > 0 ? watermark.serverCursorMs : null;
  }

  CloudSyncCredential _requireCredential(CloudSyncCredential? credential) {
    if (credential == null || credential.baseUrl.trim().isEmpty) {
      throw const ValidationError(AppErrorCode.cloudSyncNotConfigured);
    }
    final normalized = normalizeCloudSyncBaseUrl(credential.baseUrl);
    if (normalized == null) {
      throw const ValidationError(AppErrorCode.cloudSyncInvalidUrl);
    }
    return CloudSyncCredential(
      baseUrl: normalized,
      password: credential.password,
    );
  }
}

/// 面向界面的云端同步摘要文案。
String formatCloudSyncResultSummary(CloudSyncResult result) {
  if (result.mode == CloudSyncMode.bidirectional) {
    final local =
        '本机 +${result.local.addedWords} 词/+${result.local.addedLogs} 作答';
    final peer = '云端 +${result.peer.addedWords} 词/+${result.peer.addedLogs} 作答';
    return '$local，$peer';
  }
  if (result.mode == CloudSyncMode.pullMerge) {
    final delta =
        '合入 +${result.local.addedWords} 词/+${result.local.addedLogs} 作答';
    return '$delta（共 ${result.local.wordCount} 词）';
  }
  return '已用云端覆盖：共 ${result.local.wordCount} 个词条、${result.local.addedLogs} 条作答';
}

CloudSyncResult _buildMergeResult({
  required LanSyncDeltaSummary summary,
  required CloudSyncSideCounts peerCounts,
  required int totalBytes,
  required bool isIncremental,
  required bool bidirectional,
}) => CloudSyncResult(
  mode: bidirectional ? CloudSyncMode.bidirectional : CloudSyncMode.pullMerge,
  local: CloudSyncSideCounts(
    addedWords: summary.addedWords,
    updatedWords: summary.updatedWords,
    addedLogs: summary.addedLogs,
    rebuiltWords: summary.rebuiltWords,
    wordCount: summary.wordCount,
  ),
  peer: peerCounts,
  transferredBytes: totalBytes,
  isIncremental: isIncremental,
);

String _resolveLatestEpoch(
  _PulledBundle pulled,
  CloudSyncHandshakeReply handshake,
  _PushedBundle? pushed,
) {
  if (pushed != null && pushed.datasetEpoch.isNotEmpty) {
    return pushed.datasetEpoch;
  }
  if (pulled.datasetEpoch.isNotEmpty) return pulled.datasetEpoch;
  return handshake.datasetEpoch;
}

class _PullCollector {
  new(this.serverNow);

  final Map<String, List<Map<String, Object?>>> tables =
      <String, List<Map<String, Object?>>>{};
  final Map<int, Map<String, Object?>> wordRefsById =
      <int, Map<String, Object?>>{};
  Map<String, Object?>? cursor;
  int? snapshotAt;
  int serverNow;
  String datasetEpoch = '';
  bool isIncremental = false;
  int wireBytes = 0;

  void absorb(CloudSyncPullPage page) {
    snapshotAt ??= page.meta.snapshotAt;
    if (page.meta.serverNow > 0) serverNow = page.meta.serverNow;
    if (page.meta.datasetEpoch.isNotEmpty) {
      datasetEpoch = page.meta.datasetEpoch;
    }
    isIncremental = page.isIncremental;
    wireBytes += page.wireBytes;
    cursor = page.meta.nextCursor;
    for (final entry in page.tables.entries) {
      tables
          .putIfAbsent(entry.key, () => <Map<String, Object?>>[])
          .addAll(entry.value);
    }
    for (final ref in page.wordRefs) {
      final id = ref['id'];
      if (id is num) wordRefsById[id.round()] = ref;
    }
  }

  _PulledBundle finish() => _PulledBundle(
    tables: tables,
    wordRefs: wordRefsById.values.toList(growable: false),
    serverNow: serverNow,
    datasetEpoch: datasetEpoch,
    stats: (isIncremental: isIncremental, wireBytes: wireBytes),
  );
}

class _PulledBundle {
  const new({
    required this.tables,
    required this.wordRefs,
    required this.serverNow,
    required this.datasetEpoch,
    required this.stats,
  });

  final Map<String, List<Map<String, Object?>>> tables;
  final List<Map<String, Object?>> wordRefs;
  final int serverNow;
  final String datasetEpoch;
  final ({bool isIncremental, int wireBytes}) stats;

  bool get isIncremental => stats.isIncremental;
  int get wireBytes => stats.wireBytes;
}

class _PushedBundle {
  const new({
    required this.summary,
    required this.datasetEpoch,
    required this.wireBytes,
  });

  final CloudSyncSideCounts summary;
  final String datasetEpoch;
  final int wireBytes;
}

void _ignoreProgress(CloudSyncProgress _) {}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
