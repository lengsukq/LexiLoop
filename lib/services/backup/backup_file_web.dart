/// Web 端的备份交付：直接分享字节，由浏览器下载。
///
/// 由 `backup_file.dart` 条件导入选中。
library;

import 'dart:typed_data';

import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:share_plus/share_plus.dart';

/// 以字节形式分享备份，返回分享时使用的文件名。
///
/// **为什么不落盘**：`path_provider` 没有 web 实现，
/// `getTemporaryDirectory()` 在浏览器里直接抛异常；而 `File` 本身也不存在。
///
/// **下载是怎么发生的**：`share_plus` 的 web 实现先试 Web Share API
/// （`navigator.canShare`）。桌面浏览器不支持分享文件，`canShare` 返回
/// `false`，于是走 `downloadFallbackEnabled`（默认开启）的兜底分支——
/// 造一个带 `download` 属性的 `<a>` 并点击，触发浏览器下载。
/// 手机浏览器支持 Web Share 时会弹系统分享面板，用户仍可存成文件。
Future<String> shareBackupBytes({
  required Uint8List bytes,
  required String fileName,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      subject: 'LexiLoop 备份',
      files: <XFile>[
        XFile.fromData(bytes, name: fileName, mimeType: backupMimeType),
      ],
      fileNameOverrides: <String>[fileName],
    ),
  );
  return fileName;
}
