/// 词条发音：按用户自定义的多选优先级链依次尝试，失败自动顺延。
///
/// 支持三种本地/直连引擎：
/// - [SpeechSource.youdao]：有道词典真人 MP3（优先词典自带地址，缺失时直连有道接口；整句自动跳过）；
/// - [SpeechSource.edge]：Flutter 直连微软 Edge 神经网络语音；
/// - [SpeechSource.system]：设备本地系统 TTS。
///
/// 任何环节失败都不会把异常抛给界面层，而是自动顺延到下一个已启用引擎；
/// 全部失败时返回 [SpeechFailed]，全部关闭时返回 [SpeechDisabled]。
library;

import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/audio_player_port.dart';
import 'package:lexiloop/services/audio/direct_edge_tts.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/tts_service.dart';

final RegExp _youdaoTermPattern = RegExp(r"^[a-zA-Z][a-zA-Z '\-]*$");
final RegExp _whitespacePattern = RegExp(r'\s+');

/// 口音到系统朗读语言的映射。
///
/// 语言由口音决定而不是由词条携带：[Accent] 只有美音与英音两种，
/// 两者都是英语。英音必须显式给出 `en-GB`——若传 `en`，`TtsService`
/// 会按它的语言表映射成 `en-US`，用户选了英音却听到美音。
String speechLanguageOf(Accent accent) => switch (accent) {
  Accent.us => 'en-US',
  Accent.uk => 'en-GB',
};

/// 词条发音服务。
class WordSpeaker {
  /// 以播放器、缓存与系统朗读服务构造。
  new(this._player, this._cache, this._tts, {this._edge});

  final AudioPlayerPort _player;
  final AudioCache _cache;
  final TtsService _tts;
  final DirectEdgeSpeechPort? _edge;

  /// 单调递增的朗读代际号，用于打断已过期的在途下载，避免快速连点导致叠音。
  int _speakGeneration = 0;
  Timer? _activeTimer;
  Completer<void>? _cancelOnline;

  /// 朗读一个词条。
  ///
  /// 严格按 `request.playback.enabledSpeechSources` 的顺序尝试，永不抛出异常。
  Future<SpeechResult> speak(SpeechRequest request) =>
      _speakWithChain(request, onlineTimeout: null);

  /// 学习题目自动朗读。
  ///
  /// 同样遵守用户排定的优先级链（已预取的音频可直接 0ms 命中内存缓存）；
  /// 当链中后续包含离线系统朗读时，对在线引擎施加短超时（[autoPlayOnlineTimeoutMs]），
  /// 防止弱网阻塞答题节奏。
  Future<SpeechResult> speakForAutoPlay(SpeechRequest request) {
    final sources = request.playback.enabledSpeechSources;
    final hasOfflineBackup = sources.contains(SpeechSource.system);
    return _speakWithChain(
      request,
      onlineTimeout: hasOfflineBackup
          ? const Duration(milliseconds: autoPlayOnlineTimeoutMs)
          : null,
    );
  }

  /// 批量预取即将播放词条的首选在线音频。
  ///
  /// 只预热、不播放，按地址/文本去重并限制并发（[audioPreloadConcurrency]），
  /// 单条失败由缓存层吸收，整批照常完成。
  Future<void> preloadBatch(List<SpeechRequest> requests) async {
    final youdaoUrls = _distinctYoudaoUrls(requests);
    final edgeItems = _distinctEdgeRequests(requests);
    await Future.wait(<Future<void>>[
      if (youdaoUrls.isNotEmpty) _preloadUrls(youdaoUrls),
      if (edgeItems.isNotEmpty) _preloadEdge(edgeItems),
    ]);
  }

  /// 停止当前播放并取消在途等待。
  ///
  /// 播放器的释放由 `audioPlayerPortProvider` 负责，这里只停止播放。
  Future<void> stop() {
    _speakGeneration += 1;
    _cancelPendingOnlineWait();
    return _player.stop();
  }

  void _cancelPendingOnlineWait() {
    _activeTimer?.cancel();
    _activeTimer = null;
    final signal = _cancelOnline;
    _cancelOnline = null;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<SpeechResult> _speakWithChain(
    SpeechRequest request, {
    required Duration? onlineTimeout,
  }) async {
    final sources = request.playback.enabledSpeechSources;
    if (sources.isEmpty) return const SpeechDisabled();
    final generation = ++_speakGeneration;
    SpeechSource? failedPrimary;
    SpeechFailed? lastFailure;
    for (final source in sources) {
      if (generation != _speakGeneration) return const SpeechDisabled();
      final attempt = await _trySource(
        source,
        request,
        generation: generation,
        fellBackFrom: failedPrimary,
        onlineTimeout: onlineTimeout,
      );
      if (generation != _speakGeneration) return const SpeechDisabled();
      final outcome = attempt.result;
      if (outcome is SpeechFailed) {
        lastFailure = outcome;
        failedPrimary ??= source;
        continue;
      }
      if (outcome != null) return outcome;
      if (attempt.applicable) failedPrimary ??= source;
    }
    return lastFailure ??
        const SpeechFailed(
          PlatformCapabilityError(AppErrorCode.ttsSynthesisFailed),
        );
  }

  Future<({SpeechResult? result, bool applicable})> _trySource(
    SpeechSource source,
    SpeechRequest request, {
    required int generation,
    required SpeechSource? fellBackFrom,
    required Duration? onlineTimeout,
  }) async => switch (source) {
    SpeechSource.youdao => await _tryYoudao(
      request,
      generation: generation,
      fellBackFrom: fellBackFrom,
      timeout: onlineTimeout,
    ),
    SpeechSource.edge => (
      result: await _tryDirectEdge(
        request,
        generation: generation,
        fellBackFrom: fellBackFrom,
        timeout: onlineTimeout,
      ),
      applicable: true,
    ),
    SpeechSource.system => (
      result: await _speakWithSystemVoice(request, fellBackFrom: fellBackFrom),
      applicable: true,
    ),
  };

  Future<({SpeechResult? result, bool applicable})> _tryYoudao(
    SpeechRequest request, {
    required int generation,
    required SpeechSource? fellBackFrom,
    required Duration? timeout,
  }) async {
    final urls = _youdaoUrls(request);
    if (urls.isEmpty) return (result: null, applicable: false);
    for (final uri in urls) {
      final played = await _tryRecording(
        uri,
        request,
        generation: generation,
        fellBackFrom: fellBackFrom,
        timeout: timeout,
      );
      if (played != null) return (result: played, applicable: true);
      if (generation != _speakGeneration) {
        return (result: const SpeechDisabled(), applicable: true);
      }
    }
    return (result: null, applicable: true);
  }

  /// 收集该请求可用的有道/词典音频地址（去重）：
  /// 1. 词典表里已存的同口音地址优先；
  /// 2. 单词和短语始终补一条有道直连地址，修复无预存 `audioUrl` 时直接跳过有道的问题。
  List<Uri> _youdaoUrls(SpeechRequest request) {
    final seen = <String>{};
    final urls = <Uri>[];
    void addIfValid(Uri? uri) {
      if (uri != null && seen.add(uri.toString())) urls.add(uri);
    }

    addIfValid(_audioUrlOf(request));
    addIfValid(_youdaoDirectUrlOf(request));
    return urls;
  }

  Uri? _audioUrlOf(SpeechRequest request) => resolveHumanAudioUrl(
    term: request.term,
    accent: request.accent,
    pronunciations: request.pronunciations,
  );

  /// 仅为英文单词与短语构造有道直连地址；完整长句交由 Edge 或系统朗读。
  Uri? _youdaoDirectUrlOf(SpeechRequest request) {
    if (request.contentType == LexicalContentType.sentence) return null;
    final trimmed = request.term.trim();
    if (!_youdaoTermPattern.hasMatch(trimmed)) return null;
    if (trimmed.split(_whitespacePattern).length > youdaoDirectMaxWords) {
      return null;
    }
    return youdaoAudioUri(trimmed, request.accent);
  }

  Future<SpeechResult?> _tryRecording(
    Uri url,
    SpeechRequest request, {
    required int generation,
    required SpeechSource? fellBackFrom,
    required Duration? timeout,
  }) async {
    final bytes = await _resolveBytes(url, timeout: timeout);
    if (bytes == null || generation != _speakGeneration) return null;
    try {
      await _player.prepare(
        bytes,
        speed: request.playback.speedFor(request.contentType),
      );
      if (generation != _speakGeneration) return const SpeechDisabled();
      await _player.play();
      return HumanRecordingPlayed(fellBackFrom: fellBackFrom);
    } on Object {
      return null;
    }
  }

  Future<Uint8List?> _resolveBytes(Uri url, {required Duration? timeout}) =>
      _awaitOnline(_cache.resolve(url), timeout: timeout);

  Future<Uint8List?> _awaitOnline(
    Future<Uint8List?> work, {
    required Duration? timeout,
  }) async {
    if (timeout == null) return await _resolveUnbounded(work);
    _cancelPendingOnlineWait();
    final completer = Completer<Uint8List?>();
    final cancel = Completer<void>();
    _cancelOnline = cancel;
    void finish(Uint8List? value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    _activeTimer = Timer(timeout, () => finish(null));
    unawaited(cancel.future.then((_) => finish(null)));
    unawaited(work.then(finish, onError: (Object _) => finish(null)));
    try {
      return await completer.future;
    } finally {
      _activeTimer?.cancel();
      _activeTimer = null;
      if (identical(_cancelOnline, cancel)) _cancelOnline = null;
    }
  }

  Future<Uint8List?> _resolveUnbounded(Future<Uint8List?> work) async {
    try {
      return await work;
    } on Object {
      return null;
    }
  }

  /// 直接播放 Flutter 本机请求到的 Edge MP3，失败由策略层顺延下一个引擎。
  Future<SpeechResult?> _tryDirectEdge(
    SpeechRequest request, {
    required int generation,
    required SpeechSource? fellBackFrom,
    required Duration? timeout,
  }) async {
    final edge = _edge;
    if (edge == null) return null;
    final audio = await _awaitOnline(
      edge.synthesize(text: request.term, accent: request.accent),
      timeout: timeout,
    );
    if (audio == null || audio.isEmpty || generation != _speakGeneration) {
      return null;
    }
    try {
      await _player.prepare(
        audio,
        speed: request.playback.speedFor(request.contentType),
      );
      if (generation != _speakGeneration) return const SpeechDisabled();
      await _player.play();
      return DirectEdgeVoicePlayed(fellBackFrom: fellBackFrom);
    } on Object {
      return null;
    }
  }

  Future<SpeechResult> _speakWithSystemVoice(
    SpeechRequest request, {
    required SpeechSource? fellBackFrom,
  }) async {
    try {
      // 先掐掉播放器：macOS 的系统朗读不会自动停掉上一段 mp3，
      // 不掐的话会出现「真人录音与机器音叠在一起」。
      await _player.stop();
      await _tts.speakTerm(
        term: request.term,
        sourceLanguage: speechLanguageOf(request.accent),
        contentType: request.contentType,
        playback: request.playback,
      );
      return SystemVoicePlayed(fellBackFrom: fellBackFrom);
    } on Object catch (error) {
      return SpeechFailed(normalizeError(error));
    }
  }

  List<Uri> _distinctYoudaoUrls(List<SpeechRequest> requests) {
    final seen = <String>{};
    final urls = <Uri>[];
    for (final request in requests) {
      final enabled = request.playback.enabledSpeechSources;
      if (enabled.isEmpty || enabled.first != SpeechSource.youdao) continue;
      final candidates = _youdaoUrls(request);
      if (candidates.isEmpty) continue;
      final primaryUrl = candidates.first;
      if (seen.add(primaryUrl.toString())) urls.add(primaryUrl);
    }
    return urls;
  }

  List<SpeechRequest> _distinctEdgeRequests(List<SpeechRequest> requests) {
    if (_edge == null) return const <SpeechRequest>[];
    final seen = <String>{};
    final items = <SpeechRequest>[];
    for (final request in requests) {
      final enabled = request.playback.enabledSpeechSources;
      if (enabled.isEmpty || enabled.first != SpeechSource.edge) continue;
      final key = '${request.accent.wire}:${request.term.trim().toLowerCase()}';
      if (seen.add(key)) items.add(request);
    }
    return items;
  }

  Future<void> _preloadUrls(List<Uri> urls) async {
    var cursor = 0;
    final workers = min(audioPreloadConcurrency, urls.length);
    await Future.wait(<Future<void>>[
      for (var worker = 0; worker < workers; worker += 1)
        _drainUrls(urls, () => cursor++),
    ]);
  }

  Future<void> _drainUrls(List<Uri> urls, int Function() nextIndex) async {
    while (true) {
      final index = nextIndex();
      if (index >= urls.length) return;
      await _cache.resolve(urls[index]);
    }
  }

  Future<void> _preloadEdge(List<SpeechRequest> items) async {
    final edge = _edge;
    if (edge == null) return;
    var cursor = 0;
    final workers = min(audioPreloadConcurrency, items.length);
    await Future.wait(<Future<void>>[
      for (var worker = 0; worker < workers; worker += 1)
        _drainEdge(edge, items, () => cursor++),
    ]);
  }

  Future<void> _drainEdge(
    DirectEdgeSpeechPort edge,
    List<SpeechRequest> items,
    int Function() nextIndex,
  ) async {
    while (true) {
      final index = nextIndex();
      if (index >= items.length) return;
      final request = items[index];
      await edge.synthesize(text: request.term, accent: request.accent);
    }
  }
}
