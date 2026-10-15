/// 学习页发音编排的单测。
///
/// 对应旧版 `lib/tts-client.ts` 的 `playCachedTts` / `preloadTtsBatch`。
/// 这里钉的是**策略**而不是播放器：真人录音优先、设置开关生效、降级与失败
/// 都有可观测的信号、预取只预热「即将被点到的词」。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_speech.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/word_speaker.dart';
import 'package:lexiloop/services/tts_service.dart';

import '../../services/audio/audio_fakes.dart';

/// 播放设置；[humanAudioEnabled] 决定是否允许走真人录音。
PlaybackSettings _playback({bool humanAudioEnabled = true}) => PlaybackSettings(
  choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
  defaultAccent: Accent.us,
  wordSpeed: defaultSpeechRate,
  phraseSpeed: defaultSpeechRate,
  sentenceSpeed: defaultSpeechRate,
  autoPlayPronunciation: true,
  humanAudioEnabled: humanAudioEnabled,
);

/// 一个词条视图；[audioUrl] 为空表示词典没给真人录音。
StudyWordView _word({required String term, String? audioUrl}) => StudyWordView(
  id: 1,
  term: term,
  sourceLanguage: 'en',
  targetLanguage: 'zh',
  contentType: LexicalContentType.word,
  definitions: const <DefinitionValue>[],
  pronunciations: audioUrl == null
      ? const <PronunciationView>[]
      : <PronunciationView>[
          PronunciationView(
            accent: Accent.us,
            phonetic: term,
            audioUrl: audioUrl,
            source: youdaoAudioSource,
          ),
        ],
  examples: const <ExampleView>[],
);

/// 一道带发音的题目。
StudyItemView _item(int id, String term, String audioUrl) => StudyItemView(
  itemId: id,
  position: id.toDouble(),
  taskType: StudyTaskType.review,
  questionType: QuestionType.enToZhChoice,
  status: StudyItemStatus.pending,
  word: StudyWordView(
    id: id,
    term: term,
    sourceLanguage: 'en',
    targetLanguage: 'zh',
    contentType: LexicalContentType.word,
    definitions: const <DefinitionValue>[],
    pronunciations: <PronunciationView>[
      PronunciationView(
        accent: Accent.us,
        phonetic: term,
        audioUrl: audioUrl,
        source: youdaoAudioSource,
      ),
    ],
    examples: const <ExampleView>[],
  ),
);

void main() {
  late FakeAudioPlayer player;
  late FakeAudioDownloader downloader;
  late RecordingSpeechEngine engine;
  late WordSpeaker speaker;

  setUp(() {
    player = FakeAudioPlayer();
    downloader = FakeAudioDownloader()..openGate();
    engine = RecordingSpeechEngine();
    speaker = WordSpeaker(player, AudioCache(downloader), TtsService(engine));
  });

  group('朗读策略', () {
    test('有真人录音时播放录音，既不提示也不走系统朗读', () async {
      const url = 'https://example.com/apple-us.mp3';
      final request = studySpeechRequest(
        word: _word(term: 'apple', audioUrl: url),
        accent: Accent.us,
        playback: _playback(),
      );

      final message = await studySpeakTerm(
        speaker: speaker,
        request: request,
        humanAudioEnabled: true,
      );

      expect(downloader.downloaded.map((uri) => uri.toString()), <String>[url]);
      expect(player.playCount, 1);
      expect(engine.spoken, isEmpty);
      expect(message, isNull);
    });

    test('没有真人录音时回落到系统朗读并给出提示', () async {
      final request = studySpeechRequest(
        word: _word(term: 'apple'),
        accent: Accent.us,
        playback: _playback(),
      );

      final message = await studySpeakTerm(
        speaker: speaker,
        request: request,
        humanAudioEnabled: true,
      );

      expect(downloader.downloaded, isEmpty);
      expect(engine.spoken, <String>['apple']);
      expect(message, '暂无真人录音，已改用系统朗读');
    });

    test('关掉真人录音后直接走系统朗读，不发起下载也不提示', () async {
      final request = studySpeechRequest(
        word: _word(term: 'apple', audioUrl: 'https://example.com/a.mp3'),
        accent: Accent.us,
        playback: _playback(humanAudioEnabled: false),
      );

      final message = await studySpeakTerm(
        speaker: speaker,
        request: request,
        humanAudioEnabled: false,
      );

      expect(downloader.downloaded, isEmpty);
      expect(engine.spoken, <String>['apple']);
      expect(message, isNull, reason: '用户自己关的开关，不该再提示「已降级」');
    });

    test('系统朗读也失败时给出错误文案', () async {
      engine.speakError = Exception('引擎炸了');
      final request = studySpeechRequest(
        word: _word(term: 'apple'),
        accent: Accent.us,
        playback: _playback(),
      );

      final message = await studySpeakTerm(
        speaker: speaker,
        request: request,
        humanAudioEnabled: true,
      );

      expect(message, isNotNull);
      expect(message, isNotEmpty);
    });

    test('英音请求按英音解析地址', () async {
      final request = studySpeechRequest(
        word: _word(
          term: 'apple',
          audioUrl: 'https://example.com/apple-uk.mp3',
        ),
        accent: Accent.uk,
        playback: _playback(),
      );

      final result = await speaker.speak(request);

      expect(
        result.fellBackToSystemVoice,
        isTrue,
        reason: '该词条只有美音录音，英音请求应回落到系统朗读',
      );
      expect(downloader.downloaded, isEmpty);
      expect(engine.spoken, <String>['apple']);
    });
  });

  group('预取', () {
    test('向前看 5 题（含当前题）', () {
      expect(
        studyPreloadAheadCount,
        5,
        reason: '旧版是 preloadTtsBatch(items.slice(index, index + 5))',
      );
    });

    test('只请求前 5 题的去重地址', () async {
      final items = <StudyItemView>[
        for (var index = 0; index < 7; index += 1)
          _item(index, 'word$index', 'https://example.com/word$index.mp3'),
      ];

      studyPreloadAhead(
        speaker: speaker,
        items: items.take(studyPreloadAheadCount),
        accent: Accent.us,
        playback: _playback(),
      );
      await settle(20);

      expect(
        downloader.downloaded.map((uri) => uri.toString()).toList(),
        <String>[
          'https://example.com/word0.mp3',
          'https://example.com/word1.mp3',
          'https://example.com/word2.mp3',
          'https://example.com/word3.mp3',
          'https://example.com/word4.mp3',
        ],
      );
      expect(player.playCount, 0, reason: '预取只下载，不播放');
    });

    test('关掉真人录音时不预取', () async {
      studyPreloadAhead(
        speaker: speaker,
        items: <StudyItemView>[
          _item(0, 'apple', 'https://example.com/apple.mp3'),
        ],
        accent: Accent.us,
        playback: _playback(humanAudioEnabled: false),
      );
      await settle(5);

      expect(downloader.downloaded, isEmpty);
    });

    test('预取会把设置里的开关同步到发音服务上', () {
      expect(speaker.humanAudioEnabled, isTrue);

      studyPreloadAhead(
        speaker: speaker,
        items: <StudyItemView>[
          _item(0, 'apple', 'https://example.com/apple.mp3'),
        ],
        accent: Accent.us,
        playback: _playback(humanAudioEnabled: false),
      );

      expect(speaker.humanAudioEnabled, isFalse);
    });
  });
}
