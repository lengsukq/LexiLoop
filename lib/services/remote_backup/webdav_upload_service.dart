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
  ///
  new(this._exporter, this._clientFactory, this._states);

  final BackupExporter _exporter;
  final RemoteBackupClientFactory _clientFactory;
  final WebdavStateStore _states;

  /// 导出当前数据并上传；失败时记录错误码后原样抛出。
  ///
  /// 读取凭据是**每次调用现读**：用户刚改完密码就点上传，用的必须是新密码。
  Future<RemoteUploadResult> uploadNow() async {
    if ((await _states.load()).credential == null) {
      throw const ValidationError(AppErrorCode.webdavNotConfigured);
    }
    try {
      final exported = await _exporter.exportToJson(includeFingerprint: true);
      return await uploadExported(exported);
    } on AppError catch (error) {
      await _states.recordFailure(error.code.code);
      rethrow;
    } on Object {
      await _states.recordFailure(AppErrorCode.webdavUnexpectedFailure.code);
      rethrow;
    }
  }

  /// 导出一份用于自动变化检测的快照。
  Future<BackupExportResult> exportSnapshot() async {
    if ((await _states.load()).credential == null) {
      throw const ValidationError(AppErrorCode.webdavNotConfigured);
    }
    return await _exporter.exportToJson(includeFingerprint: true);
  }

  /// 上传指定导出快照，成功后记录与该快照对应的检查点。
  ///
  /// 自动备份使用此入口，避免比较完成后重新导出造成 TOCTOU 窗口。
  Future<RemoteUploadResult> uploadExported(BackupExportResult exported) async {
    final settings = await _states.load();
    final credential = settings.credential;
    if (credential == null) {
      throw const ValidationError(AppErrorCode.webdavNotConfigured);
    }

    final fileName = backupFileName(DateTime.now());
    final client = _clientFactory(credential);
    await client.ensureDirectory();
    await client.putBackup(fileName: fileName, bytes: exported.bytes);
    await _states.recordFingerprintSuccess(exported.fingerprint);
    return RemoteUploadResult(
      fileName: fileName,
      byteSize: exported.bytes.length,
      totalRows: exported.totalRows,
    );
  }
}
