/// 多引擎自定义优先级与自动顺延策略单测（有道 / Edge / 系统 TTS）。
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

/// 直连 Edge 合成器的假实现。
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

PlaybackSettings _playbackWithChain(List<SpeechSourcePreference> chain) =>
    PlaybackSettings(
      choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
      defaultAccent: Accent.us,
      wordSpeed: defaultSpeechRate,
      phraseSpeed: defaultSpeechRate,
      sentenceSpeed: defaultSpeechRate,
      autoPlayPronunciation: false,
      speechChain: chain,
    );

void main() {
  test('仅勾选 Edge 时直接合成英音并播放，不访问有道或系统 TTS', () async {
    final edge = _FakeDirectEdgeSpeech();
    final downloader = FakeAudioDownloader()..openGate();
    final player = FakeAudioPlayer();
    final system = RecordingSpeechEngine()..speakError = Exception('缺少语音包');
    final speaker = WordSpeaker(
      player,
      AudioCache(downloader),
      TtsService(system),
      edge: edge,
    );
    final playback = _playbackWithChain(const <SpeechSourcePreference>[
      SpeechSourcePreference(source: SpeechSource.edge, enabled: true),
      SpeechSourcePreference(source: SpeechSource.youdao, enabled: false),
      SpeechSourcePreference(source: SpeechSource.system, enabled: false),
    ]);

    final result = await speaker.speak(
      speechRequest(term: 'majority', accent: Accent.uk, playback: playback),
    );

    expect(result, isA<DirectEdgeVoicePlayed>());
    expect(result.fellBack, isFalse);
    expect(edge.calls, 1);
    expect(edge.accent, Accent.uk);
    expect(player.playCount, 1);
    expect(downloader.downloaded, isEmpty);
    expect(system.spoken, isEmpty);
  });

  test('按自定义顺序 Edge → 有道 → 系统依次顺延，精确记录回退来源', () async {
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
    final playback = _playbackWithChain(const <SpeechSourcePreference>[
      SpeechSourcePreference(source: SpeechSource.edge, enabled: true),
      SpeechSourcePreference(source: SpeechSource.youdao, enabled: true),
      SpeechSourcePreference(source: SpeechSource.system, enabled: true),
    ]);

    // Edge 失败 → 顺延到有道直连成功
    final second = await speaker.speak(speechRequest(playback: playback));
    expect(second, isA<HumanRecordingPlayed>());
    expect(second.fellBack, isTrue);
    expect(second.fellBackFrom, SpeechSource.edge);
    expect(downloader.downloaded.single, youdaoAudioUri('apple', Accent.us));
    expect(system.spoken, isEmpty);

    // 有道也失败 → 继续顺延到系统朗读
    downloader.failing.add(youdaoAudioUri('banana', Accent.us)!.toString());
    final third = await speaker.speak(
      speechRequest(term: 'banana', playback: playback),
    );
    expect(third, isA<SystemVoicePlayed>());
    expect(third.fellBack, isTrue);
    expect(third.fellBackFrom, SpeechSource.edge);
    expect(system.spoken, <String>['banana']);
  });

  test('未勾选备用引擎时失败直接返回 SpeechFailed，不私自调用已关闭引擎', () async {
    final edge = _FakeDirectEdgeSpeech()..audio = null;
    final downloader = FakeAudioDownloader()..openGate();
    final system = RecordingSpeechEngine();
    final speaker = WordSpeaker(
      FakeAudioPlayer(),
      AudioCache(downloader),
      TtsService(system),
      edge: edge,
    );
    final edgeOnly = _playbackWithChain(const <SpeechSourcePreference>[
      SpeechSourcePreference(source: SpeechSource.edge, enabled: true),
      SpeechSourcePreference(source: SpeechSource.youdao, enabled: false),
      SpeechSourcePreference(source: SpeechSource.system, enabled: false),
    ]);

    final result = await speaker.speak(speechRequest(playback: edgeOnly));
    expect(result, isA<SpeechFailed>());
    expect(downloader.downloaded, isEmpty);
    expect(system.spoken, isEmpty);
  });

  test('系统排第一但缺少英文包时，自动顺延到有道直连发音', () async {
    final downloader = FakeAudioDownloader()..openGate();
    final engine = RecordingSpeechEngine()..languageAvailable = false;
    final speaker = WordSpeaker(
      FakeAudioPlayer(),
      AudioCache(downloader),
      TtsService(engine),
    );
    final playback = _playbackWithChain(const <SpeechSourcePreference>[
      SpeechSourcePreference(source: SpeechSource.system, enabled: true),
      SpeechSourcePreference(source: SpeechSource.youdao, enabled: true),
      SpeechSourcePreference(source: SpeechSource.edge, enabled: false),
    ]);

    final result = await speaker.speak(speechRequest(playback: playback));
    expect(result, isA<HumanRecordingPlayed>());
    expect(result.fellBackFrom, SpeechSource.system);
    expect(downloader.downloaded.single, youdaoAudioUri('apple', Accent.us));
  });

  test('整句在默认链（有道 → Edge → 系统）下直接跳过有道并由 Edge 无降级提示播报', () async {
    final edge = _FakeDirectEdgeSpeech();
    final downloader = FakeAudioDownloader()..openGate();
    final speaker = WordSpeaker(
      FakeAudioPlayer(),
      AudioCache(downloader),
      TtsService(RecordingSpeechEngine()),
      edge: edge,
    );

    final result = await speaker.speak(
      speechRequest(
        term: 'This is a resilient team.',
        contentType: LexicalContentType.sentence,
      ),
    );
    expect(result, isA<DirectEdgeVoicePlayed>());
    expect(result.fellBack, isFalse);
    expect(downloader.downloaded, isEmpty);
    expect(edge.calls, 1);
  });

  test('全部引擎关闭时返回 SpeechDisabled，不发请求也不调用系统 TTS', () async {
    final edge = _FakeDirectEdgeSpeech();
    final downloader = FakeAudioDownloader()..openGate();
    final engine = RecordingSpeechEngine();
    final speaker = WordSpeaker(
      FakeAudioPlayer(),
      AudioCache(downloader),
      TtsService(engine),
      edge: edge,
    );
    final muted = _playbackWithChain(const <SpeechSourcePreference>[
      SpeechSourcePreference(source: SpeechSource.youdao, enabled: false),
      SpeechSourcePreference(source: SpeechSource.edge, enabled: false),
      SpeechSourcePreference(source: SpeechSource.system, enabled: false),
    ]);

    expect(
      await speaker.speak(speechRequest(playback: muted)),
      isA<SpeechDisabled>(),
    );
    expect(downloader.downloaded, isEmpty);
    expect(edge.calls, 0);
    expect(engine.spoken, isEmpty);
  });
}
