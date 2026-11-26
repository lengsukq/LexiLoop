/// 爱词霸解析测试。
///
/// 爱词霸把词条数据放在 `__NEXT_DATA__` 里，因此 fixture 是结构化 JSON
/// 而不是 HTML 片段——与有道不同，这里几乎不依赖页面结构。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/iciba.dart';
import 'package:lexiloop/data/dictionary/providers/iciba_parser.dart';
import 'package:lexiloop/domain/enums.dart';

import 'fake_http_fetcher.dart';

/// 把 `wordInfo` 包成爱词霸页面。
String icibaHtml(Map<String, Object?> wordInfo) {
  final payload = <String, Object?>{
    'props': <String, Object?>{
      'pageProps': <String, Object?>{
        'initialReduxState': <String, Object?>{
          'word': <String, Object?>{'wordInfo': wordInfo},
        },
      },
    },
  };
  return '<html><body><script id="__NEXT_DATA__" type="application/json">'
      '${jsonEncode(payload)}</script></body></html>';
}

/// 一份覆盖各字段的真实感 fixture。
Map<String, Object?> wordInfo() => <String, Object?>{
  'baesInfo': <String, Object?>{
    'word_name': 'hello',
    'symbols': <Object?>[
      <String, Object?>{
        'ph_en': 'həˈləʊ',
        'ph_am': 'həˈloʊ',
        'ph_en_mp3': 'https://res.iciba.com/en.mp3',
        'ph_am_mp3': 'https://res.iciba.com/am.mp3',
        'parts': <Object?>[
          <String, Object?>{
            'part': 'int',
            'means': <Object?>['你好', '喂'],
          },
          <String, Object?>{
            'part': 'noun',
            'means': <Object?>['问候'],
          },
        ],
      },
    ],
    'exchange': <String, Object?>{
      'word_pl': <Object?>['hellos'],
      'word_past': <Object?>['helloed'],
    },
    'word_tag': <Object?>[1, 2, 3, 6],
    'frequence': 5,
  },
  'bidec': <String, Object?>{
    'parts': <Object?>[
      <String, Object?>{
        'part_name': 'int',
        'means': <Object?>[
          <String, Object?>{
            'word_mean': '你好</seg>',
            'sentences': <Object?>[
              <String, Object?>{'en': 'Hello, world!', 'cn': '你好，世界！'},
            ],
          },
        ],
      },
    ],
  },
  'ee_mean': <Object?>[
    <String, Object?>{
      'part_name': 'noun',
      'means': <Object?>[
        <String, Object?>{
          'word_mean': '1. a greeting',
          'sentences': <Object?>[
            <String, Object?>{'sentence': 'A hello is enough.'},
          ],
        },
      ],
    },
  ],
  'collins': <Object?>[
    <String, Object?>{
      'entry': <Object?>[
        <String, Object?>{
          'def': 'a word used as a greeting',
          'tran': '问候语',
          'posp': 'noun-verb',
          'example': <Object?>[
            <String, Object?>{'ex': 'He said hello.', 'tran': '他打了个招呼。'},
          ],
        },
      ],
    },
  ],
  'synonym': <Object?>[
    <String, Object?>{
      'part_name': 'n',
      'means': <Object?>[
        <String, Object?>{
          'word_mean': 'greeting',
          'cis': <Object?>['greeting', 'salute'],
        },
      ],
    },
  ],
  'phrase': <Object?>[
    <String, Object?>{
      'cizu_name': 'hello world',
      'jx': <Object?>[
        <String, Object?>{'jx_cn_mean': '你好世界'},
      ],
    },
  ],
  'derivation': <Object?>[
    <String, Object?>{'yuyuan_name': '来自古英语'},
  ],
  'sameAnalysis': <Object?>[
    <String, Object?>{
      'word_list': 'hi,hey',
      'part_name': 'int',
      'means': <Object?>['更随意', '更口语'],
    },
  ],
  'new_sentence': <Object?>[
    <String, Object?>{
      'sentences': <Object?>[
        <String, Object?>{'en': 'She waved hello.', 'cn': '她挥手致意。'},
      ],
    },
  ],
};

ProviderRequest request({
  LexicalContentType contentType = LexicalContentType.word,
  String targetLanguage = 'zh-CN',
}) => ProviderRequest(
  term: 'hello',
  contentType: contentType,
  sourceLanguage: 'en',
  targetLanguage: targetLanguage,
  wantedFields: const <String>{},
);

List<Map<String, Object?>> records(Map<String, Object?> fields, String key) =>
    <Map<String, Object?>>[
      for (final item in (fields[key] as List? ?? <Object?>[]))
        if (item is Map) item.cast<String, Object?>(),
    ];

void main() {
  group('爱词霸解析', () {
    test('逐字段映射 wordInfo', () {
      final fields = parseIcibaHtml(
        icibaHtml(wordInfo()),
        targetLanguage: 'zh-CN',
      );

      expect(fields, isNotNull);
      final definitions = records(fields!, 'definitions');
      expect(
        definitions.any(
          (item) =>
              item['language'] == 'zh-CN' &&
              item['partOfSpeech'] == 'int' &&
              item['text'] == '你好' &&
              item['source'] == 'iciba',
        ),
        isTrue,
      );
      // `noun` 被归一化为 `n`。
      expect(
        definitions.any(
          (item) => item['partOfSpeech'] == 'n' && item['text'] == '问候',
        ),
        isTrue,
      );
      expect(
        definitions.any(
          (item) =>
              item['language'] == 'en' &&
              item['text'] == 'a word used as a greeting' &&
              item['source'] == 'iciba:collins',
        ),
        isTrue,
      );
      expect(
        definitions.any(
          (item) => item['language'] == 'zh-CN' && item['text'] == '问候语',
        ),
        isTrue,
      );

      final pronunciations = records(fields, 'pronunciations');
      expect(pronunciations, hasLength(2));
      expect(pronunciations[0]['accent'], 'UK');
      expect(pronunciations[0]['phonetic'], 'həˈləʊ');
      expect(pronunciations[0]['audioUrl'], 'https://res.iciba.com/en.mp3');
      expect(pronunciations[1]['accent'], 'US');

      final forms = records(fields, 'forms');
      expect(
        forms.any(
          (item) => item['type'] == 'PLURAL' && item['value'] == 'hellos',
        ),
        isTrue,
      );
      expect(
        forms.any(
          (item) => item['type'] == 'PAST' && item['value'] == 'helloed',
        ),
        isTrue,
      );

      final examples = records(fields, 'examples');
      expect(
        examples.any(
          (item) =>
              item['sentence'] == 'Hello, world!' &&
              item['translation'] == '你好，世界！',
        ),
        isTrue,
      );
      expect(
        examples.any(
          (item) =>
              item['sentence'] == 'A hello is enough.' &&
              item['translation'] == null,
        ),
        isTrue,
      );
      expect(
        examples.any((item) => item['sentence'] == 'She waved hello.'),
        isTrue,
      );
      expect(examples.length, lessThanOrEqualTo(20));

      expect(
        records(fields, 'phrases').any(
          (item) =>
              item['phrase'] == 'hello world' && item['translation'] == '你好世界',
        ),
        isTrue,
      );
      expect(
        records(fields, 'synonyms').map((item) => item['word']),
        containsAll(<String>['greeting', 'salute']),
      );
      expect(records(fields, 'roots').first['meaning'], '来自古英语');
      expect(
        records(fields, 'confusedWords').map((item) => item['word']),
        containsAll(<String>['hi', 'hey']),
      );
      expect(records(fields, 'confusedWords').first['difference'], '更随意');

      final summary = fields['summary']! as Map<String, Object?>;
      expect(summary['shortDefinition'], '你好');
      expect(summary['frequency'], 'VERY_COMMON');
      expect(fields['tags'], containsAll(<String>['CET4', 'CET6', '考研']));
      // word_tag 里的 6 是 COMMON，被显式排除。
      expect(fields['tags'], isNot(contains('COMMON')));
    });

    test('缺少 __NEXT_DATA__ 时返回 null', () {
      expect(
        parseIcibaHtml(
          '<html><body>blocked</body></html>',
          targetLanguage: 'zh-CN',
        ),
        isNull,
      );
    });

    test('损坏的 JSON 不抛异常', () {
      const html = '<html><script id="__NEXT_DATA__">{not json</script></html>';
      expect(parseIcibaHtml(html, targetLanguage: 'zh-CN'), isNull);
    });
  });

  group('爱词霸 provider', () {
    test('5xx 抛瞬时错误', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 503, body: 'oops'),
      );
      await expectLater(
        IcibaProvider(fetcher).fetch(request()),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.isTransient,
            'isTransient',
            isTrue,
          ),
        ),
      );
    });

    test('页面无内容时返回 null', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: '<html></html>'),
      );
      expect(await IcibaProvider(fetcher).fetch(request()), isNull);
    });

    test('不支持句子类词条', () {
      final fetcher = FakeHttpFetcher(
        (url, body) async => const HttpFetchResponse(statusCode: 200, body: ''),
      );
      final provider = IcibaProvider(fetcher);
      expect(provider.supports(request()), isTrue);
      expect(
        provider.supports(request(contentType: LexicalContentType.sentence)),
        isFalse,
      );
      expect(provider.id, 'iciba');
    });

    test('成功时返回字段与质量分', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            HttpFetchResponse(statusCode: 200, body: icibaHtml(wordInfo())),
      );
      final result = await IcibaProvider(fetcher).fetch(request());
      expect(result, isNotNull);
      expect(result!.providerId, 'iciba');
      expect(result.qualityScore, greaterThan(0));
      expect(result.fields['definitions'], isA<List<Object?>>());
    });
  });
}
