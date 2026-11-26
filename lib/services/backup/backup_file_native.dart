/// 原生端（macOS / Android）的备份交付。
///
/// 由 `backup_file.dart` 条件导入选中。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 把备份字节写入临时目录，再交给系统分享面板。
///
/// 每次导出用带时间戳的新文件名，因此**不会覆盖**上一次导出的临时文件；
/// 用户在分享面板里选的目标路径若已存在，替换与否由系统面板询问——
/// 这正是我们要的覆盖确认。
///
/// 返回分享面板里显示的文件名。
Future<String> shareBackupBytes({
  required Uint8List bytes,
  required String fileName,
  String mimeType = backupMimeType,
  String subject = 'LexiLoop 备份',
}) async {
  final directory = await getTemporaryDirectory();
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);

  await SharePlus.instance.share(
    ShareParams(
      subject: subject,
      files: <XFile>[XFile(file.path, mimeType: mimeType)],
      fileNameOverrides: <String>[fileName],
    ),
  );
  return fileName;
}
