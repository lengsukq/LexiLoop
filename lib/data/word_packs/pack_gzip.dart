/// 词书包 GZip 编解码的平台条件导出。
library;

export 'pack_gzip_native.dart'
    if (dart.library.js_interop) 'pack_gzip_web.dart';
