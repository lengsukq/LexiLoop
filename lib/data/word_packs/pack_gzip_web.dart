/// Web 端词书包解码兜底（不引入 `dart:io`）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';

const int _gzipMagic0 = 0x1f;
const int _gzipMagic1 = 0x8b;

/// 判断字节序列是否为 GZip 压缩流。
bool isGzipBytes(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == _gzipMagic0 && bytes[1] == _gzipMagic1;

/// Web 端支持明文 JSON 词书包；GZip 二进制在桌面/移动端原生解压。
String decodeWordPackBytes(Uint8List bytes) {
  if (bytes.length > wordPackMaxCompressedBytes) {
    throw const ValidationError(AppErrorCode.wordPackTooLarge);
  }
  if (isGzipBytes(bytes)) {
    throw const PlatformCapabilityError(
      AppErrorCode.wordPackInvalidFormat,
      details: '浏览器端暂不支持直接解压 .gz 词书包，请使用桌面端或移动端。',
    );
  }
  try {
    return utf8.decode(bytes);
  } on FormatException catch (error) {
    throw ValidationError(
      AppErrorCode.wordPackInvalidFormat,
      details: error.message,
    );
  }
}

/// Web 端无 `dart:io`，原样返回 UTF-8 字节。
Uint8List encodeWordPackGzip(String jsonText) =>
    Uint8List.fromList(utf8.encode(jsonText));
