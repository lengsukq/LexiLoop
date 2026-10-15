/// 备份导出的编排：序列化 → 落临时文件 → 交给系统分享面板。
///
/// 与 `BackupExporter` 的分工：后者只管把库里的行变成备份字节（纯数据逻辑，
/// 可单测），这里负责平台交互。
///
/// **为什么用 `share_plus` 而不是 `file_picker.saveFile`**：
/// `saveFile` 在 macOS 上尚可，在 Android 上依赖 SAF 的 create-document 通道，
/// 各厂商实现差异很大，常返回路径却写不进去；而 `share_plus` 在两端都落到
/// 系统原生的分享/存储面板，用户可以在那里选「文件」、AirDrop、邮件，
/// 目标已存在时由系统自己弹覆盖确认——这正是我们要的覆盖确认。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 导出文件名的固定前缀。
///
/// 让用户在「文件」应用里一眼认出这是备份，而不是某个临时文件。
const String backupFilePrefix = 'lexiloop-backup-';

/// 一次成功导出后交给 UI 汇报的结果。
class SharedBackupExport {
  /// 以导出结果、字节数与文件名构造。
  const new({
    required this.result,
    required this.byteSize,
    required this.filename,
  });

  /// 备份内容本身。
  final BackupExportResult result;

  /// 落在磁盘上的字节数。
  final int byteSize;

  /// 分享面板里显示的文件名。
  final String filename;
}

/// 备份导出服务。
class BackupExportService {
  /// 以导出器构造。
  const new(this._exporter);

  final BackupExporter _exporter;

  /// 导出并弹出系统分享面板。
  ///
  /// 全程只读数据库，不删除也不覆盖用户的任何词条。调用方负责在此之前
  /// 确认「用户知道自己在导什么、也知道导出不含什么」。
  Future<SharedBackupExport> exportAndShare() async {
    final result = await _exporter.exportToJson();
    // 导出器已经按字节卡过上限；这里再确认一次不是防御性冗余，而是因为
    // `BackupExportResult.bytes` 是公开字段，调用方可以绕过导出器构造它。
    if (result.bytes.length > maxBackupBytes) {
      throw ValidationError(
        AppErrorCode.backupTooLarge,
        details: '导出结果 ${result.bytes.length} 字节，上限 $maxBackupBytes',
      );
    }
    final file = await _writeTempFile(result.bytes);
    await SharePlus.instance.share(
      ShareParams(
        subject: 'LexiLoop 备份',
        files: <XFile>[XFile(file.path, mimeType: backupMimeType)],
        fileNameOverrides: <String>[file.uri.pathSegments.last],
      ),
    );
    return SharedBackupExport(
      result: result,
      byteSize: result.bytes.length,
      filename: file.uri.pathSegments.last,
    );
  }

  /// 写入临时目录。
  ///
  /// 每次导出用带时间戳的新文件名，因此**不会覆盖**上一次导出的临时文件；
  /// 用户在分享面板里选的目标路径若已存在，替换与否由系统面板询问。
  Future<File> _writeTempFile(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${_fileName()}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 带时间戳的备份文件名，例如 `lexiloop-backup-20261014-222752.json`。
  ///
  /// 格式与旧版 `/api/backups/json` 下发的一致，方便用户把新旧文件放在一处。
  String _fileName() {
    final now = DateTime.now();
    return '$backupFilePrefix${dateKey(now.millisecondsSinceEpoch)}'
        '-${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}.json';
  }
}

/// 两位补零，让文件名里的时间字段能按字典序排序。
String _pad(int value) =>
    // 宽度就是「一位数字 + 补位」里的两位，没有语义可命名。
    value.toString().padLeft(2, '0'); // guard:allow-magic
