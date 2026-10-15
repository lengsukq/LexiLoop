/// 初始化任务队列的领域模型。
///
/// 对应旧版 `modules/initialization/types.ts` 与 `queries.ts` 里的内联类型。
/// 旧版把查询结果直接当 `Record<string, unknown>` 用，字段名拼错只能靠运行期
/// 才发现；这里全部具名。
library;

import 'package:lexiloop/domain/enums.dart';

/// 一次入队请求。
class EnqueueRequest {
  /// 以各字段构造。
  const new({
    required this.wordId,
    required this.taskType,
    required this.mode,
    this.requestedFields = const <String>[],
    this.requestedProviders = const <String>[],
    this.strategy = ProviderStrategy.priorityFallback,
    this.priority = 0,
  });

  /// 词条 ID。
  final int wordId;

  /// 任务类型。
  final JobTaskType taskType;

  /// 初始化模式。
  final InitializationMode mode;

  /// 请求字段（逻辑字段名）。
  final List<String> requestedFields;

  /// 请求数据源（ID）。
  final List<String> requestedProviders;

  /// 数据源调用策略。
  final ProviderStrategy strategy;

  /// 优先级（越大越先执行）。
  final int priority;
}

/// 已被认领（或正在执行）的任务。
class ClaimedJob {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.wordId,
    required this.taskType,
    required this.mode,
    required this.status,
    required this.attemptCount,
    required this.maxAttempts,
    required this.requestedFields,
    required this.requestedProviders,
    required this.providerStrategy,
  });

  /// 任务 ID。
  final int id;

  /// 词条 ID。
  final int wordId;

  /// 任务类型。
  final JobTaskType taskType;

  /// 初始化模式。
  final InitializationMode mode;

  /// 当前状态。
  final InitializationStatus status;

  /// 已尝试次数（含本次）。
  final int attemptCount;

  /// 最大尝试次数。
  final int maxAttempts;

  /// 请求字段。
  final List<String> requestedFields;

  /// 请求数据源。
  final List<String> requestedProviders;

  /// 数据源调用策略。
  final ProviderStrategy providerStrategy;
}

/// 单条任务的摘要。
class InitializationTaskSummary {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.taskType,
    required this.status,
    required this.mode,
    required this.attemptCount,
    required this.maxAttempts,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
    this.lastErrorCode,
    this.completedAt,
  });

  /// 任务 ID。
  final int id;

  /// 任务类型。
  final JobTaskType taskType;

  /// 当前状态。
  final InitializationStatus status;

  /// 初始化模式。
  final InitializationMode mode;

  /// 已尝试次数。
  final int attemptCount;

  /// 最大尝试次数。
  final int maxAttempts;

  /// 创建时间。
  final int createdAt;

  /// 更新时间。
  final int updatedAt;

  /// 最近一次错误说明。
  final String? lastError;

  /// 最近一次错误码。
  final String? lastErrorCode;

  /// 完成时间。
  final int? completedAt;
}

/// 按词条聚合的任务列表项。
class InitializationWordSummary {
  /// 以各字段构造。
  const new({
    required this.wordId,
    required this.term,
    required this.status,
    required this.taskCount,
    required this.completedTaskCount,
    required this.failedTaskCount,
    required this.activeTaskCount,
    required this.updatedAt,
    required this.tasks,
    this.errorSummary,
  });

  /// 词条 ID。
  final int wordId;

  /// 词条文本。
  final String term;

  /// 聚合状态。
  final InitializationStatus status;

  /// 任务总数。
  final int taskCount;

  /// 已完成任务数。
  final int completedTaskCount;

  /// 失败任务数。
  final int failedTaskCount;

  /// 活跃（排队 / 运行中）任务数。
  final int activeTaskCount;

  /// 最近更新时间。
  final int updatedAt;

  /// 该词条的全部任务。
  final List<InitializationTaskSummary> tasks;

  /// 失败原因摘要。
  final String? errorSummary;
}

/// 分页结果。
class InitializationJobPage {
  /// 以各字段构造。
  const new({required this.items, required this.total});

  /// 当前页的词条。
  final List<InitializationWordSummary> items;

  /// 符合条件的词条总数。
  final int total;
}

/// 各状态的任务计数。
class InitializationProgress {
  /// 以各状态计数构造。
  const new(this.counts);

  /// 状态 → 计数。
  final Map<InitializationStatus, int> counts;

  /// 取某状态的计数（缺失为 0）。
  int countOf(InitializationStatus status) => counts[status] ?? 0;

  /// 任务总数。
  int get total => counts.values.fold(0, (sum, value) => sum + value);
}
