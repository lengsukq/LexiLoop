/// 浏览器端不落盘，所有语音缓存仅保留在进程内 LRU 中。
library;

import 'dart:typed_data';

import 'package:lexiloop/services/audio/speech_disk_cache.dart';

/// 创建浏览器平台空磁盘缓存实例。
SpeechDiskCachePort createPlatformDiskCache() => const WebSpeechDiskCache();

/// 浏览器端安全空实现。
class WebSpeechDiskCache implements SpeechDiskCachePort {
  /// 构造空实现。
  const new();

  @override
  bool get isSupported => false;

  @override
  Future<Uint8List?> read(SpeechCacheBucket bucket, String key) async => null;

  @override
  Future<void> write(
    SpeechCacheBucket bucket,
    String key,
    Uint8List bytes,
  ) async {}

  @override
  Future<bool> contains(SpeechCacheBucket bucket, String key) async => false;

  @override
  Future<SpeechCacheStats> stats() async => SpeechCacheStats.empty;

  @override
  Future<void> clear({SpeechCacheBucket? bucket}) async {}

  @override
  Future<int> enforceLimit(int maxBytes) async => 0;
}
