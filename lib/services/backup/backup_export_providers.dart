/// 备份导出相关的 Riverpod 提供者。
///
/// 与 `BackupService`（导入侧）分开声明：两条链路的生命周期不同——导入是一次
/// 性的破坏性操作，导出是随时可用的常规动作，不该共用同一个对象。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/services/backup/backup_export_service.dart';

/// 备份导出器（纯数据层）。
final Provider<BackupExporter> backupExporterProvider =
    Provider<BackupExporter>(
      (ref) => BackupExporter(ref.watch(databaseProvider)),
    );

/// 备份导出服务（含文件与分享面板的平台交互）。
final Provider<BackupExportService> backupExportServiceProvider =
    Provider<BackupExportService>(
      (ref) => BackupExportService(ref.watch(backupExporterProvider)),
    );
