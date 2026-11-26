/// 远程备份（WebDAV）的提供者。
///
/// **客户端是工厂而不是单例**：凭据可以在设置里随时改，而 `WebdavClient`
/// 在构造时就固定了认证头。让服务每次现读设置、现造客户端，
/// 用户改完密码立刻生效，不必重启应用。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_client.dart';
import 'package:lexiloop/data/remote_backup/webdav_client.dart';
import 'package:lexiloop/services/backup/backup_export_providers.dart';
import 'package:lexiloop/services/remote_backup/webdav_auto_backup.dart';
import 'package:lexiloop/services/remote_backup/webdav_restore_service.dart';
import 'package:lexiloop/services/remote_backup/webdav_state_store.dart';
import 'package:lexiloop/services/remote_backup/webdav_upload_service.dart';

/// 远端备份设置的读写。
final Provider<WebdavStateStore> webdavStateStoreProvider =
    Provider<WebdavStateStore>(
      (ref) => WebdavStateStore(ref.watch(settingsServiceProvider)),
    );

/// 按凭据构造远端客户端的工厂（真实实现是 WebDAV）。
final Provider<RemoteBackupClientFactory> remoteBackupClientFactoryProvider =
    Provider<RemoteBackupClientFactory>((ref) => WebdavClient.new);

/// 手动上传服务。
final Provider<WebdavUploadService> webdavUploadServiceProvider =
    Provider<WebdavUploadService>(
      (ref) => WebdavUploadService(
        ref.watch(backupExporterProvider),
        ref.watch(remoteBackupClientFactoryProvider),
        ref.watch(webdavStateStoreProvider),
      ),
    );

/// 从远端恢复的服务。
final Provider<WebdavRestoreService> webdavRestoreServiceProvider =
    Provider<WebdavRestoreService>(
      (ref) => WebdavRestoreService(
        ref.watch(remoteBackupClientFactoryProvider),
        ref.watch(webdavStateStoreProvider),
        BackupImporter(ref.watch(databaseProvider)),
      ),
    );

/// 自动备份调度器。
///
/// **只在启动时点火一次**（见 `lib/app/maintenance_bootstrap.dart`），
/// 界面层不要 `watch` 它——`dispose` 会取消定时器，界面切页不该影响备份排期。
final Provider<WebdavAutoBackup> webdavAutoBackupProvider =
    Provider<WebdavAutoBackup>((ref) {
      final backup = WebdavAutoBackup(
        ref.watch(webdavUploadServiceProvider),
        ref.watch(webdavStateStoreProvider),
      );
      ref.onDispose(backup.dispose);
      return backup;
    });
