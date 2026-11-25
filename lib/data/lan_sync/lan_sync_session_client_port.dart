/// 局域网 v2 WebSocket 双向增量会话客户端的抽象端口。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 可取消同步的轻量信号对象。
class LanSyncCancelSignal {
  /// 创建未取消的信号。
  new();

  final Completer<void> _completer = Completer<void>();

  /// 是否已被取消。
  bool get isCancelled => _completer.isCompleted;

  /// 在被取消时完成的 Future。
  Future<void> get onCancel => _completer.future;

  /// 触发取消（幂等）。
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// 客户端本地身份与对端记忆水位上下文。
class LanSyncClientContext {
  /// 以本机端点、身份与对端水位构造。
  const new({
    required this.endpoint,
    required this.identity,
    this.knownHostEpoch = '',
    this.pullSince,
  });

  /// 本机展示信息。
  final LanSyncEndpoint endpoint;

  /// 本机持久化身份与纪元。
  final LanSyncIdentity identity;

  /// 上次同步时记住的对端数据集纪元。
  final String knownHostEpoch;

  /// 上次从对端拉取的水位时钟；无记录时为 `null`。
  final int? pullSince;
}

/// 客户端落库远端载荷后的结果。
class LanSyncClientApplyResult {
  /// 以摘要与落库后的最新纪元构造。
  const new({required this.summary, required this.datasetEpoch});

  /// 本机本次新增/更新统计。
  final LanSyncDeltaSummary summary;

  /// 落库后的本机数据集纪元。
  final String datasetEpoch;
}

/// 会话编排注入的业务回调集。
class LanSyncSessionCallbacks {
  /// 以导出、落库与进度回调构造。
  const new({
    required this.exportLocalDelta,
    required this.applyIncoming,
    required this.onProgress,
    this.cancelSignal,
  });

  /// 双向模式下导出本机增量（参数为对端要求的 `pushSince`）。
  final Future<LanSyncWirePayload> Function(int? pushSince) exportLocalDelta;

  /// 落库主机发来的压缩载荷。
  final Future<LanSyncClientApplyResult> Function(
    Uint8List compressedBytes,
    LanSyncPullMode mode,
  )
  applyIncoming;

  /// 实时进度回调，用于驱动双端同步动画。
  final void Function(LanSyncTransferProgress progress) onProgress;

  /// 可选取消信号。
  final LanSyncCancelSignal? cancelSignal;
}

/// 发起一次 v2 同步会话的完整请求参数。
class LanSyncSessionRequest {
  /// 以目标主机、配对码、模式、本地上下文与回调构造。
  const new({
    required this.host,
    required this.pairingCode,
    required this.mode,
    required this.local,
    required this.callbacks,
  });

  /// 目标对端主机。
  final DiscoveredLanHost host;

  /// 6 位配对码。
  final String pairingCode;

  /// 本次请求的同步模式。
  final LanSyncPullMode mode;

  /// 本机身份与水位上下文。
  final LanSyncClientContext local;

  /// 导出、落库与进度回调。
  final LanSyncSessionCallbacks callbacks;
}

/// 一次 v2 会话完成后的综合结果。
class LanSyncSessionOutcome {
  /// 以模式、主机信息、双侧摘要与双侧水位构造。
  const new({
    required this.mode,
    required this.isIncremental,
    required this.peerEndpoint,
    required this.peerIdentity,
    required this.localSummary,
    this.peerSummary,
    this.peerServerNow = 0,
    this.localServerNow = 0,
    this.transferredWireBytes = 0,
    this.uncompressedBytes = 0,
  });

  /// 实际执行的同步模式。
  final LanSyncPullMode mode;

  /// 是否命中增量同步。
  final bool isIncremental;

  /// 对端展示信息。
  final LanSyncEndpoint peerEndpoint;

  /// 对端最新身份与数据集纪元。
  final LanSyncIdentity peerIdentity;

  /// 本机合并/覆盖摘要。
  final LanSyncDeltaSummary localSummary;

  /// 对端合并摘要（双向模式非空）。
  final LanSyncDeltaSummary? peerSummary;

  /// 主机本次导出快照时钟（供保存为下次 `peerCursorMs`）。
  final int peerServerNow;

  /// 本机本次导出快照时钟（供保存为下次 `localCursorMs`）。
  final int localServerNow;

  /// 本次双向/单向实际传输的压缩字节总量。
  final int transferredWireBytes;

  /// 解压前原始 JSON 字节总量。
  final int uncompressedBytes;
}

/// 执行一次 v2 WebSocket 双向增量同步会话。
typedef LanSyncSessionRunner = Future<LanSyncSessionOutcome> Function(
  LanSyncSessionRequest request,
);
