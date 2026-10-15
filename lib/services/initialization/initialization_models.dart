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

/// 单条入队的结果。
///
/// 入队有三种落点，必须区分：新建一个任务、合并进已有活跃任务、
/// 或者根本没入队（词条不存在或已暂停）。旧版在 `queueSelectedInitialization`
/// 里先查一次「有没有活跃任务」再入队来区分，本类把这次判定固化下来，
/// 界面才能报出「新建 N 个 / 合并 M 个」。
class EnqueueOutcome {
  /// 以任务 ID 与是否新建构造。
  const new({required this.jobId, required this.created});

  /// 未入队（词条不存在或已暂停）。
  static const EnqueueOutcome skipped = EnqueueOutcome(
    jobId: null,
    created: false,
  );

  /// 任务 ID；未入队时为 `null`。
  final int? jobId;

  /// 是否新建了任务；`false` 表示合并进已有的活跃任务。
  final bool created;

  /// 是否真的入了队。
  bool get enqueued => jobId != null;
}

/// 批量入队的回执。
class EnqueueBulkReport {
  /// 以新建、合并与跳过数构造。
  const new({
    required this.created,
    required this.merged,
    required this.skipped,
  });

  /// 新建的任务 ID。
  final List<int> created;

  /// 合并进已有活跃任务的任务 ID。
  final List<int> merged;

  /// 未入队的词条数（词条不存在或已暂停）。
  final int skipped;

  /// 实际入队的任务总数。
  int get jobCount => created.length + merged.length;

  /// 入队的任务 ID（新建在前，与旧版 `enqueueBulk` 的返回一致）。
  List<int> get jobIds => <int>[...created, ...merged];
}

/// 预览里点名的词条。
class InitializationPreviewWord {
  /// 以词条 ID 与文本构造。
  const new({required this.wordId, required this.term});

  /// 词条 ID。
  final int wordId;

  /// 词条文本。
  final String term;
}

/// 预览里「这个词条会被跳过」的一条记录。
///
/// **为什么必须带原因**：跳过有两类完全不同的原因——暂停的词条本来就不该
/// 补全，已经满足所选字段的词条则是本次配置选得太保守。只给一个数字，
/// 用户会以为配置出了问题。
class InitializationSkip {
  /// 以词条 ID、文本与原因构造。
  const new({required this.wordId, required this.term, required this.reason});

  /// 词条 ID。
  final int wordId;

  /// 词条文本。
  final String term;

  /// 面向用户的中文原因。
  final String reason;
}

/// 一次批量初始化的预览结果。
///
/// 口径与旧版 `/api/initialization/preview` 逐条对应：
/// 「范围内」是存在的词条数，「处理」是真正会入队的词条数，
/// 两者之差即跳过。**入队只发生在「处理」这一集合上**，
/// 所以预览的选集与实际入队的选集必然一致。
class InitializationPreview {
  /// 以各项计数构造。
  const new({
    required this.existingWords,
    required this.selectedWordIds,
    required this.samples,
    required this.mergedWords,
    required this.satisfiedWords,
    required this.suspendedWords,
    required this.skips,
  });

  /// 范围内的词条数。
  final int existingWords;

  /// 本次会入队的词条 ID。
  final List<int> selectedWordIds;

  /// 会入队的词条示例。
  final List<InitializationPreviewWord> samples;

  /// 其中会合并进已有活跃任务的词条数。
  final int mergedWords;

  /// 其中内容已满足所选字段、worker 会直接判为完成的词条数。
  final int satisfiedWords;

  /// 其中已暂停、不入队的词条数。
  final int suspendedWords;

  /// 跳过的词条与原因（最多若干条，供界面展示）。
  final List<InitializationSkip> skips;

  /// 会入队的词条数。
  int get selectedWords => selectedWordIds.length;

  /// 跳过的词条总数。
  int get skippedWords => satisfiedWords + suspendedWords;
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
