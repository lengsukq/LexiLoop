/// 词条发音：真人录音优先，系统朗读兜底。
///
/// **这层存在的理由**：旧版 Next 应用同时提供有道真人 mp3 与服务端 Edge-TTS，
/// 两者的口音参数、缓存键、降级判断散落在 `lib/tts-client.ts` 与详情页 hook 里；
/// 本版只剩系统 TTS 时，声音质量相对旧版是明确的退步。把策略集中成一个
/// 不抛异常的服务之后，界面层只需要「调用 → 看结果」两件事。
///
/// **三条硬性约定**：
/// - 真人录音（词典 mp3）优先，这是相对旧版唯一不能丢的能力；
/// - 任何环节失败都回落到系统朗读，**绝不把异常抛给界面层**；
/// - 回落必须能被界面层观测到，否则用户无从判断词典音频是否可用。
library;

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

  /// 是否启用真人录音。
  ///
  /// 留作运行时总开关：真人录音依赖联网与第三方站点，一旦站点不可用，
  /// 关掉它就能立刻得到「只用系统朗读」的行为，而不必改任何调用点。
  /// 设置页尚未提供该项，接线时由界面层从设置读出来赋值即可。
  bool humanAudioEnabled = true;

  /// 朗读一个词条。
  ///
  /// 永远不会抛出：调用方只需要根据返回的 `SpeechResult` 决定提示什么。
  Future<SpeechResult> speak(SpeechRequest request) async {
    final playback = request.playback;
    if (playback.speechSource == SpeechSource.off) {
      return const SpeechDisabled();
    }
    final primary = await _tryPreferred(request);
    if (primary != null) return primary;
    final strict = _strictFailure(request);
    if (strict != null) return strict;
    final system = await _speakWithSystemVoice(request);
    if (system is SystemVoicePlayed || !playback.speechFallbackEnabled) {
      return system;
    }
    return await _tryFallback(request) ?? system;
  }

  /// 学习题目自动朗读必须立即出声，不能被在线真人录音的连接超时阻塞。
  /// 普通手动朗读仍遵循音源优先级；只有「自动选择」的背景播放采用
  /// 已缓存真人录音 → 系统语音 → Edge 的快速回退策略。
  Future<SpeechResult> speakForAutoPlay(SpeechRequest request) async {
    if (request.playback.speechSource != SpeechSource.automatic) {
      return await speak(request);
    }
    final url = humanAudioEnabled ? _audioUrlOf(request) : null;
    final cached = url == null ? null : _cache.peek(url);
    if (cached != null) {
      try {
        await _player.prepare(
          cached,
          speed: request.playback.speedFor(request.contentType),
        );
        await _player.play();
        return const HumanRecordingPlayed();
      } on Object {
        // 缓存字节可能不被设备解码；系统语音继续兜底。
      }
    }
    final system = await _speakWithSystemVoice(request);
    if (system is SystemVoicePlayed ||
        !request.playback.speechFallbackEnabled) {
      return system;
    }
    return await _tryDirectEdge(request) ?? system;
  }

  Future<SpeechResult?> _tryPreferred(SpeechRequest request) {
    if (request.playback.speechSource == SpeechSource.edge) {
      return _tryDirectEdge(request);
    }
    return _tryUrls(_preferredUrls(request), request);
  }

  SpeechResult? _strictFailure(SpeechRequest request) {
    final source = request.playback.speechSource;
    if (request.playback.speechFallbackEnabled ||
        source == SpeechSource.system) {
      return null;
    }
    if (source == SpeechSource.online && _nextUrl(request) == null) {
      return const SpeechFailed(
        PlatformCapabilityError(AppErrorCode.ttsOnlineNotConfigured),
      );
    }
    if (source == SpeechSource.edge ||
        _preferredUrls(request).any((url) => url != null)) {
      return const SpeechFailed(
        PlatformCapabilityError(AppErrorCode.ttsSynthesisFailed),
      );
    }
    return null;
  }

  Future<SpeechResult?> _tryFallback(SpeechRequest request) async {
    final source = request.playback.speechSource;
    if (source == SpeechSource.automatic && humanAudioEnabled) {
      final direct = await _tryDirectEdge(request);
      if (direct != null) return direct;
    }
    final other = switch (source) {
      SpeechSource.system => <Uri?>[
        _audioUrlOf(request),
        _nextUrl(request),
        _onlineUrlOf(request),
      ],
      SpeechSource.online => <Uri?>[
        _audioUrlOf(request),
        _onlineUrlOf(request),
      ],
      SpeechSource.dictionary => <Uri?>[_nextUrl(request)],
      SpeechSource.edge => <Uri?>[_audioUrlOf(request), _onlineUrlOf(request)],
      SpeechSource.automatic => <Uri?>[
        if (humanAudioEnabled) _onlineUrlOf(request),
      ],
      SpeechSource.off => <Uri?>[],
    };
    final backup = await _tryUrls(other, request);
    if (backup != null) return backup;
    if (source == SpeechSource.online ||
        source == SpeechSource.dictionary ||
        source == SpeechSource.system) {
      return await _tryDirectEdge(request);
    }
    return null;
  }

  Uri? _nextUrl(SpeechRequest request) => onlineTtsAudioUri(
    baseUrl: request.playback.onlineTtsBaseUrl,
    term: request.term,
    accent: request.accent,
  );

  List<Uri?> _preferredUrls(SpeechRequest request) =>
      switch (request.playback.speechSource) {
        SpeechSource.automatic => <Uri?>[
          if (humanAudioEnabled) _audioUrlOf(request),
          if (humanAudioEnabled) _nextUrl(request),
        ],
        SpeechSource.dictionary => <Uri?>[
          _audioUrlOf(request),
          _onlineUrlOf(request),
        ],
        SpeechSource.online => <Uri?>[_nextUrl(request)],
        SpeechSource.edge ||
        SpeechSource.system ||
        SpeechSource.off => <Uri?>[],
      };

  /// 直接播放 Flutter 本机请求到的 Edge MP3，失败由策略层选择下一个方案。
  Future<SpeechResult?> _tryDirectEdge(SpeechRequest request) async {
    final edge = _edge;
    if (edge == null) return null;
    try {
      final audio = await edge.synthesize(
        text: request.term,
        accent: request.accent,
      );
      if (audio == null || audio.isEmpty) return null;
      await _player.prepare(
        audio,
        speed: request.playback.speedFor(request.contentType),
      );
      await _player.play();
      return const DirectEdgeVoicePlayed();
    } on Object {
      return null;
    }
  }

  /// 批量预取真人录音。
  ///
  /// 预热的是「即将被点到的词」：学习界面一次只往前看几个词，提前把音频
  /// 拉好，点击时才有「秒开」的手感。按地址去重并限制并发
  /// （[audioPreloadConcurrency]），单条失败由缓存层吸收，整批照常完成。
  ///
  /// 只预热、不播放，因此**不涉及语速**：语速是播放时的参数。
  Future<void> preloadBatch(List<SpeechRequest> requests) async {
    if (requests.isNotEmpty &&
        requests.first.playback.speechSource == SpeechSource.edge) {
      final edge = _edge;
      if (edge == null) return;
      var cursor = 0;
      final workers = min(audioPreloadConcurrency, requests.length);
      await Future.wait(<Future<void>>[
        for (var worker = 0; worker < workers; worker += 1)
          () async {
            while (cursor < requests.length) {
              final request = requests[cursor++];
              await edge.synthesize(text: request.term, accent: request.accent);
            }
          }(),
      ]);
      return;
    }
    if (!humanAudioEnabled &&
        requests.every(
          (request) =>
              request.playback.speechSource != SpeechSource.online &&
              request.playback.speechSource != SpeechSource.dictionary,
        )) {
      return;
    }
    final urls = _distinctAudioUrls(requests);
    if (urls.isEmpty) return;
    var cursor = 0;
    final workers = min(audioPreloadConcurrency, urls.length);
    await Future.wait(<Future<void>>[
      for (var worker = 0; worker < workers; worker += 1)
        _drain(urls, () => cursor++),
    ]);
  }

  /// 停止播放。
  ///
  /// 播放器的释放由 `audioPlayerPortProvider` 负责——它构造播放器，
  /// 就只有它有权释放；在本服务里也释放一次会让两处 provider 都去
  /// 关闭同一个平台资源。
  Future<void> stop() => _player.stop();

  Uri? _audioUrlOf(SpeechRequest request) => resolveHumanAudioUrl(
    term: request.term,
    accent: request.accent,
    pronunciations: request.pronunciations,
  );

  /// 播放词典录音。
  ///
  /// 录音按设置里的倍率放，与系统朗读共用同一套语速：两者都取自
  /// [PlaybackSettings.speedFor]，各自引擎的换算只发生在
  /// `TtsService._engineRate`。若播录音时不传倍率，用户把「单词语速」调到
  /// 0.5 后会发现系统朗读变慢了、词典录音却纹丝不动。
  Future<SpeechResult?> _tryRecording(Uri url, SpeechRequest request) async {
    Uint8List? bytes;
    try {
      bytes = await _cache.resolve(url);
    } on Object {
      return null;
    }
    if (bytes == null) return null;
    try {
      await _player.prepare(
        bytes,
        speed: request.playback.speedFor(request.contentType),
      );
      await _player.play();
      return url.path == '/api/tts'
          ? const OnlineVoicePlayed()
          : const HumanRecordingPlayed();
    } on Object {
      return null;
    }
  }

  /// 依次尝试多个音频 URL，相同地址只请求一次。
  Future<SpeechResult?> _tryUrls(
    Iterable<Uri?> urls,
    SpeechRequest request,
  ) async {
    final seen = <String>{};
    for (final uri in urls) {
      if (uri == null || !seen.add(uri.toString())) continue;
      final result = await _tryRecording(uri, request);
      if (result != null) return result;
    }
    return null;
  }

  /// 仅为英文单词、短语构造公开词典地址；整句不猜测为词典音频。
  Uri? _onlineUrlOf(SpeechRequest request) {
    if (request.contentType == LexicalContentType.sentence) return null;
    if (!RegExp(r"^[a-zA-Z][a-zA-Z '\-]*$").hasMatch(request.term.trim())) {
      return null;
    }
    return youdaoAudioUri(request.term, request.accent);
  }

  Future<SpeechResult> _speakWithSystemVoice(SpeechRequest request) async {
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
      return const SystemVoicePlayed();
    } on Object catch (error) {
      return SpeechFailed(normalizeError(error));
    }
  }

  List<Uri> _distinctAudioUrls(List<SpeechRequest> requests) {
    final seen = <String>{};
    final urls = <Uri>[];
    for (final request in requests) {
      final playback = request.playback;
      final url = switch (playback.speechSource) {
        SpeechSource.online => onlineTtsAudioUri(
          baseUrl: playback.onlineTtsBaseUrl,
          term: request.term,
          accent: request.accent,
        ),
        SpeechSource.off || SpeechSource.system || SpeechSource.edge => null,
        SpeechSource.dictionary || SpeechSource.automatic =>
          humanAudioEnabled ? _audioUrlOf(request) : null,
      };
      if (url == null) continue;
      if (seen.add(url.toString())) urls.add(url);
    }
    return urls;
  }

  /// 取下一个待下载的下标并下载，直到越过末尾。
  ///
  /// [nextIndex] 必须返回**本次要用的下标**（0 起）：写成 `cursor += 1`
  /// 会把下标整体推后一位，第 0 个地址永远不下载——1 条时一条都不下，
  /// 6 条时只下 5 条，而且失败得毫无声息。
  Future<void> _drain(List<Uri> urls, int Function() nextIndex) async {
    while (true) {
      final index = nextIndex();
      if (index >= urls.length) return;
      await _cache.resolve(urls[index]);
    }
  }
}
