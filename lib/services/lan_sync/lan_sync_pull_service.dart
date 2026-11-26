/// 从局域网设备同步数据：支持 v2 双向增量同步、单向增量合并与全量覆盖。
library;

import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/backup/incremental_sync_exporter.dart';
import 'package:lexiloop/data/backup/incremental_sync_payload.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_codec.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_session_client.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/backup_merge_service.dart';
import 'package:lexiloop/services/merge/incremental_merge_service.dart';

/// 一次同步的结果（覆盖、单向合并与双向增量合并统一形态）。
class LanSyncPullResult {
  /// 以各统计字段构造。
  const new({
    required this.mode,
    required this.addedWords,
    required this.updatedWords,
    required this.addedLogs,
    required this.writtenRows,
    required this.wordCount,
    this.isIncremental = false,
    this.rebuiltWords = 0,
    this.peerAddedWords = 0,
    this.peerAddedLogs = 0,
    this.transferredWireBytes = 0,
    this.uncompressedBytes = 0,
  });

  /// 本次用的模式。
  final LanSyncPullMode mode;

  /// 本机新增的词条数。
  final int addedWords;

  /// 本机更新元数据的词条数。
  final int updatedWords;

  /// 本机新增的作答条数。
  final int addedLogs;

  /// 本次写进库的行数。
  final int writtenRows;

  /// 完成后本机的词条总数。
  final int wordCount;

  /// 本次是否命中增量同步。
  final bool isIncremental;

  /// 本机重排 FSRS 的词条数。
  final int rebuiltWords;

  /// 双向模式下对端新增的词条数。
  final int peerAddedWords;

  /// 双向模式下对端新增的作答条数。
  final int peerAddedLogs;

  /// 本次网络实际传输的压缩总字节数。
  final int transferredWireBytes;

  /// 解压前的原始 JSON 总字节数。
  final int uncompressedBytes;
}

/// 局域网同步客户端编排服务。
class LanSyncPullService {
  /// 以客户端工厂、发现器、导入器、全量合并器、状态存储及可选 v2 增量通道构造。
  new(
    this._clientFactory,
    this._discovery,
    this._importer,
    this._merger,
    this._states, {
    this._sessionRunner,
    this._deltaExporter,
    this._incrementalMerger,
    int Function()? clock,
  }) : _clock = clock ?? _wallClockMs;

  final LanSyncClientFactory _clientFactory;
  final LanSyncDiscovery _discovery;
  final BackupImporter _importer;
  final BackupMergeService _merger;
  final LanSyncStateStore _states;
  final LanSyncSessionRunner? _sessionRunner;
  final IncrementalSyncExporter? _deltaExporter;
  final IncrementalMergeService? _incrementalMerger;
  final int Function() _clock;

  /// 搜索同网段的共享设备。
  Future<LanSyncDiscoveryResult> discover({String? excludeInstanceId}) async {
    final result = await _discovery.discover(
      timeout: const Duration(milliseconds: lanSyncDiscoveryTimeoutMs),
    );
    if (excludeInstanceId == null || excludeInstanceId.isEmpty) return result;
    return LanSyncDiscoveryResult(
      hosts: result.hosts
          .where((host) => host.instanceId != excludeInstanceId)
          .toList(growable: false),
      incompatibleHostCount: result.incompatibleHostCount,
    );
  }

  /// 前置校验配对码并取回对端能力与设备信息（不改动本机数据）。
  Future<LanSyncHandshake> verifyPairing({
    required DiscoveredLanHost host,
    required String pairingCode,
  }) => _clientFactory(host, pairingCode).handshake();

  /// 与指定设备执行同步（配置了 v2 通道时自动走增量 + 双向 + 实时进度）。
  Future<LanSyncPullResult> pull({
    required DiscoveredLanHost host,
    required String pairingCode,
    required LanSyncPullMode mode,
    LanSyncHandshake? verifiedHandshake,
    void Function(LanSyncTransferProgress progress)? onProgress,
    LanSyncCancelSignal? cancelSignal,
  }) async {
    final useV2 =
        _sessionRunner != null &&
        _deltaExporter != null &&
        _incrementalMerger != null;
    if (useV2) {
      return await _pullViaV2Session(
        host: host,
        pairingCode: pairingCode,
        mode: mode,
        verifiedHandshake: verifiedHandshake,
        onProgress: onProgress,
        cancelSignal: cancelSignal,
      );
    }
    return await _pullViaLegacyHttp(
      host: host,
      pairingCode: pairingCode,
      mode: mode,
      verifiedHandshake: verifiedHandshake,
    );
  }

  Future<LanSyncPullResult> _pullViaV2Session({
    required DiscoveredLanHost host,
    required String pairingCode,
    required LanSyncPullMode mode,
    LanSyncHandshake? verifiedHandshake,
    void Function(LanSyncTransferProgress progress)? onProgress,
    LanSyncCancelSignal? cancelSignal,
  }) async {
    try {
      final handshake =
          verifiedHandshake ??
          await _clientFactory(host, pairingCode).handshake();
      if (mode == LanSyncPullMode.bidirectional &&
          !handshake.allowsBidirectional) {
        throw const ValidationError(AppErrorCode.lanSyncPeerRejected);
      }
      final settings = await _states.ensureIdentity();
      final knownWm = handshake.deviceId.isEmpty
          ? null
          : settings.peerWatermarks[handshake.deviceId];
      final outcome = await _sessionRunner!(
        LanSyncSessionRequest(
          host: host,
          pairingCode: pairingCode,
          mode: mode,
          local: LanSyncClientContext(
            endpoint: LanSyncEndpoint(
              name: settings.deviceName,
              deviceKind: lanSyncDeviceKind(isDesktop: PlatformCaps.isDesktop),
            ),
            identity: settings.identity,
            knownHostEpoch: knownWm?.peerDatasetEpoch ?? '',
            pullSince: mode == LanSyncPullMode.replace
                ? null
                : knownWm?.peerCursorMs,
          ),
          callbacks: LanSyncSessionCallbacks(
            exportLocalDelta: _exportLocalDeltaForPeer,
            applyIncoming: (bytes, acceptedMode) => _applyIncomingV2(
              bytes: bytes,
              mode: acceptedMode,
              peerDeviceId: handshake.deviceId,
            ),
            onProgress: onProgress ?? _ignoreProgress,
            cancelSignal: cancelSignal,
          ),
        ),
      );
      await _recordV2Watermark(host: host, outcome: outcome);
      return _resultFromOutcome(outcome);
    } on AppError catch (error) {
      if (error.code != AppErrorCode.lanSyncCancelled) {
        await _states.recordFailure(error.code.code);
      }
      rethrow;
    }
  }

  Future<LanSyncWirePayload> _exportLocalDeltaForPeer(int? pushSince) async {
    final settings = await _states.ensureIdentity();
    final payload = await _deltaExporter!.exportDelta(
      datasetEpoch: settings.datasetEpoch,
      since: pushSince,
    );
    final encoded = await encodeJsonGzipWithStats(payload.toEnvelope());
    return LanSyncWirePayload(
      compressedBytes: encoded.compressedBytes,
      uncompressedBytes: encoded.uncompressedBytes,
      totalRows: payload.totalRows,
      isIncremental: payload.isIncremental,
      serverNow: payload.serverNow,
      datasetEpoch: payload.datasetEpoch,
    );
  }

  Future<LanSyncClientApplyResult> _applyIncomingV2({
    required Uint8List bytes,
    required LanSyncPullMode mode,
    required String peerDeviceId,
  }) async {
    if (mode == LanSyncPullMode.replace) {
      final snapshot = await _states.snapshot();
      final raw = await decodeBackupMaybeGzipUtf8(bytes);
      final imported = await _importer.import(raw);
      await _states.restoreAfterReplace(snapshot);
      final refreshed = await _states.ensureIdentity();
      final wordCount = imported.rowCounts['words'] ?? 0;
      return LanSyncClientApplyResult(
        summary: LanSyncDeltaSummary(
          addedWords: wordCount,
          addedLogs: imported.rowCounts['review_logs'] ?? 0,
          wordCount: wordCount,
        ),
        datasetEpoch: refreshed.datasetEpoch,
      );
    }
    final decoded = await decodeJsonObjectMaybeGzip(bytes);
    final delta = parseIncrementalSyncPayload(decoded);
    final summary = await _incrementalMerger!.apply(delta);
    var settings = await _states.ensureIdentity();
    var epoch = settings.datasetEpoch;
    final hasOtherPeers = settings.peerWatermarks.keys.any(
      (id) => id != peerDeviceId,
    );
    if (summary.hasChanges && hasOtherPeers) {
      epoch = (await _states.rotateDatasetEpoch()).datasetEpoch;
      settings = await _states.ensureIdentity();
    }
    return LanSyncClientApplyResult(summary: summary, datasetEpoch: epoch);
  }

  Future<void> _recordV2Watermark({
    required DiscoveredLanHost host,
    required LanSyncSessionOutcome outcome,
  }) async {
    final label = _peerLabel(host, outcome.peerEndpoint.name);
    if (outcome.peerIdentity.deviceId.isEmpty) {
      await _states.recordSuccess(peer: label);
      return;
    }
    await _states.recordPeerSync(
      watermark: LanSyncPeerWatermark(
        peerDeviceId: outcome.peerIdentity.deviceId,
        peerDatasetEpoch: outcome.peerIdentity.datasetEpoch,
        peerCursorMs: outcome.peerServerNow,
        localCursorMs: outcome.localServerNow,
        lastSyncedAt: _clock(),
      ),
      peerLabel: label,
    );
  }

  LanSyncPullResult _resultFromOutcome(LanSyncSessionOutcome outcome) {
    final local = outcome.localSummary;
    final peer = outcome.peerSummary;
    return LanSyncPullResult(
      mode: outcome.mode,
      addedWords: local.addedWords,
      updatedWords: local.updatedWords,
      addedLogs: local.addedLogs,
      writtenRows: local.addedWords + local.addedLogs,
      wordCount: local.wordCount,
      isIncremental: outcome.isIncremental,
      rebuiltWords: local.rebuiltWords,
      peerAddedWords: peer?.addedWords ?? 0,
      peerAddedLogs: peer?.addedLogs ?? 0,
      transferredWireBytes: outcome.transferredWireBytes,
      uncompressedBytes: outcome.uncompressedBytes,
    );
  }

  Future<LanSyncPullResult> _pullViaLegacyHttp({
    required DiscoveredLanHost host,
    required String pairingCode,
    required LanSyncPullMode mode,
    LanSyncHandshake? verifiedHandshake,
  }) async {
    try {
      final client = _clientFactory(host, pairingCode);
      final handshake = verifiedHandshake ?? await client.handshake();
      final snapshot = await _states.snapshot();
      final backup = await client.downloadBackup();
      final raw = await decodeBackupMaybeGzipUtf8(backup.bytes);
      final result = switch (mode) {
        LanSyncPullMode.replace => await _replace(raw),
        LanSyncPullMode.merge ||
        LanSyncPullMode.bidirectional => await _merge(raw),
      };
      if (mode == LanSyncPullMode.replace) {
        await _states.restoreAfterReplace(snapshot);
      } else {
        await _states.restore(snapshot);
      }
      await _states.recordSuccess(peer: _peerLabel(host, handshake.deviceName));
      return result;
    } on AppError catch (error) {
      await _states.recordFailure(error.code.code);
      rethrow;
    }
  }

  Future<LanSyncPullResult> _merge(String raw) async {
    final outcome = await _merger.merge(raw);
    final counts = outcome.counts;
    return LanSyncPullResult(
      mode: LanSyncPullMode.merge,
      addedWords: counts.addedWords,
      updatedWords: counts.updatedWords,
      addedLogs: counts.addedLogs,
      writtenRows: counts.addedWords + counts.addedLogs + counts.addedSessions,
      wordCount: outcome.tables['words']?.length ?? 0,
      rebuiltWords: counts.rebuiltWords,
    );
  }

  Future<LanSyncPullResult> _replace(String raw) async {
    final imported = await _importer.import(raw);
    final words = imported.rowCounts['words'] ?? 0;
    return LanSyncPullResult(
      mode: LanSyncPullMode.replace,
      addedWords: words,
      updatedWords: 0,
      addedLogs: imported.rowCounts['review_logs'] ?? 0,
      writtenRows: imported.totalRows,
      wordCount: words,
    );
  }

  String _peerLabel(DiscoveredLanHost host, String handshakeName) =>
      handshakeName.isEmpty ? host.label : '$handshakeName（${host.address}）';
}

void _ignoreProgress(LanSyncTransferProgress _) {}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
