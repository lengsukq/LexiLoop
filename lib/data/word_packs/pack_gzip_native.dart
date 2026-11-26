/// 原生端词书包 GZip 编解码（依赖 `dart:io`）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';

/// GZip 魔数首字节（`0x1F`）。
const int _gzipMagic0 = 0x1f;

/// GZip 魔数次字节（`0x8B`）。
const int _gzipMagic1 = 0x8b;

/// 判断字节序列是否为 GZip 压缩流。
bool isGzipBytes(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == _gzipMagic0 && bytes[1] == _gzipMagic1;

/// 将 `.lexipack.json.gz` 或明文 `.json` 字节解码为 UTF-8 JSON 字符串。
String decodeWordPackBytes(Uint8List bytes) {
  if (bytes.length > wordPackMaxCompressedBytes) {
    throw const ValidationError(AppErrorCode.wordPackTooLarge);
  }
  try {
    final decoded = isGzipBytes(bytes) ? gzip.decode(bytes) : bytes;
    if (decoded.length > wordPackMaxDecompressedBytes) {
      throw const ValidationError(AppErrorCode.wordPackTooLarge);
    }
    return utf8.decode(decoded);
  } on AppError {
    rethrow;
  } on Object catch (error) {
    throw ValidationError(AppErrorCode.wordPackInvalidFormat, details: error);
  }
}

/// 将 UTF-8 JSON 字符串编码为 GZip 字节（供 CLI 工具与测试使用）。
Uint8List encodeWordPackGzip(String jsonText) =>
    Uint8List.fromList(gzip.encode(utf8.encode(jsonText)));
