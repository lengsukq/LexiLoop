/// 应用入口。
///
/// 桌面端（macOS）需要先初始化 `window_manager` 设定窗口尺寸，
/// 因为侧边栏布局依赖足够的窗口宽度；Android 跳过这一步。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/app.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (PlatformCaps.isDesktop) {
    await _configureDesktopWindow();
  }

  runApp(const LexiLoopApp());
}

/// 设定 macOS 窗口的初始尺寸与最小尺寸。
///
/// 最小宽度设得比侧边栏断点小，让用户仍可把窗口缩到「底部 Tab」形态；
/// 但默认打开时给足宽度，呈现旧版那套侧边栏设计。
Future<void> _configureDesktopWindow() async {
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(defaultWindowWidth, defaultWindowHeight),
    minimumSize: Size(minWindowWidth, minWindowHeight),
    center: true,
    title: 'LexiLoop 词环',
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
