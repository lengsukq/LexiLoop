/// 共享会话的编排：配对码、服务端生命周期、v2 双向增量委托与双端进度发布。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/backup/incremental_sync_exporter.dart';
import 'package:lexiloop/data/backup/incremental_sync_payload.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_codec.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/incremental_merge_service.dart';

/// 一次共享会话的对外快照（含主机侧实时同步进度以驱动双端动画）。
class LanSyncShareSession {
  /// 以各字段构造。
  const new({
    required this.pairingCode,
    required this.instanceId,
    required this.deviceName,
    required this.baseUri,
    required this.servedCount,
    required this.lockedOut,
    this.deviceKind = '',
    this.sharePolicy = LanSyncSharePolicy.bidirectional,
    this.liveProgress,
    this.dataRevision = 0,
  });

  /// 本次会话的 6 位数字配对码。
  final String pairingCode;

  /// 本次会话的随机标识。
  final String instanceId;

  /// 本机展示名。
  final String deviceName;

  /// 对端该连的根地址（仅用于界面展示）。
  final Uri baseUri;

  /// 已经成功服务过多少次同步。
  final int servedCount;

  /// 是否因配对码连续错误而被自动停止。
  final bool lockedOut;

  /// 本机设备类型（桌面 / 手机）。
  final String deviceKind;

  /// 当前会话的共享策略（双向合并 / 只读）。
  final LanSyncSharePolicy sharePolicy;

  /// 主机侧当前或最近一次同步的实时进度快照（驱动「双端词环共振桥」动画）。
  final LanSyncTransferProgress? liveProgress;

  /// 主机因双向合并写入本地数据的修订号（递增时界面触发读库缓存失效）。
  final int dataRevision;

  /// 是否仍在正常共享。
  bool get isSharing => !lockedOut;

  /// 覆盖若干字段，其余原样保留。
  LanSyncShareSession copyWith({
    int? servedCount,
    bool? lockedOut,
    LanSyncTransferProgress? liveProgress,
    bool clearLiveProgress = false,
    int? dataRevision,
  }) => LanSyncShareSession(
    pairingCode: pairingCode,
    instanceId: instanceId,
    deviceName: deviceName,
    baseUri: baseUri,
    servedCount: servedCount ?? this.servedCount,
    lockedOut: lockedOut ?? this.lockedOut,
    deviceKind: deviceKind,
    sharePolicy: sharePolicy,
    liveProgress: clearLiveProgress
        ? null
        : (liveProgress ?? this.liveProgress),
    dataRevision: dataRevision ?? this.dataRevision,
  );
}

/// 共享服务端会话的编排。
class LanSyncShareService {
  /// 以导出器、服务端启动器、状态存储及可选增量引擎构造。
  new(
    this._exporter,
    this._starter,
    this._states, {
    this._deltaExporter,
    this._incrementalMerger,
    String Function()? codeGenerator,
    String Function()? instanceIdGenerator,
    int Function()? clock,
  }) : _generateCode = codeGenerator ?? _randomPairingCode,
       _generateInstanceId = instanceIdGenerator ?? _randomInstanceId,
       _clock = clock ?? _wallClockMs;

  final BackupExporter _exporter;
  final LanSyncHostStarter _starter;
  final LanSyncStateStore _states;
  final IncrementalSyncExporter? _deltaExporter;
  final IncrementalMergeService? _incrementalMerger;
  final String Function() _generateCode;
  final String Function() _generateInstanceId;
  final int Function() _clock;

  LanSyncHost? _host;
  LanSyncShareSession? _session;
  void Function()? _notifyServed;
  void Function()? _notifyLockedOut;
  void Function()? _notifyProgress;

  /// 当前共享会话；未共享时为 `null`。
  LanSyncShareSession? get session => _session;

  /// 是否已经开启共享。
  bool get isSharing => _session?.isSharing ?? false;

  /// 开启共享；已经开着时原样返回同一会话。
  Future<LanSyncShareSession> start({
    required void Function() onServed,
    required void Function() onLockedOut,
    void Function()? onProgress,
  }) async {
    final existing = _session;
    if (existing != null && existing.isSharing) return existing;

    _notifyServed = onServed;
    _notifyLockedOut = onLockedOut;
    _notifyProgress = onProgress;
    await _host?.stop();
    _host = null;

    final settings = await _states.ensureIdentity();
    final code = _generateCode();
    final instanceId = _generateInstanceId();
    final kind = lanSyncDeviceKind(isDesktop: PlatformCaps.isDesktop);
    final allowsBidi = settings.sharePolicy == LanSyncSharePolicy.bidirectional;
    final host = await _starter(
      LanSyncHostOptions(
        deviceName: settings.deviceName,
        port: settings.port,
        pairingCode: code,
        instanceId: instanceId,
        deviceId: settings.deviceId,
        deviceKind: kind,
        datasetEpoch: settings.datasetEpoch,
        allowsBidirectional: allowsBidi,
        backupSource: _exportBackup,
        sessionDelegate: _buildSessionDelegate(),
        onServed: _handleServed,
        onCodeLockout: _handleCodeLockout,
      ),
    );
    _host = host;
    _session = LanSyncShareSession(
      pairingCode: code,
      instanceId: instanceId,
      deviceName: settings.deviceName,
      baseUri: host.baseUri,
      servedCount: host.servedCount,
      lockedOut: false,
      deviceKind: kind,
      sharePolicy: settings.sharePolicy,
    );
    return _session!;
  }

  /// 停止共享；可重复调用。
  Future<void> stop() async {
    final host = _host;
    _host = null;
    _session = null;
    await host?.stop();
  }

  /// 清除主机卡片上保留的上次同步动画卡片，回到等待连接状态。
  void dismissLiveProgress() {
    if (_session == null) return;
    _session = _session?.copyWith(clearLiveProgress: true);
    _notifyProgress?.call();
  }

  LanSyncSessionDelegate? _buildSessionDelegate() {
    final delta = _deltaExporter;
    final merger = _incrementalMerger;
    if (delta == null || merger == null) return null;
    return _HostSessionDelegate(
      states: _states,
      exporter: _exporter,
      deltaExporter: delta,
      merger: merger,
      clock: _clock,
      onProgress: _handleProgress,
      onDataChanged: _handleDataChanged,
    );
  }

  Future<LanSyncBackup> _exportBackup() async {
    final exported = await _exporter.exportToJson();
    return LanSyncBackup(
      bytes: exported.bytes,
      fileName: backupFileName(DateTime.now()),
      totalRows: exported.totalRows,
    );
  }

  void _handleServed(int servedCount) {
    _session = _session?.copyWith(servedCount: servedCount);
    _notifyServed?.call();
  }

  void _handleCodeLockout() {
    _session = _session?.copyWith(lockedOut: true);
    _notifyLockedOut?.call();
  }

  void _handleProgress(LanSyncTransferProgress progress) {
    _session = _session?.copyWith(liveProgress: progress);
    _notifyProgress?.call();
  }

  void _handleDataChanged() {
    final current = _session;
    if (current == null) return;
    _session = current.copyWith(dataRevision: current.dataRevision + 1);
    _notifyProgress?.call();
  }
}

class _HostSessionDelegate implements LanSyncSessionDelegate {
  const new({
    required this.states,
    required this.exporter,
    required this.deltaExporter,
    required this.merger,
    required this.clock,
    required this.onProgress,
    required this.onDataChanged,
  });

  final LanSyncStateStore states;
  final BackupExporter exporter;
  final IncrementalSyncExporter deltaExporter;
  final IncrementalMergeService merger;
  final int Function() clock;
  final void Function(LanSyncTransferProgress progress) onProgress;
  final void Function() onDataChanged;

  @override
  Future<LanSyncSessionHelloReply> negotiateSession(
    LanSyncSessionHello hello,
  ) async {
    final settings = await states.ensureIdentity();
    if (hello.mode == LanSyncPullMode.bidirectional &&
        settings.sharePolicy != LanSyncSharePolicy.bidirectional) {
      throw const ValidationError(AppErrorCode.lanSyncPeerRejected);
    }
    final pullSince =
        hello.mode != LanSyncPullMode.replace &&
            hello.pullSince != null &&
            hello.knownHostEpoch == settings.datasetEpoch
        ? hello.pullSince
        : null;
    final peerWm = settings.peerWatermarks[hello.deviceId];
    final pushSince =
        hello.mode == LanSyncPullMode.bidirectional &&
            peerWm != null &&
            peerWm.peerDatasetEpoch == hello.datasetEpoch &&
            peerWm.peerCursorMs > 0
        ? peerWm.peerCursorMs
        : null;
    return LanSyncSessionHelloReply(
      acceptedMode: hello.mode,
      hostEndpoint: LanSyncEndpoint(
        name: settings.deviceName,
        deviceKind: lanSyncDeviceKind(isDesktop: PlatformCaps.isDesktop),
      ),
      hostIdentity: settings.identity,
      effectivePullSince: pullSince,
      pushSince: pushSince,
    );
  }

  @override
  Future<LanSyncWirePayload> exportForSession({
    required LanSyncPullMode mode,
    required int? since,
  }) async {
    final settings = await states.ensureIdentity();
    if (mode == LanSyncPullMode.replace) {
      final exported = await exporter.exportToJson();
      final compressed = await compressLanSyncBytes(exported.bytes);
      return LanSyncWirePayload(
        compressedBytes: compressed,
        uncompressedBytes: exported.bytes.length,
        totalRows: exported.totalRows,
        isIncremental: false,
        serverNow: clock(),
        datasetEpoch: settings.datasetEpoch,
      );
    }
    final payload = await deltaExporter.exportDelta(
      datasetEpoch: settings.datasetEpoch,
      since: since,
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

  @override
  Future<LanSyncHostApplyResult> applyIncomingDelta({
    required Uint8List compressedBytes,
    required LanSyncSessionHello peer,
    required int localServerNow,
  }) async {
    final decoded = await decodeJsonObjectMaybeGzip(compressedBytes);
    final delta = parseIncrementalSyncPayload(decoded);
    final summary = await merger.apply(delta);
    var settings = await states.ensureIdentity();
    var latestEpoch = settings.datasetEpoch;
    final hasOtherPeers = settings.peerWatermarks.keys.any(
      (id) => id != peer.deviceId,
    );
    if (summary.hasChanges && hasOtherPeers) {
      latestEpoch = (await states.rotateDatasetEpoch()).datasetEpoch;
      settings = await states.ensureIdentity();
    }
    if (peer.deviceId.isNotEmpty) {
      await states.recordPeerSync(
        watermark: LanSyncPeerWatermark(
          peerDeviceId: peer.deviceId,
          peerDatasetEpoch: delta.datasetEpoch.isEmpty
              ? peer.datasetEpoch
              : delta.datasetEpoch,
          peerCursorMs: delta.serverNow,
          localCursorMs: localServerNow,
          lastSyncedAt: clock(),
        ),
        peerLabel: peer.deviceName.isEmpty ? peer.deviceId : peer.deviceName,
      );
    }
    if (summary.hasChanges) onDataChanged();
    return LanSyncHostApplyResult(summary: summary, datasetEpoch: latestEpoch);
  }

  @override
  Future<void> recordOneWayServed({
    required LanSyncSessionHello peer,
    required int localServerNow,
  }) async {
    if (peer.deviceId.isEmpty) return;
    final current =
        (await states.ensureIdentity()).peerWatermarks[peer.deviceId];
    await states.recordPeerSync(
      watermark: LanSyncPeerWatermark(
        peerDeviceId: peer.deviceId,
        peerDatasetEpoch: current?.peerDatasetEpoch ?? peer.datasetEpoch,
        peerCursorMs: current?.peerCursorMs ?? 0,
        localCursorMs: localServerNow,
        lastSyncedAt: clock(),
      ),
      peerLabel: peer.deviceName.isEmpty ? peer.deviceId : peer.deviceName,
    );
  }

  @override
  void onSessionProgress(LanSyncTransferProgress progress) =>
      onProgress(progress);
}

String _randomPairingCode() =>
    _randomToken(lanSyncPairingCodeAlphabet, lanSyncPairingCodeLength);

String _randomInstanceId() =>
    _randomToken(lanSyncInstanceIdAlphabet, lanSyncInstanceIdLength);

String _randomToken(String alphabet, int length) {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < length; index += 1) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
