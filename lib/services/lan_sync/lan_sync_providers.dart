/// 局域网同步的 Riverpod 提供者装配。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/backup/incremental_sync_exporter.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client_dio.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_session_client.dart';
import 'package:lexiloop/services/backup/backup_export_providers.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_pull_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_share_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/incremental_merge_service.dart';
import 'package:lexiloop/services/merge/merge_providers.dart';

/// 共享服务端启动器。
final Provider<LanSyncHostStarter> lanSyncHostStarterProvider =
    Provider<LanSyncHostStarter>((ref) => createLanSyncHost);

/// 同网段设备搜索器（原生端是 UDP 广播）。
final Provider<LanSyncDiscovery> lanSyncDiscoveryProvider =
    Provider<LanSyncDiscovery>((ref) => createLanSyncDiscovery());

/// 按「目标设备 + 配对码」构造 HTTP 对端客户端。
final Provider<LanSyncClientFactory> lanSyncClientFactoryProvider =
    Provider<LanSyncClientFactory>((ref) => LanSyncHttpClient.new);

/// v2 WebSocket 双向增量会话执行器（可为空以兼容旧单测替身）。
final Provider<LanSyncSessionRunner?> lanSyncSessionRunnerProvider =
    Provider<LanSyncSessionRunner?>((ref) => runLanSyncClientSession);

/// 增量导出器。
final Provider<IncrementalSyncExporter> incrementalSyncExporterProvider =
    Provider<IncrementalSyncExporter>(
      (ref) => IncrementalSyncExporter(ref.watch(databaseProvider)),
    );

/// 增量合并落库服务。
final Provider<IncrementalMergeService> incrementalMergeServiceProvider =
    Provider<IncrementalMergeService>(
      (ref) => IncrementalMergeService(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
      ),
    );

/// 本机设置、身份与水位线读写。
final Provider<LanSyncStateStore> lanSyncStateStoreProvider =
    Provider<LanSyncStateStore>(
      (ref) => LanSyncStateStore(ref.watch(settingsServiceProvider)),
    );

/// 共享会话的编排（含 v2 双向增量委托）。
final Provider<LanSyncShareService> lanSyncShareServiceProvider =
    Provider<LanSyncShareService>(
      (ref) => LanSyncShareService(
        ref.watch(backupExporterProvider),
        ref.watch(lanSyncHostStarterProvider),
        ref.watch(lanSyncStateStoreProvider),
        deltaExporter: ref.watch(incrementalSyncExporterProvider),
        incrementalMerger: ref.watch(incrementalMergeServiceProvider),
      ),
    );

/// 同步拉取/双向合并服务。
final Provider<LanSyncPullService> lanSyncPullServiceProvider =
    Provider<LanSyncPullService>(
      (ref) => LanSyncPullService(
        ref.watch(lanSyncClientFactoryProvider),
        ref.watch(lanSyncDiscoveryProvider),
        BackupImporter(ref.watch(databaseProvider)),
        ref.watch(backupMergeServiceProvider),
        ref.watch(lanSyncStateStoreProvider),
        sessionRunner: ref.watch(lanSyncSessionRunnerProvider),
        deltaExporter: ref.watch(incrementalSyncExporterProvider),
        incrementalMerger: ref.watch(incrementalMergeServiceProvider),
      ),
    );

/// 共享会话的界面状态（keep-alive，切页后仍保持监听）。
final AsyncNotifierProvider<LanSyncShareController, LanSyncShareSession?>
lanSyncShareProvider =
    AsyncNotifierProvider<LanSyncShareController, LanSyncShareSession?>(
      LanSyncShareController.new,
    );

/// 把 [LanSyncShareService] 的会话与实时进度包装成界面可直接 watch 的异步状态。
final class LanSyncShareController extends AsyncNotifier<LanSyncShareSession?> {
  bool _disposed = false;

  @override
  Future<LanSyncShareSession?> build() async {
    final service = ref.watch(lanSyncShareServiceProvider);
    ref.onDispose(() {
      _disposed = true;
      unawaited(service.stop());
    });
    return null;
  }

  /// 开启共享。
  Future<void> start() async {
    if (state.value != null && (state.value?.isSharing ?? false)) return;
    state = const AsyncValue<LanSyncShareSession?>.loading();
    try {
      final session = await ref
          .read(lanSyncShareServiceProvider)
          .start(
            onServed: _publish,
            onLockedOut: _publish,
            onProgress: _publish,
          );
      if (_disposed) return;
      state = AsyncValue<LanSyncShareSession?>.data(session);
    } on Object catch (error, stackTrace) {
      if (_disposed) return;
      state = AsyncValue<LanSyncShareSession?>.error(error, stackTrace);
    }
  }

  /// 停止共享。
  Future<void> stop() async {
    await ref.read(lanSyncShareServiceProvider).stop();
    if (_disposed) return;
    state = const AsyncValue<LanSyncShareSession?>.data(null);
  }

  /// 收起主机卡片上已完成的同步动画摘要，回到等待连接态。
  void dismissLiveProgress() {
    ref.read(lanSyncShareServiceProvider).dismissLiveProgress();
  }

  void _publish() {
    if (_disposed) return;
    final session = ref.read(lanSyncShareServiceProvider).session;
    state = AsyncValue<LanSyncShareSession?>.data(session);
  }
}
