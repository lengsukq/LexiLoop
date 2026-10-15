/// 真人录音地址选择策略的单测。
///
/// 这层是「优先有道真人发音」这条旧版策略在新版的落点，
/// 口音参数写错会静默放出另一种口音，因此逐条钉死。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/services/audio/audio_constants.dart';
import 'package:lexiloop/services/audio/pronunciation_audio.dart';

import 'audio_fixtures.dart';

void main() {
  group('youdaoAudioUri', () {
    test('同一个词的美音与英音地址不同', () {
      final us = youdaoAudioUri('apple', Accent.us);
      final uk = youdaoAudioUri('apple', Accent.uk);

      expect(us, isNotNull);
      expect(uk, isNotNull);
      expect(us, isNot(uk));
      expect(us!.queryParameters[youdaoAudioTypeQueryKey], '2');
      expect(uk!.queryParameters[youdaoAudioTypeQueryKey], '1');
      expect(us.queryParameters[youdaoAudioQueryKey], 'apple');
    });

    test('词条为空或只有空白时没有地址', () {
      expect(youdaoAudioUri('', Accent.us), isNull);
      expect(youdaoAudioUri('   ', Accent.uk), isNull);
    });

    test('词条被 URL 编码，不会破坏查询串', () {
      final uri = youdaoAudioUri('a b&c', Accent.us);
      expect(uri, isNotNull);
      expect(uri!.queryParameters[youdaoAudioQueryKey], 'a b&c');
      expect(uri.queryParameters[youdaoAudioTypeQueryKey], '2');
    });
  });

  group('resolveHumanAudioUrl', () {
    test('优先使用词典直接给出的地址', () {
      final stored = Uri.parse('https://example.com/uk.mp3');
      final resolved = resolveHumanAudioUrl(
        term: 'apple',
        accent: Accent.uk,
        pronunciations: <PronunciationView>[
          pronunciation(accent: Accent.uk, audioUrl: stored.toString()),
        ],
      );

      expect(resolved, stored);
    });

    test('口音不匹配时不串用另一口音的地址', () {
      final resolved = resolveHumanAudioUrl(
        term: 'apple',
        accent: Accent.uk,
        pronunciations: <PronunciationView>[
          pronunciation(audioUrl: 'https://example.com/us.mp3'),
        ],
      );

      expect(resolved, isNull);
    });

    test('地址缺失但来源是有道时按词条补出地址', () {
      final resolved = resolveHumanAudioUrl(
        term: 'apple',
        accent: Accent.uk,
        pronunciations: <PronunciationView>[
          pronunciation(accent: Accent.uk, source: youdaoAudioSource),
        ],
      );

      expect(resolved, youdaoAudioUri('apple', Accent.uk));
    });

    test('来源不是有道时不猜测地址', () {
      final resolved = resolveHumanAudioUrl(
        term: 'apple',
        accent: Accent.us,
        pronunciations: <PronunciationView>[
          pronunciation(source: 'merriam-webster'),
        ],
      );

      expect(resolved, isNull);
    });

    test('空白地址视为没有地址', () {
      final resolved = resolveHumanAudioUrl(
        term: 'apple',
        accent: Accent.us,
        pronunciations: <PronunciationView>[pronunciation(audioUrl: '   ')],
      );

      expect(resolved, isNull);
    });

    test('发音列表为空时没有地址', () {
      expect(
        resolveHumanAudioUrl(
          term: 'apple',
          accent: Accent.us,
          pronunciations: const <PronunciationView>[],
        ),
        isNull,
      );
    });
  });
}
