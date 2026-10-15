/// 初始化任务队列的查询与写入。
///
/// 对应旧版 `modules/initialization/queries.ts` 与 `shared.ts`。
///
/// **部分唯一索引的处理**：`initialization_jobs_active_word_task_unique`
/// 保证同一词条同一任务类型最多一个活跃任务。这里用「先查后插 +
/// `ON CONFLICT DO NOTHING RETURNING id`」双保险：查到活跃任务就升级它
/// （保留进度），插入被索引拦下则回读并升级。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/dictionary_constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 用户取消任务时写入的错误码。
///
/// 不是 `AppErrorCode`：取消不是错误，只是终态原因，
/// 用独立标识避免污染错误码枚举。
const String cancelledJobErrorCode = 'CANCELLED';

/// 自动重试时写入的错误码（对应 `AppErrorCode.autoRetry`）。
const String autoRetryJobErrorCode = 'AUTO_RETRY';

/// 手动重试时写入的错误码。
const String manualRetryJobErrorCode = 'MANUAL_RETRY';

/// 从设置推导任务最大尝试次数。
///
/// **唯一的来源**：旧版在导入路径硬编码 5、在 AI 路径用 `aiRetryCount + 1`
/// （默认 2），同一份任务在不同入口有不同的重试上限。
/// 这里统一为「`aiRetryCount` + 1，缺失时用 [importJobMaxAttempts]」，
/// 再夹到 [maxAttemptsFloor]–[maxAttemptsCeiling]。
int maxAttemptsFromSettings(AppSettings settings) {
  final raw = settings.raw['aiRetryCount'];
  if (raw is! num) return importJobMaxAttempts;
  return (raw.round() + 1).clamp(maxAttemptsFloor, maxAttemptsCeiling);
}

/// 任务重试延迟（毫秒）。
///
/// 序列用尽后沿用最后一项，避免退避无限增长。
int retryDelayMs(int attemptCount) {
  final index = attemptCount - 1;
  if (index < 0) return retryBackoffMs.first;
  if (index >= retryBackoffMs.length) return retryBackoffMs.last;
  return retryBackoffMs[index];
}

/// 初始化任务查询与入队。
class InitializationQueries {
  /// 以数据库与设置服务构造。
  const new(this._db, this._settings);

  final AppDatabase _db;
  final SettingsService _settings;

  /// 入队一个任务。
  ///
  /// 返回任务 ID；词条已暂停时返回 `null`（不入队）。
  /// 已存在活跃任务时**升级**它而不是新建，避免丢失已累计的尝试次数。
  Future<int?> enqueueWord(EnqueueRequest request, {required int now}) async {
    if (await _isSuspended(request.wordId)) return null;
    final active = await _activeJobId(request.wordId, request.taskType);
    if (active != null) {
      await _upgradeJob(active, request, now);
      return active;
    }
    final inserted = await _insertJob(request, now);
    if (inserted != null) return inserted;
    final conflicted = await _activeJobId(request.wordId, request.taskType);
    if (conflicted == null) return null;
    await _upgradeJob(conflicted, request, now);
    return conflicted;
  }

  /// 批量入队。
  Future<List<int>> enqueueBulk(
    List<EnqueueRequest> requests, {
    required int now,
  }) async {
    final result = <int>[];
    for (final request in requests) {
      final id = await enqueueWord(request, now: now);
      if (id != null) result.add(id);
    }
    return result;
  }

  /// 读取单条任务详情。
  Future<InitializationTaskSummary?> jobDetail(int jobId) async {
    final rows = await _db
        .customSelect(
          'SELECT id, task_type, status, mode, attempt_count, max_attempts, '
          'last_error, last_error_code, created_at, updated_at, completed_at '
          'FROM initialization_jobs WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(jobId)],
        )
        .get();
    if (rows.isEmpty) return null;
    return _mapTask(rows.first);
  }

  /// 分页列出任务（按词条聚合）。
  Future<InitializationJobPage> listJobs({
    int page = 1,
    int pageSize = initializationJobPageSize,
    InitializationStatus? status,
    String search = '',
  }) async {
    final filter = _listFilter(status, search);
    final totalRow = await _db
        .customSelect(
          'SELECT COUNT(*) AS total FROM (SELECT w.id $_listFrom '
          '${filter.whereClause} GROUP BY w.id ${filter.havingClause}) grouped',
          variables: filter.variables,
        )
        .getSingle();
    final rows = await _db
        .customSelect(
          'SELECT w.id AS word_id, w.term, $_aggregateStatus AS status, '
          'COUNT(j.id) AS task_count, '
          "SUM(CASE WHEN j.status IN ('READY','PARTIAL','DISABLED') "
          'THEN 1 ELSE 0 END) AS completed_task_count, '
          "SUM(CASE WHEN j.status = 'FAILED' THEN 1 ELSE 0 END) "
          'AS failed_task_count, '
          "SUM(CASE WHEN j.status IN ('QUEUED','PENDING','RUNNING') "
          'THEN 1 ELSE 0 END) AS active_task_count, '
          'MAX(j.updated_at) AS updated_at '
          '$_listFrom ${filter.whereClause} GROUP BY w.id '
          '${filter.havingClause} '
          'ORDER BY MAX(j.updated_at) DESC, w.id DESC LIMIT ? OFFSET ?',
          variables: <Variable<Object>>[
            ...filter.variables,
            Variable<int>(pageSize),
            Variable<int>(_offset(page, pageSize)),
          ],
        )
        .get();
    final wordIds = <int>[for (final row in rows) row.read<int>('word_id')];
    final tasksByWord = await _tasksByWord(wordIds);
    return InitializationJobPage(
      total: totalRow.read<int>('total'),
      items: <InitializationWordSummary>[
        for (final row in rows) _mapWord(row, tasksByWord),
      ],
    );
  }

  /// 取消一个任务。
  Future<void> cancelJob(int jobId, {required int now}) async {
    final job = await jobDetail(jobId);
    if (job == null) throw const NotFoundError(AppErrorCode.jobNotFound);
    if (job.status == InitializationStatus.running) {
      throw const ConflictError(
        AppErrorCode.validationError,
        details: '任务正在执行，无法取消',
      );
    }
    await _db.customUpdate(
      'UPDATE initialization_jobs SET status = ?, completed_at = ?, '
      'last_error = ?, last_error_code = ?, locked_at = NULL, '
      'locked_by = NULL, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.failed.wire),
        Variable<int>(now),
        const Variable<String>('用户已取消该任务'),
        const Variable<String>(cancelledJobErrorCode),
        Variable<int>(now),
        Variable<int>(jobId),
      ],
      updateKind: UpdateKind.update,
    );
  }

  /// 重新入队一个任务（手动重试）。
  Future<void> retryJob(int jobId, {required int now}) async {
    final job = await jobDetail(jobId);
    if (job == null) throw const NotFoundError(AppErrorCode.jobNotFound);
    if (job.status == InitializationStatus.running) {
      throw const ConflictError(
        AppErrorCode.validationError,
        details: '任务正在执行，无法重新入队',
      );
    }
    await _db.customUpdate(
      'UPDATE initialization_jobs SET status = ?, attempt_count = 0, '
      'available_at = ?, completed_at = NULL, locked_at = NULL, '
      'locked_by = NULL, last_error_code = ?, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.queued.wire),
        Variable<int>(now),
        const Variable<String>(manualRetryJobErrorCode),
        Variable<int>(now),
        Variable<int>(jobId),
      ],
      updateKind: UpdateKind.update,
    );
  }

  /// 各状态的任务计数。
  Future<InitializationProgress> progressSummary() async {
    final rows = await _db
        .customSelect(
          'SELECT status, COUNT(*) AS count FROM initialization_jobs '
          'GROUP BY status',
        )
        .get();
    final counts = <InitializationStatus, int>{
      for (final status in InitializationStatus.values) status: 0,
    };
    for (final row in rows) {
      final status = wireLookup(
        InitializationStatus.values,
        row.read<String>('status'),
      );
      if (status != null) counts[status] = row.read<int>('count');
    }
    return InitializationProgress(counts);
  }

  Future<bool> _isSuspended(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT is_suspended FROM words WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) return true;
    return rows.first.read<int>('is_suspended') != 0;
  }

  Future<int?> _activeJobId(int wordId, JobTaskType taskType) async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM initialization_jobs WHERE word_id = ? '
          "AND task_type = ? AND status IN ('QUEUED','RUNNING') LIMIT 1",
          variables: <Variable<Object>>[
            Variable<int>(wordId),
            Variable<String>(taskType.wire),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<int>('id');
  }

  Future<int?> _insertJob(EnqueueRequest request, int now) async {
    final settings = await _settings.load();
    final rows = await _db
        .customSelect(
          'INSERT INTO initialization_jobs (word_id, task_type, mode, '
          'requested_fields_json, requested_providers_json, provider_strategy, '
          'status, priority, attempt_count, max_attempts, available_at, '
          'created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?) '
          'ON CONFLICT DO NOTHING RETURNING id',
          variables: _jobVariables(request, settings, now),
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<int>('id');
  }

  List<Variable<Object>> _jobVariables(
    EnqueueRequest request,
    AppSettings settings,
    int now,
  ) => <Variable<Object>>[
    Variable<int>(request.wordId),
    Variable<String>(request.taskType.wire),
    Variable<String>(request.mode.wire),
    Variable<String>(_encodeList(request.requestedFields)),
    Variable<String>(_encodeList(request.requestedProviders)),
    Variable<String>(request.strategy.wire),
    Variable<String>(InitializationStatus.queued.wire),
    Variable<int>(request.priority),
    Variable<int>(maxAttemptsFromSettings(settings)),
    Variable<int>(now),
    Variable<int>(now),
    Variable<int>(now),
  ];

  Future<void> _upgradeJob(int jobId, EnqueueRequest request, int now) async {
    await _db.customUpdate(
      'UPDATE initialization_jobs SET mode = ?, requested_fields_json = ?, '
      'requested_providers_json = ?, provider_strategy = ?, '
      'priority = MAX(priority, ?), available_at = ?, updated_at = ? '
      "WHERE id = ? AND status IN ('QUEUED','RUNNING')",
      variables: <Variable<Object>>[
        Variable<String>(request.mode.wire),
        Variable<String>(_encodeList(request.requestedFields)),
        Variable<String>(_encodeList(request.requestedProviders)),
        Variable<String>(request.strategy.wire),
        Variable<int>(request.priority),
        Variable<int>(now),
        Variable<int>(now),
        Variable<int>(jobId),
      ],
      updateKind: UpdateKind.update,
    );
  }

  Future<Map<int, List<InitializationTaskSummary>>> _tasksByWord(
    List<int> wordIds,
  ) async {
    if (wordIds.isEmpty) return <int, List<InitializationTaskSummary>>{};
    final placeholders = List<String>.filled(wordIds.length, '?').join(',');
    final rows = await _db
        .customSelect(
          'SELECT id, word_id, task_type, status, mode, attempt_count, '
          'max_attempts, last_error, last_error_code, created_at, updated_at, '
          'completed_at FROM initialization_jobs WHERE word_id IN '
          '($placeholders) ORDER BY word_id ASC, updated_at DESC, id DESC',
          variables: <Variable<Object>>[
            for (final id in wordIds) Variable<int>(id),
          ],
        )
        .get();
    final result = <int, List<InitializationTaskSummary>>{};
    for (final row in rows) {
      final wordId = row.read<int>('word_id');
      result
          .putIfAbsent(wordId, () => <InitializationTaskSummary>[])
          .add(_mapTask(row));
    }
    return result;
  }

  InitializationTaskSummary _mapTask(QueryRow row) => InitializationTaskSummary(
    id: row.read<int>('id'),
    taskType:
        wireLookup(JobTaskType.values, row.read<String>('task_type')) ??
        JobTaskType.initialize,
    status:
        wireLookup(InitializationStatus.values, row.read<String>('status')) ??
        InitializationStatus.pending,
    mode:
        wireLookup(InitializationMode.values, row.read<String>('mode')) ??
        InitializationMode.fillMissingFields,
    attemptCount: row.read<int>('attempt_count'),
    maxAttempts: row.read<int>('max_attempts'),
    createdAt: row.read<int>('created_at'),
    updatedAt: row.read<int>('updated_at'),
    lastError: row.read<String?>('last_error'),
    lastErrorCode: row.read<String?>('last_error_code'),
    completedAt: row.read<int?>('completed_at'),
  );

  InitializationWordSummary _mapWord(
    QueryRow row,
    Map<int, List<InitializationTaskSummary>> tasksByWord,
  ) {
    final wordId = row.read<int>('word_id');
    final tasks = tasksByWord[wordId] ?? <InitializationTaskSummary>[];
    String? errorSummary;
    for (final task in tasks) {
      if (task.status != InitializationStatus.failed) continue;
      if (task.lastError == null) continue;
      errorSummary = task.lastError;
      break;
    }
    return InitializationWordSummary(
      wordId: wordId,
      term: row.read<String>('term'),
      status:
          wireLookup(InitializationStatus.values, row.read<String>('status')) ??
          InitializationStatus.pending,
      taskCount: row.read<int>('task_count'),
      completedTaskCount: row.read<int>('completed_task_count'),
      failedTaskCount: row.read<int>('failed_task_count'),
      activeTaskCount: row.read<int>('active_task_count'),
      updatedAt: row.read<int>('updated_at'),
      tasks: tasks,
      errorSummary: errorSummary,
    );
  }
}

/// 按词条聚合状态的 SQL。
///
/// 运行中 > 排队 > 失败 > 部分完成 > 完成：只要还有活跃任务，
/// 聚合状态就不能显示为「完成」。
const String _aggregateStatus = '''
  CASE
    WHEN SUM(CASE WHEN j.status = 'RUNNING' THEN 1 ELSE 0 END) > 0 THEN 'RUNNING'
    WHEN SUM(CASE WHEN j.status IN ('QUEUED','PENDING') THEN 1 ELSE 0 END) > 0 THEN 'QUEUED'
    WHEN SUM(CASE WHEN j.status = 'FAILED' THEN 1 ELSE 0 END) > 0 THEN 'FAILED'
    WHEN SUM(CASE WHEN j.status = 'PARTIAL' THEN 1 ELSE 0 END) > 0 THEN 'PARTIAL'
    ELSE 'READY'
  END''';

/// 列表查询的 FROM 子句。
const String _listFrom =
    'FROM initialization_jobs j INNER JOIN words w ON w.id = j.word_id '
    'WHERE 1 = 1';

class _ListFilter {
  const new(this.whereClause, this.havingClause, this.variables);

  final String whereClause;
  final String havingClause;
  final List<Variable<Object>> variables;
}

/// 关键词走 `WHERE`，聚合状态必须走 `HAVING`。
///
/// 把聚合表达式放进 `WHERE` 会被 SQLite 判为 `misuse of aggregate`——
/// 旧版也是靠 `HAVING` 才成立的。
_ListFilter _listFilter(InitializationStatus? status, String search) {
  final conditions = <String>[];
  final variables = <Variable<Object>>[];
  final trimmed = search.trim();
  if (trimmed.isNotEmpty) {
    conditions.add('AND (w.term LIKE ? ESCAPE ? OR w.normalized_term LIKE ?)');
    final escaped = trimmed
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    variables.addAll(<Variable<Object>>[
      Variable<String>('%$escaped%'),
      const Variable<String>(r'\'),
      Variable<String>('%$escaped%'),
    ]);
  }
  var having = '';
  if (status != null) {
    having = 'HAVING $_aggregateStatus = ?';
    variables.add(Variable<String>(status.wire));
  }
  return _ListFilter(conditions.join(' '), having, variables);
}

int _offset(int page, int pageSize) {
  final safePage = page < 1 ? 1 : page;
  return (safePage - 1) * pageSize;
}

String _encodeList(List<String> values) =>
    values.isEmpty ? '[]' : jsonEncode(values);
