/// 手动上传：导出当前数据并 PUT 到 WebDAV。
///
/// 与本地导出（`BackupExportService`）的分工：两者共用同一个导出器，
/// 区别只在交付方式——一个交给系统分享面板/浏览器下载，一个传到远端目录。
/// 因此这里**不落临时文件**，也不需要 `share_plus`。
///
/// **失败不改动本地数据**：整条链路只读数据库；`recordFailure` 写的是设置表里
/// 的一行状态，与词条、学习记录无关。
library;

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/db/daos/backup_checkpoint_dao.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_client.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';
import 'package:lexiloop/services/remote_backup/webdav_state_store.dart';

/// 一次成功上传的结果。
class RemoteUploadResult {
  /// 以文件名、字节数与总行数构造。
  const new({
    required this.fileName,
    required this.byteSize,
    required this.totalRows,
  });

  /// 远端文件名。
  final String fileName;

  /// 上传的字节数。
  final int byteSize;

  /// 备份包含的总行数。
  final int totalRows;
}

/// 远端上传服务。
class WebdavUploadService {
  /// 以导出器、客户端工厂与状态存储构造。
  new(this._exporter, this._clientFactory, this._states, this._checkpoints);

  final BackupExporter _exporter;
  final RemoteBackupClientFactory _clientFactory;
  final WebdavStateStore _states;
  final BackupCheckpointDao _checkpoints;

  /// 导出当前数据并上传；失败时记录错误码后原样抛出。
  ///
  /// 读取凭据是**每次调用现读**：用户刚改完密码就点上传，用的必须是新密码。
  Future<RemoteUploadResult> uploadNow() async {
    final settings = await _states.load();
    final credential = settings.credential;
    if (credential == null) {
      throw const ValidationError(AppErrorCode.webdavNotConfigured);
    }

    try {
      final exported = await _exporter.exportToJson();
      final fileName = backupFileName(DateTime.now());
      final client = _clientFactory(credential);
      await client.ensureDirectory();
      await client.putBackup(fileName: fileName, bytes: exported.bytes);
      final checkpoint = await _checkpoints.current();
      await _states.recordSuccess(checkpoint);
      return RemoteUploadResult(
        fileName: fileName,
        byteSize: exported.bytes.length,
        totalRows: exported.totalRows,
      );
    } on AppError catch (error) {
      await _states.recordFailure(error.code.code);
      rethrow;
    }
  }
}
