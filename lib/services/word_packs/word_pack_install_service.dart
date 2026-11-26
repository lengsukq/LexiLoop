/// 词书包安装、安全卸载与按需有道补全服务。
///
/// 核心不变量：
/// 1. 同一词条在 `words` 中全局唯一，共享 FSRS 学习进度；
/// 2. 安装词书绝不覆盖用户的 `is_personal = 1`、用户笔记或手改释义；
/// 3. 卸载词书绝不删除个人词条或其他已装词书共享的词条；
///    仅属于本词书但已有学习记录的词条默认自动升格为个人词条，保留全部记忆。
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/content_normalize.dart';
import 'package:lexiloop/data/dictionary/providers/youdao_fields.dart';
import 'package:lexiloop/data/word_packs/pack_gzip.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/domain/text/normalizer.dart';
import 'package:lexiloop/services/dictionary/merge.dart';
import 'package:lexiloop/services/initialization/initialization_models.dart';
import 'package:lexiloop/services/initialization/initialization_queries.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

/// 词书包入库进度回调。
typedef WordPackImportProgressCallback = void Function(
  int processed,
  int total,
);

/// 词书包安装结果。
class WordPackInstallResult {
  /// 以词书元数据与入库分项计数构造。
  const new({
    required this.packId,
    required this.packName,
    required this.totalEntries,
    required this.createdWords,
    required this.linkedExistingWords,
    required this.backfilledWords,
  });

  /// 词书 ID。
  final String packId;

  /// 词书名称。
  final String packName;

  /// 本次处理的词书总条目数。
  final int totalEntries;

  /// 新建的词书词条数（`is_personal = 0`）。
  final int createdWords;

  /// 复用既有词条数（个人词库或其他词书中已存在，保留原归属与进度）。
  final int linkedExistingWords;

  /// 为既有未初始化词条顺带补齐内容的条数。
  final int backfilledWords;
}

/// 词书包卸载结果。
class WordPackUninstallResult {
  /// 以卸载清理明细构造。
  const new({
    required this.packId,
    required this.removedWords,
    required this.promotedToPersonalWords,
    required this.keptPersonalOrSharedWords,
  });

  /// 词书 ID。
  final String packId;

  /// 已清理的词条数。
  final int removedWords;

  /// 因已有学习记录而自动升格为个人词条的数量。
  final int promotedToPersonalWords;

  /// 保持原样的个人词或其他词书共享词数量。
  final int keptPersonalOrSharedWords;
}

/// 写入/更新词书包元信息的 SQL。
const String _upsertPackMetaSql = '''
INSERT INTO word_packs (
  id, slug, name, category, description, version, content_mode,
  word_count, include_in_daily_study, sha256, source_url,
  installed_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  slug = excluded.slug,
  name = excluded.name,
  category = excluded.category,
  description = excluded.description,
  version = excluded.version,
  content_mode = excluded.content_mode,
  word_count = excluded.word_count,
  include_in_daily_study = excluded.include_in_daily_study,
  sha256 = excluded.sha256,
  source_url = excluded.source_url,
  updated_at = excluded.updated_at''';

/// 词书包安装、卸载与有道按需补全编排服务。
class WordPackInstallService {
  /// 以数据库与设置服务构造。
  new(this._db, SettingsService settings)
    : _dao = WordPackDao(_db),
      _initQueries = InitializationQueries(_db, settings);

  final AppDatabase _db;
  final WordPackDao _dao;
  final InitializationQueries _initQueries;

  /// 从压缩/明文字节解码并安装词书包（解码在后台 Isolate 中执行）。
  Future<WordPackInstallResult> installFromBytes({
    required Uint8List bytes,
    required int now,
    bool includeInDailyStudy = false,
    String? sourceUrl,
    WordPackImportProgressCallback? onProgress,
  }) async {
    final shaHex = sha256.convert(bytes).toString().toLowerCase();
    final payload = await _decodePayload(bytes);
    return await installPayload(
      payload: payload,
      now: now,
      includeInDailyStudy: includeInDailyStudy,
      sha256Hex: shaHex,
      sourceUrl: sourceUrl,
      onProgress: onProgress,
    );
  }

  /// 将已解析的词书包载荷分批写入数据库（幂等，支持覆盖更新同版本/新版本）。
  Future<WordPackInstallResult> installPayload({
    required WordPackPayload payload,
    required int now,
    bool includeInDailyStudy = false,
    String sha256Hex = '',
    String? sourceUrl,
    WordPackImportProgressCallback? onProgress,
  }) async {
    await _upsertPackMeta(
      payload: payload,
      now: now,
      includeInDailyStudy: includeInDailyStudy,
      sha256Hex: sha256Hex,
      sourceUrl: sourceUrl,
    );
    final existingIds = await _loadExistingWordMap();
    final counters = _InstallCounters();
    final entries = payload.entries;
    for (
      var start = 0;
      start < entries.length;
      start += wordPackImportBatchSize
    ) {
      final end = math.min(start + wordPackImportBatchSize, entries.length);
      await _installBatch(
        packId: payload.id,
        mode: payload.contentMode,
        batch: entries.sublist(start, end),
        existingIds: existingIds,
        counters: counters,
        now: now,
      );
      onProgress?.call(end, entries.length);
    }
    return WordPackInstallResult(
      packId: payload.id,
      packName: payload.name,
      totalEntries: entries.length,
      createdWords: counters.created,
      linkedExistingWords: counters.linked,
      backfilledWords: counters.backfilled,
    );
  }

  /// 安全卸载词书包。
  ///
  /// [keepLearnedAsPersonal] 为 `true`（默认）时，仅属于本词书但已有复习记录
  /// 的词条自动升格为 `is_personal = 1`，完整保留 FSRS 记忆曲线；为 `false`
  /// 时一并移除孤立词书词条（仍绝不触碰个人词与其他词书共享词）。
  Future<WordPackUninstallResult> uninstallPack({
    required String packId,
    required int now,
    bool keepLearnedAsPersonal = true,
  }) async {
    final impact = await _dao.inspectUninstallImpact(packId);
    if (impact == null) {
      throw const NotFoundError(AppErrorCode.wordPackNotFound);
    }
    return await _db.transaction(() async {
      await _db.customStatement(
        'DELETE FROM word_packs WHERE id = ?',
        <Object?>[packId],
      );
      final promoted = keepLearnedAsPersonal
          ? await _promoteLearnedOrphans(now)
          : 0;
      final removed = await _deleteRemainingOrphans(
        includeLearned: !keepLearnedAsPersonal,
      );
      return WordPackUninstallResult(
        packId: packId,
        removedWords: removed,
        promotedToPersonalWords: promoted,
        keptPersonalOrSharedWords:
            impact.personalKeptCount + impact.sharedOtherPackCount,
      );
    });
  }

  /// 按需优先有道补全：仅将词书内即将学习的下一批未完整词条排入有道队列。
  Future<int> enqueueLazyEnrichment({
    required String packId,
    required int now,
    int limit = wordPackLazyEnrichBatchSize,
  }) => _enqueuePackYoudao(
    packId: packId,
    limit: limit,
    priority: wordPackLazyEnrichPriority,
    now: now,
  );

  /// 将词书内全部尚未 `READY` 的词条排入有道后台补全队列。
  Future<int> enqueueFullYoudaoEnrichment({
    required String packId,
    required int now,
  }) => _enqueuePackYoudao(
    packId: packId,
    limit: maxCsvRows,
    priority: wordPackFullEnrichPriority,
    now: now,
  );

  Future<int> _enqueuePackYoudao({
    required String packId,
    required int limit,
    required int priority,
    required int now,
  }) async {
    final wordIds = await _dao.findEnrichableWordIds(packId, limit: limit);
    if (wordIds.isEmpty) return 0;
    final requests = <EnqueueRequest>[
      for (final wordId in wordIds)
        EnqueueRequest(
          wordId: wordId,
          taskType: JobTaskType.initialize,
          mode: InitializationMode.fillMissingFields,
          requestedProviders: const <String>[youdaoDictionarySource],
          priority: priority,
        ),
    ];
    final report = await _initQueries.enqueueBulkReport(requests, now: now);
    return report.jobCount;
  }

  Future<WordPackPayload> _decodePayload(Uint8List bytes) {
    if (bytes.length < wordPackIsolateThresholdBytes) {
      return Future<WordPackPayload>.value(
        WordPackPayload.parse(decodeWordPackBytes(bytes)),
      );
    }
    return Isolate.run<WordPackPayload>(
      () => WordPackPayload.parse(decodeWordPackBytes(bytes)),
    );
  }

  Future<void> _upsertPackMeta({
    required WordPackPayload payload,
    required int now,
    required bool includeInDailyStudy,
    required String sha256Hex,
    required String? sourceUrl,
  }) async {
    await _db.transaction(() async {
      await _db.customStatement(_upsertPackMetaSql, <Object?>[
        payload.id,
        payload.slug,
        payload.name,
        payload.category.wire,
        payload.description,
        payload.version,
        payload.contentMode.wire,
        payload.entries.length,
        if (includeInDailyStudy) 1 else 0,
        sha256Hex,
        sourceUrl,
        now,
        now,
      ]);
      await _db.customStatement(
        'DELETE FROM word_pack_items WHERE pack_id = ?',
        <Object?>[payload.id],
      );
    });
  }

  Future<Map<String, _ExistingWordInfo>> _loadExistingWordMap() async {
    final rows = await _db
        .customSelect(
          'SELECT id, normalized_term, source_language, target_language, '
          'initialization_status FROM words',
        )
        .get();
    return <String, _ExistingWordInfo>{
      for (final row in rows)
        _wordKey(
          row.read<String>('normalized_term'),
          row.read<String>('source_language'),
          row.read<String>('target_language'),
        ): _ExistingWordInfo(
          id: row.read<int>('id'),
          status:
              wireLookup(
                InitializationStatus.values,
                row.read<String>('initialization_status'),
              ) ??
              InitializationStatus.pending,
        ),
    };
  }

  Future<void> _installBatch({
    required String packId,
    required WordPackContentMode mode,
    required List<WordPackEntry> batch,
    required Map<String, _ExistingWordInfo> existingIds,
    required _InstallCounters counters,
    required int now,
  }) async {
    await _db.transaction(() async {
      for (final entry in batch) {
        await _installEntry(
          packId: packId,
          mode: mode,
          entry: entry,
          existingIds: existingIds,
          counters: counters,
          now: now,
        );
      }
    });
  }

  Future<void> _installEntry({
    required String packId,
    required WordPackContentMode mode,
    required WordPackEntry entry,
    required Map<String, _ExistingWordInfo> existingIds,
    required _InstallCounters counters,
    required int now,
  }) async {
    final normalized = normalizeTerm(entry.term, entry.sourceLanguage);
    if (normalized.isEmpty) return;
    final key = _wordKey(
      normalized,
      entry.sourceLanguage,
      entry.targetLanguage,
    );
    final existing = existingIds[key];
    final wordId = existing == null
        ? await _insertPackWord(entry, normalized, mode, now)
        : existing.id;
    if (existing == null) {
      counters.created += 1;
      existingIds[key] = _ExistingWordInfo(
        id: wordId,
        status: _initialStatusFor(entry, mode),
      );
    } else {
      counters.linked += 1;
      if (_shouldBackfill(existing.status, entry)) {
        await _backfillContent(wordId, entry, mode, now);
        counters.backfilled += 1;
      }
    }
    await _db.customStatement(
      '''
INSERT INTO word_pack_items (pack_id, word_id, rank)
VALUES (?, ?, ?)
ON CONFLICT(pack_id, word_id) DO UPDATE SET rank = excluded.rank''',
      <Object?>[packId, wordId, entry.rank],
    );
  }

  Future<int> _insertPackWord(
    WordPackEntry entry,
    String normalized,
    WordPackContentMode mode,
    int now,
  ) async {
    final status = _initialStatusFor(entry, mode);
    final wordId = await _db
        .into(_db.words)
        .insert(
          WordsCompanion.insert(
            term: displayTerm(
              entry.term,
              entry.sourceLanguage,
              entry.contentType,
            ),
            normalizedTerm: normalized,
            sourceLanguage: entry.sourceLanguage,
            targetLanguage: entry.targetLanguage,
            entryType: legacyEntryType(entry.contentType),
            contentType: Value<LexicalContentType>(entry.contentType),
            initializationStatus: Value<InitializationStatus>(status),
            isPersonal: const Value<bool>(false),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final content = _normalizedContentOf(entry);
    await _insertWordContent(wordId, content, status, now);
    return wordId;
  }

  Future<void> _backfillContent(
    int wordId,
    WordPackEntry entry,
    WordPackContentMode mode,
    int now,
  ) async {
    final existingRow = await _db
        .customSelect(
          'SELECT * FROM word_contents WHERE word_id = ? LIMIT 1',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingleOrNull();
    final incoming = _normalizedContentOf(entry);
    final merged = existingRow == null
        ? incoming
        : mergeDictionaryContent(<DictionaryContent>[
            dictionaryContentFromColumns(existingRow.data),
            incoming,
          ]);
    final status = _initialStatusFor(entry, mode);
    if (existingRow == null) {
      await _insertWordContent(wordId, merged, status, now);
    } else {
      await _updateWordContent(wordId, merged, status, now);
    }
    await _db.customStatement(
      'UPDATE words SET initialization_status = ?, updated_at = ? '
      'WHERE id = ?',
      <Object?>[status.wire, now, wordId],
    );
  }

  Future<void> _insertWordContent(
    int wordId,
    DictionaryContent content,
    InitializationStatus status,
    int now,
  ) async {
    final isInit =
        status == InitializationStatus.ready ||
        status == InitializationStatus.partial;
    final fields = content.fields;
    await _db
        .into(_db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(wordId),
            definitionsJson: Value<String>(jsonEncode(fields['definitions'])),
            pronunciationsJson: Value<String>(
              jsonEncode(fields['pronunciations']),
            ),
            examplesJson: Value<String>(jsonEncode(fields['examples'])),
            phrasesJson: Value<String>(jsonEncode(fields['phrases'])),
            formsJson: Value<String>(jsonEncode(fields['forms'])),
            synonymsJson: Value<String>(jsonEncode(fields['synonyms'])),
            wordFamilyJson: Value<String>(jsonEncode(fields['wordFamily'])),
            summaryJson: Value<String>(jsonEncode(fields['summary'])),
            tagsJson: Value<String>(jsonEncode(fields['tags'])),
            contentSource: const Value<ContentSource>(
              ContentSource.dictionaryOnly,
            ),
            initializedAt: Value<int?>(isInit ? now : null),
            updatedAt: now,
          ),
        );
  }

  Future<void> _updateWordContent(
    int wordId,
    DictionaryContent content,
    InitializationStatus status,
    int now,
  ) async {
    final isInit =
        status == InitializationStatus.ready ||
        status == InitializationStatus.partial;
    final fields = content.fields;
    await _db.customStatement(
      '''
UPDATE word_contents SET
  definitions_json = ?,
  pronunciations_json = ?,
  examples_json = ?,
  phrases_json = ?,
  forms_json = ?,
  synonyms_json = ?,
  word_family_json = ?,
  summary_json = ?,
  tags_json = ?,
  content_version = content_version + 1,
  initialized_at = COALESCE(initialized_at, ?),
  updated_at = ?
WHERE word_id = ?''',
      <Object?>[
        jsonEncode(fields['definitions']),
        jsonEncode(fields['pronunciations']),
        jsonEncode(fields['examples']),
        jsonEncode(fields['phrases']),
        jsonEncode(fields['forms']),
        jsonEncode(fields['synonyms']),
        jsonEncode(fields['wordFamily']),
        jsonEncode(fields['summary']),
        jsonEncode(fields['tags']),
        if (isInit) now else null,
        now,
        wordId,
      ],
    );
  }

  Future<int> _promoteLearnedOrphans(int now) {
    return _db.customUpdate(
      '''
UPDATE words
SET is_personal = 1, updated_at = ?
WHERE is_personal = 0
  AND NOT EXISTS (SELECT 1 FROM word_pack_items pi WHERE pi.word_id = words.id)
  AND (
    EXISTS (SELECT 1 FROM review_logs rl WHERE rl.word_id = words.id)
    OR EXISTS (SELECT 1 FROM review_cards rc WHERE rc.word_id = words.id)
    OR EXISTS (SELECT 1 FROM study_session_items si WHERE si.word_id = words.id)
  )''',
      variables: <Variable<Object>>[Variable<int>(now)],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.words},
    );
  }

  Future<int> _deleteRemainingOrphans({required bool includeLearned}) {
    final historyGuard = includeLearned
        ? ''
        : '''
  AND NOT EXISTS (SELECT 1 FROM review_logs rl WHERE rl.word_id = words.id)
  AND NOT EXISTS (SELECT 1 FROM review_cards rc WHERE rc.word_id = words.id)
  AND NOT EXISTS (SELECT 1 FROM study_session_items si WHERE si.word_id = words.id)''';
    return _db.customUpdate(
      '''
DELETE FROM words
WHERE is_personal = 0
  AND NOT EXISTS (SELECT 1 FROM word_pack_items pi WHERE pi.word_id = words.id)
$historyGuard''',
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.words},
    );
  }

  bool _shouldBackfill(InitializationStatus status, WordPackEntry entry) =>
      entry.hasDefinitions &&
      (status == InitializationStatus.pending ||
          status == InitializationStatus.failed);

  InitializationStatus _initialStatusFor(
    WordPackEntry entry,
    WordPackContentMode mode,
  ) {
    if (!entry.hasDefinitions) return InitializationStatus.pending;
    if (mode == WordPackContentMode.fullYoudao && entry.hasRichContent) {
      return InitializationStatus.ready;
    }
    return entry.examples.isNotEmpty
        ? InitializationStatus.ready
        : InitializationStatus.partial;
  }

  DictionaryContent _normalizedContentOf(WordPackEntry entry) =>
      normalizeDictionaryContent(<String, Object?>{
        'definitions': entry.definitions,
        'pronunciations': entry.pronunciations,
        'examples': entry.examples,
        'phrases': entry.phrases,
        'forms': entry.forms,
        'synonyms': entry.synonyms,
        'wordFamily': entry.wordFamily,
        'summary': entry.summary,
        'tags': entry.tags,
      });

  String _wordKey(String normalized, String source, String target) =>
      '$normalized\u0000$source\u0000$target';
}

class _ExistingWordInfo {
  const new({required this.id, required this.status});

  final int id;
  final InitializationStatus status;
}

class _InstallCounters {
  int created = 0;
  int linked = 0;
  int backfilled = 0;
}
