/// 客户端 v2 WebSocket 双向增量会话执行器（`dart:io`，仅原生端）。
///
/// 通过一条 WebSocket 长连接完成：
/// 握手 → 接收主机压缩增量（确定性进环）→（双向时）推送本机压缩增量 →
/// 双端并行落库与 FSRS 重放 → 接收主机战果摘要 → 双端同频完成。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_session_client_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_ws_wire_native.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 执行一次客户端侧 v2 WebSocket 同步会话。
Future<LanSyncSessionOutcome> runLanSyncClientSession(
  LanSyncSessionRequest request,
) => _ClientSessionRunner(request).run();

class _ClientSessionRunner {
  new(this.request);

  final LanSyncSessionRequest request;

  static const Duration _ctrlTimeout = Duration(
    milliseconds: lanSyncRequestTimeoutMs,
  );
  static const Duration _ioTimeout = Duration(
    milliseconds: lanSyncTransferTimeoutMs,
  );

  late LanSyncTransferProgress _progress;

  bool get _isCancelled => request.callbacks.cancelSignal?.isCancelled ?? false;

  Future<LanSyncSessionOutcome> run() async {
    _publish(_initialProgress());
    final socket = await _connect();
    final cancelSub = request.callbacks.cancelSignal?.onCancel.then<void>(
      (_) => socket.close(),
    );
    final frames = StreamIterator<dynamic>(socket);
    try {
      return await _execute(socket, frames);
    } on AppError catch (error) {
      trySendWsError(socket, error.code);
      _publishFailed(error.code.code);
      rethrow;
    } on Object catch (error) {
      final mapped = _mapUnexpectedFailure(error);
      _publishFailed(mapped.code.code);
      throw mapped;
    } finally {
      unawaited(cancelSub);
      await frames.cancel();
      await socket.close(WebSocketStatus.normalClosure);
    }
  }

  LanSyncTransferProgress _initialProgress() => LanSyncTransferProgress(
    phase: LanSyncPhase.connecting,
    direction: request.mode == LanSyncPullMode.bidirectional
        ? LanSyncDirection.bidirectional
        : LanSyncDirection.pullOnly,
    local: request.local.endpoint,
    peer: LanSyncEndpoint(
      name: request.host.deviceName.isEmpty
          ? request.host.address
          : request.host.deviceName,
      deviceKind: request.host.deviceKind,
      address: '${request.host.address}:${request.host.port}',
    ),
  );

  AppError _mapUnexpectedFailure(Object error) {
    if (_isCancelled) {
      return const ValidationError(AppErrorCode.lanSyncCancelled);
    }
    final isTransport =
        error is SocketException ||
        error is WebSocketException ||
        error is TimeoutException ||
        error is HttpException;
    return ExternalServiceError(
      isTransport
          ? AppErrorCode.lanSyncUnreachable
          : AppErrorCode.lanSyncRequestFailed,
      isTransient: true,
      details: error,
    );
  }

  Future<WebSocket> _connect() async {
    final wsUri = request.host.baseUri
        .replace(scheme: 'ws')
        .resolve(lanSyncSessionPath);
    try {
      final socket = await WebSocket.connect(
        wsUri.toString(),
        headers: <String, Object>{lanSyncCodeHeader: request.pairingCode},
        compression: CompressionOptions.compressionOff,
      ).timeout(_ctrlTimeout);
      socket.pingInterval = const Duration(
        milliseconds: lanSyncWsPingIntervalMs,
      );
      return socket;
    } on Object catch (error) {
      final mapped = mapWsConnectException(error);
      _publishFailed(mapped.code.code);
      throw mapped;
    }
  }

  Future<LanSyncSessionOutcome> _execute(
    WebSocket socket,
    StreamIterator<dynamic> frames,
  ) async {
    _sendHello(socket);
    final ack = await _readHelloAck(frames);
    final isBidi = ack.acceptedMode == LanSyncPullMode.bidirectional;
    final pull = await _receiveHostPayload(frames);

    // 必须在合并主机数据「之前」导出本机增量，避免把刚拉来的数据原样回传给主机。
    var localServerNow = 0;
    if (isBidi) {
      final wire = await request.callbacks.exportLocalDelta(ack.pushSince);
      localServerNow = wire.serverNow;
      await _sendClientPayload(socket, wire);
    }

    _publish(_progress.copyWith(phase: LanSyncPhase.merging));
    sendWsJson(socket, const <String, Object?>{
      'type': LanSyncWsType.stage,
      'stage': 'merging',
    });

    final applied = await request.callbacks.applyIncoming(
      pull.bytes,
      ack.acceptedMode,
    );
    sendWsJson(socket, <String, Object?>{
      'type': LanSyncWsType.clientDone,
      'datasetEpoch': applied.datasetEpoch,
      'summary': applied.summary.toJson(),
    });

    final hostDone = await readWsJson(frames, timeout: _ioTimeout);
    if (hostDone['type'] != LanSyncWsType.hostDone) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    final peerSummary = hostDone['summary'] == null
        ? null
        : LanSyncDeltaSummary.fromJson(hostDone['summary']);
    final latestHostEpoch = _str(hostDone['datasetEpoch']);
    final finalEpoch = latestHostEpoch.isEmpty
        ? ack.hostIdentity.datasetEpoch
        : latestHostEpoch;

    _publish(
      _progress.copyWith(
        phase: LanSyncPhase.completed,
        detail: _progress.detail.copyWith(
          localSummary: applied.summary,
          peerSummary: peerSummary,
        ),
      ),
    );
    return LanSyncSessionOutcome(
      mode: ack.acceptedMode,
      isIncremental: _progress.detail.isIncremental,
      peerEndpoint: ack.hostEndpoint,
      peerIdentity: LanSyncIdentity(
        deviceId: ack.hostIdentity.deviceId,
        datasetEpoch: finalEpoch,
      ),
      localSummary: applied.summary,
      peerSummary: peerSummary,
      peerServerNow: pull.serverNow,
      localServerNow: localServerNow,
      transferredWireBytes: _progress.detail.bytes.transferredWireBytes,
      uncompressedBytes: _progress.detail.bytes.uncompressedBytes,
    );
  }

  void _sendHello(WebSocket socket) {
    final local = request.local;
    sendWsJson(socket, <String, Object?>{
      'type': LanSyncWsType.hello,
      'protocolVersion': lanSyncProtocolVersion,
      'deviceId': local.identity.deviceId,
      'deviceName': local.endpoint.name,
      'deviceKind': local.endpoint.deviceKind,
      'datasetEpoch': local.identity.datasetEpoch,
      'mode': request.mode.wire,
      'knownHostEpoch': local.knownHostEpoch,
      if (local.pullSince != null) 'pullSince': local.pullSince,
    });
  }

  Future<_HelloAck> _readHelloAck(StreamIterator<dynamic> frames) async {
    final ack = await readWsJson(frames, timeout: _ctrlTimeout);
    if (ack['type'] != LanSyncWsType.helloAck) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    final version = ack['protocolVersion'];
    if (version is! num || version.round() != lanSyncProtocolVersion) {
      throw const ExternalServiceError(AppErrorCode.lanSyncProtocolMismatch);
    }
    final accepted = LanSyncPullMode.fromWire(_str(ack['acceptedMode']));
    final endpoint = _endpointFromAck(ack);
    final pushSinceRaw = ack['pushSince'];
    _publish(
      _progress.copyWith(
        phase: LanSyncPhase.diffing,
        direction: accepted == LanSyncPullMode.bidirectional
            ? LanSyncDirection.bidirectional
            : LanSyncDirection.pullOnly,
        peer: endpoint,
        detail: _progress.detail.copyWith(
          isIncremental: ack['isPullIncremental'] == true,
        ),
      ),
    );
    return _HelloAck(
      acceptedMode: accepted,
      hostEndpoint: endpoint,
      hostIdentity: LanSyncIdentity(
        deviceId: _str(ack['deviceId']),
        datasetEpoch: _str(ack['datasetEpoch']),
      ),
      pushSince: pushSinceRaw is num && pushSinceRaw > 0
          ? pushSinceRaw.round()
          : null,
    );
  }

  LanSyncEndpoint _endpointFromAck(Map<String, Object?> ack) {
    final hostName = _str(ack['deviceName']);
    return LanSyncEndpoint(
      name: hostName.isEmpty ? request.host.address : hostName,
      deviceKind: _str(ack['deviceKind']),
      address: '${request.host.address}:${request.host.port}',
    );
  }

  Future<({Uint8List bytes, int serverNow})> _receiveHostPayload(
    StreamIterator<dynamic> frames,
  ) async {
    final meta = await readWsJson(frames, timeout: _ioTimeout);
    if (meta['type'] != LanSyncWsType.pullMeta) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    final total = _int(meta['totalBytes']);
    final uncompressed = _int(meta['uncompressedBytes']);
    final isIncremental = meta['isIncremental'] == true;
    final serverNow = _int(meta['serverNow']);
    _publish(
      _progress.copyWith(
        phase: LanSyncPhase.transferring,
        detail: _progress.detail.copyWith(
          isIncremental: isIncremental,
          bytes: _progress.detail.bytes.copyWith(
            totalReceiveBytes: total,
            uncompressedBytes:
                _progress.detail.bytes.uncompressedBytes + uncompressed,
          ),
        ),
      ),
    );
    final bytes = await readWsBinaryUntilEnd(
      frames,
      endType: LanSyncWsType.pullEnd,
      timeout: _ioTimeout,
      isCancelled: () => _isCancelled,
      onChunk: (received) => _publish(
        _progress.copyWith(
          detail: _progress.detail.copyWith(
            bytes: _progress.detail.bytes.copyWith(receivedBytes: received),
          ),
        ),
      ),
    );
    return (bytes: bytes, serverNow: serverNow);
  }

  Future<void> _sendClientPayload(
    WebSocket socket,
    LanSyncWirePayload wire,
  ) async {
    _publish(
      _progress.copyWith(
        phase: LanSyncPhase.transferring,
        detail: _progress.detail.copyWith(
          isIncremental: _progress.detail.isIncremental && wire.isIncremental,
          bytes: _progress.detail.bytes.copyWith(
            totalSendBytes: wire.compressedBytes.length,
            uncompressedBytes:
                _progress.detail.bytes.uncompressedBytes +
                wire.uncompressedBytes,
          ),
        ),
      ),
    );
    sendWsJson(socket, wire.toMetaFrame(LanSyncWsType.pushMeta));
    await sendWsChunkedBytes(
      socket,
      wire.compressedBytes,
      isCancelled: () => _isCancelled,
      onChunk: (sent) => _publish(
        _progress.copyWith(
          detail: _progress.detail.copyWith(
            bytes: _progress.detail.bytes.copyWith(sentBytes: sent),
          ),
        ),
      ),
    );
    sendWsJson(socket, const <String, Object?>{'type': LanSyncWsType.pushEnd});
  }

  void _publish(LanSyncTransferProgress next) {
    _progress = next;
    request.callbacks.onProgress(next);
  }

  void _publishFailed(String code) {
    _publish(
      _progress.copyWith(
        phase: LanSyncPhase.failed,
        detail: _progress.detail.copyWith(errorCode: code),
      ),
    );
  }
}

class _HelloAck {
  const new({
    required this.acceptedMode,
    required this.hostEndpoint,
    required this.hostIdentity,
    this.pushSince,
  });

  final LanSyncPullMode acceptedMode;
  final LanSyncEndpoint hostEndpoint;
  final LanSyncIdentity hostIdentity;
  final int? pushSince;
}

int _int(Object? value) => value is num ? value.round() : 0;

String _str(Object? value) => value is String ? value.trim() : '';
