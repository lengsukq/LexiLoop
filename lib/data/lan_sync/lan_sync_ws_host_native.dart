/// 主机端 v2 WebSocket 双向增量会话执行器（`dart:io`，仅原生端）。
///
/// 全程驱动主机端的「双端词环共振桥」实时状态：
/// 握手协商 → 下发增量分片 →（双向时）接收客户端增量分片 → 双端并行落库 →
/// 交换合并摘要 → 双端同频完成。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_ws_wire_native.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 在已鉴权的 [socket] 上执行一次主机侧 v2 同步会话。
Future<void> runLanSyncHostSession({
  required WebSocket socket,
  required LanSyncSessionDelegate delegate,
  required LanSyncEndpoint localEndpoint,
  required String peerAddress,
}) async {
  final runner = _HostSessionRunner(
    socket: socket,
    delegate: delegate,
    localEndpoint: localEndpoint,
    peerAddress: peerAddress,
  );
  await runner.run();
}

class _HostSessionRunner {
  new({
    required this.socket,
    required this.delegate,
    required this.localEndpoint,
    required this.peerAddress,
  });

  final WebSocket socket;
  final LanSyncSessionDelegate delegate;
  final LanSyncEndpoint localEndpoint;
  final String peerAddress;

  static const Duration _ctrlTimeout = Duration(
    milliseconds: lanSyncRequestTimeoutMs,
  );
  static const Duration _ioTimeout = Duration(
    milliseconds: lanSyncTransferTimeoutMs,
  );

  late LanSyncTransferProgress _progress;

  Future<void> run() async {
    _progress = LanSyncTransferProgress(
      phase: LanSyncPhase.connecting,
      direction: LanSyncDirection.pushOnly,
      local: localEndpoint,
    );
    delegate.onSessionProgress(_progress);
    final frames = StreamIterator<dynamic>(socket);
    try {
      await _execute(frames);
    } on AppError catch (error) {
      await _sendErrorAndFlush(error.code);
      _publishFailed(error.code.code);
      rethrow;
    } on Object {
      await _sendErrorAndFlush(AppErrorCode.lanSyncRequestFailed);
      _publishFailed(AppErrorCode.lanSyncRequestFailed.code);
      rethrow;
    } finally {
      await frames.cancel();
      await socket.close(WebSocketStatus.normalClosure);
    }
  }

  Future<void> _execute(StreamIterator<dynamic> frames) async {
    final hello = _parseHello(await readWsJson(frames, timeout: _ctrlTimeout));
    final reply = await _negotiateAndPublish(hello);
    final isBidi = reply.acceptedMode == LanSyncPullMode.bidirectional;
    final wire = await delegate.exportForSession(
      mode: reply.acceptedMode,
      since: reply.effectivePullSince,
    );
    await _sendHostPayload(wire);

    Future<LanSyncHostApplyResult>? hostApplyFuture;
    if (isBidi) {
      final incomingBytes = await _receiveClientPayload(frames);
      _publish(_progress.copyWith(phase: LanSyncPhase.merging));
      hostApplyFuture = delegate.applyIncomingDelta(
        compressedBytes: incomingBytes,
        peer: hello,
        localServerNow: wire.serverNow,
      );
    }
    await _finishSession(
      frames: frames,
      hello: hello,
      reply: reply,
      localServerNow: wire.serverNow,
      hostApplyFuture: hostApplyFuture,
    );
  }

  Future<LanSyncSessionHelloReply> _negotiateAndPublish(
    LanSyncSessionHello hello,
  ) async {
    final reply = await delegate.negotiateSession(hello);
    final peer = LanSyncEndpoint(
      name: hello.deviceName.isEmpty ? peerAddress : hello.deviceName,
      deviceKind: hello.deviceKind,
      address: peerAddress,
    );
    final direction = reply.acceptedMode == LanSyncPullMode.bidirectional
        ? LanSyncDirection.bidirectional
        : LanSyncDirection.pushOnly;
    _publish(
      LanSyncTransferProgress(
        phase: LanSyncPhase.diffing,
        direction: direction,
        local: reply.hostEndpoint,
        peer: peer,
        detail: LanSyncProgressDetail(
          isIncremental: reply.effectivePullSince != null,
        ),
      ),
    );
    _sendHelloAck(reply);
    return reply;
  }

  Future<void> _finishSession({
    required StreamIterator<dynamic> frames,
    required LanSyncSessionHello hello,
    required LanSyncSessionHelloReply reply,
    required int localServerNow,
    required Future<LanSyncHostApplyResult>? hostApplyFuture,
  }) async {
    final clientSummary = await _waitForClientDone(frames);
    final hostApply = hostApplyFuture == null ? null : await hostApplyFuture;
    if (hostApplyFuture == null) {
      await delegate.recordOneWayServed(
        peer: hello,
        localServerNow: localServerNow,
      );
    }
    final latestEpoch =
        hostApply?.datasetEpoch ?? reply.hostIdentity.datasetEpoch;
    sendWsJson(socket, <String, Object?>{
      'type': LanSyncWsType.hostDone,
      'datasetEpoch': latestEpoch,
      if (hostApply != null) 'summary': hostApply.summary.toJson(),
    });
    _publish(
      _progress.copyWith(
        phase: LanSyncPhase.completed,
        detail: _progress.detail.copyWith(
          localSummary: hostApply?.summary,
          peerSummary: clientSummary,
        ),
      ),
    );
    // 等待客户端收完 `host_done` 并先发 Close 帧，避免服务端过早关断导致对端 EOF。
    await _awaitPeerClose(frames);
  }

  Future<void> _awaitPeerClose(StreamIterator<dynamic> frames) async {
    try {
      await frames.moveNext().timeout(
        const Duration(milliseconds: lanSyncWsCloseGraceMs),
        onTimeout: () => false,
      );
    } on Object {
      // 对端已断开，属于正常收尾。
    }
  }

  Future<void> _sendErrorAndFlush(AppErrorCode code) async {
    trySendWsError(socket, code);
    await Future<void>.delayed(
      const Duration(milliseconds: lanSyncWsErrorFlushMs),
    );
  }

  void _sendHelloAck(LanSyncSessionHelloReply reply) {
    sendWsJson(socket, <String, Object?>{
      'type': LanSyncWsType.helloAck,
      'protocolVersion': lanSyncProtocolVersion,
      'deviceId': reply.hostIdentity.deviceId,
      'deviceName': reply.hostEndpoint.name,
      'deviceKind': reply.hostEndpoint.deviceKind,
      'datasetEpoch': reply.hostIdentity.datasetEpoch,
      'acceptedMode': reply.acceptedMode.wire,
      'isPullIncremental': reply.effectivePullSince != null,
      if (reply.pushSince != null) 'pushSince': reply.pushSince,
    });
  }

  Future<void> _sendHostPayload(LanSyncWirePayload wire) async {
    final bytes = _progress.detail.bytes.copyWith(
      totalSendBytes: wire.compressedBytes.length,
      uncompressedBytes:
          _progress.detail.bytes.uncompressedBytes + wire.uncompressedBytes,
    );
    _publish(
      _progress.copyWith(
        phase: LanSyncPhase.transferring,
        detail: _progress.detail.copyWith(
          isIncremental: wire.isIncremental,
          bytes: bytes,
        ),
      ),
    );
    sendWsJson(socket, wire.toMetaFrame(LanSyncWsType.pullMeta));
    await sendWsChunkedBytes(
      socket,
      wire.compressedBytes,
      onChunk: (sent) => _publish(
        _progress.copyWith(
          detail: _progress.detail.copyWith(
            bytes: _progress.detail.bytes.copyWith(sentBytes: sent),
          ),
        ),
      ),
    );
    sendWsJson(socket, const <String, Object?>{'type': LanSyncWsType.pullEnd});
  }

  Future<Uint8List> _receiveClientPayload(
    StreamIterator<dynamic> frames,
  ) async {
    final meta = await readWsJson(frames, timeout: _ioTimeout);
    if (meta['type'] != LanSyncWsType.pushMeta) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    final total = _int(meta['totalBytes']);
    final uncompressed = _int(meta['uncompressedBytes']);
    final pushIncremental = meta['isIncremental'] == true;
    _publish(
      _progress.copyWith(
        phase: LanSyncPhase.transferring,
        detail: _progress.detail.copyWith(
          isIncremental: _progress.detail.isIncremental && pushIncremental,
          bytes: _progress.detail.bytes.copyWith(
            totalReceiveBytes: total,
            uncompressedBytes:
                _progress.detail.bytes.uncompressedBytes + uncompressed,
          ),
        ),
      ),
    );
    return await readWsBinaryUntilEnd(
      frames,
      endType: LanSyncWsType.pushEnd,
      timeout: _ioTimeout,
      onChunk: (received) => _publish(
        _progress.copyWith(
          detail: _progress.detail.copyWith(
            bytes: _progress.detail.bytes.copyWith(receivedBytes: received),
          ),
        ),
      ),
    );
  }

  Future<LanSyncDeltaSummary> _waitForClientDone(
    StreamIterator<dynamic> frames,
  ) async {
    while (true) {
      final msg = await readWsJson(frames, timeout: _ioTimeout);
      final type = msg['type'];
      if (type == LanSyncWsType.stage) {
        if (msg['stage'] == 'merging' &&
            _progress.phase != LanSyncPhase.merging) {
          _publish(_progress.copyWith(phase: LanSyncPhase.merging));
        }
        continue;
      }
      if (type == LanSyncWsType.clientDone) {
        return LanSyncDeltaSummary.fromJson(msg['summary']);
      }
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
  }

  LanSyncSessionHello _parseHello(Map<String, Object?> frame) {
    if (frame['type'] != LanSyncWsType.hello) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    final version = frame['protocolVersion'];
    if (version is! num || version.round() != lanSyncProtocolVersion) {
      throw const ExternalServiceError(AppErrorCode.lanSyncProtocolMismatch);
    }
    final pullSince = frame['pullSince'];
    return LanSyncSessionHello(
      deviceId: _str(frame['deviceId']),
      deviceName: _str(frame['deviceName']),
      deviceKind: _str(frame['deviceKind']),
      datasetEpoch: _str(frame['datasetEpoch']),
      mode: LanSyncPullMode.fromWire(_str(frame['mode'])),
      knownHostEpoch: _str(frame['knownHostEpoch']),
      pullSince: pullSince is num && pullSince > 0 ? pullSince.round() : null,
    );
  }

  void _publish(LanSyncTransferProgress next) {
    _progress = next;
    delegate.onSessionProgress(next);
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

int _int(Object? value) => value is num ? value.round() : 0;

String _str(Object? value) => value is String ? value.trim() : '';
