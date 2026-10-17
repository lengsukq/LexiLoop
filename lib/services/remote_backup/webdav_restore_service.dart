/// 从远端恢复：列出备份、下载、交给现有的导入器全量替换。
///
/// **恢复语义与本地导入完全一致**：`BackupImporter.import` 在单个事务里
/// 清空并重写 12 张表，失败则原数据不变。这里是「多了一步下载」的同一条路径，
/// 不另起一套导入实现。
///
/// **为什么不在服务里失效缓存**：与界面层的 `_importBackup` 相同——
/// `invalidateLocalData` 需要 `WidgetRef`，属于界面的一次动作。
library;

import 'dart:typed_data';

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_client.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/services/backup/backup_bytes.dart';
import 'package:lexiloop/services/remote_backup/webdav_state_store.dart';

/// 远端恢复服务。
class WebdavRestoreService {
  /// 以客户端工厂、导入器与状态存储构造。
  new(this._clientFactory, this._states, this._importer);

  final RemoteBackupClientFactory _clientFactory;
  final WebdavStateStore _states;
  final BackupImporter _importer;

  /// 列出远端目录里的备份。
  Future<List<RemoteBackupEntry>> listRemoteBackups() async {
    final client = await _client();
    return await client.listBackups();
  }

  /// 下载并导入指定备份。
  Future<BackupImportResult> restore(RemoteBackupEntry entry) async {
    final client = await _client();
    final bytes = await client.downloadBackup(entry);
    return await _import(bytes);
  }

  /// 解析并导入字节。
  Future<BackupImportResult> _import(Uint8List bytes) =>
      _importer.import(decodeBackupUtf8(bytes));

  /// 按当前凭据构造客户端；未配置时抛「未配置」。
  Future<RemoteBackupClient> _client() async {
    final credential = (await _states.load()).credential;
    if (credential == null) {
      throw const ValidationError(AppErrorCode.webdavNotConfigured);
    }
    return _clientFactory(credential);
  }
}
