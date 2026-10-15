/// 数据库连接的平台分支。
///
/// **为什么必须条件导入**：原生端的 `package:drift/native.dart` 依赖
/// `dart:ffi` 与 `path_provider`，两者在 Web 上都不存在；Web 端则必须用
/// `package:drift/wasm.dart` 走浏览器存储。把连接构造收进这一层，
/// `AppDatabase.open()` 就能对两端保持同一签名。
///
/// 判定用 `dart.library.js_interop`（Dart 3.13 起替代 `dart.library.html`）。
library;

export 'database_connection_native.dart'
    if (dart.library.js_interop) 'database_connection_web.dart';
