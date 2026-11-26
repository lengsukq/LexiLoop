/// 桌面窗口初始化的原生实现（macOS / Android）。
///
/// 由 `desktop_window.dart` 条件导入选中；Web 端走
/// `desktop_window_web.dart`，因此本文件（以及 `window_manager` 依赖）
/// 不会进入浏览器构建。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:window_manager/window_manager.dart';

/// 设定 macOS 窗口的初始尺寸与最小尺寸。
///
/// 最小宽度设得比侧边栏断点小，让用户仍可把窗口缩到「底部 Tab」形态；
/// 但默认打开时给足宽度，呈现旧版那套侧边栏设计。
Future<void> configureDesktopWindow() async {
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
