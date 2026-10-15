/// 初始化队列查询层的测试。
///
/// 覆盖列表页依赖的三个聚合语义：
/// - 分页：页码必须真的传进 `listJobs`，否则用户永远停在第一页；
/// - 词条完成度：「完成」的定义被 `wordCompletion` 独占，
///   百分比算错会让整个进度条变成假数据；
/// - 词条级重试：必须精确落在「可重试」的状态集合上，
///   碰了运行中的任务会被 worker 覆盖回去。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/initialization/initialization_queries.dart';
import 'package:lexiloop/services/settings_service.dart';

void main() {
  late AppDatabase db;
  late InitializationQueries queries;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    queries = InitializationQueries(db, SettingsService(SettingsDao(db)));
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertWord(String term) => db
      .into(db.words)
      .insert(
        WordsCompanion.insert(
          term: term,
          normalizedTerm: term,
          sourceLanguage: 'en',
          targetLanguage: 'zh-CN',
          entryType: EntryType.word,
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<int> insertJob(
    int wordId, {
    InitializationStatus status = InitializationStatus.queued,
    int attemptCount = 0,
    int maxAttempts = 3,
    JobTaskType taskType = JobTaskType.initialize,
    String? lastError,
  }) => db
      .into(db.initializationJobs)
      .insert(
        InitializationJobsCompanion.insert(
          wordId: wordId,
          taskType: Value<JobTaskType>(taskType),
          mode: InitializationMode.skipInitialized,
          status: Value<InitializationStatus>(status),
          attemptCount: Value<int>(attemptCount),
          maxAttempts: Value<int>(maxAttempts),
          availableAt: Value<int>(now),
          lastError: Value<String?>(lastError),
          createdAt: now,
          updatedAt: now,
        ),
      );

  group('listJobs 分页', () {
    test('页码改变会换一批词条，total 保持不变', () async {
      for (final term in <String>['a', 'b', 'c']) {
        await insertJob(
          await insertWord(term),
          status: InitializationStatus.ready,
        );
      }

      final first = await queries.listJobs(pageSize: 2);
      final second = await queries.listJobs(page: 2, pageSize: 2);
      final third = await queries.listJobs(page: 3, pageSize: 2);

      expect(first.total, 3);
      expect(first.items, hasLength(2));
      expect(second.total, 3);
      expect(second.items, hasLength(1));
      expect(third.items, isEmpty);
      // 两页合起来正好是全部词条，且互不重叠。
      final firstIds = first.items.map((item) => item.wordId).toSet();
      final secondIds = second.items.map((item) => item.wordId).toSet();
      expect(firstIds.intersection(secondIds), isEmpty);
      expect(<int>{...firstIds, ...secondIds}, hasLength(3));
    });
  });

  group('wordCompletion：词条级完成度', () {
    test('空队列是 0% 而不是除零', () async {
      final completion = await queries.wordCompletion();

      expect(completion.totalWords, 0);
      expect(completion.completedWords, 0);
      expect(completion.percent, 0);
    });

    test('全部任务进终态的词条才算完成', () async {
      final done = await insertWord('done');
      await insertJob(done, status: InitializationStatus.ready);
      final partial = await insertWord('partial');
      await insertJob(partial, status: InitializationStatus.partial);
      final disabled = await insertWord('disabled');
      await insertJob(disabled, status: InitializationStatus.disabled);

      final completion = await queries.wordCompletion();

      expect(completion.totalWords, 3);
      expect(completion.completedWords, 3);
      expect(completion.percent, 100);
    });

    test('一个词条只要还有一个任务没进终态就算没完成', () async {
      final mixed = await insertWord('mixed');
      await insertJob(mixed, status: InitializationStatus.ready);
      await insertJob(mixed, status: InitializationStatus.failed);
      final ok = await insertWord('ok');
      await insertJob(ok, status: InitializationStatus.ready);

      final completion = await queries.wordCompletion();

      expect(completion.totalWords, 2);
      expect(completion.completedWords, 1);
      expect(completion.percent, 50);
    });

    test('没有任何任务的词条不计入分母', () async {
      await insertWord('untouched');

      final completion = await queries.wordCompletion();

      expect(completion.totalWords, 0);
      expect(completion.percent, 0);
    });
  });

  group('retryWordJobs：词条级重试', () {
    test('失败、停用、排队中的任务被重排，运行中与已完成不动', () async {
      final wordId = await insertWord('hello');
      // 三种任务类型各一个，避免「同一词条同一类型只允许一个活跃任务」
      // 的唯一索引把这条用例本身变成冲突现场。
      final failed = await insertJob(
        wordId,
        status: InitializationStatus.failed,
        attemptCount: 3,
      );
      final disabled = await insertJob(
        wordId,
        status: InitializationStatus.disabled,
        taskType: JobTaskType.mnemonic,
      );
      final queued = await insertJob(
        wordId,
        taskType: JobTaskType.exampleTranslations,
      );
      // 运行中与已完成的两个任务放在别的词条上：同一词条同一任务类型
      // 只允许一个活跃任务，放在一起就没法同时构造「可重试」与「占用名额」。
      final running = await insertJob(
        await insertWord('busy'),
        status: InitializationStatus.running,
      );
      final ready = await insertJob(
        await insertWord('done'),
        status: InitializationStatus.ready,
      );

      final retried = await queries.retryWordJobs(<int>[wordId], now: now);

      expect(retried, 3);
      expect(
        (await queries.jobDetail(failed))!.status,
        InitializationStatus.queued,
      );
      expect(
        (await queries.jobDetail(disabled))!.status,
        InitializationStatus.queued,
      );
      expect(
        (await queries.jobDetail(queued))!.status,
        InitializationStatus.queued,
      );
      expect(
        (await queries.jobDetail(running))!.status,
        InitializationStatus.running,
      );
      expect(
        (await queries.jobDetail(ready))!.status,
        InitializationStatus.ready,
      );
      // 退避计数归零，否则刚重排的任务还要再等一轮退避才会被 worker 取走。
      expect((await queries.jobDetail(failed))!.attemptCount, 0);
    });

    test('同一词条同一任务类型已有活跃任务时不再重复排队', () async {
      final wordId = await insertWord('hello');
      final failed = await insertJob(
        wordId,
        status: InitializationStatus.failed,
        attemptCount: 3,
      );
      await insertJob(wordId);

      final retried = await queries.retryWordJobs(<int>[wordId], now: now);

      // 在跑的那个任务做的本来就是同一件事，重排只会撞那条唯一索引。
      expect(retried, 1);
      expect(
        (await queries.jobDetail(failed))!.status,
        InitializationStatus.failed,
      );
    });

    test('只影响点名的词条', () async {
      final picked = await insertWord('picked');
      final other = await insertWord('other');
      final pickedJob = await insertJob(
        picked,
        status: InitializationStatus.failed,
      );
      final otherJob = await insertJob(
        other,
        status: InitializationStatus.failed,
      );

      await queries.retryWordJobs(<int>[picked], now: now);

      expect(
        (await queries.jobDetail(pickedJob))!.status,
        InitializationStatus.queued,
      );
      expect(
        (await queries.jobDetail(otherJob))!.status,
        InitializationStatus.failed,
      );
    });

    test('空入参不写库', () async {
      final wordId = await insertWord('hello');
      final jobId = await insertJob(
        wordId,
        status: InitializationStatus.failed,
      );

      expect(await queries.retryWordJobs(<int>[], now: now), 0);
      expect(await queries.retryWordJobs(<int>[-1], now: now), 0);
      expect(
        (await queries.jobDetail(jobId))!.status,
        InitializationStatus.failed,
      );
    });

    test('保留失败原因，重试之后仍然看得见', () async {
      final wordId = await insertWord('hello');
      final jobId = await insertJob(
        wordId,
        status: InitializationStatus.failed,
        lastError: '数据源不可用',
      );

      await queries.retryWordJobs(<int>[wordId], now: now);

      expect((await queries.jobDetail(jobId))!.lastError, '数据源不可用');
    });
  });
}
