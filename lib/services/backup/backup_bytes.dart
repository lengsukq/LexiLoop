/// 备份字节的解码。
///
/// **为什么单独成文件**：本地导入（文件选择器）与远端恢复（WebDAV 下载）
/// 拿到的是同一份 JSON 的字节，必须给出同一套错误语义——非法 UTF-8 归一成
/// 「备份格式无效」，而不是把裸 `FormatException` 漏给上层。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:lexiloop/core/errors.dart';

/// 把备份字节解码成文本。
///
/// 非法 UTF-8 在旧实现里会从 `readAsStringSync()` 抛出裸 `FormatException`，
/// 越过「导入失败抛 AppError」的约定；这里统一归一成备份格式错误。
String decodeBackupUtf8(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException catch (error) {
    throw ValidationError(
      AppErrorCode.backupInvalidFormat,
      details: '备份文件不是合法的 UTF-8 文本：${error.message}',
    );
  }
}
