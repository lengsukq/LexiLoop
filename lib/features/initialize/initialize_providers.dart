/// 初始化队列界面的状态与数据提供者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/services/initialization/initialization_queries.dart';

/// 初始化队列查询。
final Provider<InitializationQueries> initializationQueriesProvider =
    Provider<InitializationQueries>(
      (ref) => InitializationQueries(
        ref.watch(databaseProvider),
        ref.watch(settingsServiceProvider),
      ),
    );

/// 队列列表的筛选条件。
class QueueFilter {
  /// 以筛选条件构造。
  const new({this.status, this.search = '', this.page = 1});

  /// 按状态筛选；`null` 表示全部。
  final InitializationStatus? status;

  /// 关键词（匹配词条文本）。
  final String search;

  /// 当前页（1 起）。
  final int page;

  /// 复制并覆盖部分字段；改筛选条件时回到第 1 页。
  QueueFilter copyWith({
    InitializationStatus? status,
    bool clearStatus = false,
    String? search,
    int? page,
  }) => QueueFilter(
    status: clearStatus ? null : (status ?? this.status),
    search: search ?? this.search,
    page:
        page ??
        (search != null || status != null || clearStatus ? 1 : this.page),
  );
}

/// 筛选条件控制器。
class QueueFilterNotifier extends Notifier<QueueFilter> {
  @override
  QueueFilter build() => const QueueFilter();

  /// 覆盖筛选条件。
  ///
  /// 顺带保证页码合法：改关键词或状态时回到第 1 页，
  /// 否则用户会在一个已经变短的结果集里停在空白页上。
  void replace(QueueFilter next) {
    state = next.page < 1 ? next.copyWith(page: 1) : next;
  }
}

/// 筛选条件提供者。
final NotifierProvider<QueueFilterNotifier, QueueFilter> queueFilterProvider =
    NotifierProvider<QueueFilterNotifier, QueueFilter>(QueueFilterNotifier.new);

/// 当前页的任务列表。
final FutureProvider<InitializationJobPage> queuePageProvider =
    FutureProvider<InitializationJobPage>((ref) {
      final filter = ref.watch(queueFilterProvider);
      return ref
          .watch(initializationQueriesProvider)
          .listJobs(
            page: filter.page,
            status: filter.status,
            search: filter.search,
          );
    });

/// 各状态的任务计数。
final FutureProvider<InitializationProgress> queueProgressProvider =
    FutureProvider<InitializationProgress>(
      (ref) => ref.watch(initializationQueriesProvider).progressSummary(),
    );

/// 队列操作：取消、重试、批量入队。
///
/// 写操作后统一失效列表与计数，避免界面显示过期数字。
class QueueActions {
  /// 以容器构造。
  const new(this._ref);

  final Ref _ref;

  /// 取消一个任务。
  Future<void> cancel(int jobId) async {
    await _ref
        .read(initializationQueriesProvider)
        .cancelJob(jobId, now: _now());
    _invalidate();
  }

  /// 重试一个失败任务。
  Future<void> retry(int jobId) async {
    await _ref.read(initializationQueriesProvider).retryJob(jobId, now: _now());
    _invalidate();
  }

  /// 把一批词条加入队列，返回真正入队的任务数。
  Future<int> enqueueBulk({
    required List<int> wordIds,
    required InitializationMode mode,
  }) async {
    if (wordIds.isEmpty) return 0;
    final ids = await _ref.read(initializationQueriesProvider).enqueueBulk(
      <EnqueueRequest>[
        for (final wordId in wordIds)
          EnqueueRequest(
            wordId: wordId,
            taskType: JobTaskType.initialize,
            mode: mode,
            priority: jobPriorityManualBulk,
          ),
      ],
      now: _now(),
    );
    _invalidate();
    return ids.length;
  }

  void _invalidate() {
    _ref
      ..invalidate(queuePageProvider)
      ..invalidate(queueProgressProvider);
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;
}

/// 队列操作提供者。
final Provider<QueueActions> queueActionsProvider = Provider<QueueActions>(
  QueueActions.new,
);

/// 状态筛选项（按处理流程排序）。
const List<InitializationStatus?> queueStatusFilters = <InitializationStatus?>[
  null,
  InitializationStatus.queued,
  InitializationStatus.running,
  InitializationStatus.failed,
  InitializationStatus.ready,
  InitializationStatus.partial,
];

/// 状态的中文名。
String queueStatusLabel(InitializationStatus status) => switch (status) {
  InitializationStatus.pending => '待处理',
  InitializationStatus.queued => '排队中',
  InitializationStatus.running => '进行中',
  InitializationStatus.ready => '已完成',
  InitializationStatus.partial => '部分完成',
  InitializationStatus.failed => '失败',
  InitializationStatus.disabled => '已停用',
};
