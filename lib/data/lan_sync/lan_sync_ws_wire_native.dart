/// WebSocket 同步帧的底层收发工具（`dart:io`，仅原生端使用）。
///
/// 主机端与客户端共用分片发送与分片重组逻辑，保证两边对控制帧、二进制流、
/// 大小上限与错误码的解读完全一致。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';

/// 发送一条 JSON 控制帧。
void sendWsJson(WebSocket socket, Map<String, Object?> payload) {
  socket.add(jsonEncode(payload));
}

/// 发送一条错误帧并尝试通知对端，连接已断时静默返回。
void trySendWsError(WebSocket socket, AppErrorCode code) {
  try {
    sendWsJson(socket, <String, Object?>{
      'type': LanSyncWsType.error,
      lanSyncErrorCodeField: code.code,
    });
  } on Object {
    // 套接字可能已关闭，尽力通知即可。
  }
}

/// 将压缩字节按 [lanSyncWsChunkBytes] 分片发送，并在每片后回报已发字节数。
Future<void> sendWsChunkedBytes(
  WebSocket socket,
  Uint8List bytes, {
  required void Function(int sentBytes) onChunk,
  bool Function()? isCancelled,
}) async {
  if (bytes.isEmpty) {
    onChunk(0);
    return;
  }
  for (var offset = 0; offset < bytes.length; offset += lanSyncWsChunkBytes) {
    if (isCancelled?.call() ?? false) {
      throw const ValidationError(AppErrorCode.lanSyncCancelled);
    }
    final end = offset + lanSyncWsChunkBytes;
    final clampedEnd = end > bytes.length ? bytes.length : end;
    socket.add(Uint8List.sublistView(bytes, offset, clampedEnd));
    onChunk(clampedEnd);
    // 让出事件循环一拍，既给 socket 冲刷缓冲，也确保 UI 动画帧平滑推进。
    await Future<void>.delayed(Duration.zero);
  }
}

/// 读取下一条 JSON 控制帧；若收到错误帧则直接转为 [AppError] 抛出。
Future<Map<String, Object?>> readWsJson(
  StreamIterator<dynamic> frames, {
  required Duration timeout,
}) async {
  final hasNext = await frames.moveNext().timeout(
    timeout,
    onTimeout: () => throw const ExternalServiceError(
      AppErrorCode.lanSyncUnreachable,
      isTransient: true,
    ),
  );
  if (!hasNext) {
    throw const ExternalServiceError(
      AppErrorCode.lanSyncUnreachable,
      isTransient: true,
    );
  }
  final raw = frames.current;
  if (raw is! String) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  final map = _decodeControlFrame(raw);
  if (map['type'] == LanSyncWsType.error) {
    throw wsErrorFromCode(map[lanSyncErrorCodeField] as String?);
  }
  return map;
}

/// 连续读取二进制分片直到收到类型为 [endType] 的结束控制帧。
Future<Uint8List> readWsBinaryUntilEnd(
  StreamIterator<dynamic> frames, {
  required String endType,
  required Duration timeout,
  required void Function(int receivedBytes) onChunk,
  bool Function()? isCancelled,
}) async {
  final builder = BytesBuilder(copy: false);
  while (true) {
    if (isCancelled?.call() ?? false) {
      throw const ValidationError(AppErrorCode.lanSyncCancelled);
    }
    final hasNext = await frames.moveNext().timeout(
      timeout,
      onTimeout: () => throw const ExternalServiceError(
        AppErrorCode.lanSyncUnreachable,
        isTransient: true,
      ),
    );
    if (!hasNext) {
      throw const ExternalServiceError(
        AppErrorCode.lanSyncUnreachable,
        isTransient: true,
      );
    }
    final frame = frames.current;
    if (frame is List<int>) {
      if (builder.length + frame.length > maxBackupBytes) {
        throw const ValidationError(AppErrorCode.backupTooLarge);
      }
      builder.add(frame);
      onChunk(builder.length);
      continue;
    }
    if (frame is String) {
      final map = _decodeControlFrame(frame);
      if (map['type'] == LanSyncWsType.error) {
        throw wsErrorFromCode(map[lanSyncErrorCodeField] as String?);
      }
      if (map['type'] == endType) return builder.takeBytes();
    }
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
}

/// 把对端错误帧里的错误码映射回强类型 [AppError]。
AppError wsErrorFromCode(String? code) {
  final parsed = code == null ? null : AppErrorCode.fromCode(code);
  return switch (parsed) {
    AppErrorCode.lanSyncCodeInvalid ||
    AppErrorCode.lanSyncPeerRejected ||
    AppErrorCode.lanSyncCancelled ||
    AppErrorCode.backupTooLarge ||
    AppErrorCode.backupInvalidFormat ||
    AppErrorCode.backupInvalidJson => ValidationError(parsed!),
    AppErrorCode.lanSyncNotSharing => NotFoundError(parsed!),
    AppErrorCode.lanSyncBusy || AppErrorCode.lanSyncUnreachable =>
      ExternalServiceError(parsed!, isTransient: true),
    AppErrorCode.lanSyncProtocolMismatch => ExternalServiceError(parsed!),
    _ => const ExternalServiceError(
      AppErrorCode.lanSyncRequestFailed,
      isTransient: true,
    ),
  };
}

/// 将 WebSocket 升级阶段的 HTTP 拒绝状态码（如 401/404/409）归一化为 [AppError]。
AppError mapWsConnectException(Object error) {
  final message = error.toString();
  final match = RegExp(r'\b(401|404|409|413)\b').firstMatch(message);
  final status = int.tryParse(match?.group(1) ?? '');
  return switch (status) {
    lanSyncStatusUnauthorized => const ValidationError(
      AppErrorCode.lanSyncCodeInvalid,
    ),
    lanSyncStatusNotFound => const NotFoundError(
      AppErrorCode.lanSyncNotSharing,
    ),
    lanSyncStatusConflict => const ExternalServiceError(
      AppErrorCode.lanSyncBusy,
      isTransient: true,
    ),
    lanSyncStatusTooLarge => const ValidationError(AppErrorCode.backupTooLarge),
    _ => ExternalServiceError(
      AppErrorCode.lanSyncUnreachable,
      isTransient: true,
      details: error,
    ),
  };
}

Map<String, Object?> _decodeControlFrame(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException catch (error) {
    throw ValidationError(
      AppErrorCode.backupInvalidJson,
      details: error.message,
    );
  }
  throw const ValidationError(AppErrorCode.backupInvalidFormat);
}
