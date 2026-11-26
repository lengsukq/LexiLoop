/// 有道解析与双端点回退的测试。
///
/// 用例逐条对齐旧版 `tests/unit/youdao-provider.test.ts`：
/// 同一份 HTML 片段、同一组字段断言，确保迁移没有改变解析行为。
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/dictionary/providers/youdao.dart';
import 'package:lexiloop/data/dictionary/providers/youdao_parser.dart';
import 'package:lexiloop/domain/enums.dart';

import 'fake_http_fetcher.dart';

/// 把若干行包成旧版单测里的 HTML 形态。
String html(List<String> lines) =>
    '<html><body>${lines.map((line) => '<div>$line</div>').join()}</body></html>';

ProviderRequest request({
  String term = 'hello',
  LexicalContentType contentType = LexicalContentType.word,
  String sourceLanguage = 'en',
  String targetLanguage = 'zh-CN',
  Set<String> wantedFields = const <String>{},
}) => ProviderRequest(
  term: term,
  contentType: contentType,
  sourceLanguage: sourceLanguage,
  targetLanguage: targetLanguage,
  wantedFields: wantedFields,
);

YoudaoProvider providerFor(FakeHttpFetcher fetcher) =>
    YoudaoProvider(fetcher, random: math.Random(7), sleep: (duration) async {});

List<Map<String, Object?>> records(Map<String, Object?> fields, String key) =>
    <Map<String, Object?>>[
      for (final item in (fields[key] as List? ?? <Object?>[]))
        if (item is Map) item.cast<String, Object?>(),
    ];

void main() {
  group('有道解析', () {
    test('解析词典分栏、分隔式词形、短语与来源标记', () {
      final result = parseYoudaoHtml(
        html(<String>[
          'hello',
          '英 [həˈləʊ]',
          '美 [həˈloʊ]',
          '简明',
          'int. 你好',
          'n. 招呼，问候',
          '复数',
          'hellos',
          '网络释义',
          '1',
          'hello',
          '您好',
          '短语',
          '1',
          'Hello Kitty',
          '凯蒂猫',
          '双语例句',
          '1',
          'Hello, Paul, they chorused.',
          '你好，保罗。',
        ]),
        term: 'hello',
        contentType: LexicalContentType.word,
        targetLanguage: 'zh-CN',
      );

      expect(result, isNotNull);
      final definitions = records(result!, 'definitions');
      expect(definitions, hasLength(2));
      expect(definitions[0]['language'], 'zh-CN');
      expect(definitions[0]['partOfSpeech'], 'int');
      expect(definitions[0]['text'], '你好');
      expect(definitions[0]['source'], 'youdao');
      expect(definitions[1]['partOfSpeech'], 'n');
      expect(definitions[1]['text'], '招呼，问候');

      final pronunciations = records(result, 'pronunciations');
      expect(pronunciations, hasLength(2));
      expect(pronunciations[0]['accent'], 'UK');
      expect(pronunciations[0]['phonetic'], 'həˈləʊ');
      expect(
        pronunciations[0]['audioUrl'],
        'https://dict.youdao.com/dictvoice?audio=hello&type=1',
      );
      expect(pronunciations[1]['accent'], 'US');
      expect(
        pronunciations[1]['audioUrl'],
        'https://dict.youdao.com/dictvoice?audio=hello&type=2',
      );

      final forms = records(result, 'forms');
      expect(forms, hasLength(1));
      expect(forms.first['type'], 'PLURAL');
      expect(forms.first['value'], 'hellos');

      final phrases = records(result, 'phrases');
      expect(
        phrases.any(
          (item) =>
              item['phrase'] == 'Hello Kitty' &&
              item['translation'] == '凯蒂猫' &&
              item['source'] == 'youdao:phrase',
        ),
        isTrue,
      );

      final examples = records(result, 'examples');
      expect(examples, hasLength(1));
      expect(examples.first['sentence'], 'Hello, Paul, they chorused.');
      expect(examples.first['translation'], '你好，保罗。');
      expect(examples.first['source'], 'youdao:example');
    });

    test('短语与句子使用有道直译块', () {
      final phrase = parseYoudaoHtml(
        html(<String>['有道翻译', 'to take care of', '照顾', '以上为机器翻译']),
        term: 'to take care of',
        contentType: LexicalContentType.phrase,
        targetLanguage: 'zh-CN',
      );
      final sentence = parseYoudaoHtml(
        html(<String>['有道翻译', 'I am tired', '我累了', '以上为机器翻译']),
        term: 'I am tired',
        contentType: LexicalContentType.sentence,
        targetLanguage: 'zh-CN',
      );

      expect(phrase!['summary'], containsPair('translation', '照顾'));
      expect(
        records(phrase, 'phrases').any(
          (item) =>
              item['phrase'] == 'to take care of' &&
              item['translation'] == '照顾' &&
              item['source'] == 'youdao:translation',
        ),
        isTrue,
      );
      expect(sentence!['summary'], containsPair('translation', '我累了'));
      expect(records(sentence, 'examples').first['sentence'], 'I am tired');
      expect(records(sentence, 'examples').first['translation'], '我累了');
    });

    test('短语没有直译块时回退到网络释义（同行与分行两种）', () {
      final inline = parseYoudaoHtml(
        html(<String>['网络释义', 'The proportion of …的比例', '双语例句']),
        term: 'The proportion of',
        contentType: LexicalContentType.phrase,
        targetLanguage: 'zh-CN',
      );
      final separate = parseYoudaoHtml(
        html(<String>['网络释义', 'The proportion of', '…的比例', '双语例句']),
        term: 'The proportion of',
        contentType: LexicalContentType.phrase,
        targetLanguage: 'zh-CN',
      );

      for (final content in <Map<String, Object?>>[inline!, separate!]) {
        final definitions = records(content, 'definitions');
        expect(definitions, hasLength(1));
        expect(definitions.first['language'], 'zh-CN');
        expect(definitions.first['partOfSpeech'], isNull);
        expect(definitions.first['text'], '…的比例');
        expect(definitions.first['source'], 'youdao:network');
        expect(definitions.first['isUserEdited'], isFalse);
      }
    });

    test('短语同时有直译与网络释义时优先直译', () {
      final result = parseYoudaoHtml(
        html(<String>[
          '有道翻译',
          'The proportion of',
          '…的比例',
          '以上为机器翻译',
          '网络释义',
          'The proportion of 比例',
        ]),
        term: 'The proportion of',
        contentType: LexicalContentType.phrase,
        targetLanguage: 'zh-CN',
      );
      final definitions = records(result!, 'definitions');
      expect(definitions, hasLength(1));
      expect(definitions.first['text'], '…的比例');
      expect(definitions.first['source'], 'youdao:translation');
    });

    test('句子没有直译块时不编造释义', () {
      final result = parseYoudaoHtml(
        html(<String>['双语例句', '1', 'How are you?', '你好吗？']),
        term: 'How are you?',
        contentType: LexicalContentType.sentence,
        targetLanguage: 'zh-CN',
      );
      expect(records(result!, 'definitions'), isEmpty);
      expect(result['summary'], isNull);
    });
  });

  group('有道 provider 双端点', () {
    test('主端点 HTTP 失败时回退到备用端点', () async {
      final fetcher = FakeHttpFetcher((url, body) async {
        if (url.contains('dict.youdao.com')) {
          return const HttpFetchResponse(statusCode: 503, body: 'unavailable');
        }
        return HttpFetchResponse(
          statusCode: 200,
          body: html(<String>['英 [həˈləʊ]', '美 [həˈloʊ]', 'int. 你好']),
        );
      });

      final result = await providerFor(fetcher).fetch(
        request(
          wantedFields: <String>{'definitions', 'pronunciations.phonetic'},
        ),
      );

      expect(fetcher.calls, hasLength(2));
      expect(
        fetcher.calls.any((url) => url.contains('dict.youdao.com/w/eng/hello')),
        isTrue,
      );
      expect(
        fetcher.calls.any((url) => url.contains('www.youdao.com/result')),
        isTrue,
      );
      expect(records(result!.fields, 'definitions'), hasLength(1));
      expect(records(result.fields, 'definitions').first['text'], '你好');
      expect(records(result.fields, 'pronunciations'), hasLength(2));
      expect(result.metadata!['sourceEndpoint'], 'youdao.com/result');
      expect(result.metadata!['fallbackUsed'], isTrue);
      final attempts = result.metadata!['endpointAttempts']! as List<Object?>;
      expect(attempts, hasLength(2));
      expect((attempts.first! as Map<String, Object?>)['status'], 'FAILED');
      expect((attempts.first! as Map<String, Object?>)['statusCode'], 503);
      expect((attempts.last! as Map<String, Object?>)['status'], 'SUCCESS');
    });

    test('HTTP 5xx 不触发单端点重试', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 503, body: 'unavailable'),
      );

      await expectLater(
        providerFor(fetcher).fetch(request()),
        throwsA(isA<ExternalServiceError>()),
      );
      // 两个端点各一次，没有因为 5xx 而重试。
      expect(fetcher.calls, hasLength(2));
    });

    test('两端点都失败时抛瞬时错误并汇总原因', () async {
      final fetcher = FakeHttpFetcher((url, body) async {
        if (url.contains('dict.youdao.com')) {
          throw const HttpFailure(HttpFailureKind.timeout);
        }
        return const HttpFetchResponse(statusCode: 502, body: 'bad gateway');
      });

      await expectLater(
        providerFor(fetcher).fetch(request()),
        throwsA(
          isA<ExternalServiceError>()
              .having((error) => error.isTransient, 'isTransient', isTrue)
              .having(
                (error) => '${error.details}',
                'details',
                allOf(
                  contains('dict.youdao.com: TIMEOUT'),
                  contains('youdao.com/result: HTTP_502'),
                ),
              ),
        ),
      );
      // 超时的端点重试一次，加上另一端点共三次。
      expect(fetcher.calls, hasLength(3));
    });

    test('两端点都无内容时返回 null（EMPTY）', () async {
      final fetcher = FakeHttpFetcher(
        (url, body) async =>
            const HttpFetchResponse(statusCode: 200, body: '<html></html>'),
      );
      expect(await providerFor(fetcher).fetch(request()), isNull);
    });

    test('只支持英文来源', () {
      final provider = providerFor(
        FakeHttpFetcher(
          (url, body) async =>
              const HttpFetchResponse(statusCode: 200, body: ''),
        ),
      );
      expect(provider.supports(request()), isTrue);
      expect(provider.supports(request(sourceLanguage: 'nl')), isFalse);
      expect(
        provider.supports(request(contentType: LexicalContentType.phrase)),
        isTrue,
      );
      expect(
        provider.supports(request(contentType: LexicalContentType.sentence)),
        isTrue,
      );
      expect(provider.id, 'youdao');
      expect(provider.providedFields, contains('definitions'));
    });
  });
}
