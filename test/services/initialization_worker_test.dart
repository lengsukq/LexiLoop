/// 初始化任务队列与 worker 测试。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/lookup_service.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/services/initialization/initialization_queries.dart';
import 'package:lexiloop/services/initialization/initialization_worker.dart';
import 'package:lexiloop/services/initialization/supplemental_tasks.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../data/dictionary/fake_http_fetcher.dart';

/// 判据用：超过该时长没再答错的错词应当退出错词本。
const int staleWrongWordMs = wrongWordDecayDays * dayMs;

/// 永远失败的补充任务执行器（本组用例只关心状态机）。
class FailingSupplemental implements SupplementalTaskRunner {
  @override
  Future<void> run({
    required JobTaskType taskType,
    required int wordId,
    required int now,
  }) async {}
}

/// 有道页面的最小可用片段：目标语言释义 + 2 条例句 + 音标。
String youdaoHtml(String term) {
  final lines = <String>[
    '英 [həˈləʊ]',
    '简明',
    'int. 你好',
    '双语例句',
    '1',
    'Hello there, $term.',
    '你好。',
    '2',
    'Say $term again.',
    '再说一遍。',
  ];
  return '<html><body>${lines.map((line) => '<div>$line</div>').join()}'
      '</body></html>';
}

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late InitializationQueries queries;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    queries = InitializationQueries(db, settings);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertWord({
    String term = 'hello',
    bool isSuspended = false,
    InitializationStatus status = InitializationStatus.pending,
  }) => db
      .into(db.words)
      .insert(
        WordsCompanion.insert(
          term: term,
          normalizedTerm: term.toLowerCase(),
          sourceLanguage: 'en',
          targetLanguage: 'zh-CN',
          entryType: EntryType.word,
          initializationStatus: Value<InitializationStatus>(status),
          isSuspended: Value<bool>(isSuspended),
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<int> insertJob({
    required int wordId,
    int priority = 0,
    int? availableAt,
    int maxAttempts = 3,
    InitializationStatus status = InitializationStatus.queued,
    int attemptCount = 0,
  }) => db
      .into(db.initializationJobs)
      .insert(
        InitializationJobsCompanion.insert(
          wordId: wordId,
          mode: InitializationMode.skipInitialized,
          priority: Value<int>(priority),
          availableAt: Value<int?>(availableAt),
          maxAttempts: Value<int>(maxAttempts),
          status: Value<InitializationStatus>(status),
          attemptCount: Value<int>(attemptCount),
          createdAt: now,
          updatedAt: now,
        ),
      );

  InitializationWorker workerWith(HttpFetcher fetcher) => InitializationWorker(
    db,
    settings,
    queries,
    DictionaryLookupService(fetcher),
    FailingSupplemental(),
  );

  /// 所有数据源都返回 503 → 瞬时失败。
  FakeHttpFetcher failingFetcher() => FakeHttpFetcher(
    (url, body) async =>
        const HttpFetchResponse(statusCode: 503, body: 'unavailable'),
  );

  /// 有道端点返回可用内容，其余返回空页面。
  FakeHttpFetcher succeedingFetcher(String term) => FakeHttpFetcher(
    (url, body) async => HttpFetchResponse(
      statusCode: 200,
      body: url.contains('dict.youdao.com')
          ? youdaoHtml(term)
          : '<html></html>',
    ),
  );

  Future<Map<String, Object?>> jobRow(int jobId) async {
    final row = await db
        .customSelect(
          'SELECT * FROM initialization_jobs WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(jobId)],
        )
        .getSingle();
    return row.data;
  }

  Future<String> wordStatus(int wordId) async {
    final row = await db
        .customSelect(
          'SELECT initialization_status AS s FROM words WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingle();
    return row.read<String>('s');
  }

  group('maxAttemptsFromSettings', () {
    test('缺键时用导入默认值，存在时用 aiRetryCount + 1 并夹到区间', () {
      expect(
        maxAttemptsFromSettings(appSettingsFromRaw(<String, Object?>{})),
        importJobMaxAttempts,
      );
      expect(
        maxAttemptsFromSettings(
          appSettingsFromRaw(<String, Object?>{'aiRetryCount': 1}),
        ),
        2,
      );
      expect(
        maxAttemptsFromSettings(
          appSettingsFromRaw(<String, Object?>{'aiRetryCount': 5}),
        ),
        maxAttemptsCeiling,
      );
      expect(
        maxAttemptsFromSettings(
          appSettingsFromRaw(<String, Object?>{'aiRetryCount': 99}),
        ),
        maxAttemptsCeiling,
      );
      expect(
        maxAttemptsFromSettings(
          appSettingsFromRaw(<String, Object?>{'aiRetryCount': -5}),
        ),
        maxAttemptsFloor,
      );
    });
  });

  group('tick', () {
    test('按优先级取任务并按 defaultMaxJobsPerTick 限量', () async {
      final wordIds = <int>[];
      for (var index = 0; index < 5; index += 1) {
        wordIds.add(await insertWord(term: 'word$index'));
      }
      final jobIds = <int>[];
      for (var index = 0; index < 5; index += 1) {
        jobIds.add(
          await insertJob(
            wordId: wordIds[index],
            priority: index,
            availableAt: now,
          ),
        );
      }

      final processed = await workerWith(failingFetcher()).tick(now: now);

      expect(processed, defaultMaxJobsPerTick);
      // 优先级最高的 3 个（index 4、3、2）被尝试过。
      for (final index in <int>[4, 3, 2]) {
        expect((await jobRow(jobIds[index]))['attempt_count'], 1);
      }
      for (final index in <int>[1, 0]) {
        expect((await jobRow(jobIds[index]))['attempt_count'], 0);
      }
    });

    test('available_at 在未来的任务不会被取走', () async {
      final wordId = await insertWord();
      final jobId = await insertJob(wordId: wordId, availableAt: now + 60000);
      expect(await workerWith(failingFetcher()).tick(now: now), 0);
      expect((await jobRow(jobId))['attempt_count'], 0);
    });

    test('失败后按退避序列重排并累加尝试次数', () async {
      final wordId = await insertWord();
      final jobId = await insertJob(wordId: wordId);

      await workerWith(failingFetcher()).tick(now: now);

      final row = await jobRow(jobId);
      expect(row['status'], InitializationStatus.queued.wire);
      expect(row['attempt_count'], 1);
      expect(row['available_at'], now + retryBackoffMs.first);
      expect(row['last_error_code'], 'PROVIDER_TRANSIENT_FAILURE');
      expect(await wordStatus(wordId), InitializationStatus.queued.wire);
    });

    test('尝试次数到上限后置 FAILED', () async {
      final wordId = await insertWord();
      final jobId = await insertJob(wordId: wordId);
      final worker = workerWith(failingFetcher());

      await worker.tick(now: now);
      await worker.tick(now: now + retryBackoffMs[0]);
      await worker.tick(now: now + retryBackoffMs[0] + retryBackoffMs[1]);

      final row = await jobRow(jobId);
      expect(row['status'], InitializationStatus.failed.wire);
      expect(row['attempt_count'], 3);
      expect(row['completed_at'], isNotNull);
      expect(await wordStatus(wordId), InitializationStatus.failed.wire);
    });

    test('成功时写入内容、词条状态与数据源审计', () async {
      final wordId = await insertWord();
      final jobId = await insertJob(wordId: wordId);

      await workerWith(succeedingFetcher('hello')).tick(now: now);

      final row = await jobRow(jobId);
      expect(row['status'], InitializationStatus.ready.wire);
      expect(await wordStatus(wordId), InitializationStatus.ready.wire);

      final content = await db
          .customSelect(
            'SELECT definitions_json, content_source, provider_metadata_json '
            'FROM word_contents WHERE word_id = ?',
            variables: <Variable<Object>>[Variable<int>(wordId)],
          )
          .getSingle();
      final definitions =
          jsonDecode(content.read<String>('definitions_json')) as List<Object?>;
      expect(definitions, isNotEmpty);
      expect(content.read<String>('content_source'), 'DICTIONARY_ONLY');
      final metadata = jsonDecode(
        content.read<String>('provider_metadata_json'),
      ) as List<Object?>;
      expect(metadata, isNotEmpty);

      final attempts = await db
          .customSelect(
            'SELECT provider_id, status FROM provider_attempts '
            'WHERE initialization_job_id = ?',
            variables: <Variable<Object>>[Variable<int>(jobId)],
          )
          .get();
      expect(attempts, isNotEmpty);
      expect(
        attempts.map((attempt) => attempt.read<String>('provider_id')),
        contains('youdao'),
      );
    });

    test('SKIP_INITIALIZED 模式下已有内容直接完成，不调用数据源', () async {
      final wordId = await insertWord(status: InitializationStatus.ready);
      await db
          .into(db.wordContents)
          .insert(
            WordContentsCompanion.insert(
              wordId: Value<int>(wordId),
              definitionsJson: Value<String>(
                jsonEncode(<Object?>[
                  <String, Object?>{
                    'language': 'zh-CN',
                    'text': '你好',
                    'partOfSpeech': 'int',
                  },
                ]),
              ),
              examplesJson: Value<String>(
                jsonEncode(<Object?>[
                  <String, Object?>{'sentence': 'Hello.'},
                ]),
              ),
              updatedAt: now,
            ),
          );
      final jobId = await insertJob(wordId: wordId);
      final fetcher = failingFetcher();

      await workerWith(fetcher).tick(now: now);

      expect(fetcher.calls, isEmpty);
      expect((await jobRow(jobId))['status'], InitializationStatus.ready.wire);
    });

    test('开启 AI 但未开启「后台自动生成助记」时，有道完成后不入队助记任务', () async {
      await settings.update(<String, Object?>{
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
          },
        },
      }, now: now);
      final wordId = await insertWord();
      await insertJob(wordId: wordId);

      await workerWith(succeedingFetcher('hello')).tick(now: now);

      final mnemonicJobs = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM initialization_jobs '
            "WHERE task_type = 'MNEMONIC'",
          )
          .getSingle();
      expect(mnemonicJobs.read<int>('c'), 0);
    });

    test('显式开启「后台自动生成助记」时，有道完成后自动入队助记任务', () async {
      await settings.update(<String, Object?>{
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
            'features': <String, Object?>{'autoMnemonic': true},
          },
        },
      }, now: now);
      final wordId = await insertWord();
      await insertJob(wordId: wordId);

      await workerWith(succeedingFetcher('hello')).tick(now: now);

      final mnemonicJobs = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM initialization_jobs '
            "WHERE task_type = 'MNEMONIC'",
          )
          .getSingle();
      expect(mnemonicJobs.read<int>('c'), 1);
    });
  });

  group('resetStaleRunningJobs', () {
    test('把 RUNNING 收回 QUEUED 并同步词条状态', () async {
      final wordId = await insertWord(status: InitializationStatus.running);
      final jobId = await insertJob(
        wordId: wordId,
        status: InitializationStatus.running,
      );

      final changed = await workerWith(failingFetcher())
          .resetStaleRunningJobs(now);

      expect(changed, 1);
      final row = await jobRow(jobId);
      expect(row['status'], InitializationStatus.queued.wire);
      expect(row['last_error_code'], 'STALE_LOCK');
      expect(await wordStatus(wordId), InitializationStatus.queued.wire);
    });

    test('staleOnly 只回收锁已过期的任务', () async {
      final freshWord = await insertWord(term: 'fresh');
      final staleWord = await insertWord(term: 'stale');
      final freshJob = await insertJob(
        wordId: freshWord,
        status: InitializationStatus.running,
      );
      final staleJob = await insertJob(
        wordId: staleWord,
        status: InitializationStatus.running,
      );
      await db.customUpdate(
        'UPDATE initialization_jobs SET locked_at = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<int>(now - workerStaleAfterMs - 1),
          Variable<int>(staleJob),
        ],
        updateKind: UpdateKind.update,
      );

      final changed = await workerWith(failingFetcher())
          .resetStaleRunningJobs(now, staleOnly: true);

      expect(changed, 1);
      expect(
        (await jobRow(staleJob))['status'],
        InitializationStatus.queued.wire,
      );
      expect(
        (await jobRow(freshJob))['status'],
        InitializationStatus.running.wire,
      );
    });
  });

  group('retryFailedJobs', () {
    test('冷却已过的失败任务重新入队并清零尝试次数', () async {
      final wordId = await insertWord();
      final jobId = await insertJob(
        wordId: wordId,
        status: InitializationStatus.failed,
        attemptCount: 3,
      );
      await db.customUpdate(
        'UPDATE initialization_jobs SET completed_at = ? WHERE id = ?',
        variables: <Variable<Object>>[
          Variable<int>(now - failedRetryCooldownMs - 1),
          Variable<int>(jobId),
        ],
        updateKind: UpdateKind.update,
      );

      final changed = await workerWith(failingFetcher()).retryFailedJobs(now);

      expect(changed, 1);
      final row = await jobRow(jobId);
      expect(row['status'], InitializationStatus.queued.wire);
      expect(row['attempt_count'], 0);
      expect(row['last_error_code'], 'AUTO_RETRY');
    });

    test('冷却未过的失败任务不重排', () async {
      final wordId = await insertWord();
      final jobId = await insertJob(
        wordId: wordId,
        status: InitializationStatus.failed,
      );
      await db.customUpdate(
        'UPDATE initialization_jobs SET completed_at = ? WHERE id = ?',
        variables: <Variable<Object>>[Variable<int>(now), Variable<int>(jobId)],
        updateKind: UpdateKind.update,
      );
      expect(await workerWith(failingFetcher()).retryFailedJobs(now), 0);
    });
  });

  group('decayStaleWrongWords', () {
    /// 插入一条错词状态。
    Future<int> insertWrongWord({
      required String term,
      bool active = true,
      int? lastWrongAt,
      int? lastCorrectAt,
    }) async {
      final wordId = await insertWord(term: term);
      await db
          .into(db.wrongWordStates)
          .insert(
            WrongWordStatesCompanion.insert(
              wordId: Value<int>(wordId),
              active: Value<bool>(active),
              wrongCount: const Value<int>(1),
              lastWrongAt: Value<int?>(lastWrongAt),
              lastCorrectAt: Value<int?>(lastCorrectAt),
              updatedAt: now,
            ),
          );
      return wordId;
    }

    Future<Map<String, Object?>> wrongWordRow(int wordId) async {
      final row = await db
          .customSelect(
            'SELECT * FROM wrong_word_states WHERE word_id = ?',
            variables: <Variable<Object>>[Variable<int>(wordId)],
          )
          .getSingle();
      return row.data;
    }

    test('超过衰减天数且此后没答对过的错词退出错词本', () async {
      final stale = await insertWrongWord(
        term: 'stale',
        lastWrongAt: now - staleWrongWordMs - 1,
      );
      final recent = await insertWrongWord(
        term: 'recent',
        lastWrongAt: now - 1,
      );

      final changed = await workerWith(failingFetcher())
          .decayStaleWrongWords(now);

      expect(changed, 1);
      final staleRow = await wrongWordRow(stale);
      expect(staleRow['active'], 0);
      expect(staleRow['resolved_at'], now);
      expect(staleRow['updated_at'], now);
      expect((await wrongWordRow(recent))['active'], 1);
    });

    test('「先错很久、最近刚答对一次」的错词保留', () async {
      final wordId = await insertWrongWord(
        term: 'recovered',
        lastWrongAt: now - staleWrongWordMs - 1,
        lastCorrectAt: now - 1,
      );

      expect(await workerWith(failingFetcher()).decayStaleWrongWords(now), 0);
      expect((await wrongWordRow(wordId))['active'], 1);
    });

    test('恰好卡在衰减边界上不衰减，且已退出的不重复处理', () async {
      final boundary = await insertWrongWord(
        term: 'boundary',
        lastWrongAt: now - staleWrongWordMs,
      );
      final inactive = await insertWrongWord(
        term: 'inactive',
        active: false,
        lastWrongAt: now - staleWrongWordMs - 1,
      );

      expect(await workerWith(failingFetcher()).decayStaleWrongWords(now), 0);
      expect((await wrongWordRow(boundary))['active'], 1);
      expect((await wrongWordRow(inactive))['resolved_at'], isNull);
    });
  });

  group('expireStaleImportBatches', () {
    /// 插入一个导入批次。
    Future<int> insertBatch({
      required int createdAt,
      ImportBatchStatus status = ImportBatchStatus.pending,
    }) async {
      final id = await db
          .into(db.importBatches)
          .insert(
            ImportBatchesCompanion.insert(
              filename: 'words.csv',
              importMode: ImportMode.fillMissing,
              status: Value<ImportBatchStatus>(status),
              totalRows: const Value<int>(3),
              validRows: const Value<int>(3),
              createdAt: createdAt,
            ),
          );
      return id;
    }

    Future<String> batchStatus(int batchId) async {
      final row = await db
          .customSelect(
            'SELECT status FROM import_batches WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(batchId)],
          )
          .getSingle();
      return row.read<String>('status');
    }

    test('卡在 PENDING 超过过期时长的批次置为 FAILED', () async {
      final stuck = await insertBatch(createdAt: now - importBatchExpiryMs - 1);

      final changed = await workerWith(failingFetcher())
          .expireStaleImportBatches(now);

      expect(changed, 1);
      expect(await batchStatus(stuck), ImportBatchStatus.failed.wire);
      final row = await db
          .customSelect(
            'SELECT completed_at FROM import_batches WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(stuck)],
          )
          .getSingle();
      expect(row.read<int>('completed_at'), now);
    });

    test('未到期的批次与已结束的批次都不动', () async {
      final fresh = await insertBatch(createdAt: now - 1);
      final committed = await insertBatch(
        status: ImportBatchStatus.committed,
        createdAt: now - importBatchExpiryMs - 1,
      );

      final changed = await workerWith(failingFetcher())
          .expireStaleImportBatches(now);

      expect(changed, 0);
      expect(await batchStatus(fresh), ImportBatchStatus.pending.wire);
      expect(await batchStatus(committed), ImportBatchStatus.committed.wire);
    });
  });

  group('InitializationQueries', () {
    test('同一词条同一任务类型不会重复入队（部分唯一索引）', () async {
      final wordId = await insertWord();
      final first = await queries.enqueueWord(
        EnqueueRequest(
          wordId: wordId,
          taskType: JobTaskType.initialize,
          mode: InitializationMode.skipInitialized,
          priority: jobPriorityNewWord,
        ),
        now: now,
      );
      final second = await queries.enqueueWord(
        EnqueueRequest(
          wordId: wordId,
          taskType: JobTaskType.initialize,
          mode: InitializationMode.forceOverwrite,
          priority: jobPriorityForceOverwrite,
        ),
        now: now + 1,
      );

      expect(first, isNotNull);
      expect(second, first);
      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM initialization_jobs')
          .getSingle();
      expect(count.read<int>('c'), 1);
      // 已存在活跃任务时升级它而不是新建：模式与优先级都被更新。
      final row = await jobRow(first!);
      expect(row['mode'], InitializationMode.forceOverwrite.wire);
      expect(row['priority'], jobPriorityForceOverwrite);
    });

    test('不同任务类型可以并存', () async {
      final wordId = await insertWord();
      await queries.enqueueWord(
        EnqueueRequest(
          wordId: wordId,
          taskType: JobTaskType.initialize,
          mode: InitializationMode.skipInitialized,
        ),
        now: now,
      );
      await queries.enqueueWord(
        EnqueueRequest(
          wordId: wordId,
          taskType: JobTaskType.mnemonic,
          mode: InitializationMode.fillMissingFields,
        ),
        now: now,
      );
      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM initialization_jobs')
          .getSingle();
      expect(count.read<int>('c'), 2);
    });

    test('已暂停的词条不入队', () async {
      final wordId = await insertWord(isSuspended: true);
      final id = await queries.enqueueWord(
        EnqueueRequest(
          wordId: wordId,
          taskType: JobTaskType.initialize,
          mode: InitializationMode.skipInitialized,
        ),
        now: now,
      );
      expect(id, isNull);
      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM initialization_jobs')
          .getSingle();
      expect(count.read<int>('c'), 0);
    });

    test('批量入队跳过暂停词条', () async {
      final active = await insertWord(term: 'active');
      final paused = await insertWord(term: 'paused', isSuspended: true);
      final ids = await queries.enqueueBulk(<EnqueueRequest>[
        EnqueueRequest(
          wordId: active,
          taskType: JobTaskType.initialize,
          mode: InitializationMode.skipInitialized,
        ),
        EnqueueRequest(
          wordId: paused,
          taskType: JobTaskType.initialize,
          mode: InitializationMode.skipInitialized,
        ),
      ], now: now);
      expect(ids, hasLength(1));
    });

    test('progressSummary 按状态计数', () async {
      final first = await insertWord(term: 'a');
      final second = await insertWord(term: 'b');
      await insertJob(wordId: first, status: InitializationStatus.ready);
      await insertJob(wordId: second, status: InitializationStatus.failed);
      final progress = await queries.progressSummary();
      expect(progress.countOf(InitializationStatus.ready), 1);
      expect(progress.countOf(InitializationStatus.failed), 1);
      expect(progress.total, 2);
    });

    test('listJobs 按词条聚合且支持状态筛选', () async {
      final wordId = await insertWord();
      await insertJob(wordId: wordId, status: InitializationStatus.ready);
      final page = await queries.listJobs();
      expect(page.total, 1);
      expect(page.items.single.term, 'hello');
      expect(page.items.single.status, InitializationStatus.ready);
      expect(page.items.single.tasks, hasLength(1));

      final failedPage = await queries.listJobs(
        status: InitializationStatus.failed,
      );
      expect(failedPage.total, 0);
    });

    test('retryJob 与 cancelJob 改变任务状态', () async {
      final wordId = await insertWord();
      final jobId = await insertJob(
        wordId: wordId,
        status: InitializationStatus.failed,
        attemptCount: 2,
      );
      await queries.retryJob(jobId, now: now);
      var row = await jobRow(jobId);
      expect(row['status'], InitializationStatus.queued.wire);
      expect(row['attempt_count'], 0);

      await queries.cancelJob(jobId, now: now);
      row = await jobRow(jobId);
      expect(row['status'], InitializationStatus.failed.wire);
      expect(row['last_error_code'], cancelledJobErrorCode);
    });
  });
}
