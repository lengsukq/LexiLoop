/// 统一离线语音磁盘缓存端口（按引擎分桶，支持统计、清理与 LRU 容量裁剪）。
///
/// 实际文件系统实现通过条件导出隔离在 `speech_disk_cache_native.dart` 中，
/// 浏览器端安全降级到 `speech_disk_cache_web.dart`，保持全应用可编译至 Web。
library;

import 'dart:typed_data';

import 'package:lexiloop/services/audio/speech_disk_cache_web.dart'
    if (dart.library.io) 'package:lexiloop/services/audio/speech_disk_cache_native.dart'
    as impl;

/// 离线语音缓存分桶。
enum SpeechCacheBucket {
  /// 有道直连与词典真人 MP3。
  youdao('youdao', '有道词典发音'),

  /// 微软 Edge 神经网络语音 MP3。
  edge('edge', '微软 Edge 语音');

  new(this.folder, this.label);

  /// 对应的子目录名（位于 `<AppSupport>/speech_cache/<folder>`）。
  final String folder;

  /// 设置页展示名称。
  final String label;
}

/// 离线语音磁盘缓存占用统计。
class SpeechCacheStats {
  /// 以两桶文件数与字节数构造。
  const new({
    required this.youdaoFiles,
    required this.youdaoBytes,
    required this.edgeFiles,
    required this.edgeBytes,
  });

  /// 空统计。
  static const SpeechCacheStats empty = SpeechCacheStats(
    youdaoFiles: 0,
    youdaoBytes: 0,
    edgeFiles: 0,
    edgeBytes: 0,
  );

  /// 有道 MP3 文件数。
  final int youdaoFiles;

  /// 有道 MP3 总字节数。
  final int youdaoBytes;

  /// Edge 语音文件数。
  final int edgeFiles;

  /// Edge 语音总字节数。
  final int edgeBytes;

  /// 总文件数。
  int get totalFiles => youdaoFiles + edgeFiles;

  /// 总字节数。
  int get totalBytes => youdaoBytes + edgeBytes;
}

/// 运行时磁盘缓存策略快照。
class SpeechCachePolicy {
  /// 以启用开关与字节上限构造。
  const new({required this.enabled, required this.maxBytes});

  /// 默认策略（启用持久化，不限容量，具体上限由设置层注入）。
  static const SpeechCachePolicy defaultEnabled = SpeechCachePolicy(
    enabled: true,
    maxBytes: 0,
  );

  /// 是否允许读写磁盘缓存。
  final bool enabled;

  /// 容量上限（字节）；`0` 表示不限制。
  final int maxBytes;
}

/// 磁盘缓存策略读取回调。
typedef SpeechCachePolicyReader = SpeechCachePolicy Function();

/// 统一离线语音磁盘缓存端口。
abstract interface class SpeechDiskCachePort {
  /// 当前平台是否支持持久化磁盘缓存（移动端/桌面端为 `true`，Web 为 `false`）。
  bool get isSupported;

  /// 读取一条已缓存音频；不存在或读取失败返回 `null`。
  Future<Uint8List?> read(SpeechCacheBucket bucket, String key);

  /// 原子写入一条音频。
  Future<void> write(SpeechCacheBucket bucket, String key, Uint8List bytes);

  /// 快速检查一条音频是否已落盘（不把字节加载进内存）。
  Future<bool> contains(SpeechCacheBucket bucket, String key);

  /// 统计各分桶的文件数与字节占用。
  Future<SpeechCacheStats> stats();

  /// 清空指定分桶，或省略 [bucket] 清空全部离线语音缓存。
  Future<void> clear({SpeechCacheBucket? bucket});

  /// 若总占用超出 [maxBytes]（且 [maxBytes] > 0），按最久未使用顺序淘汰旧文件。
  ///
  /// 返回本次被删除的文件数。
  Future<int> enforceLimit(int maxBytes);
}

/// 创建当前平台对应的磁盘缓存实现。
SpeechDiskCachePort createSpeechDiskCache() => impl.createPlatformDiskCache();
