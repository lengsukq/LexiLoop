/// 局域网同步的提供者。
///
/// **客户端是工厂而不是单例**：目标设备与配对码每次同步都由用户决定，
/// 让服务每次现读现造客户端，就不存在「握着上一次的目标或上一次的码」这种状态。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client_dio.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/services/backup/backup_export_providers.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_pull_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_share_service.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';
import 'package:lexiloop/services/merge/merge_providers.dart';

/// 数据层的单一引用点。
///
/// **为什么不让服务直接 import `lan_sync_host.dart`**：那是条件导入的出口，
/// 直接引用会让「谁依赖平台实现」这件事散落在服务里；收成一个 provider 之后，
/// 测试用 `overrideWithValue` 换成假启动器即可完全不碰端口。
final Provider<LanSyncHostStarter> lanSyncHostStarterProvider =
    Provider<LanSyncHostStarter>((ref) => createLanSyncHost);

/// 同网段设备搜索器（原生端是 UDP 广播）。
final Provider<LanSyncDiscovery> lanSyncDiscoveryProvider =
    Provider<LanSyncDiscovery>((ref) => createLanSyncDiscovery());

/// 按「目标设备 + 配对码」构造对端客户端。
final Provider<LanSyncClientFactory> lanSyncClientFactoryProvider =
    Provider<LanSyncClientFactory>((ref) => LanSyncHttpClient.new);

/// 本机设置与上次同步状态的读写。
final Provider<LanSyncStateStore> lanSyncStateStoreProvider =
    Provider<LanSyncStateStore>(
      (ref) => LanSyncStateStore(ref.watch(settingsServiceProvider)),
    );

/// 共享会话的编排（不含界面状态）。
final Provider<LanSyncShareService> lanSyncShareServiceProvider =
    Provider<LanSyncShareService>(
      (ref) => LanSyncShareService(
        ref.watch(backupExporterProvider),
        ref.watch(lanSyncHostStarterProvider),
        ref.watch(lanSyncStateStoreProvider),
      ),
    );

/// 拉取服务。
final Provider<LanSyncPullService> lanSyncPullServiceProvider =
    Provider<LanSyncPullService>(
      (ref) => LanSyncPullService(
        ref.watch(lanSyncClientFactoryProvider),
        ref.watch(lanSyncDiscoveryProvider),
        BackupImporter(ref.watch(databaseProvider)),
        ref.watch(backupMergeServiceProvider),
        ref.watch(lanSyncStateStoreProvider),
      ),
    );

/// 共享会话的界面状态。
///
/// **keep-alive**（`Provider` 默认如此，不是 `autoDispose`）：用户开启共享后
/// 会切到别的 tab 甚至别的页面，服务端必须继续监听。这与
/// `webdavAutoBackupProvider` 的处境相反——那个是后台行为、界面不该 watch；
/// 本 provider 恰恰是给界面 watch 的。
final AsyncNotifierProvider<LanSyncShareController, LanSyncShareSession?>
lanSyncShareProvider =
    AsyncNotifierProvider<LanSyncShareController, LanSyncShareSession?>(
      LanSyncShareController.new,
    );

/// 把 [LanSyncShareService] 的会话包装成界面可直接 watch 的异步状态。
final class LanSyncShareController extends AsyncNotifier<LanSyncShareSession?> {
  /// 停止共享是异步的，而 `ref.onDispose` 是同步回调；这里只登记意图，
  /// 真正的收尾由 [LanSyncShareService.stop] 自己保证幂等。
  bool _disposed = false;

  @override
  Future<LanSyncShareSession?> build() async {
    final service = ref.watch(lanSyncShareServiceProvider);
    ref.onDispose(() {
      _disposed = true;
      // 不 await：`onDispose` 不能是异步的，而 `stop()` 只是关套接字，
      // 即使这一轮没跑完也不会留下需要回收的状态。
      unawaited(service.stop());
    });
    // 初始不共享：共享必须由用户显式开启（每次都会生成新的配对码）。
    return null;
  }

  /// 开启共享。
  Future<void> start() async {
    if (state.value != null && (state.value?.isSharing ?? false)) return;
    state = const AsyncValue<LanSyncShareSession?>.loading();
    try {
      final session = await ref
          .read(lanSyncShareServiceProvider)
          .start(onServed: _publish, onLockedOut: _publish);
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

  /// 把服务里的最新快照搬进界面状态。
  void _publish() {
    if (_disposed) return;
    final session = ref.read(lanSyncShareServiceProvider).session;
    state = AsyncValue<LanSyncShareSession?>.data(session);
  }
}
