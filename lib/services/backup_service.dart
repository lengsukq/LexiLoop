/// 备份导入的编排：选文件 → 读取 → 导入。
///
/// 与 `BackupImporter` 的分工：后者只负责解析与写库（纯数据逻辑，可单测），
/// 这里负责平台交互（文件选择）与错误归一化。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_import.dart';

/// 备份导入服务。
class BackupService {
  /// 以导入器构造。
  const new(this._importer);

  final BackupImporter _importer;

  /// 弹出文件选择器并导入所选备份。
  ///
  /// 返回 `null` 表示用户取消；导入失败时抛出 [AppError]。
  Future<BackupImportResult?> pickAndImport() async {
    // file_picker 13.x 起直接返回文件列表，空列表即用户取消。
    final files = await FilePickerPlatform.instance.pickFiles(
      dialogTitle: '选择 LexiLoop 备份文件',
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (files.isEmpty) return null;

    final path = files.first.path;
    if (path == null) {
      throw const ValidationError(
        AppErrorCode.backupInvalidFormat,
        details: '所选文件没有本地路径，无法读取',
      );
    }

    final file = File(path);
    if (!file.existsSync()) {
      throw const ValidationError(
        AppErrorCode.backupInvalidFormat,
        details: '所选文件不存在或无法读取',
      );
    }

    final result = await _importer.import(file.readAsStringSync());
    return result;
  }
}
