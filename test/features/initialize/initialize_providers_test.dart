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
  late int jobWordId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    runner = _AdvancingRunner(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
    jobWordId = await db
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
            wordId: jobWordId,
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

  test('翻页会带着页码重查，翻过头就查不到数据', () async {
    expect(
      (await container.read(queuePageProvider.future)).items,
      hasLength(1),
    );

    container
        .read(queueFilterProvider.notifier)
        .replace(const QueueFilter(page: 2));

    final page = await container.read(queuePageProvider.future);
    // 页码进了 SQL（结果为空），且 total 不随页码变化。
    expect(page.items, isEmpty);
    expect(page.total, 1);
  });

  test('页码可以停在用户翻到的页上', () {
    final moved = filterAfter(
      container,
      (current) => const QueueFilter(page: 3, search: 'a'),
    );

    expect(moved.page, 3);
  });

  test('改关键词会把页码复位到 1', () {
    filterAfter(
      container,
      (current) => const QueueFilter(page: 3, search: 'a'),
    );
    final searched = filterAfter(
      container,
      (current) => current.copyWith(search: 'ab'),
    );

    expect(searched.page, 1);
    expect(searched.search, 'ab');
  });

  test('改状态筛选会把页码复位到 1', () {
    filterAfter(container, (current) => const QueueFilter(page: 4));
    final filtered = filterAfter(
      container,
      (current) => current.copyWith(status: InitializationStatus.failed),
    );

    expect(filtered.page, 1);
    expect(filtered.status, InitializationStatus.failed);
  });

  test('多选只跟着点名过的词条走', () {
    expect(selectionAfter(container, (notifier) => notifier.toggle(1)), <int>{
      1,
    });
    // 再点一次就是取消，而不是「又加了一个」。
    expect(
      selectionAfter(container, (notifier) => notifier.toggle(1)),
      isEmpty,
    );

    expect(selectionAfter(container, (notifier) => notifier.toggle(1)), <int>{
      1,
    });
    expect(selectionAfter(container, (notifier) => notifier.toggle(3)), <int>{
      1,
      3,
    });
    // 全选当前页只增不减，别的页勾过的词条不会被这里带走。
    expect(
      selectionAfter(
        container,
        (notifier) => notifier.setVisible(<int>[1, 3], selected: true),
      ),
      <int>{1, 3},
    );
    expect(
      selectionAfter(
        container,
        (notifier) => notifier.setVisible(<int>[3], selected: false),
      ),
      <int>{1},
    );
    expect(selectionAfter(container, (notifier) => notifier.clear()), isEmpty);
  });

  test('词条级重试把选中的任务重排并让界面重查', () async {
    await container.read(queuePageProvider.future);
    await db.customUpdate(
      'UPDATE initialization_jobs SET status = ? WHERE word_id = ?',
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.failed.wire),
        Variable<int>(jobWordId),
      ],
      updateKind: UpdateKind.update,
    );

    final retried = await container.read(queueActionsProvider).retryWords(<int>[
      jobWordId,
    ]);

    expect(retried, 1);
    final page = await container.read(queuePageProvider.future);
    expect(page.items.single.status, InitializationStatus.queued);
  });
}

/// 施加一次筛选变更并返回变更后的筛选条件。
///
/// 「变更 + 取值」收进同一个调用，断言之间不会出现可级联的重复接收者。
QueueFilter filterAfter(
  ProviderContainer container,
  QueueFilter Function(QueueFilter current) change,
) {
  final next = change(container.read(queueFilterProvider));
  container.read(queueFilterProvider.notifier).replace(next);
  return container.read(queueFilterProvider);
}

/// 施加一次多选操作并返回变更后的选中集合。
Set<int> selectionAfter(
  ProviderContainer container,
  void Function(QueueSelectionNotifier notifier) action,
) {
  action(container.read(queueSelectionProvider.notifier));
  return container.read(queueSelectionProvider);
}
