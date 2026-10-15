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

import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/audio_constants.dart';
import 'package:lexiloop/services/audio/audio_player_port.dart';
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
  new(this._player, this._cache, this._tts);

  final AudioPlayerPort _player;
  final AudioCache _cache;
  final TtsService _tts;

  /// 是否启用真人录音。
  ///
  /// 留作运行时总开关：真人录音依赖联网与第三方站点，一旦站点不可用，
  /// 关掉它就能立刻得到「只用系统朗读」的行为，而不必改任何调用点。
  /// 设置页尚未提供该项，接线时由界面层从设置读出来赋值即可。
  bool humanAudioEnabled = true;

  /// 朗读一个词条。
  ///
  /// 永远不会抛出：调用方只需要根据返回的 `SpeechResult` 决定提示什么。
  Future<SpeechResult> speak(SpeechRequest request) {
    if (!humanAudioEnabled) return _speakWithSystemVoice(request);
    final url = _audioUrlOf(request);
    if (url == null) return _speakWithSystemVoice(request);
    return _playRecording(url, request);
  }

  /// 批量预取真人录音。
  ///
  /// 预热的是「即将被点到的词」：学习界面一次只往前看几个词，提前把音频
  /// 拉好，点击时才有「秒开」的手感。按地址去重并限制并发
  /// （[audioPreloadConcurrency]），单条失败由缓存层吸收，整批照常完成。
  Future<void> preloadBatch(List<SpeechRequest> requests) async {
    if (!humanAudioEnabled) return;
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

  Future<SpeechResult> _playRecording(Uri url, SpeechRequest request) async {
    final bytes = await _cache.resolve(url);
    if (bytes == null) return await _speakWithSystemVoice(request);
    try {
      await _player.prepare(bytes);
      await _player.play();
      return const HumanRecordingPlayed();
    } on Object {
      return await _speakWithSystemVoice(request);
    }
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
      final url = _audioUrlOf(request);
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
