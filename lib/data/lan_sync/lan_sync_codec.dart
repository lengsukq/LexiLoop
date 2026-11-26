/// 局域网同步编解码入口（GZip 压缩 + 后台 Isolate JSON 编解码）。
///
/// 原生端在 `lan_sync_codec_native.dart` 中使用 `dart:io` 的 `gzip` 与
/// `dart:isolate` 的 `Isolate.run`，确保大词库同步期间 UI 线程不掉帧；
/// Web 端退化为无压缩同步实现以保持全平台可编译。
library;

export 'lan_sync_codec_native.dart'
    if (dart.library.js_interop) 'lan_sync_codec_web.dart';
