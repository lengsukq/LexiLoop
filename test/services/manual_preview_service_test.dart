/// 手动「词典批量预览」服务的测试。
///
/// 钉住六件事：上限文案、只用有道 + AI 兜底的两段语义、**预览不落库**、
/// 令牌过期、确认幂等、以及确认时「新建 vs 合并」两条路径的落库结果
/// （内容、`provider_attempts`、被禁用的排队任务）。
/// 全程用假词典与内存 Drift 库，不发任何网络请求。
library;

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/data/import/content_type.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/manual_preview_service.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

/// 记录调用参数、按预置逻辑返回结果的假词典。
class _FakeDictionary {
  /// 每次调用收到的选择来源。
  final List<List<String>> selections = <List<String>>[];

  /// 每次调用收到的查询请求。
  final List<ProviderRequest> requests = <ProviderRequest>[];

  /// 按「选择来源」产出结果；未设置时返回一份空内容。
  Future<DictionaryLookupResult> Function(List<String> selectedProviders)?
  handler;

  /// 假词典的调用入口（与 [ManualPreviewLookup] 同形）。
  Future<DictionaryLookupResult> call({
    required AppSettings settings,
    required ProviderRequest request,
    required List<String> selectedProviders,
    required ProviderStrategy strategy,
  }) {
    selections.add(selectedProviders);
    requests.add(request);
    final current = handler;
    if (current != null) return current(selectedProviders);
    return Future<DictionaryLookupResult>.value(_emptyResult());
  }
}

/// 一条释义。
Map<String, Object?> _definition(String text) => <String, Object?>{
  'language': 'zh-CN',
  'text': text,
  'source': 'youdao',
};

/// 一条例句。
Map<String, Object?> _example(String sentence) => <String, Object?>{
  'sentence': sentence,
  'source': 'youdao',
};

/// 一份「可用」的抓取结果（有释义 + 例句 → READY）。
DictionaryLookupResult _richResult({String providerId = 'youdao'}) =>
    DictionaryLookupResult(
      content: DictionaryContent(<String, Object?>{
        'definitions': <Object?>[_definition('苹果')],
        'examples': <Object?>[_example('An apple a day.')],
      }),
      attempts: <ProviderAttemptRecord>[
        ProviderAttemptRecord(
          providerId: providerId,
          status: ProviderAttemptStatus.success,
          durationMs: 12,
          fieldsReturned: const <String>[],
        ),
      ],
      hasTransientFailure: false,
      contentSource: ContentSource.dictionaryOnly,
    );

/// 一份「不可用」的抓取结果。
DictionaryLookupResult _emptyResult() => DictionaryLookupResult(
  content: emptyDictionaryContent(),
  attempts: <ProviderAttemptRecord>[
    const ProviderAttemptRecord(
      providerId: 'youdao',
      status: ProviderAttemptStatus.empty,
      durationMs: 8,
      fieldsReturned: <String>[],
      errorCode: 'REQUESTED_FIELDS_EMPTY',
      errorMessage: '数据源没有返回可用内容',
    ),
  ],
  hasTransientFailure: false,
  contentSource: ContentSource.dictionaryOnly,
);

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late _FakeDictionary dictionary;
  late ManualPreviewService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    dictionary = _FakeDictionary();
    service = ManualPreviewService(
      db,
      settings,
      dictionary.call,
      WordEditService(db),
    );
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> countOf(String table) async {
    final row = await db
        .customSelect('SELECT count(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  /// 造一个已存在的词条（含内容行），返回 ID。
  Future<int> insertWord({
    String term = 'apple',
    String definitionsJson = '[]',
    String userNote = '我的笔记',
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh-CN',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            userNote: Value<String?>(userNote),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: Value<String>(definitionsJson),
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 给某词条入队一个初始化任务，返回任务 ID。
  Future<int> insertJob({
    required int wordId,
    JobTaskType taskType = JobTaskType.initialize,
    InitializationStatus status = InitializationStatus.queued,
  }) => db
      .into(db.initializationJobs)
      .insert(
        InitializationJobsCompanion.insert(
          wordId: wordId,
          taskType: Value<JobTaskType>(taskType),
          mode: InitializationMode.skipInitialized,
          status: Value<InitializationStatus>(status),
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<ManualPreview> preview({
    String text = 'apple',
    LexicalContentType? contentType,
    String sourceLanguage = 'en',
    String targetLanguage = 'zh-CN',
  }) => service.createPreview(
    text: text,
    sourceLanguage: sourceLanguage,
    sourceLanguageName: '英语',
    targetLanguage: targetLanguage,
    targetLanguageName: '简体中文',
    contentType: contentType,
    now: now,
  );

  group('批量上限', () {
    test('行数超限时报旧版文案', () {
      final text = <String>[
        for (var i = 0; i <= manualBatchMaxRows; i += 1) 'word$i',
      ].join('\n');

      expect(manualBatchLimitError(text), '一次最多支持 100 行，请分多次添加。');
    });

    test('单行超限时报旧版文案（截前 24 字符）', () {
      final long = 'a' * (manualBatchMaxCharsPerLine + 1);

      expect(
        manualBatchLimitError(long),
        '“${'a' * 24}…”超过单行 1200 字符限制，请缩短后重试。',
      );
    });

    test('总长度超限时报错', () {
      final text = List<String>.filled(30, 'a' * 900).join('\n');

      expect(text.length, greaterThan(manualBatchMaxTotalChars));
      expect(manualBatchLimitError(text), '一次最多支持 24000 字符，请分多次添加。');
    });

    test('恰好卡在上限内时不报错', () {
      final text = List<String>.filled(
        manualBatchMaxRows,
        'a' * 200,
      ).join('\n');

      expect(text.length, lessThanOrEqualTo(manualBatchMaxTotalChars));
      expect(manualBatchLimitError(text), isNull);
    });

    test('行切分去掉空行与首尾空白', () {
      expect(manualBatchLines(' apple \n\n  \npear\n'), <String>[
        'apple',
        'pear',
      ]);
    });
  });

  group('并发', () {
    test('同时在跑的任务数不超过上限', () async {
      var inFlight = 0;
      var peak = 0;
      final items = <int>[for (var i = 0; i < 20; i += 1) i];

      await runWithConcurrency<int>(
        items,
        limit: manualBatchPreviewConcurrency,
        task: (item, index) async {
          inFlight += 1;
          peak = inFlight > peak ? inFlight : peak;
          await Future<void>.delayed(Duration.zero);
          inFlight -= 1;
        },
      );

      expect(peak, manualBatchPreviewConcurrency);
    });

    test('单项失败不影响其他项（调用方逐项捕获）', () async {
      final succeeded = <int>[];
      final failed = <int>[];

      await runWithConcurrency<int>(
        <int>[for (var i = 0; i < 9; i += 1) i],
        limit: manualBatchPreviewConcurrency,
        task: (item, index) async {
          try {
            if (item == 4) {
              throw const ValidationError(AppErrorCode.validationError);
            }
            succeeded.add(item);
          } on AppError {
            failed.add(item);
          }
        },
      );

      expect(failed, <int>[4]);
      expect(succeeded, <int>[0, 1, 2, 3, 5, 6, 7, 8]);
    });
  });

  group('预览', () {
    test('只用有道，且不写任何表', () async {
      dictionary.handler = (_) async => _richResult();

      final result = await preview();

      expect(dictionary.selections.single, <String>['youdao']);
      expect(dictionary.requests.single.wantedFields, isEmpty);
      expect(dictionary.requests.single.contentType, LexicalContentType.word);
      expect(result.sourceLanguageName, '英语');
      expect(result.targetLanguageName, '简体中文');
      expect(result.normalizedTerm, 'apple');
      expect(result.existingWordId, isNull);
      expect(await countOf('words'), 0);
      expect(await countOf('word_contents'), 0);
      expect(await countOf('provider_attempts'), 0);
    });

    test('内容类型缺省时按输入判定，显式传入时以传入为准', () async {
      dictionary.handler = (_) async => _richResult();

      final auto = await preview(text: 'Practice makes perfect.');
      final forced = await preview(
        text: 'Practice makes perfect.',
        contentType: LexicalContentType.phrase,
      );

      expect(auto.contentType, LexicalContentType.sentence);
      expect(forced.contentType, LexicalContentType.phrase);
    });

    test('已存在的词条记下 existingWordId', () async {
      dictionary.handler = (_) async => _richResult();
      final existingId = await insertWord();

      final result = await preview();

      expect(result.existingWordId, existingId);
    });

    test('调用记录缺字段时用内容里实际非空的字段补齐', () async {
      dictionary.handler = (_) async => _richResult();

      final result = await preview();

      expect(result.providerAttempts.single.fieldsReturned, <String>[
        'definitions',
        'examples',
      ]);
    });

    Future<void> enableAiFallback() => settings.update(<String, Object?>{
      'llmConfig': <String, Object?>{
        'providers': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'name': 'OpenAI',
            'apiType': 'openai',
            'baseUrl': 'https://a.example/v1',
            'apiKey': 'sk-test',
          },
        ],
        'ai': <String, Object?>{
          'enabled': true,
          'providerId': 'p1',
          'model': 'gpt-4o',
          'features': <String, Object?>{'dictionaryFallback': true},
        },
      },
    }, now: now);

    test('默认不开启 AI 兜底时，有道无结果不会静默调用 AI', () async {
      dictionary.handler = (_) async => _emptyResult();

      await expectLater(
        preview(),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.details,
            'details',
            contains('当前仅使用有道词典查词'),
          ),
        ),
      );
      expect(dictionary.selections, <List<String>>[
        <String>['youdao'],
      ]);
    });

    test('开启 AI 兜底且有道没有可用内容时再用 AI 兜底一次', () async {
      await enableAiFallback();
      dictionary.handler = (selected) async => selected.contains('ai')
          ? _richResult(providerId: 'ai:openai:gpt-4o')
          : _emptyResult();

      final result = await preview();

      expect(dictionary.selections, hasLength(2));
      expect(dictionary.selections.first, <String>['youdao']);
      expect(dictionary.selections.last, <String>['ai']);
      expect(result.content.records('definitions'), hasLength(1));
      expect(result.providerAttempts, hasLength(2));
    });

    test('两次都没有可用内容时报错，文案点明可操作原因', () async {
      await enableAiFallback();
      dictionary.handler = (_) async => _emptyResult();

      await expectLater(
        preview(),
        throwsA(
          isA<ExternalServiceError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.requestedFieldsEmpty,
              )
              .having(
                (error) => error.details,
                'details',
                contains('词典没有返回可用释义，请调整输入或稍后重试。'),
              ),
        ),
      );
    });

    test('AI 兜底不可用时，报错里说明「AI 不可用」', () async {
      await enableAiFallback();
      dictionary.handler = (selected) async {
        if (selected.contains('ai')) {
          throw const ExternalServiceError(
            AppErrorCode.providerNotFound,
            details: '没有可用的数据源',
          );
        }
        return _emptyResult();
      };

      await expectLater(
        preview(),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.details,
            'details',
            contains('AI 兜底不可用：没有可用的数据源'),
          ),
        ),
      );
    });

    test('有道不可用（如源语言不是英语）时不冒 providerNotFound，而是报可操作原因', () async {
      dictionary.handler = (selected) async {
        if (selected.contains('youdao')) {
          throw const ExternalServiceError(
            AppErrorCode.providerNotFound,
            details: '没有可用的数据源（未启用、不支持该请求，或请求字段无交集）',
          );
        }
        return _emptyResult();
      };

      await expectLater(
        preview(text: 'こんにちは', sourceLanguage: 'ja'),
        throwsA(
          isA<ExternalServiceError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.requestedFieldsEmpty,
              )
              .having(
                (error) => error.details,
                'details',
                contains('有道词典不可用：没有可用的数据源'),
              ),
        ),
      );
    });

    test('空输入被拒', () async {
      await expectLater(
        preview(text: '   '),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.termRequired,
          ),
        ),
      );
    });
  });

  group('确认', () {
    test('新建词条：写词条、内容与审计，状态由内容推导', () async {
      dictionary.handler = (_) async => _richResult();
      final pending = await preview();

      final result = await service.confirmPreview(
        previewToken: pending.previewToken,
        now: now,
      );

      expect(result.created, isTrue);
      expect(result.idempotent, isFalse);
      expect(result.contentType, LexicalContentType.word);
      expect(result.initializationStatus, InitializationStatus.ready);

      final word = await db
          .customSelect(
            'SELECT * FROM words WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(result.wordId)],
          )
          .getSingle();
      expect(word.read<String>('term'), 'apple');
      expect(word.read<String>('mastery_level'), 'NEW');
      expect(word.read<int>('mastery_score'), 0);
      expect(word.read<bool>('is_suspended'), isFalse);
      expect(word.read<String>('source_created_at'), isNotNull);
      expect(word.read<String>('content_type'), 'WORD');
      expect(word.read<String>('source_language_name'), '英语');

      final attempts = await db
          .customSelect('SELECT * FROM provider_attempts')
          .get();
      expect(attempts, hasLength(1));
      expect(attempts.single.read<String>('provider_id'), 'youdao');
      expect(attempts.single.read<int?>('initialization_job_id'), isNull);
      expect(
        attempts.single.read<String>('fields_returned_json'),
        contains('definitions'),
      );
    });

    test('已有词条：把预览内容合并进已有内容，并保留用户笔记', () async {
      dictionary.handler = (_) async => _richResult();
      final existingId = await insertWord(
        definitionsJson:
            '[{"language":"zh-CN","text":"旧释义","source":"youdao"}]',
      );
      final pending = await preview();

      final result = await service.confirmPreview(
        previewToken: pending.previewToken,
        now: now,
      );

      expect(result.created, isFalse);
      expect(result.wordId, existingId);
      expect(await countOf('words'), 1);
      final content = await db
          .customSelect(
            'SELECT definitions_json FROM word_contents WHERE word_id = ?',
            variables: <Variable<Object>>[Variable<int>(existingId)],
          )
          .getSingle();
      final definitions = content.read<String>('definitions_json');
      expect(definitions, contains('旧释义'));
      expect(definitions, contains('苹果'));
      final word = await db
          .customSelect(
            'SELECT user_note FROM words WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(existingId)],
          )
          .getSingle();
      expect(word.read<String?>('user_note'), '我的笔记');
    });

    test('同一令牌确认两次返回同一个 wordId 且幂等', () async {
      dictionary.handler = (_) async => _richResult();
      final pending = await preview();

      final first = await service.confirmPreview(
        previewToken: pending.previewToken,
        now: now,
      );
      final second = await service.confirmPreview(
        previewToken: pending.previewToken,
        now: now + 1,
      );

      expect(second.wordId, first.wordId);
      expect(second.idempotent, isTrue);
      expect(second.created, isFalse);
      expect(second.initializationStatus, first.initializationStatus);
      expect(await countOf('words'), 1);
      expect(await countOf('provider_attempts'), 1);
    });

    test('令牌过期后确认报「预览已过期，请重新生成」', () async {
      dictionary.handler = (_) async => _richResult();
      final pending = await preview();

      await expectLater(
        service.confirmPreview(
          previewToken: pending.previewToken,
          now: now + importPreviewTtlMs + 1,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.details,
            'details',
            '预览已过期，请重新生成。',
          ),
        ),
      );
      // 过期预览被丢弃：再用一个合法时间也找不到它。
      await expectLater(
        service.confirmPreview(previewToken: pending.previewToken, now: now),
        throwsA(
          isA<AppError>().having(
            (error) => error.details,
            'details',
            '预览不存在，请重新生成。',
          ),
        ),
      );
    });

    test('未确认过的令牌报「预览不存在」', () async {
      await expectLater(
        service.confirmPreview(previewToken: 'nope', now: now),
        throwsA(isA<AppError>()),
      );
    });

    test('确认后该词条排队中的初始化任务被禁用，其他词条不受影响', () async {
      dictionary.handler = (_) async => _richResult();
      final targetId = await insertWord();
      final otherId = await insertWord(term: 'pear');
      final targetJob = await insertJob(wordId: targetId);
      final otherJob = await insertJob(wordId: otherId);
      final pending = await preview();

      await service.confirmPreview(
        previewToken: pending.previewToken,
        now: now,
      );

      final target = await db
          .customSelect(
            'SELECT * FROM initialization_jobs WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(targetJob)],
          )
          .getSingle();
      expect(target.read<String>('status'), 'DISABLED');
      expect(target.read<String>('last_error'), 'Manual preview confirmed');
      expect(
        target.read<String>('last_error_code'),
        'MANUAL_PREVIEW_CONFIRMED',
      );
      expect(target.read<int?>('completed_at'), isNotNull);
      expect(target.read<int?>('updated_at'), isNotNull);
      expect(target.read<int?>('locked_at'), isNull);
      expect(target.read<String?>('locked_by'), isNull);

      final other = await db
          .customSelect(
            'SELECT status FROM initialization_jobs WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(otherJob)],
          )
          .getSingle();
      expect(other.read<String>('status'), 'QUEUED');
    });

    test('已有的非排队任务不被改动', () async {
      dictionary.handler = (_) async => _richResult();
      final targetId = await insertWord();
      final running = await insertJob(
        wordId: targetId,
        taskType: JobTaskType.exampleTranslations,
        status: InitializationStatus.running,
      );
      final pending = await preview();

      await service.confirmPreview(
        previewToken: pending.previewToken,
        now: now,
      );

      final row = await db
          .customSelect(
            'SELECT status FROM initialization_jobs WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(running)],
          )
          .getSingle();
      expect(row.read<String>('status'), 'RUNNING');
    });
  });

  group('内容类型与入口一致性', () {
    test('句子类词条的 entry_type 落成 PHRASE', () async {
      dictionary.handler = (_) async => DictionaryLookupResult(
        content: DictionaryContent(<String, Object?>{
          'definitions': <Object?>[_definition('熟能生巧。')],
          'examples': <Object?>[_example('Practice makes perfect.')],
        }),
        attempts: const <ProviderAttemptRecord>[],
        hasTransientFailure: false,
        contentSource: ContentSource.dictionaryOnly,
      );
      final pending = await preview(text: 'Practice makes perfect.');

      final result = await service.confirmPreview(
        previewToken: pending.previewToken,
        now: now,
      );

      expect(result.contentType, LexicalContentType.sentence);
      expect(entryTypeFor(result.contentType), EntryType.phrase);
    });
  });
}
