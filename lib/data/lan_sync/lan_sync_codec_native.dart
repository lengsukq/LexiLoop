/// 原生端局域网同步编解码：后台 Isolate JSON 序列化 + GZip 压缩。
///
/// **为什么放进后台 Isolate**：大词库（27 MB+）在主线程跑 `jsonEncode` /
/// `jsonDecode` / `gzip` 会阻塞 UI 线程 0.5–2 秒，导致双端同步动画冻住。
/// 每次编解码在单次 `Isolate.run` 内完成，避免超大载荷在 Isolate 间多次拷贝。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';

/// GZip 魔数首字节（`0x1F`）。
const int _gzipMagic0 = 0x1f;

/// GZip 魔数次字节（`0x8B`）。
const int _gzipMagic1 = 0x8b;

/// 判断字节序列是否为 GZip 压缩流。
bool isLanSyncGzipBytes(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == _gzipMagic0 && bytes[1] == _gzipMagic1;

/// 在后台 Isolate 中单次完成 JSON 序列化 + GZip 压缩，同时返回压缩前后字节数。
Future<({Uint8List compressedBytes, int uncompressedBytes})>
encodeJsonGzipWithStats(Object payload) async {
  final result = await Isolate.run<({Uint8List compressed, int rawLength})>(() {
    final raw = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    if (raw.length > maxBackupBytes) {
      return (compressed: Uint8List(0), rawLength: raw.length);
    }
    return (
      compressed: Uint8List.fromList(gzip.encode(raw)),
      rawLength: raw.length,
    );
  });
  _ensureWithinBackupLimit(result.rawLength, '待传输载荷');
  return (
    compressedBytes: result.compressed,
    uncompressedBytes: result.rawLength,
  );
}

/// 在后台 Isolate 中将 JSON 对象编码为 GZip 字节流。
Future<Uint8List> encodeJsonGzipBytes(Object payload) async =>
    (await encodeJsonGzipWithStats(payload)).compressedBytes;

/// 在后台 Isolate 中对原始字节做 GZip 压缩。
Future<Uint8List> compressLanSyncBytes(Uint8List bytes) =>
    Isolate.run(() => Uint8List.fromList(gzip.encode(bytes)));

/// 在后台 Isolate 中解码（可选 GZip 压缩的）UTF-8 备份文本。
Future<String> decodeBackupMaybeGzipUtf8(Uint8List bytes) async {
  _validateIncomingBytes(bytes);
  try {
    final result = await Isolate.run<({String text, int rawLength})>(
      () => _decompressToText(bytes),
    );
    _ensureWithinBackupLimit(result.rawLength, '解压后载荷');
    return result.text;
  } on AppError {
    rethrow;
  } on Object catch (error) {
    throw ValidationError(
      AppErrorCode.backupInvalidFormat,
      details: '同步载荷解压或 UTF-8 解码失败：$error',
    );
  }
}

/// 在后台 Isolate 中单次完成解压 + UTF-8 解码 + JSON 解析。
Future<Map<String, Object?>> decodeJsonObjectMaybeGzip(Uint8List bytes) async {
  _validateIncomingBytes(bytes);
  try {
    final result = await Isolate.run<({Object? json, int rawLength})>(
      () => _decompressToJson(bytes),
    );
    _ensureWithinBackupLimit(result.rawLength, '解压后载荷');
    final decoded = result.json;
    if (decoded is! Map<String, Object?>) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    return decoded;
  } on AppError {
    rethrow;
  } on FormatException catch (error) {
    throw ValidationError(
      AppErrorCode.backupInvalidJson,
      details: error.message,
    );
  } on Object catch (error) {
    throw ValidationError(
      AppErrorCode.backupInvalidFormat,
      details: '同步载荷解压或 JSON 解析失败：$error',
    );
  }
}

void _validateIncomingBytes(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  _ensureWithinBackupLimit(bytes.length, '收到载荷');
}

void _ensureWithinBackupLimit(int length, String label) {
  if (length <= maxBackupBytes) return;
  throw ValidationError(
    AppErrorCode.backupTooLarge,
    details: '$label $length 字节，上限 $maxBackupBytes',
  );
}

({String text, int rawLength}) _decompressToText(Uint8List bytes) {
  final decoded = isLanSyncGzipBytes(bytes)
      ? Uint8List.fromList(gzip.decode(bytes))
      : bytes;
  if (decoded.length > maxBackupBytes) {
    return (text: '', rawLength: decoded.length);
  }
  return (text: utf8.decode(decoded), rawLength: decoded.length);
}

({Object? json, int rawLength}) _decompressToJson(Uint8List bytes) {
  final text = _decompressToText(bytes);
  if (text.rawLength > maxBackupBytes) {
    return (json: null, rawLength: text.rawLength);
  }
  return (json: jsonDecode(text.text), rawLength: text.rawLength);
}
