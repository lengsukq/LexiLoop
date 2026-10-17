/// 同网段设备搜索的平台分支。
///
/// 与 `database_connection.dart`、`backup_file.dart` 同一套约定：调用方
/// import 不带后缀的本文件，由它选中实现。
library;

export 'lan_sync_discovery_native.dart'
    if (dart.library.js_interop) 'lan_sync_discovery_web.dart';
