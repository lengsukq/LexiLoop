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
import 'package:lexiloop/features/initialize/widgets/queue_list.dart';
import 'package:lexiloop/features/initialize/widgets/queue_toolbar.dart';
import 'package:lexiloop/services/initialization/initialization_queries.dart';
import 'package:lexiloop/services/initialization/job_runner.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  Future<int> insertWordWithJob({
    String term = 'hello',
    InitializationStatus status = InitializationStatus.queued,
    int attemptCount = 0,
    String? lastError,
  }) async {
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
            status: Value<InitializationStatus>(status),
            priority: const Value(jobPriorityManualBulk),
            availableAt: Value<int>(now),
            maxAttempts: const Value(3),
            attemptCount: Value<int>(attemptCount),
            lastError: Value<String?>(lastError),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return wordId;
  }

  /// 批量插入词条，用于把队列撑到第二页。
  ///
  /// `updatedAt` 全部相同，因此排序退化成 `word_id DESC`，
  /// 第 N 页的内容是可以算出来的，断言不依赖时间抖动。
  Future<void> insertWords(int count) async {
    for (var i = 0; i < count; i += 1) {
      await insertWordWithJob(term: 'w${i.toString().padLeft(2, '0')}');
    }
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

    expect(find.text('内容补全队列'), findsOneWidget);
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

    // 取消是任务明细里的动作，必须先展开。
    await tester.tap(find.text('展开 1 个任务'));
    await tester.pumpAndSettle();
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

  testWidgets('「刷新列表」重新查询队列（在「⋯」菜单里）', (tester) async {
    await pumpPage(tester);
    expect(find.text('没有符合条件的任务'), findsOneWidget);

    await insertWordWithJob(term: 'late');
    expect(find.text('late'), findsNothing);

    // 刷新只读不写，收在「⋯」里：工具栏的主位置留给「立即处理一批」。
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新列表'));
    await tester.pumpAndSettle();

    expect(find.text('late'), findsOneWidget);
    expect(find.text('没有符合条件的任务'), findsNothing);
  });

  group('分页', () {
    testWidgets('翻页会带着页码重查列表', (tester) async {
      await insertWords(wordsBeyondFirstPage);
      await pumpPage(tester);

      expect(
        find.text('第 1 / 2 页 · 共 $wordsBeyondFirstPage 个词条'),
        findsOneWidget,
      );
      // 第一页按 id 倒序，最新的 'w50' 在最上面。
      expect(find.text('w50'), findsOneWidget);

      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();

      // 第二页只剩最早的 'w00'：看到它就说明页码真的进了 SQL。
      expect(
        find.text('第 2 / 2 页 · 共 $wordsBeyondFirstPage 个词条'),
        findsOneWidget,
      );
      expect(find.text('w00'), findsOneWidget);
      expect(find.text('w50'), findsNothing);

      await tester.tap(find.text('上一页'));
      await tester.pumpAndSettle();

      expect(
        find.text('第 1 / 2 页 · 共 $wordsBeyondFirstPage 个词条'),
        findsOneWidget,
      );
      expect(find.text('w50'), findsOneWidget);
    });

    testWidgets('改关键词会回到第 1 页', (tester) async {
      await insertWords(wordsBeyondFirstPage);
      await pumpPage(tester);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'w00');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 只命中一个词条：既钉住了页码复位，也钉住了查询确实重跑了。
      // 限定在列表内找——搜索框里的输入同样会被 `find.text` 命中。
      expect(find.text('第 1 / 1 页 · 共 1 个词条'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(QueueList), matching: find.text('w00')),
        findsOneWidget,
      );
    });

    testWidgets('改状态筛选会回到第 1 页', (tester) async {
      await insertWords(wordsBeyondFirstPage);
      await pumpPage(tester);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(QueueToolbar),
          matching: find.text('已完成'),
        ),
      );
      await tester.pumpAndSettle();

      // 51 个词条全是排队中，「已完成」筛不出东西。筛空之后**不再显示
      // 分页条**（它会在空态上方画一行「第 1 / 1 页 · 共 0 个词条」，
      // 读起来像分页坏了），所以这里断言的是分页条消失。
      expect(find.textContaining('页 · 共'), findsNothing);
      expect(find.text('没有符合条件的任务'), findsOneWidget);
    });
  });

  group('多选', () {
    testWidgets('「选择本页」全选当前页并显示选中数量', (tester) async {
      await insertWordWithJob(term: 'alpha');
      await insertWordWithJob(term: 'beta');
      await pumpPage(tester);

      expect(find.text('已选 2 个词条'), findsNothing);

      await tester.tap(find.text('选择本页'));
      await tester.pumpAndSettle();

      expect(find.text('已选 2 个词条'), findsOneWidget);

      await tester.tap(find.text('取消选择'));
      await tester.pumpAndSettle();

      expect(find.text('已选 2 个词条'), findsNothing);
    });

    testWidgets('批量重试把选中词条的全部任务重新排队', (tester) async {
      await insertWordWithJob(
        term: 'alpha',
        status: InitializationStatus.failed,
        lastError: '数据源不可用',
      );
      await insertWordWithJob(
        term: 'beta',
        status: InitializationStatus.failed,
      );
      await pumpPage(tester);

      await tester.tap(find.text('选择本页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试这些词条的全部任务'));
      await tester.pumpAndSettle();

      // 批量重试会再次打词典与 AI，必须先过确认；没点之前任务不能动。
      expect(find.text('重试这些词条的全部任务？'), findsOneWidget);
      var jobs = await db.select(db.initializationJobs).get();
      expect(
        jobs.map((job) => job.status),
        isNot(everyElement(InitializationStatus.queued)),
      );

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      jobs = await db.select(db.initializationJobs).get();
      expect(
        jobs.map((job) => job.status),
        everyElement(InitializationStatus.queued),
      );
      expect(find.text('已重试 2 个任务'), findsOneWidget);
    });

    testWidgets('行内「重试」只重排这个词条的任务', (tester) async {
      await insertWordWithJob(
        term: 'alpha',
        status: InitializationStatus.failed,
      );
      await insertWordWithJob(
        term: 'beta',
        status: InitializationStatus.failed,
      );
      await pumpPage(tester);

      // 卡片外层还有一层 Surface 容器；取最近的一层，否则会把相邻词条的
      // 按钮也算进来。
      final alphaTile = find
          .ancestor(of: find.text('alpha'), matching: find.byType(Surface))
          .first;
      // 行内既有「词条级重试」（带旋转图标），也有展开后任务级的「重试」
      // （纯文字按钮）；这里点的是词条级那个。
      await tester.tap(
        find.descendant(
          of: alphaTile,
          matching: find.widgetWithIcon(TextButton, LucideIcons.rotateCcw),
        ),
      );
      await tester.pumpAndSettle();

      final byTerm = await _statusByTerm(db);
      expect(byTerm['alpha'], <InitializationStatus>[
        InitializationStatus.queued,
      ]);
      expect(byTerm['beta'], <InitializationStatus>[
        InitializationStatus.failed,
      ]);
      expect(find.text('已重试 1 个任务'), findsOneWidget);
    });

    testWidgets('取消选择后浮条消失', (tester) async {
      await insertWordWithJob(term: 'alpha');
      await pumpPage(tester);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 个词条'), findsOneWidget);

      await tester.tap(find.text('取消选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 个词条'), findsNothing);
    });
  });

  testWidgets('展开任务区能看到编号、尝试次数、更新时间和失败原因', (tester) async {
    await insertWordWithJob(
      term: 'alpha',
      status: InitializationStatus.failed,
      attemptCount: 2,
      lastError: '数据源不可用',
    );
    await pumpPage(tester);
    final job = (await db.select(db.initializationJobs).get()).single;

    expect(find.textContaining('任务 #'), findsNothing);

    await tester.tap(find.text('展开 1 个任务'));
    await tester.pumpAndSettle();

    expect(find.text('内容补全 · 任务 #${job.id}'), findsOneWidget);
    expect(find.textContaining('重试 2/3'), findsOneWidget);
    expect(
      find.textContaining('更新时间 ${formatTaskStamp(job.updatedAt)}'),
      findsOneWidget,
    );
    // 失败原因出现两次：折叠时的词条摘要一次，展开后的任务明细一次。
    expect(find.text('数据源不可用'), findsNWidgets(2));

    await tester.tap(find.text('收起任务'));
    await tester.pumpAndSettle();
    expect(find.textContaining('任务 #'), findsNothing);
  });

  group('词条完成度', () {
    testWidgets('空队列显示 0%', (tester) async {
      await pumpPage(tester);

      expect(find.text('已完成 0 / 0 个词条'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('部分完成显示 50%', (tester) async {
      await insertWordWithJob(
        term: 'alpha',
        status: InitializationStatus.ready,
      );
      await insertWordWithJob(
        term: 'beta',
        status: InitializationStatus.failed,
      );
      await pumpPage(tester);

      expect(find.text('已完成 1 / 2 个词条'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('全部完成显示 100%', (tester) async {
      await insertWordWithJob(
        term: 'alpha',
        status: InitializationStatus.ready,
      );
      await insertWordWithJob(
        term: 'beta',
        status: InitializationStatus.partial,
      );
      await pumpPage(tester);

      // PARTIAL 也是终态：数据源本身没那个字段，重试多少次都不会变 READY。
      expect(find.text('已完成 2 / 2 个词条'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });
  });
}

/// 撑到第二页所需的词条数（页大小是 50）。
const int wordsBeyondFirstPage = 51;

/// 按词条文本归拢任务状态，供断言点名某一个词条。
Future<Map<String, List<InitializationStatus>>> _statusByTerm(
  AppDatabase db,
) async {
  final rows = await db
      .customSelect(
        'SELECT w.term AS term, j.status AS status FROM initialization_jobs j '
        'INNER JOIN words w ON w.id = j.word_id',
      )
      .get();
  final result = <String, List<InitializationStatus>>{};
  for (final row in rows) {
    final status = wireLookup(
      InitializationStatus.values,
      row.read<String>('status'),
    );
    result
        .putIfAbsent(row.read<String>('term'), () => <InitializationStatus>[])
        .add(status ?? InitializationStatus.pending);
  }
  return result;
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
