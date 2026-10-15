/// 测试用的应用外壳。
///
/// **为什么需要它**：本项目的颜色、圆角等视觉 token 由 `LexiTheme` 通过
/// `Theme` 扩展（`context.lexiColors`）注入，而不是全局单例。任何直接
/// `pumpWidget(Widget)` 而没挂主题的用例，都会在第一次读 `lexiColors`
/// 时抛空断言——而报错信息指向 `AmbientBackground` / `DashboardCard`
/// 的内部实现，与「忘了挂主题」之间没有任何线索，很容易被误判成组件 bug。
///
/// 所以：**所有**渲染本项目 widget 的用例都必须经过这里，不要自己拼
/// `MaterialApp`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 给 [child] 套上应用主题与最小方向性环境。
///
/// 只需要 `MaterialApp` 就够：本项目的卡片大多自带 `LiquidGlass` 底板，
/// 不依赖 `Scaffold` 提供的 safe area。
Widget wrapWithAppTheme(Widget child) =>
    MaterialApp(theme: LexiTheme.light, home: child);

/// 把 [child] 套上主题与 [ProviderScope]。
///
/// [overrides] 用于注入内存数据库或假服务。
Widget wrapWithScope(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(overrides: overrides, child: wrapWithAppTheme(child));
