/// 初始化任务 worker。
///
/// 对应旧版 `modules/initialization/worker.ts`。
///
/// **为什么要重写而不是移植**：旧版的 `processJob` 约 95 行，把「读词条、
/// 判断跳过、跑管线、合并、落库、写审计、排补充任务」全部塞在一个函数里
/// （`docs/CLEAN_CODE_BASELINE.md` 点名）。这里拆成
/// 「取任务 → 判定 → 拉取 → 落库 → 收尾」五个单一职责的小函数，
/// 每一步都可以单独读、单独测。
///
/// **单进程假设**：没有其他 worker，因此 `resetStaleRunningJobs` 在启动时
/// 无条件把 RUNNING 收回队列；`workerStaleAfterMs` 只用于会话中途兜底。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/lookup_service.dart';
import 'package:lexiloop/services/dictionary/merge.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/dictionary/selection.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/services/initialization/initialization_queries.dart';
import 'package:lexiloop/services/initialization/job_runner.dart';
import 'package:lexiloop/services/initialization/supplemental_tasks.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 认领任务时写入 `locked_by` 的标识。
const String initializationWorkerId = 'flutter-local-worker';

/// 崩溃恢复时写入的错误说明。
const String staleLockMessage = '进程重启前的运行中任务已重新排队';

/// 初始化任务 worker。
///
/// 实现 [InitializationJobRunner]，供后台维护调度与队列页按钮调用。
class InitializationWorker implements InitializationJobRunner {
  /// 以数据库、设置、查询入口、词典服务与补充任务执行器构造。
  const new(
    this._db,
    this._settings,
    this._queries,
    this._dictionary,
    this._supplemental,
  );

  final AppDatabase _db;
  final SettingsService _settings;
  final InitializationQueries _queries;
  final DictionaryLookupService _dictionary;
  final SupplementalTaskRunner _supplemental;

  @override
  Future<int> tick({required int now}) async {
    final jobs = await _claim(now);
    var processed = 0;
    for (final job in jobs) {
      await _process(job, now);
      processed += 1;
    }
    return processed;
  }

  /// 执行单个任务（用户手动触发时也走这条路径）。
  Future<void> runJob(int jobId, {required int now}) async {
    final loaded = await _loadJob(jobId);
    if (loaded == null) throw const NotFoundError(AppErrorCode.jobNotFound);
    final job = await _ensureRunning(loaded, now);
    if (job == null) return;
    await _process(job, now);
  }

  /// 把 RUNNING 任务收回队列。
  ///
  /// [staleOnly] 为真时只回收 `locked_at` 早于 `workerStaleAfterMs` 的任务
  /// （会话中途的异常兜底）；为假时全量回收（应用启动时的崩溃恢复）。
  @override
  Future<int> resetStaleRunningJobs(int now, {bool staleOnly = false}) async {
    final sql = staleOnly
        ? 'UPDATE initialization_jobs SET status = ?, locked_at = NULL, '
              'locked_by = NULL, available_at = ?, last_error = ?, '
              'last_error_code = ?, updated_at = ? '
              "WHERE status = 'RUNNING' AND locked_at IS NOT NULL "
              'AND locked_at < ?'
        : 'UPDATE initialization_jobs SET status = ?, locked_at = NULL, '
              'locked_by = NULL, available_at = ?, last_error = ?, '
              'last_error_code = ?, updated_at = ? '
              "WHERE status = 'RUNNING'";
    final variables = <Variable<Object>>[
      Variable<String>(InitializationStatus.queued.wire),
      Variable<int>(now),
      const Variable<String>(staleLockMessage),
      Variable<String>(AppErrorCode.staleLock.code),
      Variable<int>(now),
      if (staleOnly) Variable<int>(now - workerStaleAfterMs),
    ];
    final changes = await _db.customUpdate(
      sql,
      variables: variables,
      updateKind: UpdateKind.update,
    );
    await _syncQueuedWords(now);
    return changes;
  }

  /// 把冷却已过的失败任务重新入队。
  @override
  Future<int> retryFailedJobs(int now) async {
    final changes = await _db.customUpdate(
      'UPDATE initialization_jobs SET status = ?, attempt_count = 0, '
      'available_at = ?, completed_at = NULL, locked_at = NULL, '
      'locked_by = NULL, last_error_code = ?, updated_at = ? '
      "WHERE status = 'FAILED' AND completed_at IS NOT NULL "
      'AND completed_at <= ?',
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.queued.wire),
        Variable<int>(now),
        const Variable<String>(autoRetryJobErrorCode),
        Variable<int>(now),
        Variable<int>(now - failedRetryCooldownMs),
      ],
      updateKind: UpdateKind.update,
    );
    await _syncQueuedWords(now);
    return changes;
  }

  /// 让长期没再答错的词条退出错词本。
  ///
  /// SQL 与旧版 `decayStaleWrongWords` 逐字等价：判据是
  /// 「最后答错早于 `wrongWordDecayDays` 天前」且「此后没有答对过」，
  /// 两者取交集——只用前者会把「先错很久、最近刚答对一次」的词条误伤。
  @override
  Future<int> decayStaleWrongWords(int now) {
    final cutoff = now - wrongWordDecayDays * dayMs;
    return _db.customUpdate(
      'UPDATE wrong_word_states '
      'SET active = 0, resolved_at = ?, updated_at = ? '
      'WHERE active = 1 AND last_wrong_at IS NOT NULL AND last_wrong_at < ? '
      'AND (last_correct_at IS NULL OR last_correct_at < ?)',
      variables: <Variable<Object>>[
        Variable<int>(now),
        Variable<int>(now),
        Variable<int>(cutoff),
        Variable<int>(cutoff),
      ],
      updateKind: UpdateKind.update,
    );
  }

  /// 把卡在 `PENDING` 超过 `importBatchExpiryMs` 的导入批次置为失败。
  ///
  /// 刻意只改状态、不删行：批次里的逐行明细要留给用户看失败原因。
  @override
  Future<int> expireStaleImportBatches(int now) {
    return _db.customUpdate(
      'UPDATE import_batches SET status = ?, completed_at = ? '
      "WHERE status = 'PENDING' AND created_at < ?",
      variables: <Variable<Object>>[
        Variable<String>(ImportBatchStatus.failed.wire),
        Variable<int>(now),
        Variable<int>(now - importBatchExpiryMs),
      ],
      updateKind: UpdateKind.update,
    );
  }

  Future<List<ClaimedJob>> _claim(int now) async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM initialization_jobs '
          "WHERE status = 'QUEUED' AND attempt_count < max_attempts "
          'AND (available_at IS NULL OR available_at <= ?) '
          'ORDER BY priority DESC, available_at ASC, id ASC LIMIT ?',
          variables: <Variable<Object>>[
            Variable<int>(now),
            const Variable<int>(defaultMaxJobsPerTick),
          ],
        )
        .get();
    final claimed = <ClaimedJob>[];
    for (final row in rows) {
      final id = row.read<int>('id');
      if (!await _markRunning(id, now)) continue;
      final job = await _loadJob(id);
      if (job != null) claimed.add(job);
    }
    return claimed;
  }

  Future<ClaimedJob?> _ensureRunning(ClaimedJob job, int now) async {
    if (job.status == InitializationStatus.running) return job;
    if (job.status != InitializationStatus.queued) return null;
    if (!await _markRunning(job.id, now)) return null;
    return await _loadJob(job.id);
  }

  Future<bool> _markRunning(int jobId, int now) async {
    final changes = await _db.customUpdate(
      'UPDATE initialization_jobs SET status = ?, locked_at = ?, '
      'locked_by = ?, attempt_count = attempt_count + 1, updated_at = ? '
      "WHERE id = ? AND status = 'QUEUED'",
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.running.wire),
        Variable<int>(now),
        const Variable<String>(initializationWorkerId),
        Variable<int>(now),
        Variable<int>(jobId),
      ],
      updateKind: UpdateKind.update,
    );
    return changes > 0;
  }

  Future<void> _process(ClaimedJob job, int now) async {
    if (job.taskType == JobTaskType.initialize) {
      await _setWordStatus(job.wordId, InitializationStatus.running, now);
    }
    try {
      if (job.taskType == JobTaskType.initialize) {
        await _processInitialize(job, now);
      } else {
        await _processSupplemental(job, now);
      }
    } on AppError catch (error) {
      await _failOrRetry(job, error, now);
    } on Object catch (error) {
      await _failOrRetry(
        job,
        ExternalServiceError(
          AppErrorCode.workerException,
          isTransient: true,
          details: '$error',
        ),
        now,
      );
    }
  }

  Future<void> _processInitialize(ClaimedJob job, int now) async {
    final word = await _loadWord(job.wordId);
    if (word == null) {
      await _failOrRetry(
        job,
        const NotFoundError(AppErrorCode.wordNotFound),
        now,
      );
      return;
    }
    if (word.isSuspended) {
      await _failOrRetry(
        job,
        const ConflictError(AppErrorCode.wordSuspended),
        now,
      );
      return;
    }
    final existing = await _loadExistingContent(job.wordId);
    final requested = normalizeRequestedFields(job.requestedFields);
    final skipStatus = _skipStatus(word, existing, requested, job.mode);
    if (skipStatus != null) {
      await _complete(
        job,
        skipStatus,
        now,
        wordStatus: contentStatus(existing, word.contentType),
      );
      return;
    }
    await _fetchAndStore(job, word, existing, requested, now);
  }

  /// 已有内容是否已经满足本次任务，满足则无需再调用数据源。
  InitializationStatus? _skipStatus(
    _WordRow word,
    DictionaryContent existing,
    List<String> requested,
    InitializationMode mode,
  ) {
    if (mode == InitializationMode.skipInitialized) {
      if (word.contentType == LexicalContentType.sentence) {
        final status = contentStatus(existing, word.contentType);
        return status == InitializationStatus.failed ? null : status;
      }
      final ready =
          requestedFieldStatusForLanguages(
            existing,
            <String>[definitionsField],
            word.sourceLanguage,
            word.targetLanguage,
          ) ==
          InitializationStatus.ready;
      return ready ? contentStatus(existing, word.contentType) : null;
    }
    if (mode == InitializationMode.fillMissingFields && requested.isNotEmpty) {
      final status = requestedFieldStatusForLanguages(
        existing,
        requested,
        word.sourceLanguage,
        word.targetLanguage,
      );
      return status == InitializationStatus.ready
          ? InitializationStatus.ready
          : null;
    }
    return null;
  }

  Future<void> _fetchAndStore(
    ClaimedJob job,
    _WordRow word,
    DictionaryContent existing,
    List<String> requested,
    int now,
  ) async {
    final settings = await _settings.load();
    final result = await _dictionary.lookup(
      settings: settings,
      request: ProviderRequest(
        term: word.term,
        contentType: word.contentType,
        sourceLanguage: word.sourceLanguage,
        targetLanguage: word.targetLanguage,
        wantedFields: requested.toSet(),
      ),
      selectedProviders: job.requestedProviders,
      strategy: job.providerStrategy,
    );
    await _saveAttempts(job.id, job.wordId, result.attempts, now);
    final incomingStatus = _incomingStatus(result.content, requested, word);
    if (incomingStatus == InitializationStatus.failed) {
      await _failOrRetry(job, _emptyContentError(requested, result), now);
      return;
    }
    final merged = _mergeContent(
      existing: existing,
      incoming: result.content,
      requested: requested,
      mode: job.mode,
    );
    await _saveContent(
      job.wordId,
      merged,
      result.attempts,
      result.contentSource,
      now,
    );
    await _complete(
      job,
      incomingStatus,
      now,
      wordStatus: _wordStatus(merged, incomingStatus, word),
    );
    await _queueSupplemental(job, merged, settings, word, requested, now);
  }

  Future<void> _processSupplemental(ClaimedJob job, int now) async {
    try {
      await _supplemental.run(
        taskType: job.taskType,
        wordId: job.wordId,
        now: now,
      );
      await _saveAttempts(job.id, job.wordId, <ProviderAttemptRecord>[
        ProviderAttemptRecord(
          providerId: 'ai:${job.taskType.wire.toLowerCase()}',
          status: ProviderAttemptStatus.success,
          durationMs: 0,
          fieldsReturned: <String>[job.taskType.wire],
        ),
      ], now);
      await _complete(job, InitializationStatus.ready, now);
    } on ExternalServiceError catch (error) {
      await _saveAttempts(job.id, job.wordId, <ProviderAttemptRecord>[
        ProviderAttemptRecord(
          providerId: 'ai:${job.taskType.wire.toLowerCase()}',
          status: ProviderAttemptStatus.failed,
          durationMs: 0,
          fieldsReturned: const <String>[],
          errorCode: error.code.code,
          errorMessage: error.message,
        ),
      ], now);
      await _failOrRetry(job, error, now);
    }
  }

  Future<void> _failOrRetry(ClaimedJob job, AppError error, int now) async {
    if (error.isTransient && job.attemptCount < job.maxAttempts) {
      await _requeue(job, error, now);
      return;
    }
    await _markFailed(job, error, now);
  }

  Future<void> _requeue(ClaimedJob job, AppError error, int now) async {
    await _db.customUpdate(
      'UPDATE initialization_jobs SET status = ?, locked_at = NULL, '
      'locked_by = NULL, available_at = ?, last_error = ?, '
      'last_error_code = ?, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.queued.wire),
        Variable<int>(now + retryDelayMs(job.attemptCount)),
        Variable<String>(_errorMessage(error)),
        Variable<String>(error.code.code),
        Variable<int>(now),
        Variable<int>(job.id),
      ],
      updateKind: UpdateKind.update,
    );
    if (job.taskType == JobTaskType.initialize) {
      await _setWordStatus(job.wordId, InitializationStatus.queued, now);
    }
  }

  Future<void> _markFailed(ClaimedJob job, AppError error, int now) async {
    await _db.customUpdate(
      'UPDATE initialization_jobs SET status = ?, locked_at = NULL, '
      'locked_by = NULL, completed_at = ?, last_error = ?, '
      'last_error_code = ?, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.failed.wire),
        Variable<int>(now),
        Variable<String>(_errorMessage(error)),
        Variable<String>(error.code.code),
        Variable<int>(now),
        Variable<int>(job.id),
      ],
      updateKind: UpdateKind.update,
    );
    if (job.taskType == JobTaskType.initialize) {
      await _setWordStatus(job.wordId, InitializationStatus.failed, now);
    }
  }

  Future<void> _complete(
    ClaimedJob job,
    InitializationStatus status,
    int now, {
    InitializationStatus? wordStatus,
  }) async {
    await _db.customUpdate(
      'UPDATE initialization_jobs SET status = ?, locked_at = NULL, '
      'locked_by = NULL, completed_at = ?, updated_at = ?, '
      'last_error = NULL, last_error_code = NULL WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<String>(status.wire),
        Variable<int>(now),
        Variable<int>(now),
        Variable<int>(job.id),
      ],
      updateKind: UpdateKind.update,
    );
    if (job.taskType == JobTaskType.initialize) {
      await _setWordStatus(job.wordId, wordStatus ?? status, now);
    }
  }

  Future<void> _setWordStatus(
    int wordId,
    InitializationStatus status,
    int now,
  ) async {
    await _db.customUpdate(
      'UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<String>(status.wire),
        Variable<int>(now),
        Variable<int>(wordId),
      ],
      updateKind: UpdateKind.update,
    );
  }

  /// 让「有排队 INITIALIZE 任务」的词条回到 QUEUED。
  Future<void> _syncQueuedWords(int now) async {
    await _db.customUpdate(
      'UPDATE words SET initialization_status = ?, updated_at = ? '
      "WHERE initialization_status IN ('RUNNING','FAILED') AND EXISTS ( "
      'SELECT 1 FROM initialization_jobs j WHERE j.word_id = words.id '
      "AND j.task_type = 'INITIALIZE' AND j.status = 'QUEUED')",
      variables: <Variable<Object>>[
        Variable<String>(InitializationStatus.queued.wire),
        Variable<int>(now),
      ],
      updateKind: UpdateKind.update,
    );
  }

  Future<void> _queueSupplemental(
    ClaimedJob job,
    DictionaryContent merged,
    AppSettings settings,
    _WordRow word,
    List<String> requested,
    int now,
  ) async {
    if (requested.isNotEmpty) return;
    final llmConfig = llmConfigFromSettings(settings.raw);
    if (!llmConfig.isUsable) return;
    if (word.contentType == LexicalContentType.sentence) {
      if (!llmConfig.canAutoTranslate) return;
      if (_hasTargetTranslation(merged, word.targetLanguage)) return;
      await _queries.enqueueWord(
        EnqueueRequest(
          wordId: job.wordId,
          taskType: JobTaskType.exampleTranslations,
          mode: InitializationMode.fillMissingFields,
          priority: jobPrioritySupplemental,
        ),
        now: now,
      );
      return;
    }
    if (!llmConfig.canAutoMnemonic) return;
    final mnemonic = merged.record('learning')['mnemonic'];
    final hasMnemonic = mnemonic is String && mnemonic.trim().isNotEmpty;
    if (word.sourceLanguage.startsWith('en') && !hasMnemonic) {
      await _queries.enqueueWord(
        EnqueueRequest(
          wordId: job.wordId,
          taskType: JobTaskType.mnemonic,
          mode: InitializationMode.fillMissingFields,
          priority: jobPrioritySupplemental,
        ),
        now: now,
      );
    }
  }

  bool _hasTargetTranslation(DictionaryContent content, String targetLanguage) {
    final summary = content.record(summaryField)['translation'];
    if (summary is String && summary.trim().isNotEmpty) return true;
    return content
        .records(definitionsField)
        .any(
          (item) =>
              item['language'] == targetLanguage &&
              item['text'] is String &&
              (item['text']! as String).trim().isNotEmpty,
        );
  }

  InitializationStatus _incomingStatus(
    DictionaryContent content,
    List<String> requested,
    _WordRow word,
  ) => requested.isEmpty
      ? contentStatus(content, word.contentType)
      : requestedFieldStatusForLanguages(
          content,
          requested,
          word.sourceLanguage,
          word.targetLanguage,
        );

  InitializationStatus _wordStatus(
    DictionaryContent merged,
    InitializationStatus taskStatus,
    _WordRow word,
  ) {
    final wordStatus = contentStatus(merged, word.contentType);
    if (wordStatus == InitializationStatus.failed &&
        taskStatus != InitializationStatus.failed) {
      return InitializationStatus.partial;
    }
    return wordStatus;
  }

  DictionaryContent _mergeContent({
    required DictionaryContent existing,
    required DictionaryContent incoming,
    required List<String> requested,
    required InitializationMode mode,
  }) {
    if (requested.isNotEmpty) {
      return mergeRequestedFields(
        existing: existing,
        incoming: incoming,
        requestedFields: requested,
        mode: mode,
      );
    }
    if (mode == InitializationMode.forceOverwrite) {
      return preserveUserContent(existing, incoming);
    }
    return mergeDictionaryContent(<DictionaryContent>[existing, incoming]);
  }

  ExternalServiceError _emptyContentError(
    List<String> requested,
    DictionaryLookupResult result,
  ) {
    final summary = result.attempts
        .map(
          (attempt) =>
              '${attempt.providerId}=${attempt.status.wire}'
              '${attempt.errorCode == null ? '' : '[${attempt.errorCode}]'}',
        )
        .join(' ');
    final detail = requested.isEmpty
        ? '没有获取到可用释义。数据源执行情况：$summary'
        : '所选数据源没有返回本次要求的字段。数据源执行情况：$summary';
    return ExternalServiceError(
      result.hasTransientFailure
          ? AppErrorCode.providerTransientFailure
          : AppErrorCode.requestedFieldsEmpty,
      isTransient: result.hasTransientFailure,
      details: detail,
    );
  }

  Future<void> _saveAttempts(
    int jobId,
    int wordId,
    List<ProviderAttemptRecord> attempts,
    int now,
  ) async {
    for (final attempt in attempts) {
      await _db.customInsert(
        'INSERT INTO provider_attempts (initialization_job_id, word_id, '
        'provider_id, status, duration_ms, fields_returned_json, error_code, '
        'error_message, metadata_json, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: <Variable<Object>>[
          Variable<int>(jobId),
          Variable<int>(wordId),
          Variable<String>(attempt.providerId),
          Variable<String>(attempt.status.wire),
          Variable<int>(attempt.durationMs),
          Variable<String>(jsonEncode(attempt.fieldsReturned)),
          Variable<String>(attempt.errorCode),
          Variable<String>(attempt.errorMessage),
          Variable<String>(
            attempt.metadata == null ? null : jsonEncode(attempt.metadata),
          ),
          Variable<int>(now),
        ],
      );
    }
  }

  Future<void> _saveContent(
    int wordId,
    DictionaryContent content,
    List<ProviderAttemptRecord> attempts,
    ContentSource source,
    int now,
  ) async {
    final columns = content.toJsonColumns();
    final names = <String>[
      'word_id',
      ...columns.keys,
      'provider_metadata_json',
      'content_source',
      'content_version',
      'initialized_at',
      'updated_at',
    ];
    final variables = <Variable<Object>>[
      Variable<int>(wordId),
      for (final column in columns.keys) Variable<String>(columns[column]),
      Variable<String>(
        jsonEncode(<Object?>[
          for (final attempt in attempts) _attemptJson(attempt),
        ]),
      ),
      Variable<String>(source.wire),
      const Variable<int>(1),
      Variable<int>(now),
      Variable<int>(now),
    ];
    final placeholders = List<String>.filled(names.length, '?').join(', ');
    // content_version 必须自增：它是本地并发冲突提示的依据，
    // 用 excluded 覆盖会永远停在 1。
    final assignments = <String>[
      for (final name in names)
        if (name != 'word_id' && name != 'content_version')
          '$name = excluded.$name',
      'content_version = word_contents.content_version + 1',
    ];

    await _db.customUpdate(
      'INSERT INTO word_contents (${names.join(', ')}) '
      'VALUES ($placeholders) ON CONFLICT(word_id) DO UPDATE SET '
      '${assignments.join(', ')}',
      variables: variables,
      updateKind: UpdateKind.update,
    );
  }

  Future<_WordRow?> _loadWord(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT term, source_language, target_language, content_type, '
          'is_suspended FROM words WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return _WordRow(
      term: row.read<String>('term'),
      sourceLanguage: row.read<String>('source_language'),
      targetLanguage: row.read<String>('target_language'),
      contentType:
          wireLookup(
            LexicalContentType.values,
            row.read<String>('content_type'),
          ) ??
          LexicalContentType.word,
      isSuspended: row.read<int>('is_suspended') != 0,
    );
  }

  Future<DictionaryContent> _loadExistingContent(int wordId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM word_contents WHERE word_id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    if (rows.isEmpty) return emptyDictionaryContent();
    return dictionaryContentFromColumns(
      rows.first.data.cast<String, Object?>(),
    );
  }

  Future<ClaimedJob?> _loadJob(int jobId) async {
    final rows = await _db
        .customSelect(
          'SELECT id, word_id, task_type, mode, status, attempt_count, '
          'max_attempts, requested_fields_json, requested_providers_json, '
          'provider_strategy FROM initialization_jobs WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(jobId)],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return ClaimedJob(
      id: row.read<int>('id'),
      wordId: row.read<int>('word_id'),
      taskType:
          wireLookup(JobTaskType.values, row.read<String>('task_type')) ??
          JobTaskType.initialize,
      mode:
          wireLookup(InitializationMode.values, row.read<String>('mode')) ??
          InitializationMode.skipInitialized,
      status:
          wireLookup(InitializationStatus.values, row.read<String>('status')) ??
          InitializationStatus.pending,
      attemptCount: row.read<int>('attempt_count'),
      maxAttempts: row.read<int>('max_attempts'),
      requestedFields: _decodeStrings(
        row.read<String?>('requested_fields_json'),
      ),
      requestedProviders: _decodeStrings(
        row.read<String?>('requested_providers_json'),
      ),
      providerStrategy:
          wireLookup(
            ProviderStrategy.values,
            row.read<String>('provider_strategy'),
          ) ??
          ProviderStrategy.priorityFallback,
    );
  }
}

/// worker 需要的词条信息。
class _WordRow {
  const new({
    required this.term,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
    required this.isSuspended,
  });

  final String term;
  final String sourceLanguage;
  final String targetLanguage;
  final LexicalContentType contentType;
  final bool isSuspended;
}

Map<String, Object?> _attemptJson(ProviderAttemptRecord attempt) =>
    <String, Object?>{
      'providerId': attempt.providerId,
      'status': attempt.status.wire,
      'durationMs': attempt.durationMs,
      'fieldsReturned': attempt.fieldsReturned,
      if (attempt.errorCode != null) 'errorCode': attempt.errorCode,
      if (attempt.errorMessage != null) 'errorMessage': attempt.errorMessage,
      if (attempt.metadata != null) 'metadata': attempt.metadata,
    };

String _errorMessage(AppError error) => error.details == null
    ? error.message
    : '${error.message}（${error.details}）';

List<String> _decodeStrings(String? raw) {
  if (raw == null || raw.isEmpty) return const <String>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return <String>[
      for (final item in decoded)
        if (item is String && item.isNotEmpty) item,
    ];
  } on FormatException {
    return const <String>[];
  }
}
