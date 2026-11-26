/// 纯 JSON 数据源的解析测试：dictionaryapi.dev、MyMemory、Merriam-Webster。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/dictionary_api.dart';
import 'package:lexiloop/data/dictionary/providers/merriam_webster.dart';
import 'package:lexiloop/data/dictionary/providers/my_memory.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

import 'fake_http_fetcher.dart';

const String dictionaryApiBody = '''
[
  {
    "phonetic": "həˈləʊ",
    "phonetics": [
      {
        "text": "həˈləʊ",
        "audio": "https://api.dictionaryapi.dev/media/pronunciations/en/hello-uk.mp3",
        "sourceUrl": "https://commons.wikimedia.org/w/index.php?curid=1"
      }
    ],
    "meanings": [
      {
        "partOfSpeech": "noun",
        "synonyms": ["greeting"],
        "definitions": [
          {
            "definition": "A greeting.",
            "example": "He gave a hello.",
            "synonyms": ["salute"],
            "antonyms": ["goodbye"]
          }
        ]
      }
    ]
  }
]
''';

const String myMemoryBody = '''
{
  "responseStatus": 200,
  "responseData": {"translatedText": "你好", "match": 1},
  "matches": [
    {"translation": "您好", "match": 0.9},
    {"translation": "低匹配译文", "match": 0.5}
  ]
}
''';

const String merriamDictionaryBody = '''
[
  {
    "meta": {"id": "hello"},
    "hwi": {
      "prs": [
        {"mw": "hə-ˈlō", "sound": {"audio": "hello01"}}
      ]
    },
    "fl": "noun",
    "shortdef": ["an expression of greeting", "{a_link|salutation}"],
    "def": [
      {
        "sseq": [
          [
            [
              "sense",
              {
                "dt": [
                  ["text", "{bc}an expression of greeting"],
                  [
                    "vis",
                    [{"t": "He said {it}hello{/it} to everyone."}]
                  ]
                ]
              }
            ]
          ]
        ]
      }
    ]
  }
]
''';

const String merriamThesaurusBody = '''
[
  {
    "meta": {"id": "hello", "syns": [["greeting", "salutation"]], "ants": [["goodbye"]]}
  }
]
''';

ProviderRequest wordRequest({
  String term = 'hello',
  LexicalContentType contentType = LexicalContentType.word,
  String sourceLanguage = 'en',
  String targetLanguage = 'zh-CN',
}) => ProviderRequest(
  term: term,
  contentType: contentType,
  sourceLanguage: sourceLanguage,
  targetLanguage: targetLanguage,
  wantedFields: const <String>{},
);

List<Map<String, Object?>> records(Map<String, Object?> fields, String key) =>
    <Map<String, Object?>>[
      for (final item in (fields[key] as List? ?? <Object?>[]))
        if (item is Map) item.cast<String, Object?>(),
    ];

AppSettings settingsWithMerriam({
  bool enabled = true,
  String dictionaryKey = 'dict-key',
  String thesaurusKey = 'thes-key',
}) => appSettingsFromRaw(<String, Object?>{
  'merriamWebsterEnabled': enabled,
  'merriamWebsterDictionaryKey': dictionaryKey,
  'merriamWebsterThesaurusKey': thesaurusKey,
});

void main() {
  group('dictionaryapi.dev', () {
    test('解析音标、释义、例句与同反义词', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: dictionaryApiBody),
      );
      final result = await DictionaryApiProvider(fetcher).fetch(wordRequest());

      expect(result, isNotNull);
      final definitions = records(result!.fields, 'definitions');
      expect(definitions, hasLength(1));
      expect(definitions.first['language'], 'en');
      expect(definitions.first['partOfSpeech'], 'noun');
      expect(definitions.first['text'], 'A greeting.');

      final pronunciations = records(result.fields, 'pronunciations');
      expect(pronunciations, hasLength(1));
      // 音频地址里带 uk，因此判为英音。
      expect(pronunciations.first['accent'], 'UK');
      expect(pronunciations.first['phonetic'], 'həˈləʊ');

      expect(
        records(result.fields, 'examples').first['sentence'],
        'He gave a hello.',
      );
      expect(
        records(result.fields, 'synonyms').map((item) => item['word']),
        containsAll(<String>['greeting', 'salute']),
      );
      expect(
        records(result.fields, 'antonyms').map((item) => item['word']),
        contains('goodbye'),
      );
    });

    test('404 表示词条不存在，返回 null', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 404, body: '{}'),
      );
      expect(await DictionaryApiProvider(fetcher).fetch(wordRequest()), isNull);
    });

    test('429 抛瞬时错误', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 429, body: 'slow down'),
      );
      await expectLater(
        DictionaryApiProvider(fetcher).fetch(wordRequest()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.isTransient,
            'isTransient',
            isTrue,
          ),
        ),
      );
    });

    test('响应不是数组时返回 null', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: '{"a":1}'),
      );
      expect(await DictionaryApiProvider(fetcher).fetch(wordRequest()), isNull);
    });

    test('只支持英文单词', () {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: '[]'),
      );
      final provider = DictionaryApiProvider(fetcher);
      expect(provider.supports(wordRequest()), isTrue);
      expect(provider.supports(wordRequest(sourceLanguage: 'zh-CN')), isFalse);
      expect(
        provider.supports(wordRequest(contentType: LexicalContentType.phrase)),
        isFalse,
      );
    });
  });

  group('MyMemory', () {
    test('取主译文与高匹配度备用译文', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: myMemoryBody),
      );
      final result = await MyMemoryProvider(fetcher).fetch(wordRequest());
      final definitions = records(result!.fields, 'definitions');
      expect(definitions.map((item) => item['text']), <String>['你好', '您好']);
      expect(definitions.first['language'], 'zh-CN');
    });

    test('译文与原文相同时返回 null', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async => const HttpFetchResponse(
          statusCode: 200,
          body: '{"responseData": {"translatedText": "hello"}}',
        ),
      );
      expect(await MyMemoryProvider(fetcher).fetch(wordRequest()), isNull);
    });

    test('不支持的语言对不参与调用', () {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: '{}'),
      );
      final provider = MyMemoryProvider(fetcher);
      expect(provider.supports(wordRequest()), isTrue);
      expect(provider.supports(wordRequest(targetLanguage: 'th')), isFalse);
    });
  });

  group('Merriam-Webster', () {
    test('没有 API Key 时 isEnabled 为 false', () {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: '[]'),
      );
      final provider = MerriamWebsterProvider(
        settingsWithMerriam(
          enabled: false,
          dictionaryKey: '',
          thesaurusKey: '',
        ),
        fetcher,
      );
      expect(provider.isEnabled(settingsWithMerriam()), isTrue);
      expect(
        provider.isEnabled(
          settingsWithMerriam(dictionaryKey: '', thesaurusKey: ''),
        ),
        isFalse,
      );
      expect(provider.isEnabled(settingsWithMerriam(enabled: false)), isFalse);
    });

    test('未配置 Key 时抛明确的配置错误', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: '[]'),
      );
      final provider = MerriamWebsterProvider(
        settingsWithMerriam(dictionaryKey: '', thesaurusKey: ''),
        fetcher,
      );
      await expectLater(
        provider.fetch(wordRequest()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.aiConfigIncomplete,
          ),
        ),
      );
      expect(fetcher.calls, isEmpty);
    });

    test('合并词典与同义词典两路结果', () async {
      final fetcher = routedFetcher(<String, HttpFetchResponse>{
        'collegiate': const HttpFetchResponse(
          statusCode: 200,
          body: merriamDictionaryBody,
        ),
        'thesaurus': const HttpFetchResponse(
          statusCode: 200,
          body: merriamThesaurusBody,
        ),
      });
      final result = await MerriamWebsterProvider(
        settingsWithMerriam(),
        fetcher,
      ).fetch(wordRequest());

      expect(result, isNotNull);
      final definitions = records(result!.fields, 'definitions');
      expect(definitions, hasLength(2));
      // `{a_link|salutation}` 里的标记被剥掉。
      expect(definitions.last['text'], 'salutation');
      expect(definitions.first['partOfSpeech'], 'noun');

      final pronunciations = records(result.fields, 'pronunciations');
      expect(pronunciations, hasLength(1));
      expect(pronunciations.first['phonetic'], 'hə-ˈlō');
      expect(
        pronunciations.first['audioUrl'],
        'https://media.merriam-webster.com/audio/prons/en/us/mp3/h/hello01.mp3',
      );

      expect(
        records(result.fields, 'examples').first['sentence'],
        'He said hello to everyone.',
      );
      expect(
        records(result.fields, 'synonyms').map((item) => item['word']),
        containsAll(<String>['greeting', 'salutation']),
      );
      expect(
        records(result.fields, 'antonyms').map((item) => item['word']),
        contains('goodbye'),
      );
    });

    test('两路都失败时抛瞬时错误', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async => throw const HttpFailure(HttpFailureKind.network),
      );
      await expectLater(
        MerriamWebsterProvider(
          settingsWithMerriam(),
          fetcher,
        ).fetch(wordRequest()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.isTransient,
            'isTransient',
            isTrue,
          ),
        ),
      );
    });

    test('词典没有该词条时返回 null', () async {
      final fetcher = routedFetcher(<String, HttpFetchResponse>{
        'collegiate': const HttpFetchResponse(statusCode: 200, body: '[]'),
        'thesaurus': const HttpFetchResponse(statusCode: 200, body: '[]'),
      });
      expect(
        await MerriamWebsterProvider(
          settingsWithMerriam(),
          fetcher,
        ).fetch(wordRequest()),
        isNull,
      );
    });
  });
}
