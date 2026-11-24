/// 直接从 Edge Read Aloud 服务生成 MP3；不依赖外部后端或 API Key。
///
/// 服务使用非官方协议，可能因上游调整而不可用；由 WordSpeaker 负责自动顺延。
/// 磁盘持久化统一委托给 [SpeechDiskCachePort]（`edge` 分桶），纳入统一容量管理。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';

/// 抽象直连音频生成，允许纯内存单元测试覆盖网络请求。
abstract interface class DirectEdgeSpeechPort {
  /// 返回 MP3 音频；请求失败时返回 null，不把上游异常泄漏到学习页。
  Future<Uint8List?> synthesize({required String text, required Accent accent});
}

/// 生成 Edge 音频磁盘缓存键（与历史路径完全一致，老缓存零丢失）。
String edgeSpeechCacheKey(String text, Accent accent) =>
    '${accent.wire}:${text.trim().toLowerCase()}';

/// 用 FlutterEdgeTts 完成 WebSocket 合成，带 L1 内存 LRU、L2 磁盘缓存与并发去重。
class DirectEdgeSpeech implements DirectEdgeSpeechPort {
  /// 构建独立合成服务；默认使用当前平台的磁盘缓存实现。
  new({SpeechDiskCachePort? diskCache, this.policy})
    : _diskCache = diskCache ?? createSpeechDiskCache();

  final SpeechDiskCachePort _diskCache;

  /// 运行时磁盘缓存策略回调；为空时默认开启持久化。
  final SpeechCachePolicyReader? policy;

  final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _pending =
      <String, Future<Uint8List?>>{};
  int _writesSinceEvict = 0;

  /// 清空进程内 L1 缓存（配合设置页清空缓存动作使用）。
  void clearMemoryCache() {
    _cache.clear();
  }

  @override
  Future<Uint8List?> synthesize({
    required String text,
    required Accent accent,
  }) {
    final term = text.trim();
    if (term.isEmpty) return Future<Uint8List?>.value();
    final key = edgeSpeechCacheKey(term, accent);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return Future<Uint8List?>.value(hit);
    }
    final inflight = _pending[key];
    if (inflight != null) return inflight;
    final future = _loadOrFetch(key, term, accent)
        .then((bytes) {
          if (bytes != null && bytes.isNotEmpty) _putMemory(key, bytes);
          return bytes;
        })
        .whenComplete(() => _pending.remove(key));
    _pending[key] = future;
    return future;
  }

  Future<Uint8List?> _loadOrFetch(
    String key,
    String term,
    Accent accent,
  ) async {
    final currentPolicy = policy?.call() ?? SpeechCachePolicy.defaultEnabled;
    if (currentPolicy.enabled) {
      final cached = await _diskCache.read(SpeechCacheBucket.edge, key);
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final bytes = await _fetch(term, accent);
    if (bytes != null && bytes.isNotEmpty && currentPolicy.enabled) {
      await _diskCache.write(SpeechCacheBucket.edge, key, bytes);
      if (currentPolicy.maxBytes > 0) {
        _writesSinceEvict += 1;
        if (_writesSinceEvict >= audioCacheEvictWriteStride) {
          _writesSinceEvict = 0;
          unawaited(_diskCache.enforceLimit(currentPolicy.maxBytes));
        }
      }
    }
    return bytes;
  }

  void _putMemory(String key, Uint8List bytes) {
    _cache.remove(key);
    _cache[key] = bytes;
    while (_cache.length > ttsCacheMaxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  Future<Uint8List?> _fetch(String text, Accent accent) async {
    final tts = FlutterEdgeTts(
      voice: accent == Accent.uk ? 'en-GB-SoniaNeural' : 'en-US-JennyNeural',
      connectionTimeout: const Duration(
        seconds: directEdgeConnectTimeoutSeconds,
      ),
    );
    try {
      final result = await tts
          .synthesize(text)
          .timeout(const Duration(seconds: directEdgeRequestTimeoutSeconds));
      return result.audioBytes.isEmpty ? null : result.audioBytes;
    } on Object {
      // Edge 接口非官方；403、超时、断网均交给下一语音来源顺延。
      return null;
    } finally {
      await tts.close();
    }
  }

  /// 诊断模式不吞掉异常，以便区分网络、合成和播放器问题。
  Future<Uint8List> diagnose({
    required String text,
    required Accent accent,
  }) async {
    final tts = FlutterEdgeTts(
      voice: accent == Accent.uk ? 'en-GB-SoniaNeural' : 'en-US-JennyNeural',
      connectionTimeout: const Duration(
        seconds: directEdgeConnectTimeoutSeconds,
      ),
    );
    try {
      final result = await tts
          .synthesize(text)
          .timeout(const Duration(seconds: directEdgeRequestTimeoutSeconds));
      if (result.audioBytes.isEmpty) throw StateError('Edge 返回空音频');
      return result.audioBytes;
    } finally {
      await tts.close();
    }
  }
}
