/// 合并同步的提供者。
///
/// **与局域网解耦**：合并本身不认识「对端从哪来」，将来把 WebDAV 恢复也接上
/// 合并模式时，只需要在这里多一个消费者。`docs/LAN_SYNC.md` 记录的
/// 合并语义因此只写一遍。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/services/backup/backup_export_providers.dart';
import 'package:lexiloop/services/merge/backup_merge_service.dart';

/// 把对端备份合并进本机的服务。
final Provider<BackupMergeService> backupMergeServiceProvider =
    Provider<BackupMergeService>(
      (ref) => BackupMergeService(
        ref.watch(backupExporterProvider),
        BackupImporter(ref.watch(databaseProvider)),
        ref.watch(settingsServiceProvider),
      ),
    );
