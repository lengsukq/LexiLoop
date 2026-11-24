/// 应用启动时的后台维护点火器。
///
/// **为什么不直接写在 `main()` 里**：`main()` 没有 `WidgetRef`，拿不到
/// `ProviderScope`；而用 `ProviderContainer` 手动管理又会和 `runApp` 里的
/// `ProviderScope` 变成两个容器、两个数据库实例。用一个最外层的
/// `ConsumerStatefulWidget` 点火，既能拿到 `ref`，又能随组件树一起释放。
///
/// 挂在 `main()` 而不是 [LexiLoopApp]：这样测试直接 `pumpWidget(LexiLoopApp())`
/// 时不会启动定时器（`pumpAndSettle` 遇到未取消的 `Timer.periodic` 会挂住，
/// 测试进程结尾也会报「Timer 仍在挂起」）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/app.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/app/share_intent_bridge.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/features/add/article_providers.dart';
import 'package:lexiloop/services/remote_backup/webdav_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';

/// 在首帧之后启动后台维护。
///
/// 点火三件事：初始化任务队列的推进（[initializationMaintenanceProvider]）、
/// WebDAV 自动备份排期（[webdavAutoBackupProvider]），以及 Android 系统分享
/// 通道监听（[ShareIntentBridge]）。同时监听应用前后台生命周期，切入后台时
/// 暂停定时器以节省电量，回到前台时自动恢复。
class MaintenanceBootstrap extends ConsumerStatefulWidget {
  /// 以子组件构造。
  const new({required this.child, super.key});

  /// 被包裹的应用根组件。
  final Widget child;

  @override
  ConsumerState<MaintenanceBootstrap> createState() =>
      _MaintenanceBootstrapState();
}

class _MaintenanceBootstrapState extends ConsumerState<MaintenanceBootstrap>
    with WidgetsBindingObserver {
  late final ShareIntentBridge _shareBridge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 故意不在 initState 里 `await`：数据库查询是异步的，
    // 挂在 initState 会把首帧阻塞在「等 worker 跑完」上。
    unawaited(
      ref
          .read(initializationMaintenanceProvider)
          .start(now: DateTime.now().millisecondsSinceEpoch),
    );
    // 自动备份的调度也挂在这里：它同样只在应用启动时点火一次。
    // 未配置 WebDAV 或周期为 0 时，`start` 自己不会发任何请求。
    unawaited(ref.read(webdavAutoBackupProvider).start());
    _shareBridge = ShareIntentBridge(onSharedText: _handleSharedText);
    unawaited(_shareBridge.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareBridge.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final maintenance = ref.read(initializationMaintenanceProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        maintenance.resume();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        maintenance.pause();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _handleSharedText(String text) {
    if (!mounted) return;
    appRouter.go(articlePath);
    unawaited(
      ref.read(articleWizardProvider.notifier).ingestExternalText(text),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
