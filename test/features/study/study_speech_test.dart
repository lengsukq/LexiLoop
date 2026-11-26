/// 学习页发音编排的单测。
///
/// 钉住策略：按用户排定的多选优先级链发音、失败自动顺延并给出提示、
/// 仅启用系统朗读时静默直走系统 TTS、预取只预热即将到来的题。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_speech.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';
import 'package:lexiloop/services/audio/word_speaker.dart';
import 'package:lexiloop/services/tts_service.dart';

import '../../services/audio/audio_fakes.dart';

const List<SpeechSourcePreference> _systemOnlyChain = <SpeechSourcePreference>[
  SpeechSourcePreference(source: SpeechSource.system, enabled: true),
  SpeechSourcePreference(source: SpeechSource.youdao, enabled: false),
  SpeechSourcePreference(source: SpeechSource.edge, enabled: false),
];

/// 播放设置；[speechChain] 决定发音引擎启用与顺延顺序。
PlaybackSettings _playback({
  List<SpeechSourcePreference> speechChain = defaultSpeechChain,
}) => PlaybackSettings(
  choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
  defaultAccent: Accent.us,
  wordSpeed: defaultSpeechRate,
  phraseSpeed: defaultSpeechRate,
  sentenceSpeed: defaultSpeechRate,
  autoPlayPronunciation: true,
  speechChain: speechChain,
);

/// 一个词条视图；[audioUrl] 为空表示词典没存固定地址。
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

      final message = await studySpeakTerm(speaker: speaker, request: request);

      expect(downloader.downloaded.map((uri) => uri.toString()), <String>[url]);
      expect(player.playCount, 1);
      expect(engine.spoken, isEmpty);
      expect(message, isNull);
    });

    test('有道不可用时顺延到系统朗读并给出准确提示', () async {
      downloader.failing.add(youdaoAudioUri('apple', Accent.us)!.toString());
      final request = studySpeechRequest(
        word: _word(term: 'apple'),
        accent: Accent.us,
        playback: _playback(),
      );

      final message = await studySpeakTerm(speaker: speaker, request: request);

      expect(engine.spoken, <String>['apple']);
      expect(message, '有道词典发音暂不可用，已自动切换为设备系统朗读');
    });

    test('仅启用系统朗读时直接走系统朗读，不发起下载也不提示降级', () async {
      final request = studySpeechRequest(
        word: _word(term: 'apple', audioUrl: 'https://example.com/a.mp3'),
        accent: Accent.us,
        playback: _playback(speechChain: _systemOnlyChain),
      );

      final message = await studySpeakTerm(speaker: speaker, request: request);

      expect(downloader.downloaded, isEmpty);
      expect(engine.spoken, <String>['apple']);
      expect(message, isNull, reason: '用户自己选择了仅系统朗读，不该再提示降级');
    });

    test('全部引擎均失败时给出错误文案', () async {
      engine.speakError = Exception('引擎炸了');
      downloader.failing.add(youdaoAudioUri('apple', Accent.us)!.toString());
      final request = studySpeechRequest(
        word: _word(term: 'apple'),
        accent: Accent.us,
        playback: _playback(),
      );

      final message = await studySpeakTerm(speaker: speaker, request: request);

      expect(message, isNotNull);
      expect(message, startsWith('发音暂不可用：'));
    });

    test('英音请求即使词条仅存美音，也能通过有道直连英音播报', () async {
      final request = studySpeechRequest(
        word: _word(
          term: 'apple',
          audioUrl: 'https://example.com/apple-us.mp3',
        ),
        accent: Accent.uk,
        playback: _playback(),
      );

      final result = await speaker.speak(request);

      expect(result.fellBack, isFalse);
      expect(downloader.downloaded, <Uri>[youdaoAudioUri('apple', Accent.uk)!]);
      expect(engine.spoken, isEmpty);
    });
  });

  group('预取', () {
    test('向前看 5 题（含当前题）', () {
      expect(studyPreloadAheadCount, 5);
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

    test('仅启用系统朗读时不预取网络音频', () async {
      studyPreloadAhead(
        speaker: speaker,
        items: <StudyItemView>[
          _item(0, 'apple', 'https://example.com/apple.mp3'),
        ],
        accent: Accent.us,
        playback: _playback(speechChain: _systemOnlyChain),
      );
      await settle(5);

      expect(downloader.downloaded, isEmpty);
    });
  });
}
