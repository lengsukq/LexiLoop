/// Web 端局域网同步编解码占位实现（不引入 `dart:io` / `dart:isolate`）。
library;

import 'dart:convert';
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

/// Web 端以明文 UTF-8 JSON 编码并返回字节统计。
Future<({Uint8List compressedBytes, int uncompressedBytes})>
encodeJsonGzipWithStats(Object payload) async {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  if (bytes.length > maxBackupBytes) {
    throw const ValidationError(AppErrorCode.backupTooLarge);
  }
  return (compressedBytes: bytes, uncompressedBytes: bytes.length);
}

/// Web 端直接以明文 UTF-8 JSON 编码。
Future<Uint8List> encodeJsonGzipBytes(Object payload) async =>
    (await encodeJsonGzipWithStats(payload)).compressedBytes;

/// Web 端原样返回字节。
Future<Uint8List> compressLanSyncBytes(Uint8List bytes) async => bytes;

/// Web 端解码非压缩 UTF-8 备份文本；遇 GZip 时报不支持。
Future<String> decodeBackupMaybeGzipUtf8(Uint8List bytes) async {
  if (bytes.isEmpty || isLanSyncGzipBytes(bytes)) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  if (bytes.length > maxBackupBytes) {
    throw const ValidationError(AppErrorCode.backupTooLarge);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException catch (error) {
    throw ValidationError(
      AppErrorCode.backupInvalidFormat,
      details: error.message,
    );
  }
}

/// Web 端解码 JSON 对象。
Future<Map<String, Object?>> decodeJsonObjectMaybeGzip(Uint8List bytes) async {
  final text = await decodeBackupMaybeGzipUtf8(bytes);
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw const ValidationError(AppErrorCode.backupInvalidFormat);
    }
    return decoded;
  } on FormatException catch (error) {
    throw ValidationError(
      AppErrorCode.backupInvalidJson,
      details: error.message,
    );
  }
}
