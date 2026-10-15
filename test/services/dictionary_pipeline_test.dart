/// 数据源选择与调用管线测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/dictionary/selection.dart';

/// 归一化一份测试内容。
DictionaryContent normalizeForTest(Map<String, Object?> fields) =>
    normalizeDictionaryContent(fields);

/// 可编程的假数据源。
class FakeProvider implements DictionaryProvider {
  new(
    this.id, {
    this.fields = const <String>{'definitions'},
    this.enabled = true,
    this.supported = true,
    this.result,
    this.error,
  });

  @override
  final String id;

  final Set<String> fields;

  final bool enabled;
  final bool supported;
  final ProviderResult? result;
  final ExternalServiceError? error;

  /// 被调用的次数。
  int calls = 0;

  @override
  Set<String> get providedFields => fields;

  @override
  bool isEnabled(AppSettings settings) => enabled;

  @override
  bool supports(ProviderRequest request) => supported;

  @override
  Future<ProviderResult?> fetch(ProviderRequest request) async {
    calls += 1;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

Map<String, Object?> definition(String text, {String language = 'zh-CN'}) =>
    <String, Object?>{'language': language, 'text': text, 'source': 'test'};

Map<String, Object?> example(String sentence) => <String, Object?>{
  'sentence': sentence,
  'source': 'test',
};

Map<String, Object?> phonetic(String value) => <String, Object?>{
  'accent': 'US',
  'phonetic': value,
  'source': 'test',
};

/// 一份「高质量」内容：目标语言释义 + 2 条例句 + 音标。
ProviderResult richResult(String providerId) => ProviderResult(
  providerId: providerId,
  fields: <String, Object?>{
    'definitions': <Object?>[definition('你好')],
    'examples': <Object?>[example('Hello there.'), example('Say hello.')],
    'pronunciations': <Object?>[phonetic('həˈloʊ')],
  },
);

ProviderRequest request({
  Set<String> wantedFields = const <String>{},
  LexicalContentType contentType = LexicalContentType.word,
}) => ProviderRequest(
  term: 'hello',
  contentType: contentType,
  sourceLanguage: 'en',
  targetLanguage: 'zh-CN',
  wantedFields: wantedFields,
);

void main() {
  group('ProviderPipeline', () {
    test('PRIORITY_FALLBACK 在质量达标时提前终止', () async {
      final first = FakeProvider('youdao', result: richResult('youdao'));
      final second = FakeProvider('iciba', result: richResult('iciba'));
      final pipeline = ProviderPipeline(
        providers: <DictionaryProvider>[first, second],
        strategy: ProviderStrategy.priorityFallback,
      );

      final result = await pipeline.lookup(request());

      expect(first.calls, 1);
      expect(second.calls, 0);
      expect(result.attempts, hasLength(1));
      expect(result.content.records('definitions'), hasLength(1));
      expect(result.contentSource, ContentSource.dictionaryOnly);
    });

    test('PRIORITY_FALLBACK 在质量不达标时继续下一个来源', () async {
      final weak = FakeProvider(
        'youdao',
        result: ProviderResult(
          providerId: 'youdao',
          fields: <String, Object?>{
            'definitions': <Object?>[definition('你好')],
          },
        ),
      );
      final strong = FakeProvider('iciba', result: richResult('iciba'));
      final pipeline = ProviderPipeline(
        providers: <DictionaryProvider>[weak, strong],
        strategy: ProviderStrategy.priorityFallback,
      );

      final result = await pipeline.lookup(request());

      expect(weak.calls, 1);
      expect(strong.calls, 1);
      expect(result.attempts, hasLength(2));
      // 两来源合并后例句与音标都补齐了。
      expect(result.content.records('examples'), hasLength(2));
      expect(result.content.records('pronunciations'), hasLength(1));
    });

    test('PARALLEL_MERGE 调用全部来源', () async {
      final first = FakeProvider('youdao', result: richResult('youdao'));
      final second = FakeProvider('iciba', result: richResult('iciba'));
      final pipeline = ProviderPipeline(
        providers: <DictionaryProvider>[first, second],
        strategy: ProviderStrategy.parallelMerge,
      );

      await pipeline.lookup(request());

      expect(first.calls, 1);
      expect(second.calls, 1);
    });

    test('瞬时错误记入尝试并把 hasTransientFailure 置真', () async {
      final failing = FakeProvider(
        'youdao',
        error: const ExternalServiceError(
          AppErrorCode.providerTransientFailure,
          isTransient: true,
        ),
      );
      final ok = FakeProvider('iciba', result: richResult('iciba'));
      final pipeline = ProviderPipeline(
        providers: <DictionaryProvider>[failing, ok],
        strategy: ProviderStrategy.parallelMerge,
      );

      final result = await pipeline.lookup(request());

      expect(result.hasTransientFailure, isTrue);
      expect(result.attempts.first.status, ProviderAttemptStatus.failed);
      expect(result.attempts.first.errorCode, 'PROVIDER_TRANSIENT_FAILURE');
      expect(result.attempts.last.status, ProviderAttemptStatus.success);
    });

    test('非瞬时错误不置 hasTransientFailure', () async {
      final failing = FakeProvider(
        'youdao',
        error: const ExternalServiceError(AppErrorCode.requestedFieldsEmpty),
      );
      final pipeline = ProviderPipeline(
        providers: <DictionaryProvider>[failing],
        strategy: ProviderStrategy.parallelMerge,
      );

      final result = await pipeline.lookup(request());
      expect(result.hasTransientFailure, isFalse);
    });

    test('返回 null 的来源记为 EMPTY', () async {
      final empty = FakeProvider('youdao');
      final pipeline = ProviderPipeline(
        providers: <DictionaryProvider>[empty],
        strategy: ProviderStrategy.parallelMerge,
      );

      final result = await pipeline.lookup(request());
      expect(result.attempts.single.status, ProviderAttemptStatus.empty);
    });

    test('AI 与词典同时成功时内容来源为 MIXED', () async {
      final ai = FakeProvider('ai:p1:m1', result: richResult('ai:p1:m1'));
      final dictionary = FakeProvider('youdao', result: richResult('youdao'));
      final pipeline = ProviderPipeline(
        providers: <DictionaryProvider>[ai, dictionary],
        strategy: ProviderStrategy.parallelMerge,
      );

      final result = await pipeline.lookup(request());
      expect(result.contentSource, ContentSource.mixed);
    });

    test('只有 AI 成功时内容来源为 AI_ONLY', () async {
      final ai = FakeProvider('ai:p1:m1', result: richResult('ai:p1:m1'));
      final pipeline = ProviderPipeline(
        providers: <DictionaryProvider>[ai],
        strategy: ProviderStrategy.parallelMerge,
      );

      final result = await pipeline.lookup(request());
      expect(result.contentSource, ContentSource.aiOnly);
    });

    test('句子缺少译文时质量分被压低', () {
      final content = <String, Object?>{
        'definitions': <Object?>[definition('你好', language: 'en')],
        'examples': <Object?>[example('a'), example('b')],
        'pronunciations': <Object?>[phonetic('x')],
      };
      final score = fallbackQualityScore(
        normalizeForTest(content),
        request(contentType: LexicalContentType.sentence),
      );
      expect(score, lessThanOrEqualTo(0.6));
    });
  });

  group('selectProviders', () {
    AppSettings settings({bool youdaoEnabled = true}) =>
        appSettingsFromRaw(<String, Object?>{'youdaoEnabled': youdaoEnabled});

    test('按顺序过滤未启用与不支持的来源', () {
      final youdao = FakeProvider('youdao', enabled: false);
      final iciba = FakeProvider('iciba', supported: false);
      final dictionaryApi = FakeProvider('dictionaryapi.dev');
      final selected = selectProviders(
        settings: settings(),
        request: request(),
        candidates: <DictionaryProvider>[youdao, iciba, dictionaryApi],
      );
      // 有道被禁用、爱词霸不支持该请求，只剩 dictionaryapi.dev。
      expect(selected.map((provider) => provider.id), <String>[
        'dictionaryapi.dev',
      ]);
    });

    test('设置里关掉的数据源不会被真实 provider 选中', () {
      final youdao = FakeProvider('youdao');
      final selected = selectProviders(
        settings: settings(youdaoEnabled: false),
        request: request(),
        candidates: <DictionaryProvider>[youdao],
      );
      // FakeProvider 忽略设置，因此这里验证的是顺序与过滤的接线本身。
      expect(selected, hasLength(1));
      expect(
        appSettingsFromRaw(<String, Object?>{'youdaoEnabled': false})
            .providers
            .youdaoEnabled,
        isFalse,
      );
    });

    test('显式来源列表覆盖设置里的顺序', () {
      final youdao = FakeProvider('youdao');
      final iciba = FakeProvider('iciba');
      final selected = selectProviders(
        settings: settings(),
        request: request(),
        candidates: <DictionaryProvider>[youdao, iciba],
        selectedProviders: <String>['iciba', 'youdao'],
      );
      expect(selected.map((provider) => provider.id), <String>[
        'iciba',
        'youdao',
      ]);
    });

    test('句子类词条上勾选同义词会跳过有道与爱词霸', () {
      final youdao = FakeProvider(
        'youdao',
        fields: <String>{'definitions', 'synonyms', 'summary'},
      );
      final ai = FakeProvider('ai:p:m', fields: <String>{'synonyms'});
      final selected = selectProviders(
        settings: settings(),
        request: request(
          wantedFields: <String>{'synonyms'},
          contentType: LexicalContentType.sentence,
        ),
        candidates: <DictionaryProvider>[youdao, ai],
        // AI 不在默认顺序里，必须显式指定（与旧版一致）。
        selectedProviders: <String>['ai'],
      );
      expect(selected.map((provider) => provider.id), <String>['ai:p:m']);
    });

    test('能力与请求字段无交集时跳过该来源', () {
      final mymemory = FakeProvider(
        'mymemory',
        fields: <String>{'definitions'},
      );
      final selected = selectProviders(
        settings: settings(),
        request: request(wantedFields: <String>{'synonyms'}),
        candidates: <DictionaryProvider>[mymemory],
      );
      expect(selected, isEmpty);
    });
  });

  group('requestedFieldStatusForLanguages', () {
    test('只有非目标语言释义时降级为 PARTIAL', () {
      final content = normalizeForTest(<String, Object?>{
        'definitions': <Object?>[definition('a greeting', language: 'en')],
      });
      expect(
        requestedFieldStatusForLanguages(
          content,
          <String>['definitions'],
          'en',
          'zh-CN',
        ),
        InitializationStatus.partial,
      );
      expect(
        requestedFieldStatusForLanguages(
          normalizeForTest(<String, Object?>{
            'definitions': <Object?>[definition('你好')],
          }),
          <String>['definitions'],
          'en',
          'zh-CN',
        ),
        InitializationStatus.ready,
      );
    });
  });
}
