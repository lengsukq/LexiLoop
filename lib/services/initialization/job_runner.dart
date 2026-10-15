/// 初始化任务执行器的抽象接口。
///
/// **为什么要接口而不是直接依赖具体 worker**：后台维护的职责是
/// 「什么时候跑、跑几批、失败怎么办」，这些策略必须能脱离数据库单测。
/// 直接持有具体类就只能靠真实 worker 测，一旦构造它就得连上 Drift、
/// 设置与词典管线，测试会退化成端到端。
///
/// `InitializationWorker` 是唯一实现；测试用假实现断言调用序列与次数。
library;

/// 初始化任务执行器。
abstract interface class InitializationJobRunner {
  /// 取一批可执行任务并逐个执行，返回实际处理的数量。
  Future<int> tick({required int now});

  /// 把 RUNNING 任务收回队列，返回收回的数量。
  ///
  /// [staleOnly] 为真时只回收锁已过期的任务（会话中途兜底）；
  /// 为假时全量回收（应用启动时的崩溃恢复）。
  Future<int> resetStaleRunningJobs(int now, {bool staleOnly = false});

  /// 把冷却到期的失败任务重新入队，返回恢复的数量。
  Future<int> retryFailedJobs(int now);

  /// 让长期没再答错的词条退出错词本，返回退出的数量。
  ///
  /// 只在「最近一次答错已超过 `wrongWordDecayDays` 天，且此后没有答对过」
  /// 时才退出。用户不再复习的词条会一直挂在错词本上，不衰减就只增不减。
  Future<int> decayStaleWrongWords(int now);

  /// 把卡在 `PENDING` 超过 `importBatchExpiryMs` 的导入批次置为失败，返回数量。
  ///
  /// 批次停在 `PENDING` 说明导入中途崩了；不回收的话撤销入口会永远停用。
  Future<int> expireStaleImportBatches(int now);
}
