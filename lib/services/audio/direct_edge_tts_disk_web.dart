/// 浏览器不使用 dart:io 磁盘缓存，保留 DirectEdgeSpeech 的内存缓存。
library;

import 'dart:typed_data';

/// Web 中不保存合成音频到应用文件系统。
Future<Uint8List?> readCachedEdgeAudio(String key) async => null;

/// Web 缓存交由 DirectEdgeSpeech 的进程内 LRU 管理。
Future<void> writeCachedEdgeAudio(String key, Uint8List bytes) async {}
