/// Next.js 云端同步的 Riverpod 提供者装配。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client_dio.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/services/cloud_sync/cloud_sync_service.dart';
import 'package:lexiloop/services/cloud_sync/cloud_sync_state_store.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_providers.dart';

/// 按服务器凭据构造云端同步 HTTP 客户端。
final Provider<CloudSyncClientFactory> cloudSyncClientFactoryProvider =
    Provider<CloudSyncClientFactory>((ref) => CloudSyncHttpClient.new);

/// 本机云端同步设置与水位线存储。
final Provider<CloudSyncStateStore> cloudSyncStateStoreProvider =
    Provider<CloudSyncStateStore>(
      (ref) => CloudSyncStateStore(ref.watch(settingsServiceProvider)),
    );

/// Next.js 云端跨端同步编排服务。
final Provider<CloudSyncService> cloudSyncServiceProvider =
    Provider<CloudSyncService>(
      (ref) => CloudSyncService(
        ref.watch(cloudSyncClientFactoryProvider),
        ref.watch(cloudSyncStateStoreProvider),
        ref.watch(lanSyncStateStoreProvider),
        CloudSyncLocalEngine(
          deltaExporter: ref.watch(incrementalSyncExporterProvider),
          incrementalMerger: ref.watch(incrementalMergeServiceProvider),
          importer: BackupImporter(ref.watch(databaseProvider)),
        ),
      ),
    );
