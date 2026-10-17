/// 应用根组件。
///
/// 负责装配主题、路由，以及 `⌘1`–`⌘8`（macOS）/ `Ctrl+1`–`Ctrl+8` 的
/// 全局导航快捷键，与旧版 `app-shell.tsx` 的快捷键行为一致。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/app/router.dart';
import 'package:lexiloop/ui/feedback/messenger.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 快捷键 1–8 对应的数字键。
///
/// `LogicalKeyboardKey` 不支持算术运算，必须显式列表映射。
const List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
];

/// LexiLoop 应用根组件。
class LexiLoopApp extends StatelessWidget {
  /// 创建应用根组件。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LexiLoop 词环',
      debugShowCheckedModeBanner: false,
      // 让「没有 BuildContext」的代码也能把失败说给用户听，见
      // `ui/feedback/messenger.dart`：设置写库失败是唯一一个这样的场景，
      // 而它此前完全静默。
      scaffoldMessengerKey: appMessengerKey,
      theme: LexiTheme.light,
      darkTheme: LexiTheme.dark,
      routerConfig: appRouter,
      builder: (context, child) => _GlobalShortcuts(child: child),
    );
  }
}

/// 提供全局导航快捷键的包装层。
///
/// 同时绑定 `⌘`（macOS）与 `Ctrl`（其他平台），避免平台分支。
class _GlobalShortcuts extends StatelessWidget {
  const new({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{};
    for (final destination in appDestinations) {
      final key = _digitKeys[destination.shortcut - 1];
      void go() => context.go(destination.path);
      bindings[SingleActivator(key, meta: true)] = go;
      bindings[SingleActivator(key, control: true)] = go;
    }

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child ?? const SizedBox.shrink()),
    );
  }
}
