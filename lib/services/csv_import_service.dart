/// CSV 导入的编排：预览 → 提交 → 撤销。
///
/// 对应旧版 `app/api/imports/preview/route.ts`、`commit.ts` 与
/// `[id]/rollback/route.ts`，以及 `modules/imports/*`。
///
/// **与旧版的差异**：
/// 1. 没有预览令牌表——预览直接写 `import_batches` / `import_rows`
///    （`status = PENDING`），过期时间由 [importPreviewTtlMs] 决定；
/// 2. 没有 HTTP 层，错误直接抛 [AppError] 的密封子类；
/// 3. 撤销的依赖检查用 SQL 一次问清，而不是逐词条查三张表。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/import/content_payload.dart';
import 'package:lexiloop/data/import/content_type.dart';
import 'package:lexiloop/data/import/csv_parser.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/data/import/provider_targets.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/text/normalizer.dart';
import 'package:lexiloop/services/learning_progress_reset.dart';
import 'package:lexiloop/services/settings_service.dart';

/// CSV 导入服务。
class CsvImportService {
  /// 以数据库与设置服务构造。
  new(this._db, this._settings);

  final AppDatabase _db;
  final SettingsService _settings;

  /// 选择文件并解析出预览。
  ///
  /// 预览会落 `import_batches` / `import_rows`（**不落词条**），
  /// 有效期 [importPreviewTtlMs]。用户取消选择时抛
  /// [AppErrorCode.csvRequired]，调用方按「取消」处理即可。
  Future<ImportPreview> preview({
    required String sourceLanguage,
    required String targetLanguage,
    required int now,
  }) async {
    final picked = await _pickCsvFile();
    if (picked == null) {
      throw const ValidationError(
        AppErrorCode.csvRequired,
        details: '用户取消了文件选择',
      );
    }
    return await previewFromContent(
      picked.content,
      filename: picked.name,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      now: now,
    );
  }

  /// 从已读取的文本解析并落预览。
  ///
  /// 与 [preview] 分开是为了让「解析 + 落库」可以脱离文件选择器测试。
  Future<ImportPreview> previewFromContent(
    String content, {
    required String filename,
    required String sourceLanguage,
    required String targetLanguage,
    required int now,
  }) async {
    final parsed = parseEasyDictCsv(
      content,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    final rows = await _annotateExisting(
      parsed.rows,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    final batchId = await _insertBatch(filename, rows, now);
    await _insertPreviewRows(batchId, rows, now);

    return ImportPreview(
      batchId: batchId,
      filename: filename,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      createdAt: now,
      expiresAt: now + importPreviewTtlMs,
      rows: rows,
      skippedCount: parsed.skippedCount,
    );
  }

  /// 提交某个批次：写词条与内容，并为新词条入队初始化任务。
  ///
  /// [resetLearningProgress] 对应旧版 `csv-tab.tsx` 的
  /// 「重置本次已有词条的学习进度」勾选框：命中的**已有**词条会被清空
  /// 复习日志、复习卡、错词状态与物化统计，并撤下它在会话里未作答的题目。
  /// 新增词条本来就没有进度，不受影响。
  ///
  /// 该参数**没有默认值**是有意的：这是一枚会销毁历史数据的开关，
  /// 让每个调用点都必须显式表态，而不是继承一个隐式的 `false`。
  ///
  /// 整个过程在**一个事务**内：要么整批写入，要么一行都不写。
  /// 否则中途失败会留下「批次已提交但只导入了一半」的状态。
  Future<ImportCommitResult> commit({
    required int batchId,
    required ImportMode mode,
    required bool resetLearningProgress,
    required int now,
  }) async {
    if (batchId <= 0) {
      throw const ValidationError(AppErrorCode.importBatchIdInvalid);
    }
    return await _db.transaction(
      () => _commit(
        batchId: batchId,
        mode: mode,
        resetLearningProgress: resetLearningProgress,
        now: now,
      ),
    );
  }

  /// 撤销某个批次。
  ///
  /// 只有「纯新增、未改动已有词条」的批次可以无损撤销；且批次内词条
  /// 一旦有复习日志或错词记录，撤销会破坏历史聚合，必须拒绝。
  Future<void> rollback({required int batchId, required int now}) async {
    if (batchId <= 0) {
      throw const ValidationError(AppErrorCode.importBatchIdInvalid);
    }
    await _db.transaction(() => _rollback(batchId, now));
  }

  /// 列出最近的批次。
  Future<List<ImportBatchSummary>> recentBatches() async {
    final query = _db.select(_db.importBatches)
      ..orderBy(<OrderClauseGenerator<$ImportBatchesTable>>[
        (table) => OrderingTerm.desc(table.createdAt),
        (table) => OrderingTerm.desc(table.id),
      ])
      ..limit(recentImportBatchLimit);
    final rows = await query.get();
    return rows.map(_toBatchSummary).toList(growable: false);
  }

  /// 分页列出某个批次的行。
  Future<List<ImportRowSummary>> batchRows(
    int batchId, {
    required int limit,
    required int offset,
  }) async {
    if (batchId <= 0) {
      throw const ValidationError(AppErrorCode.importBatchIdInvalid);
    }
    final query = _db.select(_db.importRows)
      ..where((table) => table.importBatchId.equals(batchId))
      ..orderBy(<OrderClauseGenerator<$ImportRowsTable>>[
        (table) => OrderingTerm.asc(table.rowNumber),
      ])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return rows.map(_toRowSummary).toList(growable: false);
  }

  /// 清理过期的未提交预览，返回删除的批次数。
  ///
  /// 只删 [ImportBatchStatus.pending] 的批次：已提交批次是审计记录，
  /// 过期与否都要保留，否则导入历史会凭空少几条。
  Future<int> purgeExpiredPreviews(int now) async {
    final cutoff = now - importBatchExpiryMs;
    final query = _db.delete(_db.importBatches)
      ..where(
        (table) =>
            table.status.equalsValue(ImportBatchStatus.pending) &
            table.createdAt.isSmallerThanValue(cutoff),
      );
    return await query.go();
  }

  // ── 预览 ──

  Future<_PickedCsv?> _pickCsvFile() async {
    // file_picker 13.x 起直接返回文件列表，空列表即用户取消。
    final files = await FilePickerPlatform.instance.pickFiles(
      dialogTitle: '选择 EasyDict CSV 文件',
      type: FileType.custom,
      allowedExtensions: <String>['csv'],
    );
    if (files.isEmpty) return null;

    final picked = files.first;
    if (picked.extension?.toLowerCase() != 'csv') {
      throw const ValidationError(
        AppErrorCode.csvTypeInvalid,
        details: '仅支持 .csv 文件',
      );
    }
    // 用 PlatformFile.readAsBytes 而不是 File(path)：Android 上
    // 选择器返回的 content:// 没有本地路径，只有字节流是可靠的。
    return _PickedCsv(picked.name, _decodeCsv(await picked.readAsBytes()));
  }

  String _decodeCsv(Uint8List bytes) {
    if (bytes.length > maxCsvBytes) {
      throw ValidationError(
        AppErrorCode.csvTooLarge,
        details: '文件 ${bytes.length} 字节，上限 $maxCsvBytes',
      );
    }
    try {
      final content = utf8.decode(bytes);
      return content.startsWith('\uFEFF') ? content.substring(1) : content;
    } on FormatException catch (error) {
      throw ValidationError(
        AppErrorCode.csvEncodingInvalid,
        details: error.message,
      );
    }
  }

  /// 标出与库中已有词条重复的行。
  Future<List<ParsedCsvRow>> _annotateExisting(
    List<ParsedCsvRow> rows, {
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    final existing = await _existingWordIds(sourceLanguage, targetLanguage);
    if (existing.isEmpty) return rows;
    return List<ParsedCsvRow>.unmodifiable(
      rows.map((row) {
        if (row.status != ImportRowStatus.newWord) return row;
        final key = identityKey(
          row.normalizedTerm,
          sourceLanguage,
          targetLanguage,
        );
        return existing.containsKey(key)
            ? row.copyWithStatus(ImportRowStatus.existing)
            : row;
      }),
    );
  }

  /// 一次读回该语言方向下的全部词条身份。
  ///
  /// 逐行 `SELECT` 会让两万行的预览跑两万次查询；按语言方向整体取回
  /// 只需一次扫描，身份键在内存里比对。
  Future<Map<String, int>> _existingWordIds(
    String sourceLanguage,
    String targetLanguage,
  ) async {
    final query = _db.select(_db.words)
      ..where(
        (table) =>
            table.sourceLanguage.equals(sourceLanguage) &
            table.targetLanguage.equals(targetLanguage),
      );
    final rows = await query.get();
    return <String, int>{
      for (final row in rows)
        identityKey(row.normalizedTerm, row.sourceLanguage, row.targetLanguage):
            row.id,
    };
  }

  Future<int> _insertBatch(String filename, List<ParsedCsvRow> rows, int now) {
    // 预览阶段的 import_mode 只是占位：真正的模式在 commit 时写入。
    // 列非空且无默认值，不得不给一个值。
    return _db
        .into(_db.importBatches)
        .insert(
          ImportBatchesCompanion.insert(
            filename: filename,
            importMode: ImportMode.skipExisting,
            status: const Value(ImportBatchStatus.pending),
            totalRows: Value(rows.length),
            validRows: Value(rows.where((row) => row.isValid).length),
            invalidRows: Value(_countStatus(rows, ImportRowStatus.invalid)),
            duplicateRows: Value(_countStatus(rows, ImportRowStatus.duplicate)),
            createdAt: now,
          ),
        );
  }

  Future<void> _insertPreviewRows(
    int batchId,
    List<ParsedCsvRow> rows,
    int now,
  ) async {
    for (final chunk in _chunks(rows)) {
      await _db.batch((batch) {
        for (final row in chunk) {
          batch.insert(
            _db.importRows,
            ImportRowsCompanion.insert(
              importBatchId: batchId,
              rowNumber: row.rowNumber,
              status: row.status,
              rawJson: Value(jsonEncode(row.toJson())),
              normalizedTerm: Value(
                row.normalizedTerm.isEmpty ? null : row.normalizedTerm,
              ),
              errorCode: Value(row.errorCode?.code),
              errorMessage: Value(row.errorMessage),
              createdAt: now,
            ),
          );
        }
      });
    }
  }

  // ── 提交 ──

  Future<ImportCommitResult> _commit({
    required int batchId,
    required ImportMode mode,
    required bool resetLearningProgress,
    required int now,
  }) async {
    final batch = await _requirePendingBatch(batchId, now);
    final inputs = await _loadRowInputs(batchId);
    final languages = _languagesOf(inputs);
    final counters = _CommitCounters();

    if (languages != null) {
      await _commitRows(
        inputs,
        mode: mode,
        resetLearningProgress: resetLearningProgress,
        languages: languages,
        counters: counters,
        now: now,
      );
    }

    await _finishBatch(
      batchId: batch.id,
      mode: mode,
      resetLearningProgress: resetLearningProgress,
      counters: counters,
      now: now,
    );
    return ImportCommitResult(
      batchId: batch.id,
      created: counters.created,
      existing: counters.existing,
      duplicate: counters.duplicate,
      invalid: counters.invalid,
      failed: counters.failed,
      queuedInitializations: counters.queued,
    );
  }

  Future<void> _commitRows(
    List<_RowInput> inputs, {
    required ImportMode mode,
    required bool resetLearningProgress,
    required _LanguagePair languages,
    required _CommitCounters counters,
    required int now,
  }) async {
    final existing = await _existingWordIds(languages.source, languages.target);
    final contents = await _existingContents(existing.values);
    final providers = await _requestedProvidersJson();

    for (final chunk in _chunks(inputs)) {
      final outcomes = <_RowOutcome>[];
      for (final input in chunk) {
        outcomes.add(
          await _applyRow(
            input,
            mode: mode,
            resetLearningProgress: resetLearningProgress,
            existing: existing,
            contents: contents,
            providers: providers,
            counters: counters,
            now: now,
          ),
        );
      }
      await _flush(outcomes);
    }
  }

  /// 处理一行，返回需要在批次里落地的写入。
  ///
  /// 新词条的 `words` 行**必须立刻插入**：`word_contents` 与
  /// `initialization_jobs` 都要它的自增 ID。其余写入合并成批，
  /// 按 [sqlBatchChunkSize] 分块执行。
  Future<_RowOutcome> _applyRow(
    _RowInput input, {
    required ImportMode mode,
    required bool resetLearningProgress,
    required Map<String, int> existing,
    required Map<int, WordContentRow> contents,
    required String? providers,
    required _CommitCounters counters,
    required int now,
  }) async {
    final row = input.row;
    if (row == null) return _corruptOutcome(input, counters);

    final skipped = _skippedOutcome(input, counters);
    if (skipped != null) return skipped;

    final wordId = existing[_rowKey(row)];
    if (wordId == null) {
      return await _createWord(input, row, providers, counters, now);
    }
    return _updateWord(
      input,
      row,
      wordId: wordId,
      current: contents[wordId],
      mode: mode,
      resetLearningProgress: resetLearningProgress,
      counters: counters,
      now: now,
    );
  }

  /// `raw_json` 无法还原的行：留痕为 `ERROR` 而不是静默跳过。
  _RowOutcome _corruptOutcome(_RowInput input, _CommitCounters counters) {
    counters.failed += 1;
    return _RowOutcome(
      rowId: input.rowId,
      status: ImportRowStatus.error,
      errorCode: AppErrorCode.validationError,
      errorMessage: '该行数据已损坏，无法提交。',
    );
  }

  /// 非法行与重复行的终态；其余行返回 `null` 表示需要继续处理。
  _RowOutcome? _skippedOutcome(_RowInput input, _CommitCounters counters) {
    return switch (input.status) {
      ImportRowStatus.invalid => _countInvalid(input, counters),
      ImportRowStatus.duplicate => _countDuplicate(input, counters),
      _ => null,
    };
  }

  _RowOutcome _countInvalid(_RowInput input, _CommitCounters counters) {
    counters.invalid += 1;
    return _RowOutcome(rowId: input.rowId, status: ImportRowStatus.invalid);
  }

  _RowOutcome _countDuplicate(_RowInput input, _CommitCounters counters) {
    counters.duplicate += 1;
    return _RowOutcome(rowId: input.rowId, status: ImportRowStatus.duplicate);
  }

  Future<_RowOutcome> _createWord(
    _RowInput input,
    ParsedCsvRow row,
    String? providers,
    _CommitCounters counters,
    int now,
  ) async {
    final wordId = await _db
        .into(_db.words)
        .insert(
          WordsCompanion.insert(
            term: row.term,
            normalizedTerm: row.normalizedTerm,
            sourceLanguage: row.sourceLanguage,
            targetLanguage: row.targetLanguage,
            entryType: entryTypeFor(row.contentType),
            contentType: Value(row.contentType),
            initializationStatus: const Value(InitializationStatus.queued),
            createdAt: now,
            updatedAt: now,
          ),
        );
    counters
      ..created += 1
      ..queued += 1;
    return _RowOutcome(
      rowId: input.rowId,
      status: ImportRowStatus.imported,
      wordId: wordId,
      contents: _contentCompanion(
        contentColumnsFromRow(row, targetLanguage: row.targetLanguage),
        wordId: wordId,
        now: now,
      ),
      insertContents: true,
      job: _jobCompanion(wordId, providers, now),
    );
  }

  _RowOutcome _updateWord(
    _RowInput input,
    ParsedCsvRow row, {
    required int wordId,
    required WordContentRow? current,
    required ImportMode mode,
    required bool resetLearningProgress,
    required _CommitCounters counters,
    required int now,
  }) {
    counters.existing += 1;
    final resetAt = _resetAtFor(mode, resetLearningProgress, now);
    if (mode == ImportMode.skipExisting) {
      return _existingOutcome(input, wordId: wordId);
    }

    final merged = _mergeColumns(row, current, mode: mode);
    if (merged.isEmpty) {
      return _existingOutcome(input, wordId: wordId, resetProgressAt: resetAt);
    }
    return _RowOutcome(
      rowId: input.rowId,
      status: ImportRowStatus.existing,
      wordId: wordId,
      contents: _contentCompanion(
        merged,
        now: now,
        version: current == null ? null : current.contentVersion + 1,
      ),
      insertContents: current == null,
      resetProgressAt: resetAt,
    );
  }

  /// 只登记「这一行命中了已有词条」，不写任何内容。
  _RowOutcome _existingOutcome(
    _RowInput input, {
    required int wordId,
    int? resetProgressAt,
  }) {
    return _RowOutcome(
      rowId: input.rowId,
      status: ImportRowStatus.existing,
      wordId: wordId,
      resetProgressAt: resetProgressAt,
    );
  }

  /// 本行是否需要重置学习进度，返回重置时间戳或 `null`。
  ///
  /// **与旧版 `imports/commit.ts:92-96` 的唯一差别**：旧版在
  /// `SKIP_EXISTING` 模式下也会重置，但那一整个分支的语义是「已有的词条
  /// 完全不动」。保留旧行为会让用户在「仅新增 + 重置进度」时看到一批毫无
  /// 关联的词条进度被清空，且撤销检查还会因为 `import_mode` 不符而拒绝。
  static int? _resetAtFor(ImportMode mode, bool requested, int now) =>
      resetAtFor(mode, requested: requested, now: now);

  /// 按 [ImportMode] 计算要写入的列。
  ///
  /// - `FILL_MISSING`：只写「当前为空」的列（见 [isContentColumnMissing]）；
  /// - `FORCE_DICTIONARY_REFRESH`：CSV 提供了的列一律覆盖；
  /// - `SKIP_EXISTING`：不进入本函数。
  ///
  /// 两种模式下 CSV 的空单元格都不会清空已有内容——用户导入的是一份
  /// 不完整的词典，用它抹掉 AI 补齐的释义是不可逆的损失。
  Map<String, String> _mergeColumns(
    ParsedCsvRow row,
    WordContentRow? current, {
    required ImportMode mode,
  }) {
    final payload = contentColumnsFromRow(
      row,
      targetLanguage: row.targetLanguage,
    );
    final currentColumns = current == null
        ? const <String, String>{}
        : _columnsOf(current);
    final result = <String, String>{};
    for (final entry in payload.entries) {
      if (mode == ImportMode.forceDictionaryRefresh) {
        result[entry.key] = entry.value;
        continue;
      }
      final missing = isContentColumnMissing(
        entry.key,
        currentColumns[entry.key],
        targetLanguage: row.targetLanguage,
      );
      if (missing) result[entry.key] = entry.value;
    }
    return result;
  }

  /// 把一批行的写入合并成批执行。
  ///
  /// 分块的意义：`word_contents` 每行 11 个 JSON 列，两万行一次性提交会
  /// 撑爆 SQLite 的绑定变量上限（保守值 [sqlBatchChunkSize]）。
  Future<void> _flush(List<_RowOutcome> outcomes) async {
    await _db.batch((batch) {
      for (final outcome in outcomes) {
        _writeOutcome(batch, outcome);
      }
    });
  }

  void _writeOutcome(Batch batch, _RowOutcome outcome) {
    batch.update(
      _db.importRows,
      ImportRowsCompanion(
        status: Value(outcome.status),
        wordId: Value(outcome.wordId),
        errorCode: _present(outcome.errorCode?.code),
        errorMessage: _present(outcome.errorMessage),
      ),
      where: (table) => table.id.equals(outcome.rowId),
    );
    final contents = outcome.contents;
    if (contents != null) {
      if (outcome.insertContents) {
        batch.insert(_db.wordContents, contents);
      } else {
        batch.update(
          _db.wordContents,
          contents,
          where: (table) => table.wordId.equals(outcome.wordId ?? 0),
        );
      }
    }
    final job = outcome.job;
    if (job != null) batch.insert(_db.initializationJobs, job);

    final resetAt = outcome.resetProgressAt;
    final wordId = outcome.wordId;
    if (resetAt != null && wordId != null) {
      _writeProgressReset(batch, wordId: wordId, now: resetAt);
    }
  }

  /// 清空一个**已有**词条的学习进度。
  ///
  /// 实现见 [writeProgressReset]（与文章导入共用同一份语句表）。
  void _writeProgressReset(
    Batch batch, {
    required int wordId,
    required int now,
  }) {
    writeProgressReset(batch, db: _db, wordId: wordId, now: now);
  }

  Future<void> _finishBatch({
    required int batchId,
    required ImportMode mode,
    required bool resetLearningProgress,
    required _CommitCounters counters,
    required int now,
  }) async {
    final query = _db.update(_db.importBatches)
      ..where((table) => table.id.equals(batchId));
    await query.write(
      ImportBatchesCompanion(
        importMode: Value(mode),
        // 必须落库：`rollback` 的静态资格检查会读这一列，否则一个重置过
        // 学习进度的批次会被当成可无损撤销，把已经删掉的历史算作「无副作用」。
        resetLearningProgress: Value(resetLearningProgress),
        status: const Value(ImportBatchStatus.committed),
        createdWords: Value(counters.created),
        existingWords: Value(counters.existing),
        queuedInitializations: Value(counters.queued),
        completedAt: Value(now),
      ),
    );
  }

  // ── 撤销 ──

  Future<void> _rollback(int batchId, int now) async {
    final batch = await _requireBatch(batchId);
    if (batch.status != ImportBatchStatus.committed) {
      throw ValidationError(
        AppErrorCode.importBatchNotRollbackable,
        details: '批次状态为 ${batch.status.wire}',
      );
    }
    final wordIds = await _importedWordIds(batchId);
    _assertStaticEligibility(batch);
    if (wordIds.isEmpty) {
      await _markRolledBack(batchId, now);
      return;
    }

    final hard = await _blockedTerms(wordIds, batchId: batchId, hard: true);
    if (hard.isNotEmpty) {
      throw ValidationError(
        AppErrorCode.importBatchNotRollbackable,
        details: hard,
      );
    }
    final soft = await _blockedTerms(wordIds, batchId: batchId, hard: false);
    if (soft.isNotEmpty) {
      throw ConflictError(
        AppErrorCode.importBatchHasDependencies,
        details: soft,
      );
    }

    await _deleteWords(wordIds);
    await _markRolledBack(batchId, now);
  }

  /// 静态条件：只有纯新增、未重置学习进度、未改动已有词条的批次可撤销。
  void _assertStaticEligibility(ImportBatchRow batch) {
    final eligible =
        batch.importMode == ImportMode.skipExisting &&
        !batch.resetLearningProgress &&
        batch.existingWords == 0;
    if (!eligible) {
      throw const ValidationError(
        AppErrorCode.importBatchNotRollbackable,
        details: '该批次改动过已有词条或重置过学习进度',
      );
    }
  }

  /// 找出阻碍撤销的词条文本。
  ///
  /// [hard] 为真时查「复习日志 / 错词记录」，为假时查「会话引用 /
  /// 后续批次引用」。分两趟是为了给出不同的错误码：前者是学习历史
  /// （不可逆），后者是引用关系（换个批次再撤销可能就通过了）。
  Future<List<String>> _blockedTerms(
    List<int> wordIds, {
    required int batchId,
    required bool hard,
  }) async {
    final condition = hard ? _hardDependencySql : _softDependencySql;

    final blocked = <String>[];
    for (final chunk in _chunks(wordIds)) {
      final placeholders = _placeholders(chunk.length);
      final variables = <Variable<Object>>[
        for (final id in chunk) Variable<int>(id),
        if (!hard) Variable<int>(batchId),
        const Variable<int>(rollbackBlockedTermLimit),
      ];
      final rows = await _db
          .customSelect(
            'SELECT w.term FROM words w '
            'WHERE w.id IN ($placeholders) AND $condition '
            'ORDER BY w.id LIMIT ?',
            variables: variables,
          )
          .get();
      blocked.addAll(rows.map((row) => row.read<String>('term')));
      if (blocked.length >= rollbackBlockedTermLimit) break;
    }
    return blocked;
  }

  Future<List<int>> _importedWordIds(int batchId) async {
    final query = _db.select(_db.importRows)
      ..where(
        (table) =>
            table.importBatchId.equals(batchId) &
            table.status.equalsValue(ImportRowStatus.imported) &
            table.wordId.isNotNull(),
      );
    final rows = await query.get();
    return rows
        .map((row) => row.wordId)
        .whereType<int>()
        .toList(growable: false);
  }

  Future<void> _deleteWords(List<int> wordIds) async {
    for (final chunk in _chunks(wordIds)) {
      final query = _db.delete(_db.words)
        ..where((table) => table.id.isIn(chunk));
      await query.go();
    }
  }

  Future<void> _markRolledBack(int batchId, int now) async {
    final query = _db.update(_db.importBatches)
      ..where((table) => table.id.equals(batchId));
    await query.write(
      ImportBatchesCompanion(
        status: const Value(ImportBatchStatus.rolledBack),
        rolledBackAt: Value(now),
      ),
    );
  }

  // ── 公共查询 ──

  Future<ImportBatchRow> _requireBatch(int batchId) async {
    final query = _db.select(_db.importBatches)
      ..where((table) => table.id.equals(batchId));
    final row = await query.getSingleOrNull();
    if (row == null) {
      throw const NotFoundError(AppErrorCode.notFound, details: '导入批次不存在');
    }
    return row;
  }

  Future<ImportBatchRow> _requirePendingBatch(int batchId, int now) async {
    final batch = await _requireBatch(batchId);
    if (batch.status != ImportBatchStatus.pending) {
      throw ValidationError(
        AppErrorCode.importPreviewExpired,
        details: '批次状态为 ${batch.status.wire}',
      );
    }
    if (batch.createdAt + importPreviewTtlMs < now) {
      throw const ValidationError(
        AppErrorCode.importPreviewExpired,
        details: '预览已超过有效期',
      );
    }
    return batch;
  }

  Future<List<_RowInput>> _loadRowInputs(int batchId) async {
    final query = _db.select(_db.importRows)
      ..where((table) => table.importBatchId.equals(batchId))
      ..orderBy(<OrderClauseGenerator<$ImportRowsTable>>[
        (table) => OrderingTerm.asc(table.rowNumber),
      ]);
    final rows = await query.get();
    return rows.map(_toRowInput).toList(growable: false);
  }

  _RowInput _toRowInput(ImportRowRow record) {
    return _RowInput(
      rowId: record.id,
      status: record.status,
      row: _decodeRow(record.rawJson),
    );
  }

  ParsedCsvRow? _decodeRow(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      return decoded is Map<String, Object?>
          ? ParsedCsvRow.fromJson(decoded)
          : null;
    } on FormatException {
      // 行数据损坏时返回 null，由调用方标为 ERROR——
      // 一行坏 JSON 不该让整批提交失败。
      return null;
    }
  }

  /// 取语言方向：所有行的语言来自同一批次，取第一行的即可。
  ///
  /// 用私有类而不是 Dart 记录：记录的取值器是 `$1` / `$2`，
  /// 而 `$2` 里的裸数字会被架构守卫的魔法数字检查拦下。
  _LanguagePair? _languagesOf(List<_RowInput> inputs) {
    for (final input in inputs) {
      final row = input.row;
      if (row == null) continue;
      if (row.sourceLanguage.isEmpty || row.targetLanguage.isEmpty) continue;
      return _LanguagePair(row.sourceLanguage, row.targetLanguage);
    }
    return null;
  }

  Future<Map<int, WordContentRow>> _existingContents(
    Iterable<int> wordIds,
  ) async {
    final ids = wordIds.toList(growable: false);
    final result = <int, WordContentRow>{};
    for (final chunk in _chunks(ids)) {
      final query = _db.select(_db.wordContents)
        ..where((table) => table.wordId.isIn(chunk));
      for (final row in await query.get()) {
        result[row.wordId] = row;
      }
    }
    return result;
  }

  Future<String?> _requestedProvidersJson() async {
    final settings = await _settings.load();
    final ids = enabledProviderIds(settings.providers);
    return ids.isEmpty ? null : jsonEncode(ids);
  }

  /// 词条唯一性键。
  ///
  /// 必须与 `parseEasyDictCsv` 的批次内去重走**同一个**函数，
  /// 否则会出现「预览说重复、提交却新增」的错位。
  String _rowKey(ParsedCsvRow row) =>
      identityKey(row.normalizedTerm, row.sourceLanguage, row.targetLanguage);

  /// 把内容行的 JSON 列读成「列 → 文本」，与 CSV 载荷逐列比对。
  Map<String, String> _columnsOf(WordContentRow row) => <String, String>{
    ContentColumns.definitions: row.definitionsJson,
    ContentColumns.pronunciations: row.pronunciationsJson,
    ContentColumns.examples: row.examplesJson,
    ContentColumns.phrases: row.phrasesJson,
    ContentColumns.synonyms: row.synonymsJson,
    ContentColumns.antonyms: row.antonymsJson,
    ContentColumns.wordFamily: row.wordFamilyJson,
    ContentColumns.confusedWords: row.confusedWordsJson,
    ContentColumns.roots: row.rootsJson,
    ContentColumns.affixes: row.affixesJson,
    ContentColumns.tags: row.tagsJson,
  };

  WordContentsCompanion _contentCompanion(
    Map<String, String> values, {
    required int now,
    int? wordId,
    int? version,
  }) {
    return WordContentsCompanion(
      wordId: wordId == null ? const Value.absent() : Value(wordId),
      definitionsJson: _jsonValue(values, ContentColumns.definitions),
      pronunciationsJson: _jsonValue(values, ContentColumns.pronunciations),
      examplesJson: _jsonValue(values, ContentColumns.examples),
      phrasesJson: _jsonValue(values, ContentColumns.phrases),
      synonymsJson: _jsonValue(values, ContentColumns.synonyms),
      antonymsJson: _jsonValue(values, ContentColumns.antonyms),
      wordFamilyJson: _jsonValue(values, ContentColumns.wordFamily),
      confusedWordsJson: _jsonValue(values, ContentColumns.confusedWords),
      rootsJson: _jsonValue(values, ContentColumns.roots),
      affixesJson: _jsonValue(values, ContentColumns.affixes),
      tagsJson: _jsonValue(values, ContentColumns.tags),
      contentSource: wordId == null
          ? const Value.absent()
          : const Value(ContentSource.dictionaryOnly),
      contentVersion: version == null ? const Value.absent() : Value(version),
      updatedAt: Value(now),
    );
  }

  InitializationJobsCompanion _jobCompanion(
    int wordId,
    String? providers,
    int now,
  ) {
    return InitializationJobsCompanion.insert(
      wordId: wordId,
      // 新词条已经有 CSV 内容，任务只需补齐缺失字段。
      mode: InitializationMode.fillMissingFields,
      requestedProvidersJson: Value(providers),
      status: const Value(InitializationStatus.queued),
      priority: const Value(jobPriorityManualBulk),
      maxAttempts: const Value(importJobMaxAttempts),
      availableAt: Value(now),
      createdAt: now,
      updatedAt: now,
    );
  }

  ImportBatchSummary _toBatchSummary(ImportBatchRow row) => ImportBatchSummary(
    id: row.id,
    filename: row.filename,
    status: row.status,
    importMode: row.importMode,
    totalRows: row.totalRows,
    validRows: row.validRows,
    invalidRows: row.invalidRows,
    duplicateRows: row.duplicateRows,
    createdWords: row.createdWords,
    existingWords: row.existingWords,
    queuedInitializations: row.queuedInitializations,
    createdAt: row.createdAt,
    resetLearningProgress: row.resetLearningProgress,
    completedAt: row.completedAt,
    rolledBackAt: row.rolledBackAt,
  );

  ImportRowSummary _toRowSummary(ImportRowRow row) => ImportRowSummary(
    id: row.id,
    rowNumber: row.rowNumber,
    term: _decodeRow(row.rawJson)?.term ?? row.normalizedTerm ?? '',
    status: row.status,
    errorMessage: row.errorMessage,
    wordId: row.wordId,
  );
}

/// 撤销时的硬依赖：词条已有复习日志或错词记录。
const String _hardDependencySql =
    '(EXISTS (SELECT 1 FROM review_logs r WHERE r.word_id = w.id) '
    'OR EXISTS (SELECT 1 FROM wrong_word_states s WHERE s.word_id = w.id '
    'AND (s.active = 1 OR s.wrong_count > 0)))';

/// 撤销时的软依赖：词条已进入会话，或被后续批次引用。
const String _softDependencySql =
    '(EXISTS (SELECT 1 FROM study_session_items i WHERE i.word_id = w.id) '
    'OR EXISTS (SELECT 1 FROM import_rows ir WHERE ir.word_id = w.id '
    'AND ir.import_batch_id <> ?))';

/// `null` 表示「不改动该列」。
///
/// 非法行的原因在预览时就写好了，提交时不能因为处理结果里没有原因就抹掉它。
Value<String> _present(String? value) =>
    value == null ? const Value.absent() : Value(value);

Value<String> _jsonValue(Map<String, String> values, String column) {
  final value = values[column];
  return value == null ? const Value.absent() : Value(value);
}

int _countStatus(List<ParsedCsvRow> rows, ImportRowStatus status) =>
    rows.where((row) => row.status == status).length;

/// 生成 `?, ?, ?` 占位符。
String _placeholders(int count) => List<String>.filled(count, '?').join(', ');

/// 按 [sqlBatchChunkSize] 切分，避免超过 SQLite 的绑定变量上限。
Iterable<List<T>> _chunks<T>(List<T> items) sync* {
  for (var start = 0; start < items.length; start += sqlBatchChunkSize) {
    final end = start + sqlBatchChunkSize;
    yield items.sublist(start, end > items.length ? items.length : end);
  }
}

/// 批次的词条语言方向。
class _LanguagePair {
  const new(this.source, this.target);

  final String source;
  final String target;
}

/// 选中的 CSV 文件。
class _PickedCsv {
  const new(this.name, this.content);

  final String name;
  final String content;
}

/// 从 `import_rows` 还原出的一行输入。
class _RowInput {
  const new({required this.rowId, required this.status, required this.row});

  final int rowId;
  final ImportRowStatus status;
  final ParsedCsvRow? row;
}

/// 一行的处理结果（待落地的写入）。
class _RowOutcome {
  const new({
    required this.rowId,
    required this.status,
    this.wordId,
    this.errorCode,
    this.errorMessage,
    this.contents,
    this.insertContents = false,
    this.job,
    this.resetProgressAt,
  });

  final int rowId;
  final ImportRowStatus status;
  final int? wordId;
  final AppErrorCode? errorCode;
  final String? errorMessage;
  final WordContentsCompanion? contents;
  final bool insertContents;
  final InitializationJobsCompanion? job;

  /// 非空表示这一行要连带清空 [wordId] 的学习进度，值即重置时间戳。
  ///
  /// 只对**命中已有词条**的行设置：新增词条本就没有进度可清。
  final int? resetProgressAt;
}

/// 提交过程的计数器。
class _CommitCounters {
  int created = 0;
  int existing = 0;
  int duplicate = 0;
  int invalid = 0;
  int failed = 0;
  int queued = 0;
}
