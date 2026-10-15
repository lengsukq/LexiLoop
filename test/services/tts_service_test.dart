/// 朗读服务的单元测试。
///
/// 用假引擎而不是真插件：`flutter_tts` 是平台通道插件，在测试进程里不可用。
/// 这里验证的是**调度逻辑**——语速按内容类型区分、配置去重、语言映射、
/// 语音包缺失时的降级。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/tts_service.dart';

/// 记录调用轨迹的假引擎。
class FakeSpeechEngine implements SpeechEngine {
  /// 每次 `configure` 的参数（语速, 语言）。
  final List<(double, String)> configureCalls = <(double, String)>[];

  /// 每次 `speak` 的文本。
  final List<String> spoken = <String>[];

  /// `stop` 的调用次数。
  int stopCount = 0;

  /// `isLanguageAvailable` 的返回值。
  bool languageAvailable = true;

  /// `speak` 时抛出的异常；为 null 表示不抛。
  Exception? speakError;

  @override
  Future<void> configure({
    required double rate,
    required String language,
  }) async {
    configureCalls.add((rate, language));
  }

  @override
  Future<void> speak(String text) async {
    final error = speakError;
    if (error != null) throw error;
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<bool> isLanguageAvailable(String language) async => languageAvailable;
}

PlaybackSettings _playback({
  double wordSpeed = 1,
  double phraseSpeed = 1,
  double sentenceSpeed = 1,
}) => PlaybackSettings(
  choiceRevealDelaySeconds: defaultChoiceRevealDelaySeconds,
  defaultAccent: Accent.us,
  wordSpeed: wordSpeed,
  phraseSpeed: phraseSpeed,
  sentenceSpeed: sentenceSpeed,
  autoPlayPronunciation: true,
);

void main() {
  late FakeSpeechEngine engine;
  late TtsService service;

  setUp(() {
    engine = FakeSpeechEngine();
    service = TtsService(engine);
  });

  group('基本朗读', () {
    test('朗读单词时配置并朗读', () async {
      await service.speakTerm(
        term: 'apple',
        sourceLanguage: 'en',
        contentType: LexicalContentType.word,
        playback: _playback(),
      );

      expect(engine.configureCalls, hasLength(1));
      expect(engine.configureCalls.single.$2, 'en-US');
      expect(engine.spoken, <String>['apple']);
    });

    test('首尾空白被裁掉', () async {
      await service.speakTerm(
        term: '  apple  ',
        sourceLanguage: 'en',
        contentType: LexicalContentType.word,
        playback: _playback(),
      );
      expect(engine.spoken, <String>['apple']);
    });

    test('空文本不触发任何调用', () async {
      for (final term in <String>['', '   ', '\n\t']) {
        await service.speakTerm(
          term: term,
          sourceLanguage: 'en',
          contentType: LexicalContentType.word,
          playback: _playback(),
        );
      }
      expect(engine.configureCalls, isEmpty);
      expect(engine.spoken, isEmpty);
    });
  });

  group('语速按内容类型区分', () {
    test('句子比单词慢，短语居中', () async {
      final playback = _playback(phraseSpeed: 0.8, sentenceSpeed: 0.6);
      for (final type in <LexicalContentType>[
        LexicalContentType.word,
        LexicalContentType.phrase,
        LexicalContentType.sentence,
      ]) {
        await service.speakTerm(
          term: 'sample text',
          sourceLanguage: 'en',
          contentType: type,
          playback: playback,
        );
      }

      expect(engine.configureCalls.map((call) => call.$1).toList(), <double>[
        1,
        0.8,
        0.6,
      ]);
    });

    test('语速被夹到合法区间', () async {
      final playback = _playback(wordSpeed: maxSpeechRate * 10);
      await service.speakTerm(
        term: 'apple',
        sourceLanguage: 'en',
        contentType: LexicalContentType.word,
        playback: playback,
      );
      expect(engine.configureCalls.single.$1, maxSpeechRate);
    });
  });

  group('配置去重', () {
    test('同语速同语言不重复配置', () async {
      final playback = _playback();
      for (var i = 0; i < 3; i += 1) {
        await service.speakTerm(
          term: 'apple',
          sourceLanguage: 'en',
          contentType: LexicalContentType.word,
          playback: playback,
        );
      }
      expect(engine.configureCalls, hasLength(1));
      expect(engine.spoken, hasLength(3));
    });

    test('语速变化时重新配置', () async {
      final playback = _playback();
      await service.speakTerm(
        term: 'apple',
        sourceLanguage: 'en',
        contentType: LexicalContentType.word,
        playback: playback,
      );
      await service.speakTerm(
        term: 'a full sentence here',
        sourceLanguage: 'en',
        contentType: LexicalContentType.sentence,
        playback: _playback(sentenceSpeed: 0.5),
      );
      expect(engine.configureCalls, hasLength(2));
    });

    test('语言变化时重新配置', () async {
      await service.speak('apple', languageCode: 'en', rate: defaultSpeechRate);
      await service.speak('苹果', languageCode: 'zh', rate: defaultSpeechRate);
      expect(engine.configureCalls.map((call) => call.$2).toList(), <String>[
        'en-US',
        'zh-CN',
      ]);
    });
  });

  group('语言映射', () {
    test('已知语言映射为 BCP-47', () async {
      for (final entry in <(String, String)>[
        ('en', 'en-US'),
        ('zh', 'zh-CN'),
        ('ja', 'ja-JP'),
        ('de', 'de-DE'),
      ]) {
        final localEngine = FakeSpeechEngine();
        final localService = TtsService(localEngine);
        await localService.speak(
          'text',
          languageCode: entry.$1,
          rate: defaultSpeechRate,
        );
        expect(localEngine.configureCalls.single.$2, entry.$2);
      }
    });

    test('未知语言原样透传', () async {
      await service.speak(
        'text',
        languageCode: 'xx-YY',
        rate: defaultSpeechRate,
      );
      expect(engine.configureCalls.single.$2, 'xx-YY');
    });

    test('语言代码大小写不敏感', () async {
      await service.speak('text', languageCode: 'EN', rate: defaultSpeechRate);
      expect(engine.configureCalls.single.$2, 'en-US');
    });
  });

  group('失败处理', () {
    test('引擎抛错时包装为可识别的 AppError', () async {
      engine.speakError = Exception('channel closed');
      await expectLater(
        service.speak('apple', languageCode: 'en', rate: defaultSpeechRate),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.ttsSynthesisFailed,
          ),
        ),
      );
    });

    test('stop 透传到引擎', () async {
      await service.stop();
      expect(engine.stopCount, 1);
    });
  });
}
