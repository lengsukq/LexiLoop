/// 应用入口。
///
/// 桌面端（macOS）需要先初始化 `window_manager` 设定窗口尺寸，
/// 因为侧边栏布局依赖足够的窗口宽度；Android 与 Web 跳过这一步。
///
/// **窗口配置为什么走 `app/desktop_window.dart`**：`window_manager` 在 Web 上
/// 编译不过，必须由条件导入隔离，调用点因此不能再直接 import 它。
///
/// **为什么在 `runApp` 之前手动建一个 `ProviderContainer`**：外观设置存在
/// 本地数据库里，而主题必须在首帧就正确——否则选了深色的用户每次启动都会
/// 先看到一帧白屏。这里预读一次设置（最多等 `appearancePreloadBudgetMs`），
/// 再用 `UncontrolledProviderScope` 把**同一个容器**交给组件树。
/// 不能用「外面再包一个 `ProviderScope`」：那会得到两个容器、两个数据库实例。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/app.dart';
import 'package:lexiloop/app/desktop_window.dart';
import 'package:lexiloop/app/maintenance_bootstrap.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/data/db/dao_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (PlatformCaps.isDesktop) {
    await configureDesktopWindow();
  }

  final container = ProviderContainer();
  await _preloadAppearance(container);

  // MaintenanceBootstrap 在 Scope 之内、App 之外，负责点火初始化任务的
  // 后台维护（对应旧版由常驻进程驱动的定时任务）。
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MaintenanceBootstrap(child: LexiLoopApp()),
    ),
  );
}

/// 预读外观设置，最多等 [appearancePreloadBudgetMs]。
///
/// 读失败或超时都不阻断启动：页面会显示自己的错误态，主题先用默认外观，
/// 等设置真正到达后再平滑切过去。失败被就地吞掉是有意的——这里没有
/// 可以向用户展示错误的位置，而 `main` 抛异常只会得到一个黑屏。
Future<void> _preloadAppearance(ProviderContainer container) async {
  final ready = container
      .read(appSettingsProvider.future)
      .then<void>((_) {}, onError: (Object _) {});
  try {
    await Future.any<void>(<Future<void>>[
      ready,
      Future<void>.delayed(
        const Duration(milliseconds: appearancePreloadBudgetMs),
      ),
    ]);
  } on Object {
    // 见函数注释：启动不因外观读取失败而中断。
  }
}
