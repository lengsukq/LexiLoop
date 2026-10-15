/// 初始化任务队列的领域模型。
///
/// 对应旧版 `modules/initialization/types.ts` 与 `queries.ts` 里的内联类型。
/// 旧版把查询结果直接当 `Record<string, unknown>` 用，字段名拼错只能靠运行期
/// 才发现；这里全部具名。
library;

import 'package:lexiloop/data/dictionary/dictionary_constants.dart';
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

/// 词条级完成度。
///
/// 队列页真正回答的问题是「我导入的词条补全到几成了」，
/// 而不是「有多少个任务跑完了」——一个词条挂 3 个任务，
/// 任务口径会把它的权重放大三倍。
class InitializationWordCompletion {
  /// 以词条总数与已完成数构造。
  const new({required this.totalWords, required this.completedWords});

  /// 队列里出现过任务的词条总数。
  ///
  /// 分母与 `listJobs` 的取数口径一致（只算有任务的词条），
  /// 否则进度条会和下面的列表对不上。
  final int totalWords;

  /// 全部任务都已进入终态的词条数。
  final int completedWords;

  /// 完成百分比（0–100，整数）。
  ///
  /// 队列为空时是 0 而不是除零：空队列没有「完成」可言。
  int get percent => totalWords == 0
      ? 0
      : (completedWords * percentScale / totalWords).round();
}

/// 各状态的任务计数。
class InitializationProgress {
  /// 以各状态计数与词条完成度构造。
  const new(this.counts, {required this.completion});

  /// 状态 → 计数。
  final Map<InitializationStatus, int> counts;

  /// 词条级完成度。
  final InitializationWordCompletion completion;

  /// 取某状态的计数（缺失为 0）。
  int countOf(InitializationStatus status) => counts[status] ?? 0;

  /// 任务总数。
  int get total => counts.values.fold(0, (sum, value) => sum + value);
}
