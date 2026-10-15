/// 队列页「后台跑完自动刷新」的接线测试。
///
/// 这里不测界面，只测 provider 之间的连线：后台一批跑完后
/// [queuePageProvider] 与 [queueProgressProvider] 会不会自己重查。
/// 页面上的表现由 `initialize_page_test.dart` 覆盖。
library;

import 'package:drift/drift.dart' show UpdateKind, Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/services/initialization/job_runner.dart';

/// 把排队中的任务就地推进成已完成的假执行器。
class _AdvancingRunner implements InitializationJobRunner {
  new(this._db);

  final AppDatabase _db;

  /// `tick` 报给维护层的处理数量。
  int tickResult = 1;

  /// `tick` 被调用的次数。
  int tickCount = 0;

  @override
  Future<int> tick({required int now}) async {
    tickCount += 1;
    await _db.customUpdate(
      'UPDATE initialization_jobs SET status = ?, updated_at = ? '
      "WHERE status = 'QUEUED'",
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.ready.wire),
        Variable<int>(now),
      ],
      updateKind: UpdateKind.update,
    );
    return tickResult;
  }

  @override
  Future<int> resetStaleRunningJobs(int now, {bool staleOnly = false}) async =>
      0;

  @override
  Future<int> retryFailedJobs(int now) async => 0;

  @override
  Future<int> decayStaleWrongWords(int now) async => 0;

  @override
  Future<int> expireStaleImportBatches(int now) async => 0;
}

void main() {
  late AppDatabase db;
  late _AdvancingRunner runner;
  late ProviderContainer container;
  late int now;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    runner = _AdvancingRunner(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
    final wordId = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: 'hello',
            normalizedTerm: 'hello',
            sourceLanguage: 'en',
            targetLanguage: 'zh-CN',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.pending,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.initializationJobs)
        .insert(
          InitializationJobsCompanion.insert(
            wordId: wordId,
            mode: InitializationMode.skipInitialized,
            status: const Value<InitializationStatus>(
              InitializationStatus.queued,
            ),
            priority: const Value(jobPriorityManualBulk),
            availableAt: Value<int>(now),
            maxAttempts: const Value(3),
            createdAt: now,
            updatedAt: now,
          ),
        );
    container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        initializationJobRunnerProvider.overrideWithValue(runner),
      ],
    );
  });

  tearDown(() async {
    // 容器释放会顺带 dispose 维护对象、取消它挂着的定时器。
    container.dispose();
    await db.close();
  });

  Future<InitializationStatus> aggregateOf(ProviderContainer c) async =>
      (await c.read(queuePageProvider.future)).items.single.status;

  Future<int> readyCount(ProviderContainer c) async =>
      (await c.read(queueProgressProvider.future))
          .countOf(InitializationStatus.ready);

  test('初始时间戳为 0，队列页读到的还是排队中', () async {
    expect(container.read(backgroundTickProvider), 0);

    expect(await aggregateOf(container), InitializationStatus.queued);
    expect(await readyCount(container), 0);
    expect(container.read(backgroundTickProvider), 0);
  });

  test('后台一批跑完后列表与计数自动重查', () async {
    await container.read(queuePageProvider.future);
    await container.read(queueProgressProvider.future);

    final stamp = container.read(backgroundTickProvider);
    await container.read(initializationMaintenanceProvider).start(now: now);

    expect(runner.tickCount, 1);
    expect(container.read(backgroundTickProvider), greaterThan(stamp));
    expect(await aggregateOf(container), InitializationStatus.ready);
    expect(await readyCount(container), 1);
  });

  test('空跑的一批不更新时间戳，也就不触发多余查询', () async {
    runner.tickResult = 0;
    await container.read(queuePageProvider.future);

    final stamp = container.read(backgroundTickProvider);
    final pageBefore = container.read(queuePageProvider);
    await container.read(initializationMaintenanceProvider).start(now: now);

    expect(container.read(backgroundTickProvider), stamp);
    expect(identical(container.read(queuePageProvider), pageBefore), isTrue);
  });

  test('用户手动「立即处理」不冒充后台 tick，不触发自动刷新', () async {
    await container.read(queuePageProvider.future);

    final stamp = container.read(backgroundTickProvider);
    final pageBefore = container.read(queuePageProvider);
    await container.read(initializationMaintenanceProvider).pumpOnce(now: now);

    expect(runner.tickCount, 1);
    expect(container.read(backgroundTickProvider), stamp);
    expect(identical(container.read(queuePageProvider), pageBefore), isTrue);
  });
}
