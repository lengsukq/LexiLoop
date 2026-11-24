/// 词条发音策略的单测。
///
/// 覆盖有道直连发音、自定义引擎优先级、失败自动顺延、口音选择与批量预取。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/speech_request.dart';
import 'package:lexiloop/services/audio/speech_result.dart';
import 'package:lexiloop/services/audio/word_speaker.dart';
import 'package:lexiloop/services/tts_service.dart';

import 'audio_fakes.dart';
import 'audio_fixtures.dart';

/// 一条带美音音频地址的发音。
PronunciationView _withRecording() => pronunciation(
  audioUrl: Uri.parse('https://example.com/apple-us.mp3').toString(),
);

/// 仅启用系统朗读的设置。
const PlaybackSettings _systemOnlyPlayback = PlaybackSettings(
  choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
  defaultAccent: Accent.us,
  wordSpeed: defaultSpeechRate,
  phraseSpeed: defaultSpeechRate,
  sentenceSpeed: defaultSpeechRate,
  autoPlayPronunciation: true,
  speechChain: <SpeechSourcePreference>[
    SpeechSourcePreference(source: SpeechSource.system, enabled: true),
    SpeechSourcePreference(source: SpeechSource.youdao, enabled: false),
    SpeechSourcePreference(source: SpeechSource.edge, enabled: false),
  ],
);

/// 一个明显慢于默认值的单词语速，用来验证倍率确实传到了播放器。
const double slowSpeed = 0.6;

void main() {
  late FakeAudioPlayer player;
  late FakeAudioDownloader downloader;
  late RecordingSpeechEngine engine;
  late AudioCache cache;
  late WordSpeaker speaker;

  setUp(() {
    player = FakeAudioPlayer();
    downloader = FakeAudioDownloader();
    engine = RecordingSpeechEngine();
    cache = AudioCache(downloader);
    speaker = WordSpeaker(player, cache, TtsService(engine));
    downloader.openGate();
  });

  group('学习自动朗读', () {
    test('已预缓存的录音自动播放时直接命中内存，不重复下载也不走系统发音', () async {
      final url = Uri.parse('https://example.com/apple-us.mp3');
      await cache.resolve(url);
      downloader.downloaded.clear();

      final result = await speaker.speakForAutoPlay(
        speechRequest(pronunciations: <PronunciationView>[_withRecording()]),
      );
      expect(result, isA<HumanRecordingPlayed>());
      expect(player.playCount, 1);
      expect(engine.spoken, isEmpty);
      expect(downloader.downloaded, isEmpty);
    });

    test('未预缓存时也按优先级播放有道直连发音，不静默退化为系统音', () async {
      final result = await speaker.speakForAutoPlay(speechRequest());
      expect(result, isA<HumanRecordingPlayed>());
      expect(downloader.downloaded, <Uri>[youdaoAudioUri('apple', Accent.us)!]);
      expect(engine.spoken, isEmpty);
    });

    test('全部引擎均不可用时上报失败供页面提示', () async {
      downloader.failing.add(youdaoAudioUri('apple', Accent.us)!.toString());
      engine.languageAvailable = false;
      final result = await speaker.speakForAutoPlay(speechRequest());
      expect(result, isA<SpeechFailed>());
    });
  });

  group('有道与词典真人录音优先', () {
    test('有预存音频地址时优先播放预存地址且不再朗读', () async {
      final stored = Uri.parse('https://example.com/apple-us.mp3');
      final result = await speaker.speak(
        speechRequest(
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: stored.toString()),
          ],
        ),
      );

      expect(result, isA<HumanRecordingPlayed>());
      expect(result.fellBack, isFalse);
      expect(downloader.downloaded, <Uri>[stored]);
      expect(player.prepared, hasLength(1));
      expect(player.playCount, 1);
      expect(engine.spoken, isEmpty);
    });

    test('发音列表为空时也能直接通过有道接口播放单词真人发音', () async {
      final result = await speaker.speak(speechRequest());

      expect(result, isA<HumanRecordingPlayed>());
      expect(result.fellBack, isFalse);
      expect(downloader.downloaded, <Uri>[youdaoAudioUri('apple', Accent.us)!]);
      expect(player.playCount, 1);
      expect(engine.spoken, isEmpty);
    });

    test('真人录音按设置里的倍率播放，与系统朗读同一套语速', () async {
      const playback = PlaybackSettings(
        choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
        defaultAccent: Accent.us,
        wordSpeed: slowSpeed,
        phraseSpeed: defaultSpeechRate,
        sentenceSpeed: defaultSpeechRate,
        autoPlayPronunciation: true,
      );
      await speaker.speak(
        speechRequest(
          pronunciations: <PronunciationView>[_withRecording()],
          playback: playback,
        ),
      );

      expect(player.preparedSpeeds, <double>[slowSpeed]);
    });
  });

  group('自动顺延与关闭引擎', () {
    test('下载失败时顺延到系统朗读并标记回退来源', () async {
      downloader.failing.add(youdaoAudioUri('apple', Accent.us)!.toString());
      final result = await speaker.speak(
        speechRequest(
          pronunciations: <PronunciationView>[
            pronunciation(source: youdaoAudioSource),
          ],
        ),
      );

      expect(result, isA<SystemVoicePlayed>());
      expect(result.fellBackToSystemVoice, isTrue);
      expect(result.fellBackFrom, SpeechSource.youdao);
      expect(engine.spoken, <String>['apple']);
    });

    test('播放器装载失败时自动顺延到系统朗读', () async {
      player.prepareError = Exception('播放器打不开');
      final result = await speaker.speak(
        speechRequest(
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: 'https://example.com/a.mp3'),
          ],
        ),
      );

      expect(result, isA<SystemVoicePlayed>());
      expect(result.fellBackFrom, SpeechSource.youdao);
      expect(engine.spoken, <String>['apple']);
    });

    test('有道与系统朗读均失败时返回 SpeechFailed 而不是抛出', () async {
      engine.speakError = Exception('没有语音包');
      downloader.failing.add(youdaoAudioUri('apple', Accent.us)!.toString());
      final result = await speaker.speak(speechRequest());

      expect(result, isA<SpeechFailed>());
      expect(result.played, isFalse);
      expect(result.fellBackToSystemVoice, isFalse);
    });

    test('仅启用系统朗读时连网络请求都不发，且不算回退', () async {
      final result = await speaker.speak(
        speechRequest(
          playback: _systemOnlyPlayback,
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: 'https://example.com/a.mp3'),
          ],
        ),
      );

      expect(result, isA<SystemVoicePlayed>());
      expect(result.fellBack, isFalse);
      expect(downloader.downloaded, isEmpty);
      expect(player.prepared, isEmpty);
    });

    test('回落到系统朗读前会掐掉播放器，避免两段音频叠加', () async {
      await speaker.speak(
        speechRequest(pronunciations: <PronunciationView>[_withRecording()]),
      );
      downloader.failing.add(youdaoAudioUri('banana', Accent.us)!.toString());
      await speaker.speak(speechRequest(term: 'banana'));

      expect(player.stopCount, 1);
      expect(player.playCount, 1);
      expect(engine.spoken, <String>['banana']);
    });
  });

  group('按口音选择', () {
    test('美音与英音取到不同的有道地址', () async {
      await speaker.speak(speechRequest());
      await speaker.speak(speechRequest(accent: Accent.uk));

      expect(downloader.downloaded, <Uri>[
        youdaoAudioUri('apple', Accent.us)!,
        youdaoAudioUri('apple', Accent.uk)!,
      ]);
      expect(player.playCount, 2);
    });

    test('系统朗读也按口音选语言', () async {
      await speaker.speak(
        speechRequest(accent: Accent.uk, playback: _systemOnlyPlayback),
      );

      expect(engine.configureCalls.single.$2, 'en-GB');
    });

    test('同口音只下载一次', () async {
      final request = speechRequest(
        pronunciations: <PronunciationView>[
          pronunciation(audioUrl: 'https://example.com/a.mp3'),
        ],
      );
      await speaker.speak(request);
      await speaker.speak(request);

      expect(downloader.downloaded, hasLength(1));
      expect(player.playCount, 2);
    });
  });

  group('批量预取', () {
    test('去重后只下载一份', () async {
      final requests = List<SpeechRequest>.generate(
        5,
        (_) => speechRequest(
          pronunciations: <PronunciationView>[_withRecording()],
        ),
      );
      await speaker.preloadBatch(requests);

      expect(downloader.downloaded, <Uri>[
        Uri.parse('https://example.com/apple-us.mp3'),
      ]);
      expect(downloader.peakConcurrency, 1);
    });

    test('无预存地址的单词也能预取有道直连发音，整句自动跳过', () async {
      await speaker.preloadBatch(<SpeechRequest>[
        speechRequest(),
        speechRequest(
          term: 'This is a sentence.',
          contentType: LexicalContentType.sentence,
        ),
      ]);

      expect(downloader.downloaded, <Uri>[youdaoAudioUri('apple', Accent.us)!]);
    });

    test('并发数不超过上限', () async {
      final slow = FakeAudioDownloader();
      final slowSpeaker = WordSpeaker(
        FakeAudioPlayer(),
        AudioCache(slow),
        TtsService(RecordingSpeechEngine()),
      );
      final requests = List<SpeechRequest>.generate(
        6,
        (index) => speechRequest(
          term: 'word$index',
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: 'https://example.com/w$index.mp3'),
          ],
        ),
      );

      final batch = slowSpeaker.preloadBatch(requests);
      await settle(4);

      expect(slow.active, audioPreloadConcurrency);

      slow.openGate();
      await batch;
      expect(slow.downloaded, hasLength(6));
    });

    test('单条失败不影响整批', () async {
      final broken = Uri.parse('https://example.com/w1.mp3');
      downloader.failing.add(broken.toString());
      final requests = List<SpeechRequest>.generate(
        4,
        (index) => speechRequest(
          term: 'word$index',
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: 'https://example.com/w$index.mp3'),
          ],
        ),
      );
      await expectLater(speaker.preloadBatch(requests), completes);
      expect(downloader.downloaded, hasLength(4));
      expect(cache.length, 3);
    });

    test('仅启用系统朗读时整批跳过预取', () async {
      final requests = <SpeechRequest>[
        speechRequest(
          playback: _systemOnlyPlayback,
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: 'https://example.com/a.mp3'),
          ],
        ),
      ];

      await speaker.preloadBatch(requests);

      expect(downloader.downloaded, isEmpty);
    });
  });

  group('生命周期', () {
    test('stop 透传给播放器', () async {
      await speaker.stop();

      expect(player.stopCount, 1);
    });
  });
}
