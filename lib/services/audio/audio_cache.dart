/// 有道/词典真人录音的二级缓存（L1 内存 LRU + L2 原生磁盘持久化）。
///
/// - L1（进程内 LRU，容量 [ttsCacheMaxEntries]）：保证学习会话内切词 0 ms 响应；
/// - L2（原生磁盘 [SpeechDiskCachePort]）：重启 App 与离线飞行模式下照常秒放；
/// - 单测不传 [SpeechDiskCachePort] 时自动退化为纯内存 LRU，保持零磁盘依赖。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/services/audio/audio_downloader.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';

/// 已下载真人录音的二级缓存。
class AudioCache {
  /// 以下载器与可选磁盘缓存端口构造。
  ///
  /// [maxEntries] 必须为正；传非正数等于禁用 L1 缓存。
  new(
    this._downloader, {
    this.maxEntries = ttsCacheMaxEntries,
    this.diskCache,
    this.policy,
  });

  final AudioDownloadPort _downloader;

  /// 可选磁盘缓存端口；为空时仅使用进程内内存 LRU。
  final SpeechDiskCachePort? diskCache;

  /// 运行时磁盘缓存策略读取回调；为空时默认开启持久化。
  final SpeechCachePolicyReader? policy;

  /// L1 内存缓存最多保留多少条音频。
  final int maxEntries;

  final LinkedHashMap<String, Uint8List> _entries =
      LinkedHashMap<String, Uint8List>();

  final Map<String, Future<Uint8List?>> _pending =
      <String, Future<Uint8List?>>{};

  int _writesSinceEvict = 0;

  /// 当前 L1 内存缓存的条目数。
  int get length => _entries.length;

  /// 仅取已经加载到内存的音频，不等待磁盘与网络。
  Uint8List? peek(Uri url) {
    final key = url.toString();
    final bytes = _entries.remove(key);
    if (bytes != null) _entries[key] = bytes;
    return bytes;
  }

  /// 取音频字节：L1 内存 → L2 磁盘 → 并发去重联网下载。
  ///
  /// **从不抛异常**：任何失败都返回 `null`，确保批量预取与自动顺延稳定。
  Future<Uint8List?> resolve(Uri url) {
    final key = url.toString();
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return Future<Uint8List?>.value(cached);
    }
    final inflight = _pending[key];
    if (inflight != null) return inflight;
    final request = _loadOrDownload(key, url).whenComplete(() {
      _pending.removeWhere((pending, value) => pending == key);
    });
    _pending[key] = request;
    return request;
  }

  /// 清空 L1 内存缓存（磁盘清理由 [SpeechDiskCachePort.clear] 独立负责）。
  void clear() {
    _entries.clear();
  }

  Future<Uint8List?> _loadOrDownload(String key, Uri url) async {
    final disk = diskCache;
    final currentPolicy = policy?.call() ?? SpeechCachePolicy.defaultEnabled;
    if (disk != null && currentPolicy.enabled) {
      final fromDisk = await disk.read(SpeechCacheBucket.youdao, key);
      if (fromDisk != null && fromDisk.isNotEmpty) {
        _putMemory(key, fromDisk);
        return fromDisk;
      }
    }
    final downloaded = await _download(key, url);
    if (downloaded != null && disk != null && currentPolicy.enabled) {
      await _persistToDisk(disk, key, downloaded, currentPolicy.maxBytes);
    }
    return downloaded;
  }

  Future<Uint8List?> _download(String key, Uri url) async {
    try {
      final bytes = await _downloader.download(url);
      if (bytes.isEmpty) return null;
      _putMemory(key, bytes);
      return bytes;
    } on Object {
      // 断网、限流、站点不可用都是常态而非缺陷，交由上层顺延下一个引擎。
      return null;
    }
  }

  Future<void> _persistToDisk(
    SpeechDiskCachePort disk,
    String key,
    Uint8List bytes,
    int maxBytes,
  ) async {
    await disk.write(SpeechCacheBucket.youdao, key, bytes);
    if (maxBytes <= 0) return;
    _writesSinceEvict += 1;
    if (_writesSinceEvict >= audioCacheEvictWriteStride) {
      _writesSinceEvict = 0;
      unawaited(disk.enforceLimit(maxBytes));
    }
  }

  void _putMemory(String key, Uint8List bytes) {
    _entries.remove(key);
    _entries[key] = bytes;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}
