/// Flutter 复用 Next.js Edge TTS 的 HTTP 音频契约及失败降级。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/direct_edge_tts.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/audio/word_speaker.dart';
import 'package:lexiloop/services/tts_service.dart';

import 'audio_fakes.dart';
import 'audio_fixtures.dart';

/// 直连合成器的假实现：记录请求，验证无后端依赖的路径。
class _FakeDirectEdgeSpeech implements DirectEdgeSpeechPort {
  int calls = 0;
  Accent? accent;
  Uint8List? audio = Uint8List.fromList(<int>[1, 2, 3]);

  @override
  Future<Uint8List?> synthesize({
    required String text,
    required Accent accent,
  }) async {
    calls += 1;
    this.accent = accent;
    return audio;
  }
}

PlaybackSettings _settings(
  SpeechSource source, {
  bool fallback = true,
  String server = 'https://speech.example.com',
}) => PlaybackSettings(
  choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
  defaultAccent: Accent.us,
  wordSpeed: defaultSpeechRate,
  phraseSpeed: defaultSpeechRate,
  sentenceSpeed: defaultSpeechRate,
  autoPlayPronunciation: false,
  speechSource: source,
  speechFallbackEnabled: fallback,
  onlineTtsBaseUrl: server,
);

void main() {
  test('Edge TTS 可直接合成英音并播放，不要求 Next.js 地址', () async {
    final edge = _FakeDirectEdgeSpeech();
    final downloader = FakeAudioDownloader()..openGate();
    final player = FakeAudioPlayer();
    final system = RecordingSpeechEngine()..speakError = Exception('本机缺少英文语音包');
    final speaker = WordSpeaker(
      player,
      AudioCache(downloader),
      TtsService(system),
      edge: edge,
    );
    final request = speechRequest(
      term: 'majority',
      accent: Accent.uk,
      playback: _settings(SpeechSource.edge, server: '', fallback: false),
    );

    expect(await speaker.speak(request), isA<DirectEdgeVoicePlayed>());
    expect(edge.calls, 1);
    expect(edge.accent, Accent.uk);
    expect(player.playCount, 1);
    expect(downloader.downloaded, isEmpty);
    expect(system.spoken, isEmpty);
  });

  test('Edge TTS 不可用时可自动回退系统发音', () async {
    final edge = _FakeDirectEdgeSpeech()..audio = null;
    final downloader = FakeAudioDownloader()..openGate();
    final player = FakeAudioPlayer();
    final system = RecordingSpeechEngine();
    final speaker = WordSpeaker(
      player,
      AudioCache(downloader),
      TtsService(system),
      edge: edge,
    );

    expect(
      await speaker.speak(
        speechRequest(playback: _settings(SpeechSource.edge, server: '')),
      ),
      isA<SystemVoicePlayed>(),
    );
    expect(system.spoken, <String>['apple']);
    expect(
      await speaker.speak(
        speechRequest(
          playback: _settings(SpeechSource.edge, server: '', fallback: false),
        ),
      ),
      isA<SpeechFailed>(),
    );
  });

  test('自动来源在无词典音频时使用直连 Edge，不要求配置服务地址', () async {
    final edge = _FakeDirectEdgeSpeech();
    final downloader = FakeAudioDownloader()..openGate();
    final system = RecordingSpeechEngine()..speakError = Exception('本机缺少英文语音包');
    final speaker = WordSpeaker(
      FakeAudioPlayer(),
      AudioCache(downloader),
      TtsService(system),
      edge: edge,
    );

    expect(
      await speaker.speak(
        speechRequest(playback: _settings(SpeechSource.automatic, server: '')),
      ),
      isA<DirectEdgeVoicePlayed>(),
    );
    expect(edge.calls, 1);
    expect(system.spoken, isEmpty);
  });

  test('Next.js URL 与美音/英音、特殊字符参数保持接口一致', () {
    final us = onlineTtsAudioUri(
      baseUrl: 'https://speech.example.com/',
      term: 'hello world',
      accent: Accent.us,
    )!;
    expect(us.path, '/api/tts');
    expect(us.queryParameters, <String, String>{
      'word': 'hello world',
      'accent': 'US',
    });
    final uk = onlineTtsAudioUri(
      baseUrl: 'https://speech.example.com',
      term: 'majority',
      accent: Accent.uk,
    )!;
    expect(uk.queryParameters['accent'], 'UK');
    expect(
      onlineTtsAudioUri(
        baseUrl: 'http://not-secure.example.com',
        term: 'hello',
        accent: Accent.us,
      ),
      isNull,
    );
    expect(
      onlineTtsAudioUri(
        baseUrl: 'https://speech.example.com/private',
        term: 'hello',
        accent: Accent.us,
      ),
      isNull,
    );
  });

  test('选择 Next.js 在线 TTS，直接播放 MP3，命中缓存不重复下载', () async {
    final downloader = FakeAudioDownloader()..openGate();
    final player = FakeAudioPlayer();
    final engine = RecordingSpeechEngine();
    final speaker = WordSpeaker(
      player,
      AudioCache(downloader),
      TtsService(engine),
    );
    final request = speechRequest(
      playback: _settings(SpeechSource.online),
      term: 'majority',
      accent: Accent.uk,
    );

    expect(await speaker.speak(request), isA<OnlineVoicePlayed>());
    expect(await speaker.speak(request), isA<OnlineVoicePlayed>());
    expect(downloader.downloaded, hasLength(1));
    expect(downloader.downloaded.single.path, '/api/tts');
    expect(downloader.downloaded.single.queryParameters['accent'], 'UK');
    expect(player.playCount, 2);
    expect(engine.spoken, isEmpty);
  });

  test('Next.js 请求失败：允许降级时系统朗读，不允许时明确失败', () async {
    final downloader = FakeAudioDownloader()..openGate();
    final player = FakeAudioPlayer();
    final engine = RecordingSpeechEngine();
    final speaker = WordSpeaker(
      player,
      AudioCache(downloader),
      TtsService(engine),
    );
    final url = onlineTtsAudioUri(
      baseUrl: 'https://speech.example.com',
      term: 'apple',
      accent: Accent.us,
    )!;
    downloader.failing.add(url.toString());

    expect(
      await speaker.speak(
        speechRequest(playback: _settings(SpeechSource.online)),
      ),
      isA<SystemVoicePlayed>(),
    );
    expect(engine.spoken, <String>['apple']);
    expect(
      await speaker.speak(
        speechRequest(
          playback: _settings(SpeechSource.online, fallback: false),
        ),
      ),
      isA<SpeechFailed>(),
    );
  });

  test('没有在线服务地址且不允许降级时返回配置提示', () async {
    final downloader = FakeAudioDownloader()..openGate();
    final speaker = WordSpeaker(
      FakeAudioPlayer(),
      AudioCache(downloader),
      TtsService(RecordingSpeechEngine()),
    );
    final result = await speaker.speak(
      speechRequest(
        playback: _settings(SpeechSource.online, server: '', fallback: false),
      ),
    );
    expect(result, isA<SpeechFailed>());
    expect((result as SpeechFailed).error.message, contains('Next.js'));
    expect(downloader.downloaded, isEmpty);
  });

  test('系统 TTS 无英文包时自动回退到在线词典录音', () async {
    final downloader = FakeAudioDownloader()..openGate();
    final engine = RecordingSpeechEngine()..languageAvailable = false;
    final speaker = WordSpeaker(
      FakeAudioPlayer(),
      AudioCache(downloader),
      TtsService(engine),
    );
    final result = await speaker.speak(
      speechRequest(playback: _settings(SpeechSource.automatic, server: '')),
    );
    expect(result, isA<HumanRecordingPlayed>());
    expect(downloader.downloaded.single, youdaoAudioUri('apple', Accent.us));
  });

  test('关闭发音时不会访问网络或系统 TTS', () async {
    final downloader = FakeAudioDownloader()..openGate();
    final engine = RecordingSpeechEngine();
    final speaker = WordSpeaker(
      FakeAudioPlayer(),
      AudioCache(downloader),
      TtsService(engine),
    );
    expect(
      await speaker.speak(speechRequest(playback: _settings(SpeechSource.off))),
      isA<SpeechDisabled>(),
    );
    expect(downloader.downloaded, isEmpty);
    expect(engine.spoken, isEmpty);
  });
}
