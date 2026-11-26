/// 初始化队列界面的状态与数据提供者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/initialization/initialization_maintenance.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';

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

/// 最近一次后台批处理完成的时刻（毫秒）；`0` 表示还没跑过。
///
/// 队列页 `watch` 它就能在后台跑完时自动重查，不必让用户离开页面再回来
/// 才看到进度（对应旧版 `BACKGROUND_TICK_EVENT`）。
final NotifierProvider<BackgroundTickNotifier, int> backgroundTickProvider =
    NotifierProvider<BackgroundTickNotifier, int>(BackgroundTickNotifier.new);

/// 把后台维护的「一批跑完」事件翻译成一次可被 `watch` 的时间戳变化。
///
/// 订阅放在界面侧而不是让调度器认识 Riverpod：`lib/services` 不允许反向
/// 依赖 `lib/features`，因此事件源只暴露一个回调，由这里接上。
class BackgroundTickNotifier extends Notifier<int> {
  @override
  int build() {
    final maintenance = ref.watch(initializationMaintenanceProvider);
    final listener = _onBackgroundTick;
    maintenance.addTickListener(listener);
    // build 重建时同样会触发 onDispose，否则监听者会在调度器上越挂越多。
    ref.onDispose(() => maintenance.removeTickListener(listener));
    return 0;
  }

  /// 空跑的一批不更新时间戳：队列没有任何变化，刷新只会白白多查一次库。
  void _onBackgroundTick(int processed) {
    if (processed <= 0) return;
    state = DateTime.now().millisecondsSinceEpoch;
  }
}

/// 当前页的任务列表。
final FutureProvider<InitializationJobPage> queuePageProvider =
    FutureProvider<InitializationJobPage>((ref) {
      // watch 这份时间戳即等于订阅「后台跑完请重查」，代价只有一个 provider。
      ref.watch(backgroundTickProvider);
      final filter = ref.watch(queueFilterProvider);
      return ref
          .watch(initializationQueriesProvider)
          .listJobs(
            page: filter.page,
            status: filter.status,
            search: filter.search,
          );
    });

/// 多选中的词条 ID。
///
/// 存的是 ID 而不是行号：翻页、后台刷新都会重排列表，
/// 存索引会让底部的「已选 N 个」指向别的词条。
final NotifierProvider<QueueSelectionNotifier, Set<int>>
queueSelectionProvider = NotifierProvider<QueueSelectionNotifier, Set<int>>(
  QueueSelectionNotifier.new,
);

/// 多选状态的控制器。
class QueueSelectionNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => <int>{};

  /// 选中 / 取消选中一个词条。
  void toggle(int wordId) {
    final next = <int>{...state};
    if (!next.remove(wordId)) next.add(wordId);
    state = next;
  }

  /// 把当前页显示出来的词条整体并入 / 移出选择。
  ///
  /// 只影响「当前可见」的词条：用户勾选是为了对眼前这一页做批量操作，
  /// 跨页累积会让翻页后的批量重试作用到看不见的词条上。
  void setVisible(Iterable<int> wordIds, {required bool selected}) {
    final next = <int>{...state};
    for (final wordId in wordIds) {
      if (selected) {
        next.add(wordId);
      } else {
        next.remove(wordId);
      }
    }
    state = next;
  }

  /// 清空选择。
  void clear() => state = <int>{};
}

/// 各状态的任务计数。
final FutureProvider<InitializationProgress> queueProgressProvider =
    FutureProvider<InitializationProgress>((ref) {
      ref.watch(backgroundTickProvider);
      return ref.watch(initializationQueriesProvider).progressSummary();
    });

/// 队列操作：取消、重试、批量入队。
///
/// 写操作后统一失效列表与计数，避免界面显示过期数字。
class QueueActions {
  /// 以容器构造。
  const new(this._ref);

  final Ref _ref;

  /// 立即处理一批任务，返回实际处理的数量。
  ///
  /// 用户不必等 10 分钟的定时器。走 [InitializationMaintenance.pumpOnce]
  /// 而不是直接调 `tick`：它带重入保护，避免与定时器那一批并发写库。
  Future<int> processNow() async {
    final processed = await _ref
        .read(initializationMaintenanceProvider)
        .pumpOnce(now: _now());
    _invalidate();
    return processed;
  }

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
    _ref.read(initializationMaintenanceProvider).kick();
  }

  /// 重试一个词条下的全部可重试任务，返回真正重排的任务数。
  Future<int> retryWord(int wordId) => retryWords(<int>[wordId]);

  /// 重试一批词条下的全部可重试任务，返回真正重排的任务数。
  ///
  /// 走一条 SQL 而不是逐个 `retryJob`：一次导入可能有几百个词条，
  /// 逐条读改写会把批量操作变成几百次往返。
  Future<int> retryWords(List<int> wordIds) async {
    final retried = await _ref
        .read(initializationQueriesProvider)
        .retryWordJobs(wordIds, now: _now());
    _invalidate();
    if (retried > 0) _ref.read(initializationMaintenanceProvider).kick();
    return retried;
  }

  /// 手动刷新列表与计数。
  ///
  /// 后台保活已经会自动重查，这条只是给「我刚在别的页面改了设置、
  /// 想立刻看到」的场合一个确定性的入口，不必等下一轮定时器。
  void refresh() => _invalidate();

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
    if (ids.isNotEmpty) _ref.read(initializationMaintenanceProvider).kick();
    return ids.length;
  }

  /// 按配置器给出的请求入队，返回新建与合并的分项计数。
  ///
  /// 请求由界面组装（字段、来源、策略都在界面草稿里），这一层只负责
  /// 落库与刷新列表；这样配置器不必知道查询层的方法签名，
  /// 而「新建 / 合并」的判定始终只有查询层一份实现。
  Future<EnqueueBulkReport> enqueueRequests(
    List<EnqueueRequest> requests,
  ) async {
    if (requests.isEmpty) {
      return const EnqueueBulkReport(
        created: <int>[],
        merged: <int>[],
        skipped: 0,
      );
    }
    final report = await _ref
        .read(initializationQueriesProvider)
        .enqueueBulkReport(requests, now: _now());
    _invalidate();
    if (report.created.isNotEmpty || report.merged.isNotEmpty) {
      _ref.read(initializationMaintenanceProvider).kick();
    }
    return report;
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
