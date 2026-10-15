/// 应用入口。
///
/// 桌面端（macOS）需要先初始化 `window_manager` 设定窗口尺寸，
/// 因为侧边栏布局依赖足够的窗口宽度；Android 与 Web 跳过这一步。
///
/// **窗口配置为什么走 `app/desktop_window.dart`**：`window_manager` 在 Web 上
/// 编译不过，必须由条件导入隔离，调用点因此不能再直接 import 它。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/app.dart';
import 'package:lexiloop/app/desktop_window.dart';
import 'package:lexiloop/app/maintenance_bootstrap.dart';
import 'package:lexiloop/core/platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (PlatformCaps.isDesktop) {
    await configureDesktopWindow();
  }

  // ProviderScope 必须包在根部：数据库实例等依赖由它持有与释放。
  // MaintenanceBootstrap 在 Scope 之内、App 之外，负责点火初始化任务的
  // 后台维护（对应旧版由常驻进程驱动的定时任务）。
  runApp(
    const ProviderScope(child: MaintenanceBootstrap(child: LexiLoopApp())),
  );
}
