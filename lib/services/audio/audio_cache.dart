/// 已下载真人录音的内存 LRU。
///
/// **为什么只放内存、不落盘**：一份 1000 词的词库按每个发音约 10KB 估算，
/// 总量约 10MB——这正好是一次学习会话里真正会被反复点开的规模，落盘只会
/// 换来缓存失效策略、临时文件清理与磁盘占用审计三笔债，换不到任何东西。
/// 旧版 `src/modules/tts/cache.ts` 也是进程内 LRU，本版把「进程」换成
/// 「应用生命周期」，语义没有变化。
///
/// **容量**取 [ttsCacheMaxEntries]（200 条），与旧版 `MAX_CACHE_SIZE` 一致。
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/services/audio/audio_downloader.dart';

/// 已下载真人录音的内存 LRU 缓存。
class AudioCache {
  /// 以下载器构造。
  ///
  /// [maxEntries] 必须为正；传非正数等于禁用缓存，调用方通常不需要这样做。
  new(this._downloader, {this.maxEntries = ttsCacheMaxEntries});

  final AudioDownloadPort _downloader;

  /// 最多保留多少条音频。
  final int maxEntries;

  final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();

  final Map<String, Future<Uint8List?>> _pending =
      <String, Future<Uint8List?>>{};

  /// 当前已缓存的条目数。
  int get length => _entries.length;

  /// 取音频字节，命中缓存时完全不联网。
  ///
  /// **从不抛异常**：任何失败都返回 `null`。这是 `preloadBatch`
  /// 「单条失败不拖垮整批」的结构性保证——批量预取因此不需要任何
  /// `catch`，也就不会留下「静默吞异常」的空 catch 违规。
  ///
  /// 同一个地址的并发请求共享同一个下载（对应旧版 `pendingAudio`），
  /// 否则连点两次播放会同时拉两份音频。
  Future<Uint8List?> resolve(Uri url) {
    final key = url.toString();
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return Future<Uint8List?>.value(cached);
    }
    final inflight = _pending[key];
    if (inflight != null) return inflight;
    final request = _download(key, url).whenComplete(() {
      _pending.removeWhere((pending, value) => pending == key);
    });
    _pending[key] = request;
    return request;
  }

  /// 清空缓存。
  void clear() {
    _entries.clear();
  }

  Future<Uint8List?> _download(String key, Uri url) async {
    try {
      final bytes = await _downloader.download(url);
      if (bytes.isEmpty) return null;
      _entries.remove(key);
      _entries[key] = bytes;
      _evictOverflow();
      return bytes;
    } on Object {
      // 断网、限流、站点改地址都是常态而非缺陷，上层统一按
      // 「没有真人录音」处理并回落到系统朗读。
      return null;
    }
  }

  void _evictOverflow() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}
