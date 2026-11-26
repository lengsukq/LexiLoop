/// 备份文件交付的平台分支。
///
/// **为什么必须条件导入**：原生端要把备份落到临时目录再交给系统分享面板
/// （`path_provider` + `dart:io`），Web 端没有可写临时目录，只能把字节交给
/// `share_plus`，由浏览器下载。两端共用同一个函数签名，调用方无需分支。
library;

export 'backup_file_native.dart'
    if (dart.library.js_interop) 'backup_file_web.dart';
