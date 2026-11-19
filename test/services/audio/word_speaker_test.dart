/// 词条发音策略的单测。
///
/// 钉的是旧版 Next 应用里最明显的听觉退步：真人 mp3 与系统朗读之间的
/// 选择、降级与提示信号——它们全部发生在一个界面层看不见的地方，
/// 少写一条就等于用户永远听到机器音。
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

  group('学习自动朗读快路径', () {
    test('录音尚未下载时立即用系统发音，绝不等在线请求', () async {
      final result = await speaker.speakForAutoPlay(
        speechRequest(pronunciations: <PronunciationView>[_withRecording()]),
      );
      expect(result, isA<SystemVoicePlayed>());
      expect(engine.spoken, <String>['apple']);
      expect(downloader.downloaded, isEmpty);
    });

    test('已预缓存的录音自动播放时无需联网，也不重复系统发音', () async {
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

    test('系统英语语音不可用时上报失败供页面提示', () async {
      engine.languageAvailable = false;
      final result = await speaker.speakForAutoPlay(speechRequest());
      expect(result, isA<SpeechFailed>());
    });
  });

  group('真人录音优先', () {
    test('有音频地址时播放词典录音且不再朗读', () async {
      final stored = Uri.parse('https://example.com/apple-us.mp3');
      final result = await speaker.speak(
        speechRequest(
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: stored.toString()),
          ],
        ),
      );

      expect(result, isA<HumanRecordingPlayed>());
      expect(result.fellBackToSystemVoice, isFalse);
      expect(downloader.downloaded, <Uri>[stored]);
      expect(player.prepared, hasLength(1));
      expect(player.playCount, 1);
      expect(engine.spoken, isEmpty);
    });

    test('mp3 成功时不触发系统朗读——不得两段一起响', () async {
      await speaker.speak(
        speechRequest(pronunciations: <PronunciationView>[_withRecording()]),
      );

      expect(player.playCount, 1);
      expect(engine.spoken, isEmpty);
      expect(engine.configureCalls, isEmpty);
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

      // 不传倍率时播放器只会用原速，用户调慢的语速在录音上会完全失效。
      expect(player.preparedSpeeds, <double>[slowSpeed]);
    });
  });

  group('回落到系统朗读', () {
    test('没有音频地址时直接用系统朗读', () async {
      final result = await speaker.speak(
        speechRequest(pronunciations: <PronunciationView>[pronunciation()]),
      );

      expect(result, isA<SystemVoicePlayed>());
      expect(result.fellBackToSystemVoice, isTrue);
      expect(downloader.downloaded, isEmpty);
      expect(engine.spoken, <String>['apple']);
    });

    test('地址是空白串时视为没有录音', () async {
      final result = await speaker.speak(
        speechRequest(
          pronunciations: <PronunciationView>[pronunciation(audioUrl: '   ')],
        ),
      );

      expect(result, isA<SystemVoicePlayed>());
      expect(downloader.downloaded, isEmpty);
    });

    test('下载失败时回落且不下结论式地缓存失败', () async {
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
      expect(engine.spoken, <String>['apple']);
    });

    test('播放器装载失败时回落', () async {
      player.prepareError = Exception('播放器打不开');
      final result = await speaker.speak(
        speechRequest(
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: 'https://example.com/a.mp3'),
          ],
        ),
      );

      expect(result, isA<SystemVoicePlayed>());
      expect(engine.spoken, <String>['apple']);
    });

    test('系统朗读也失败时返回失败而不是抛出', () async {
      engine.speakError = Exception('没有语音包');
      downloader.failing.add(youdaoAudioUri('apple', Accent.us)!.toString());
      final result = await speaker.speak(speechRequest());

      expect(result, isA<SpeechFailed>());
      expect(result.played, isFalse);
      expect(result.fellBackToSystemVoice, isFalse);
    });

    test('功能关闭时连网络请求都不发', () async {
      speaker.humanAudioEnabled = false;
      final result = await speaker.speak(
        speechRequest(
          pronunciations: <PronunciationView>[
            pronunciation(audioUrl: 'https://example.com/a.mp3'),
          ],
        ),
      );

      expect(result, isA<SystemVoicePlayed>());
      expect(result.fellBackToSystemVoice, isTrue);
      expect(downloader.downloaded, isEmpty);
      expect(player.prepared, isEmpty);
    });

    test('回落到系统朗读前会掐掉播放器，避免两段音频叠加', () async {
      await speaker.speak(
        speechRequest(pronunciations: <PronunciationView>[_withRecording()]),
      );
      await speaker.speak(speechRequest());

      expect(player.stopCount, 1);
      expect(player.playCount, 1);
      expect(engine.spoken, <String>['apple']);
    });
  });

  group('按口音选择', () {
    test('美音与英音取到不同的地址', () async {
      final requests = <SpeechRequest>[
        speechRequest(
          pronunciations: <PronunciationView>[
            pronunciation(source: youdaoAudioSource),
          ],
        ),
        speechRequest(
          accent: Accent.uk,
          pronunciations: <PronunciationView>[
            pronunciation(accent: Accent.uk, source: youdaoAudioSource),
          ],
        ),
      ];

      await speaker.speak(requests[0]);
      await speaker.speak(requests[1]);

      expect(downloader.downloaded, <Uri>[
        youdaoAudioUri('apple', Accent.us)!,
        youdaoAudioUri('apple', Accent.uk)!,
      ]);
      expect(player.playCount, 2);
    });

    test('系统朗读也按口音选语言', () async {
      await speaker.speak(speechRequest(accent: Accent.uk));

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

    test('并发数不超过上限', () async {
      // 用一个还没放行的下载器，才能在挂起状态下观察到并发峰值。
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

    test('没有真人录音的词不参与预取', () async {
      await speaker.preloadBatch(<SpeechRequest>[speechRequest()]);

      expect(downloader.downloaded, isEmpty);
    });

    test('功能关闭时整批跳过', () async {
      speaker.humanAudioEnabled = false;
      final requests = <SpeechRequest>[
        speechRequest(
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
