/// AI 词条 provider 测试。
///
/// 覆盖「把 LLM 包成 DictionaryProvider」这条链路：术语一致性、
/// 语义校验、质量门与截断，全部走注入的假 HTTP 响应，不发真实请求。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/ai_lexical.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/llm/llm_client.dart';
import 'package:lexiloop/services/llm/llm_config.dart';

import 'fake_http_fetcher.dart';

/// 一份通过质量门的模型输出。
Map<String, Object?> goodOutput() => <String, Object?>{
  'term': 'hello',
  'summary': <String, Object?>{
    'shortDefinition': 'a greeting',
    'translation': '你好',
    'cefrLevel': 'A1',
    'frequency': 'VERY_COMMON',
  },
  'senses': <Object?>[
    <String, Object?>{
      'id': '1',
      'partOfSpeech': 'int',
      'definition': 'used as a greeting',
      'translation': '你好',
      'register': 'NEUTRAL',
      'usageNote': null,
      'examples': <Object?>[
        <String, Object?>{
          'sentence': 'Hello, how are you?',
          'translation': '你好，你好吗？',
          'difficulty': 'EASY',
        },
        <String, Object?>{
          'sentence': 'She said hello to me.',
          'translation': '她向我问好。',
          'difficulty': 'EASY',
        },
      ],
      'synonyms': <Object?>[
        <String, Object?>{
          'word': 'hi',
          'translation': '嗨',
          'partOfSpeech': 'int',
          'difference': null,
        },
      ],
      'antonyms': <Object?>[
        <String, Object?>{
          'word': 'goodbye',
          'translation': '再见',
          'partOfSpeech': 'int',
          'difference': null,
        },
      ],
      'collocations': <Object?>[
        <String, Object?>{
          'phrase': 'say hello',
          'translation': '打招呼',
          'example': null,
        },
      ],
    },
  ],
  'morphology': <String, Object?>{
    'lemma': 'hello',
    'forms': <Object?>[
      <String, Object?>{'type': 'PLURAL', 'value': 'hellos'},
    ],
    'roots': <Object?>[],
    'affixes': <Object?>[],
    'wordFamily': <Object?>[
      <String, Object?>{
        'word': 'hellos',
        'translation': null,
        'partOfSpeech': 'n',
        'difference': null,
        'relation': 'WORD_FAMILY',
      },
    ],
  },
  'phrases': <Object?>[],
  'confusedWords': <Object?>[
    <String, Object?>{
      'word': 'hi',
      'translation': null,
      'partOfSpeech': null,
      'difference': null,
    },
  ],
  'sentenceAnalysis': <String, Object?>{
    'grammarPattern': null,
    'grammarExplanation': null,
    'grammarNotes': <Object?>[],
    'keyExpressions': <Object?>[],
    'similarExamples': <Object?>[],
    'variations': <Object?>[],
  },
  'learning': <String, Object?>{
    'pronunciationTip': null,
    'mnemonic': '把 hello 记成「哈喽」，打招呼时的口头语。',
    'commonMistakes': <Object?>[],
  },
  'tags': <Object?>['CET4'],
};

/// 包装成 OpenAI 兼容的成功响应。
String openAiBody(
  Map<String, Object?> output, {
  String finishReason = 'stop',
}) => jsonEncode(<String, Object?>{
  'choices': <Object?>[
    <String, Object?>{
      'message': <String, Object?>{'content': jsonEncode(output)},
      'finish_reason': finishReason,
    },
  ],
});

Map<String, Object?> llmConfigRaw({bool enabled = true}) => <String, Object?>{
  'providers': <Object?>[
    <String, Object?>{
      'id': 'p1',
      'name': '本地',
      'apiType': 'openai',
      'baseUrl': 'https://a.example/v1',
      'apiKey': 'k1',
    },
  ],
  'ai': <String, Object?>{
    'enabled': enabled,
    'providerId': 'p1',
    'model': 'm1',
  },
};

AppSettings settingsWith({bool enabled = true}) => appSettingsFromRaw(
  <String, Object?>{'llmConfig': llmConfigRaw(enabled: enabled)},
);

ProviderRequest request() => const ProviderRequest(
  term: 'hello',
  contentType: LexicalContentType.word,
  sourceLanguage: 'en',
  targetLanguage: 'zh-CN',
  wantedFields: <String>{},
);

AiLexicalProvider providerFor(FakeHttpFetcher fetcher, {bool enabled = true}) {
  final config = llmConfigFromRaw(llmConfigRaw(enabled: enabled));
  return AiLexicalProvider(LlmClient(fetcher, config), config);
}

FakeHttpFetcher fetcherReturning(String body, {int statusCode = 200}) =>
    FakeHttpFetcher(
      (url, requestBody) async =>
          HttpFetchResponse(statusCode: statusCode, body: body),
    );

void main() {
  group('AiLexicalProvider', () {
    test('成功时把模型输出映射为词条字段', () async {
      final result = await providerFor(
        fetcherReturning(openAiBody(goodOutput())),
      ).fetch(request());

      expect(result, isNotNull);
      expect(result!.providerId, 'ai:p1:m1');
      expect(
        result.qualityScore,
        greaterThanOrEqualTo(aiQualityScoreThreshold),
      );
      expect(result.fields['definitions'], isA<List<Object?>>());
      expect(result.fields['examples'], isA<List<Object?>>());
      expect(result.fields['synonyms'], isA<List<Object?>>());
      final learning = result.fields['learning']! as Map<String, Object?>;
      // 助记词是合格中文，被保留。
      expect(learning['mnemonic'], isNotNull);
      final summary = result.fields['summary']! as Map<String, Object?>;
      expect(summary['translation'], '你好');
      expect(result.metadata!['model'], 'm1');
    });

    test('模型返回其他词条时抛 aiTermMismatch', () async {
      final output = goodOutput()..['term'] = 'world';
      await expectLater(
        providerFor(fetcherReturning(openAiBody(output))).fetch(request()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiTermMismatch,
          ),
        ),
      );
    });

    test('质量分过低时抛 aiQualityLow', () async {
      final output = <String, Object?>{
        'term': 'hello',
        'summary': <String, Object?>{'translation': null},
        'senses': <Object?>[],
        'morphology': <String, Object?>{},
        'phrases': <Object?>[],
        'confusedWords': <Object?>[],
        'sentenceAnalysis': <String, Object?>{},
        'learning': <String, Object?>{},
        'tags': <Object?>[],
      };
      await expectLater(
        providerFor(fetcherReturning(openAiBody(output))).fetch(request()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiQualityLow,
          ),
        ),
      );
    });

    test('例句不含目标词时抛 aiSemanticInvalid', () async {
      final output = goodOutput();
      final senses = output['senses']! as List<Object?>;
      final sense = senses.first! as Map<String, Object?>;
      sense['examples'] = <Object?>[
        <String, Object?>{
          'sentence': 'A generic sentence without the term.',
          'translation': '一个不含目标词的句子。',
          'difficulty': 'EASY',
        },
      ];
      await expectLater(
        providerFor(fetcherReturning(openAiBody(output))).fetch(request()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiSemanticInvalid,
          ),
        ),
      );
    });

    test('输出被截断时抛 aiOutputTruncated', () async {
      await expectLater(
        providerFor(
          fetcherReturning(openAiBody(goodOutput(), finishReason: 'length')),
        ).fetch(request()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiOutputTruncated,
          ),
        ),
      );
    });

    test('未启用时抛 aiDisabled', () async {
      final fetcher = fetcherReturning(openAiBody(goodOutput()));
      await expectLater(
        providerFor(fetcher, enabled: false).fetch(request()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiDisabled,
          ),
        ),
      );
      expect(fetcher.calls, isEmpty);
    });

    test('isEnabled 取决于设置里的 llmConfig', () {
      final provider = providerFor(fetcherReturning('{}'));
      expect(provider.isEnabled(settingsWith()), isTrue);
      expect(provider.isEnabled(settingsWith(enabled: false)), isFalse);
      expect(provider.isEnabled(AppSettings.defaults), isFalse);
    });

    test('能力覆盖 AI 独有字段', () {
      final provider = providerFor(fetcherReturning('{}'));
      expect(provider.providedFields, contains('learning'));
      expect(provider.providedFields, contains('sentenceAnalysis'));
      expect(provider.supports(request()), isTrue);
    });
  });
}
