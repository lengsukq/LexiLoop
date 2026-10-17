/// 远端备份的内存替身。
///
/// 上传 / 恢复 / 自动备份三个服务只依赖 `RemoteBackupClient` 的 4 个方法，
/// 因此这里用一个 `Map` 就能覆盖全部业务分支——协议细节由
/// `test/data/remote_backup/webdav_client_test.dart` 单独钉住。
library;

import 'dart:typed_data';

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_client.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';

/// 内存里的远端备份目录。
final class FakeRemoteBackupClient implements RemoteBackupClient {
  /// 以可选的初始文件构造（文件名 → 字节）。
  new([Map<String, Uint8List>? files]) : files = <String, Uint8List>{...?files};

  /// 目录内容。
  final Map<String, Uint8List> files;

  /// `ensureDirectory` 被调用的次数。
  int ensureDirectoryCalls = 0;

  /// `putBackup` 被调用的次数。
  ///
  /// 与 [files] 的长度分开计数：同一秒内的两次上传会落在同一个文件名上
  /// （命名精确到秒），此时「文件数」不变但确实传了两次。
  int putCalls = 0;

  /// 下一次调用要抛出的错误（抛一次后自动清空）。
  AppError? failWith;

  /// 每个条目的修改时间；缺省为 `null`。
  final Map<String, DateTime> modifiedAt = <String, DateTime>{};

  @override
  Future<void> ensureDirectory() async {
    ensureDirectoryCalls += 1;
    _maybeFail();
  }

  @override
  Future<void> putBackup({
    required String fileName,
    required Uint8List bytes,
  }) async {
    _maybeFail();
    putCalls += 1;
    files[fileName] = bytes;
    modifiedAt[fileName] = DateTime.now().toUtc();
  }

  @override
  Future<List<RemoteBackupEntry>> listBackups() async {
    _maybeFail();
    final entries = <RemoteBackupEntry>[
      for (final entry in files.entries)
        RemoteBackupEntry(
          name: entry.key,
          sizeBytes: entry.value.length,
          modifiedAt: modifiedAt[entry.key],
        ),
    ]..sort((a, b) => b.name.compareTo(a.name));
    return entries;
  }

  @override
  Future<Uint8List> downloadBackup(RemoteBackupEntry entry) async {
    _maybeFail();
    final bytes = files[entry.name];
    if (bytes == null) {
      throw const NotFoundError(AppErrorCode.webdavNotFound);
    }
    return bytes;
  }

  /// 目录里本应用产生的备份文件名（按名字排序）。
  List<String> get backupNames =>
      files.keys.where((name) => name.startsWith(backupFilePrefix)).toList()
        ..sort();

  void _maybeFail() {
    final failure = failWith;
    if (failure == null) return;
    failWith = null;
    throw failure;
  }
}
