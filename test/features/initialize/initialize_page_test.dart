/// 初始化队列页的 widget 测试。
///
/// 覆盖「空态文案」「筛选芯片」「取消/重试」与「立即处理一批」按钮：
/// 后者是后台维护接线的界面入口，必须验证它真的调用了执行器。
library;

import 'package:drift/drift.dart' show UpdateKind, Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/initialize/initialize_page.dart';
import 'package:lexiloop/features/initialize/widgets/queue_toolbar.dart';
import 'package:lexiloop/services/initialization/initialization_queries.dart';
import 'package:lexiloop/services/initialization/job_runner.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 记录调用次数的假执行器。
class _RecordingRunner implements InitializationJobRunner {
  /// `tick` 被调用的次数。
  int tickCount = 0;

  /// `tick` 的返回值。
  int tickResult = 2;

  /// 让 `tick` 顺手把任务推进成已完成，用来模拟后台真的处理了一批。
  ///
  /// 默认不接线：多数用例只关心「有没有被调用过」。
  AppDatabase? db;

  @override
  Future<int> tick({required int now}) async {
    tickCount += 1;
    final database = db;
    if (database != null) {
      await database.customUpdate(
        'UPDATE initialization_jobs SET status = ?, updated_at = ? '
        "WHERE status = 'QUEUED'",
        variables: <Variable<Object>>[
          Variable<String>(InitializationStatus.ready.wire),
          Variable<int>(now),
        ],
        updateKind: UpdateKind.update,
      );
    }
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
  late _RecordingRunner runner;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    runner = _RecordingRunner();
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 插入一个带初始化任务的词条。
  Future<int> insertWordWithJob({String term = 'hello'}) async {
    final wordId = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
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
    return wordId;
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          initializationJobRunnerProvider.overrideWithValue(runner),
        ],
        child: MaterialApp(
          theme: LexiTheme.light,
          home: const Scaffold(body: InitializePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('空队列显示引导文案', (tester) async {
    await pumpPage(tester);

    expect(find.text('初始化队列'), findsOneWidget);
    expect(find.textContaining('导入词条后任务会出现在这里'), findsOneWidget);
    expect(find.text('没有符合条件的任务'), findsOneWidget);
  });

  testWidgets('有任务时列出词条并显示排队数', (tester) async {
    await insertWordWithJob();
    await pumpPage(tester);

    expect(find.text('hello'), findsOneWidget);
    // 摘要是「N 个任务 · N 进行中」的合并文本。
    expect(find.text('1 个任务 · 1 进行中'), findsOneWidget);
    // 「排队中」出现三处：进度卡的计数标签、工具栏的筛选芯片、词条行的徽标。
    expect(find.text('排队中'), findsNWidgets(3));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('「立即处理一批」调用执行器并提示处理数量', (tester) async {
    await insertWordWithJob();
    await pumpPage(tester);

    await tester.tap(find.text('立即处理一批'));
    await tester.pumpAndSettle();

    expect(runner.tickCount, 1);
    expect(find.text('已处理 2 个任务'), findsOneWidget);
  });

  testWidgets('没有可处理任务时给出空提示', (tester) async {
    runner.tickResult = 0;
    await pumpPage(tester);

    await tester.tap(find.text('立即处理一批'));
    await tester.pumpAndSettle();

    expect(runner.tickCount, 1);
    expect(find.text('没有可处理的任务'), findsOneWidget);
  });

  testWidgets('点击「取消」把排队中的任务撤回', (tester) async {
    await insertWordWithJob();
    await pumpPage(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final jobs = await db.select(db.initializationJobs).get();
    expect(jobs.single.status, InitializationStatus.failed);
    expect(jobs.single.lastErrorCode, cancelledJobErrorCode);
  });

  testWidgets('状态筛选芯片可切换', (tester) async {
    await insertWordWithJob();
    await pumpPage(tester);

    // 「已完成」既出现在筛选芯片也出现在进度卡的计数标签里，
    // 因此限定在工具栏内点，避免命中歧义。
    await tester.tap(
      find.descendant(
        of: find.byType(QueueToolbar),
        matching: find.text('已完成'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有符合条件的任务'), findsOneWidget);
  });

  testWidgets('后台一批跑完后页面自动刷新，不需要用户重新进入', (tester) async {
    await insertWordWithJob();
    runner.db = db;
    await pumpPage(tester);
    // 「排队中」出现三处：进度卡计数、工具栏筛选芯片、队列行徽标。
    expect(find.text('排队中'), findsNWidgets(3));

    await startBackgroundMaintenance(tester);
    await tester.pumpAndSettle();

    // 队列行徽标翻成「已完成」，全程没有离开过这一页。
    // 进度卡与筛选芯片仍然渲染这两个状态名，所以各少一次、多一次。
    expect(find.text('排队中'), findsNWidgets(2));
    expect(find.text('已完成'), findsNWidgets(3));
  });
}

/// 用 provider 里那个真实的维护对象跑一批，模拟后台定时器到点。
Future<void> startBackgroundMaintenance(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(InitializePage)),
  );
  // 挂上的定时器由 provider 的 onDispose 负责取消，
  // flutter_test 在核对「没有遗留定时器」之前会先卸载整棵树。
  await container
      .read(initializationMaintenanceProvider)
      .start(now: DateTime.now().millisecondsSinceEpoch);
}
