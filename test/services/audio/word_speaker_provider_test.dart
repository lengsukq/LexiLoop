/// 发音服务 provider 接线的单测。
///
/// **重点不是覆盖率，而是守住接线的形状**：界面层拿到的是
/// `wordSpeakerProvider`，测试要能只覆盖依赖就换成假实现、不碰任何平台通道。
/// 这与现有 `ttsServiceProvider.overrideWithValue(...)` 的写法是同一套。
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/audio/direct_edge_tts.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/tts_service.dart';

import 'audio_fakes.dart';
import 'audio_fixtures.dart';

class _OfflineEdgeSpeech implements DirectEdgeSpeechPort {
  @override
  Future<Uint8List?> synthesize({
    required String text,
    required Accent accent,
  }) async => null;
}

void main() {
  late FakeAudioPlayer player;
  late FakeAudioDownloader downloader;
  late RecordingSpeechEngine engine;

  setUp(() {
    player = FakeAudioPlayer();
    downloader = FakeAudioDownloader();
    engine = RecordingSpeechEngine();
    downloader.openGate();
  });

  ProviderContainer containerWithOverrides() => ProviderContainer(
    overrides: [
      audioPlayerPortProvider.overrideWithValue(player),
      audioDownloaderProvider.overrideWithValue(downloader),
      directEdgeSpeechProvider.overrideWithValue(_OfflineEdgeSpeech()),
      ttsServiceProvider.overrideWithValue(TtsService(engine)),
    ],
  );

  test('只覆盖依赖就能拿到不发网络请求的发音服务', () async {
    final container = containerWithOverrides();
    addTearDown(container.dispose);

    final result = await container
        .read(wordSpeakerProvider)
        .speak(
          speechRequest(
            pronunciations: <PronunciationView>[
              pronunciation(audioUrl: 'https://example.com/apple-us.mp3'),
            ],
          ),
        );

    expect(result, isA<HumanRecordingPlayed>());
    expect(downloader.downloaded, hasLength(1));
    expect(player.playCount, 1);
    expect(engine.spoken, isEmpty);
  });

  test('覆盖 ttsServiceProvider 即可观察降级路径', () async {
    downloader.failing.add(
      'https://dict.youdao.com/dictvoice?audio=apple&type=1',
    );
    final container = containerWithOverrides();
    addTearDown(container.dispose);

    final result = await container
        .read(wordSpeakerProvider)
        .speak(speechRequest(accent: Accent.uk));

    expect(result, isA<SystemVoicePlayed>());
    expect(result.fellBackToSystemVoice, isTrue);
    expect(engine.configureCalls.single.$2, 'en-GB');
  });

  test('缓存与播放器在多次读取间复用同一份', () {
    final container = containerWithOverrides();
    addTearDown(container.dispose);

    expect(
      container.read(audioCacheProvider),
      same(container.read(audioCacheProvider)),
    );
    expect(
      container.read(wordSpeakerProvider),
      same(container.read(wordSpeakerProvider)),
    );
  });
}
