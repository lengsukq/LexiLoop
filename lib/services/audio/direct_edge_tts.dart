/// 直接从 Edge Read Aloud 服务生成 MP3；不依赖 Next.js 或用户 API Key。
///
/// 服务使用非官方协议，可能因上游调整而不可用；由 WordSpeaker 负责降级。
library;

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';

import 'package:lexiloop/services/audio/direct_edge_tts_disk_web.dart'
    if (dart.library.io) 'package:lexiloop/services/audio/direct_edge_tts_disk_native.dart'
    as edge_disk;

/// 抽象直连音频生成，允许纯内存单元测试覆盖网络请求。
abstract interface class DirectEdgeSpeechPort {
  /// 返回 MP3 音频；请求失败时返回 null，不把上游异常泄漏到学习页。
  Future<Uint8List?> synthesize({required String text, required Accent accent});
}

/// 用 FlutterEdgeTts 完成 WebSocket 合成，带会话内 LRU 缓存与并发去重。
class DirectEdgeSpeech implements DirectEdgeSpeechPort {
  /// 构建独立合成服务。
  new();

  final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List?>> _pending =
      <String, Future<Uint8List?>>{};

  @override
  Future<Uint8List?> synthesize({
    required String text,
    required Accent accent,
  }) {
    final term = text.trim();
    if (term.isEmpty) return Future<Uint8List?>.value();
    final key = '${accent.wire}:${term.toLowerCase()}';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return Future<Uint8List?>.value(hit);
    }
    final inflight = _pending[key];
    if (inflight != null) return inflight;
    final future = _loadOrFetch(key, term, accent)
        .then((bytes) {
          if (bytes != null && bytes.isNotEmpty) {
            _cache[key] = bytes;
            while (_cache.length > ttsCacheMaxEntries) {
              _cache.remove(_cache.keys.first);
            }
          }
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
    try {
      final cached = await edge_disk.readCachedEdgeAudio(key);
      if (cached != null && cached.isNotEmpty) return cached;
    } on Object {
      // 缓存不可用不影响联网合成。
    }
    final bytes = await _fetch(term, accent);
    if (bytes != null && bytes.isNotEmpty) {
      try {
        await edge_disk.writeCachedEdgeAudio(key, bytes);
      } on Object {
        // 写缓存失败不应丢掉已经获取到的音频。
      }
    }
    return bytes;
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
      // Edge 接口非官方；403、超时、断网均交给下一语音来源兜底。
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
