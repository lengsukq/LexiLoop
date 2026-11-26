/// 桌面窗口初始化的平台分支。
///
/// **为什么必须条件导入**：`window_manager` 0.5.2 的 Dart 代码 import
/// `dart:io`，Web 端编译不过。把它挡在条件导入之后，浏览器构建的依赖图里
/// 根本不会出现这个包；原生端的调用点（`lib/main.dart`）不用改一行。
///
/// 判定用 `dart.library.js_interop` 而非已废弃的 `dart.library.html`：
/// 后者在 Dart 3.13 起不再推荐，且无法区分 Wasm 与 JS 两种编译目标。
library;

export 'desktop_window_native.dart'
    if (dart.library.js_interop) 'desktop_window_web.dart';
