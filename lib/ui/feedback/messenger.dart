/// 应用级消息通道。
///
/// **为什么需要它**：有些失败发生在**没有 `BuildContext` 的位置**——
/// 最典型的是设置页的写库：`saveSettings(ref, …)` 只拿到 `WidgetRef`，
/// 而 `ScaffoldMessenger.of(context)` 需要 context。收敛前那 17 处调用
/// 全部写成 `unawaited(saveSettings(...))`，于是写失败既没有提示、
/// 也不会回滚：开关看起来已经切过去了，库里还是旧值，下次冷启动又弹回来。
///
/// 一个挂在 `MaterialApp.scaffoldMessengerKey` 上的全局 key 解决这件事：
/// 写库代码不必握住 context 也能把失败说给用户听。
///
/// **它不是用来替代 `ScaffoldMessenger.of(context)` 的**：页面里能拿到
/// context 的地方仍然用 `runGuarded` / `showSnackBar`，就近反馈更准确。
/// 这里只服务「非 widget 代码」这一种情况。
library;

import 'package:flutter/material.dart';

/// 全局消息 key，挂在 `MaterialApp.scaffoldMessengerKey` 上。
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 弹一条应用级提示；没有挂载 messenger 时静默返回。
///
/// 静默返回是有意的：这条通道服务于「原本完全没有反馈」的路径，
/// 在没有 UI 的测试环境里（`ProviderContainer` 单测）它不该变成新的失败点。
void showAppMessage(String message) {
  final messenger = appMessengerKey.currentState;
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}
