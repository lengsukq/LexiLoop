/// 共享服务端的平台分支。
///
/// 与 `database_connection.dart`、`backup_file.dart` 同一套约定：调用方
/// import 不带后缀的本文件，由它选中实现。判定用 `dart.library.js_interop`
/// （Dart 3.13 起替代 `dart.library.html`）。
///
/// **为什么必须条件导入**：原生实现要 `dart:io` 的 `HttpServer` 与
/// `RawDatagramSocket`，两者在 Web 构建的依赖图里根本不存在；
/// 而架构守卫又把 `dart:io` 限制在 `*_native.dart` 里。
library;

export 'lan_sync_host_native.dart'
    if (dart.library.js_interop) 'lan_sync_host_web.dart';
