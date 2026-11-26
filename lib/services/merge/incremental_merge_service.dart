/// 增量同步的 SQLite 事务落库服务：局部 Upsert + 局部 FSRS 重放。
///
/// 相比全量 `BackupMergeService`（读整库 → 清空 14 张表 → 全量重插）：
/// - 只按本次增量涉及的词条、会话、日志查库并做局部 Upsert；
/// - 派生状态（卡片 / 错词 / 熟练度 / 复习统计）只重算本次收到新作答的词条；
/// - 全程包裹在单次 SQLite 事务内，失败时原数据零改动；
/// - 合并语义（身份对齐、元数据取新、会话推进、日志去重与重放）与全量合并
///   完全一致，由收敛测试对拍保证。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/backup/incremental_sync_payload.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/review/wrong_state.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/merge/backup_merge.dart';
import 'package:lexiloop/services/merge/learning_replay.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 合并时可随对端更新的 `words` 元数据列（与 `backup_merge.dart` 保持一致）。
const List<String> _mergeableWordCols = <String>[
  'term',
  'source_language_name',
  'target_language_name',
  'entry_type',
  'content_type',
  'source_created_at',
  'is_suspended',
  'user_note',
  'updated_at',
];

/// 可推进已有会话的进度汇总列。
const List<String> _sessionAdvanceCols = <String>[
  'completed_at',
  'planned_count',
  'completed_count',
  'correct_count',
  'wrong_count',
  'skipped_count',
  'duration_ms',
];

/// 增量同步落库服务。
class IncrementalMergeService {
  /// 以数据库、设置服务与可选时钟构造。
  const new(this._db, this._settings, {int Function()? clock})
    : _clock = clock ?? _wallClockMs;

  final AppDatabase _db;
  final SettingsService _settings;
  final int Function() _clock;

  /// 将一份 [payload] 以单事务增量合入本机数据库，返回本次合并摘要。
  Future<LanSyncDeltaSummary> apply(IncrementalSyncPayload payload) async {
    final settings = await _settings.load();
    final scheduler = FsrsScheduler(
      requestRetention: settings.studyPlan.targetRetentionRate,
    );
    final summary = await _db.transaction(
      () => _IncrementalApplyRun(
        db: _db,
        payload: payload,
        scheduler: scheduler,
        now: _clock(),
      ).execute(),
    );
    _settings.invalidate();
    return summary;
  }
}

class _IncrementalApplyRun {
  new({
    required this.db,
    required this.payload,
    required this.scheduler,
    required this.now,
  });

  final AppDatabase db;
  final IncrementalSyncPayload payload;
  final FsrsScheduler scheduler;
  final int now;

  final Map<String, List<String>> _columnCache = <String, List<String>>{};
  final Map<int, int> _wordIdMap = <int, int>{};
  final Map<int, int> _sessionIdMap = <int, int>{};
  final Map<int, int> _itemIdMap = <int, int>{};
  final Set<int> _touchedWordIds = <int>{};

  int _addedWords = 0;
  int _updatedWords = 0;
  int _addedLogs = 0;

  Future<LanSyncDeltaSummary> execute() async {
    await _resolveAndMergeWords();
    await _mergeContents();
    await _mergeSessions();
    await _mergeLogs();
    await _rebuildTouchedDerived();
    await _mergeSettings();
    await _mergeWordPacks();
    await _mergeWordPackItems();

    final countRow = await db
        .customSelect('SELECT count(*) AS c FROM words')
        .getSingle();
    return LanSyncDeltaSummary(
      addedWords: _addedWords,
      updatedWords: _updatedWords,
      addedLogs: _addedLogs,
      rebuiltWords: _touchedWordIds.length,
      wordCount: countRow.read<int>('c'),
    );
  }

  Future<void> _resolveAndMergeWords() async {
    final incomingWords = _rowsOf('words');
    final terms = <String>{
      for (final row in payload.wordRefs) _str(row['normalized_term']),
      for (final row in incomingWords) _str(row['normalized_term']),
    }..remove('');
    final existingByIdentity = await _loadExistingWords(terms);

    for (final ref in payload.wordRefs) {
      final existing = existingByIdentity[wordIdentityOf(ref)];
      final remoteId = _int(ref['id']);
      if (existing != null && remoteId != null) {
        _wordIdMap[remoteId] = _int(existing['id'])!;
      }
    }
    if (incomingWords.isEmpty) return;

    final cols = await _columnsOf('words');
    for (final incoming in incomingWords) {
      await _upsertWordRow(incoming, existingByIdentity, cols);
    }
  }

  Future<void> _upsertWordRow(
    Map<String, Object?> incoming,
    Map<String, Map<String, Object?>> byIdentity,
    List<String> tableCols,
  ) async {
    final identity = wordIdentityOf(incoming);
    final remoteId = _int(incoming['id']);
    final existing = byIdentity[identity];
    if (existing == null) {
      final prepared = <String, Object?>{
        ...incoming,
        'is_personal': _isPersonalTruthy(incoming['is_personal']) ? 1 : 0,
        if (incoming.containsKey('initialization_status'))
          'initialization_status': _normalizeInitStatus(
            incoming['initialization_status'],
          ),
      }..remove('id');
      final insertedId = await _insertReturningId('words', prepared, tableCols);
      prepared['id'] = insertedId;
      byIdentity[identity] = prepared;
      if (remoteId != null) _wordIdMap[remoteId] = insertedId;
      _addedWords += 1;
      return;
    }

    final localId = _int(existing['id'])!;
    if (remoteId != null) _wordIdMap[remoteId] = localId;
    final updates = _wordUpdates(existing, incoming);
    if (updates.isEmpty) return;
    final isMetadataChange = _isNewer(incoming, existing);
    await _updateWhereId('words', localId, updates, tableCols);
    existing.addAll(updates);
    if (isMetadataChange) _updatedWords += 1;
  }

  Map<String, Object?> _wordUpdates(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    final updates = <String, Object?>{};
    if (!_isPersonalTruthy(existing['is_personal']) &&
        _isPersonalTruthy(incoming['is_personal'])) {
      updates['is_personal'] = 1;
    }
    if (_isNewer(incoming, existing)) {
      for (final col in _mergeableWordCols) {
        if (incoming.containsKey(col)) updates[col] = incoming[col];
      }
    }
    return updates;
  }

  Future<void> _mergeContents() async {
    final incoming = _rowsOf('word_contents');
    if (incoming.isEmpty) return;
    final mappedWordIds = <int>{
      for (final row in incoming) ?_wordIdMap[_int(row['word_id'])],
    };
    final existingByWord = await _loadByIntKey(
      'word_contents',
      'word_id',
      mappedWordIds,
    );
    final cols = await _columnsOf('word_contents');

    for (final row in incoming) {
      final wordId = _wordIdMap[_int(row['word_id'])];
      if (wordId == null) continue;
      final existing = existingByWord[wordId];
      if (existing != null && !_isNewer(row, existing)) continue;
      final prepared = <String, Object?>{...row, 'word_id': wordId};
      await _upsertByConflict('word_contents', 'word_id', prepared, cols);
      existingByWord[wordId] = prepared;
    }
  }

  Future<void> _mergeSessions() async {
    final incomingSessions = _rowsOf('study_sessions');
    if (incomingSessions.isEmpty) return;
    final itemsByRemoteSession = _groupItemsBySession(
      _rowsOf('study_session_items'),
    );
    final existingSessions = await _loadExistingSessions(incomingSessions);
    final sessionCols = await _columnsOf('study_sessions');
    final itemCols = await _columnsOf('study_session_items');

    for (final incoming in incomingSessions) {
      final remoteId = _int(incoming['id']);
      final identity = sessionIdentityOf(incoming);
      final existing = existingSessions[identity];
      final remoteItems = itemsByRemoteSession[remoteId];
      if (existing != null) {
        final localId = _int(existing['id'])!;
        if (remoteId != null) _sessionIdMap[remoteId] = localId;
        await _advanceSession(existing, incoming, sessionCols);
        await _mergeExistingSessionItems(localId, remoteItems, itemCols);
        continue;
      }
      await _insertNewSession(
        incoming: incoming,
        identity: identity,
        remoteId: remoteId,
        remoteItems: remoteItems,
        existingSessions: existingSessions,
        sessionCols: sessionCols,
        itemCols: itemCols,
      );
    }
  }

  Future<void> _insertNewSession({
    required Map<String, Object?> incoming,
    required String identity,
    required int? remoteId,
    required List<Map<String, Object?>>? remoteItems,
    required Map<String, Map<String, Object?>> existingSessions,
    required List<String> sessionCols,
    required List<String> itemCols,
  }) async {
    final prepared = <String, Object?>{...incoming}..remove('id');
    final localId = await _insertReturningId(
      'study_sessions',
      prepared,
      sessionCols,
    );
    prepared['id'] = localId;
    existingSessions[identity] = prepared;
    if (remoteId != null) _sessionIdMap[remoteId] = localId;
    await _insertSessionItems(localId, remoteItems, itemCols);
  }

  Future<void> _advanceSession(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
    List<String> cols,
  ) async {
    final incomingDone = _int(incoming['completed_at']);
    final existingDone = _int(existing['completed_at']);
    final shouldAdvance =
        (incomingDone != null && existingDone == null) ||
        _progressOf(incoming) > _progressOf(existing);
    if (!shouldAdvance) return;
    final updates = <String, Object?>{
      for (final col in _sessionAdvanceCols)
        if (incoming.containsKey(col)) col: incoming[col],
    };
    if (updates.isEmpty) return;
    await _updateWhereId(
      'study_sessions',
      _int(existing['id'])!,
      updates,
      cols,
    );
    existing.addAll(updates);
  }

  Future<void> _mergeExistingSessionItems(
    int localSessionId,
    List<Map<String, Object?>>? incomingItems,
    List<String> itemCols,
  ) async {
    if (incomingItems == null || incomingItems.isEmpty) return;
    final localRows = await _query(
      'SELECT * FROM study_session_items WHERE study_session_id = ?',
      <Object>[localSessionId],
    );
    final byPos = <double, Map<String, Object?>>{
      for (final row in localRows)
        if (row['position'] is num) (row['position']! as num).toDouble(): row,
    };
    for (final item in incomingItems) {
      await _upsertSessionItem(localSessionId, item, byPos, itemCols);
    }
  }

  Future<void> _upsertSessionItem(
    int localSessionId,
    Map<String, Object?> item,
    Map<double, Map<String, Object?>> byPos,
    List<String> itemCols,
  ) async {
    final remoteId = _int(item['id']);
    final pos = item['position'] is num
        ? (item['position']! as num).toDouble()
        : null;
    final existing = pos == null ? null : byPos[pos];
    if (existing != null) {
      final localItemId = _int(existing['id'])!;
      if (remoteId != null) _itemIdMap[remoteId] = localItemId;
      if (_str(existing['status']) == StudyItemStatus.pending.wire &&
          _str(item['status']) != StudyItemStatus.pending.wire) {
        final updates = <String, Object?>{
          'status': item['status'],
          'answered_at': item['answered_at'],
          'skip_reason': item['skip_reason'],
        };
        await _updateWhereId(
          'study_session_items',
          localItemId,
          updates,
          itemCols,
        );
        existing.addAll(updates);
      }
      return;
    }
    final wordId = _wordIdMap[_int(item['word_id'])];
    if (wordId == null) return;
    final prepared = <String, Object?>{
      ...item,
      'study_session_id': localSessionId,
      'word_id': wordId,
    }..remove('id');
    final insertedId = await _insertReturningId(
      'study_session_items',
      prepared,
      itemCols,
    );
    if (pos != null) {
      byPos[pos] = <String, Object?>{...prepared, 'id': insertedId};
    }
    if (remoteId != null) _itemIdMap[remoteId] = insertedId;
  }

  Future<void> _insertSessionItems(
    int localSessionId,
    List<Map<String, Object?>>? items,
    List<String> itemCols,
  ) async {
    if (items == null || items.isEmpty) return;
    for (final item in items) {
      final wordId = _wordIdMap[_int(item['word_id'])];
      if (wordId == null) continue;
      final remoteId = _int(item['id']);
      final prepared = <String, Object?>{
        ...item,
        'study_session_id': localSessionId,
        'word_id': wordId,
      }..remove('id');
      final insertedId = await _insertReturningId(
        'study_session_items',
        prepared,
        itemCols,
      );
      if (remoteId != null) _itemIdMap[remoteId] = insertedId;
    }
  }

  Future<void> _mergeLogs() async {
    final incoming = _rowsOf('review_logs');
    if (incoming.isEmpty) return;
    final answerIds = <String>{
      for (final row in incoming) _str(row['client_answer_id']),
    }..remove('');
    final seen = await _loadExistingAnswerIds(answerIds);
    final cols = await _columnsOf('review_logs');

    for (final row in incoming) {
      final answerId = _str(row['client_answer_id']);
      if (answerId.isEmpty || !seen.add(answerId)) continue;
      final wordId = _wordIdMap[_int(row['word_id'])];
      if (wordId == null) continue;
      final prepared = <String, Object?>{
        ...row,
        'word_id': wordId,
        'study_session_id': _sessionIdMap[_int(row['study_session_id'])],
        'study_session_item_id': _itemIdMap[_int(row['study_session_item_id'])],
      }..remove('id');
      await _insertRow('review_logs', prepared, cols);
      _touchedWordIds.add(wordId);
      _addedLogs += 1;
    }
  }

  Future<void> _rebuildTouchedDerived() async {
    if (_touchedWordIds.isEmpty) return;
    final wordIds = _touchedWordIds.toList(growable: false);
    final logsByWord = await _loadLogsForWords(wordIds);
    final existingCards = await _loadByIntKey(
      'review_cards',
      'word_id',
      _touchedWordIds,
    );
    final cardCols = await _columnsOf('review_cards');
    final wrongCols = await _columnsOf('wrong_word_states');

    for (final entry in logsByWord.entries) {
      final replayed = replayWordHistory(
        logs: entry.value,
        scheduler: scheduler,
        now: now,
      );
      await _writeReplayedWord(
        wordId: entry.key,
        replayed: replayed,
        existingCard: existingCards[entry.key],
        cardCols: cardCols,
        wrongCols: wrongCols,
      );
    }
    await _recomputeStatsForWords(wordIds);
  }

  Future<void> _writeReplayedWord({
    required int wordId,
    required ReplayedLearningState replayed,
    required Map<String, Object?>? existingCard,
    required List<String> cardCols,
    required List<String> wrongCols,
  }) async {
    await _upsertByConflict(
      'review_cards',
      'word_id',
      _cardMap(wordId, replayed.card, existingCard),
      cardCols,
    );
    final wrong = _wrongMap(
      wordId,
      replayed.wrong,
      fallbackUpdatedAt: replayed.card.lastReviewAt ?? now,
    );
    if (wrong == null) {
      await db.customStatement(
        'DELETE FROM wrong_word_states WHERE word_id = ?',
        <Object?>[wordId],
      );
    } else {
      await _upsertByConflict('wrong_word_states', 'word_id', wrong, wrongCols);
    }
    await db.customStatement(
      'UPDATE words SET mastery_score = ?, mastery_level = ? WHERE id = ?',
      <Object?>[replayed.masteryScore, replayed.masteryLevel.wire, wordId],
    );
  }

  Future<void> _recomputeStatsForWords(List<int> wordIds) async {
    final since14 = now - performanceWindowMs;
    final since30 = now - masteryWindowMs;
    for (final chunk in _batchOf(wordIds)) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      await db.customStatement(
        'DELETE FROM word_review_stats WHERE word_id IN ($marks)',
        chunk,
      );
      await db.customStatement(
        '''
INSERT INTO word_review_stats (
  word_id, total_reviews, correct_reviews,
  recent_again_30d, recent_again_14d, recent_wrong_14d, recent_hard_14d,
  total_duration_ms, duration_count, last_reviewed_at, updated_at
)
SELECT
  word_id,
  count(*),
  coalesce(sum(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0),
  coalesce(sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
  coalesce(sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
  coalesce(sum(CASE WHEN is_correct = 0 AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
  coalesce(sum(CASE WHEN rating = 'HARD' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
  coalesce(sum(CASE WHEN duration_ms > 0 THEN duration_ms ELSE 0 END), 0),
  coalesce(sum(CASE WHEN duration_ms > 0 THEN 1 ELSE 0 END), 0),
  max(reviewed_at),
  ?
FROM review_logs
WHERE word_id IN ($marks)
GROUP BY word_id
''',
        <Object?>[since30, since14, since14, since14, now, ...chunk],
      );
    }
  }

  Future<void> _mergeSettings() async {
    final incoming = _rowsOf('settings');
    if (incoming.isEmpty) return;
    final keys = <String>{
      for (final row in incoming)
        if (!mergeExcludedSettingKeys.contains(_str(row['key'])))
          _str(row['key']),
    }..remove('');
    if (keys.isEmpty) return;
    final existing = await _loadByStringKey('settings', 'key', keys);
    final cols = await _columnsOf('settings');

    for (final row in incoming) {
      final key = _str(row['key']);
      if (key.isEmpty || mergeExcludedSettingKeys.contains(key)) continue;
      final current = existing[key];
      if (current != null && !_isNewer(row, current)) continue;
      await _upsertByConflict('settings', 'key', row, cols);
      existing[key] = row;
    }
  }

  Future<void> _mergeWordPacks() async {
    final incoming = _rowsOf('word_packs');
    if (incoming.isEmpty) return;
    final ids = <String>{for (final row in incoming) _str(row['id'])}
      ..remove('');
    final existing = await _loadByStringKey('word_packs', 'id', ids);
    final cols = await _columnsOf('word_packs');

    for (final row in incoming) {
      final id = _str(row['id']);
      if (id.isEmpty) continue;
      final current = existing[id];
      if (current != null && !_isNewer(row, current)) continue;
      await _upsertByConflict('word_packs', 'id', row, cols);
      existing[id] = row;
    }
  }

  Future<void> _mergeWordPackItems() async {
    final incoming = _rowsOf('word_pack_items');
    if (incoming.isEmpty) return;
    final packIds = <String>{for (final row in incoming) _str(row['pack_id'])}
      ..remove('');
    final existingPacks = await _loadByStringKey('word_packs', 'id', packIds);
    for (final row in incoming) {
      final packId = _str(row['pack_id']);
      final wordId = _wordIdMap[_int(row['word_id'])];
      if (packId.isEmpty ||
          wordId == null ||
          !existingPacks.containsKey(packId)) {
        continue;
      }
      await db.customStatement(
        'INSERT OR IGNORE INTO word_pack_items (pack_id, word_id, rank) '
        'VALUES (?, ?, ?)',
        <Object?>[packId, wordId, _int(row['rank']) ?? 0],
      );
    }
  }

  Future<Map<String, Map<String, Object?>>> _loadExistingWords(
    Set<String> normalizedTerms,
  ) async {
    final byIdentity = <String, Map<String, Object?>>{};
    for (final chunk in _batchOf(normalizedTerms.toList(growable: false))) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _query(
        'SELECT * FROM words WHERE normalized_term IN ($marks)',
        chunk,
      );
      for (final row in rows) {
        byIdentity[wordIdentityOf(row)] = row;
      }
    }
    return byIdentity;
  }

  Future<Map<String, Map<String, Object?>>> _loadExistingSessions(
    List<Map<String, Object?>> incoming,
  ) async {
    final startedAts = <int>{
      for (final row in incoming) ?_int(row['started_at']),
    };
    final byIdentity = <String, Map<String, Object?>>{};
    for (final chunk in _batchOf(startedAts.toList(growable: false))) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _query(
        'SELECT * FROM study_sessions WHERE started_at IN ($marks)',
        chunk,
      );
      for (final row in rows) {
        byIdentity[sessionIdentityOf(row)] = row;
      }
    }
    return byIdentity;
  }

  Future<Set<String>> _loadExistingAnswerIds(Set<String> answerIds) async {
    final seen = <String>{};
    for (final chunk in _batchOf(answerIds.toList(growable: false))) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _query(
        'SELECT client_answer_id FROM review_logs '
        'WHERE client_answer_id IN ($marks)',
        chunk,
      );
      for (final row in rows) {
        seen.add(_str(row['client_answer_id']));
      }
    }
    return seen;
  }

  Future<Map<int, List<ReplayLog>>> _loadLogsForWords(List<int> wordIds) async {
    final grouped = <int, List<Map<String, Object?>>>{};
    for (final chunk in _batchOf(wordIds)) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _query(
        'SELECT * FROM review_logs WHERE word_id IN ($marks)',
        chunk,
      );
      for (final row in rows) {
        final wid = _int(row['word_id']);
        if (wid != null) {
          grouped.putIfAbsent(wid, () => <Map<String, Object?>>[]).add(row);
        }
      }
    }
    return <int, List<ReplayLog>>{
      for (final entry in grouped.entries)
        entry.key: (entry.value..sort(_compareLogRows))
            .map(replayLogFromRow)
            .toList(growable: false),
    };
  }

  Future<Map<int, Map<String, Object?>>> _loadByIntKey(
    String table,
    String column,
    Set<int> keys,
  ) async {
    final map = <int, Map<String, Object?>>{};
    for (final chunk in _batchOf(keys.toList(growable: false))) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _query(
        'SELECT * FROM $table WHERE $column IN ($marks)',
        chunk,
      );
      for (final row in rows) {
        final key = _int(row[column]);
        if (key != null) map[key] = row;
      }
    }
    return map;
  }

  Future<Map<String, Map<String, Object?>>> _loadByStringKey(
    String table,
    String column,
    Set<String> keys,
  ) async {
    final map = <String, Map<String, Object?>>{};
    for (final chunk in _batchOf(keys.toList(growable: false))) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _query(
        'SELECT * FROM $table WHERE $column IN ($marks)',
        chunk,
      );
      for (final row in rows) {
        final key = _str(row[column]);
        if (key.isNotEmpty) map[key] = row;
      }
    }
    return map;
  }

  Future<int> _insertReturningId(
    String table,
    Map<String, Object?> row,
    List<String> tableCols,
  ) async {
    await _insertRow(table, row, tableCols);
    final idRow = await db
        .customSelect('SELECT last_insert_rowid() AS id')
        .getSingle();
    return idRow.read<int>('id');
  }

  Future<void> _insertRow(
    String table,
    Map<String, Object?> row,
    List<String> tableCols,
  ) async {
    final usable = tableCols.where(row.containsKey).toList(growable: false);
    if (usable.isEmpty) return;
    assertBackupEnumValues(table, <Map<String, Object?>>[row], usable);
    final marks = List<String>.filled(usable.length, '?').join(', ');
    await db.customStatement(
      'INSERT INTO $table (${usable.join(', ')}) VALUES ($marks)',
      usable.map((col) => row[col]).toList(growable: false),
    );
  }

  Future<void> _upsertByConflict(
    String table,
    String conflictCol,
    Map<String, Object?> row,
    List<String> tableCols,
  ) async {
    final usable = tableCols.where(row.containsKey).toList(growable: false);
    if (usable.isEmpty) return;
    assertBackupEnumValues(table, <Map<String, Object?>>[row], usable);
    final marks = List<String>.filled(usable.length, '?').join(', ');
    final updates = usable
        .where((col) => col != conflictCol)
        .map((col) => '$col = excluded.$col')
        .join(', ');
    final sql = updates.isEmpty
        ? 'INSERT OR IGNORE INTO $table (${usable.join(', ')}) VALUES ($marks)'
        : 'INSERT INTO $table (${usable.join(', ')}) VALUES ($marks) '
              'ON CONFLICT($conflictCol) DO UPDATE SET $updates';
    await db.customStatement(
      sql,
      usable.map((col) => row[col]).toList(growable: false),
    );
  }

  Future<void> _updateWhereId(
    String table,
    int id,
    Map<String, Object?> updates,
    List<String> tableCols,
  ) async {
    final usable = tableCols
        .where((col) => col != 'id' && updates.containsKey(col))
        .toList(growable: false);
    if (usable.isEmpty) return;
    assertBackupEnumValues(table, <Map<String, Object?>>[updates], usable);
    final clause = usable.map((col) => '$col = ?').join(', ');
    await db.customStatement(
      'UPDATE $table SET $clause WHERE id = ?',
      <Object?>[...usable.map((col) => updates[col]), id],
    );
  }

  Future<List<String>> _columnsOf(String table) async {
    final cached = _columnCache[table];
    if (cached != null) return cached;
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    final cols = rows
        .map((r) => r.read<String>('name'))
        .toList(growable: false);
    _columnCache[table] = cols;
    return cols;
  }

  Future<List<Map<String, Object?>>> _query(
    String sql,
    List<Object> params,
  ) async {
    final rows = await db
        .customSelect(
          sql,
          variables: params.map(Variable<Object>.new).toList(growable: false),
        )
        .get();
    return rows
        .map((row) => Map<String, Object?>.from(row.data))
        .toList(growable: false);
  }

  List<Map<String, Object?>> _rowsOf(String table) =>
      payload.tables[table] ?? const <Map<String, Object?>>[];
}

Map<int, List<Map<String, Object?>>> _groupItemsBySession(
  List<Map<String, Object?>> items,
) {
  final grouped = <int, List<Map<String, Object?>>>{};
  for (final item in items) {
    final sid = _int(item['study_session_id']);
    if (sid != null) {
      grouped.putIfAbsent(sid, () => <Map<String, Object?>>[]).add(item);
    }
  }
  return grouped;
}

Map<String, Object?> _cardMap(
  int wordId,
  ReviewCardState card,
  Map<String, Object?>? existing,
) => <String, Object?>{
  'word_id': wordId,
  'due_at': card.dueAt,
  'stability': card.stability,
  'difficulty': card.difficulty,
  'elapsed_days': card.elapsedDays,
  'scheduled_days': card.scheduledDays,
  'reps': card.reps,
  'lapses': card.lapses,
  'fsrs_state': card.fsrsState,
  'learning_steps': card.learningSteps,
  'last_review_at': card.lastReviewAt,
  'created_at': existing?['created_at'] ?? card.dueAt,
  'updated_at': existing?['updated_at'] ?? card.dueAt,
};

Map<String, Object?>? _wrongMap(
  int wordId,
  WrongStateTransition? t, {
  required int fallbackUpdatedAt,
}) => t == null
    ? null
    : <String, Object?>{
        'word_id': wordId,
        'active': t.active ? 1 : 0,
        'wrong_count': t.wrongCount,
        'hard_count': t.hardCount,
        'consecutive_correct': t.consecutiveCorrect,
        'last_wrong_at': t.lastWrongAt,
        'last_correct_at': t.lastCorrectAt,
        'resolved_at': t.resolvedAt,
        'updated_at': t.lastCorrectAt ?? t.lastWrongAt ?? fallbackUpdatedAt,
      };

int _compareLogRows(Map<String, Object?> a, Map<String, Object?> b) {
  final byTime = (_int(a['reviewed_at']) ?? 0).compareTo(
    _int(b['reviewed_at']) ?? 0,
  );
  if (byTime != 0) return byTime;
  return _str(a['client_answer_id']).compareTo(_str(b['client_answer_id']));
}

int _progressOf(Map<String, Object?> row) =>
    (_int(row['completed_count']) ?? 0) + (_int(row['skipped_count']) ?? 0);

bool _isNewer(Map<String, Object?> incoming, Map<String, Object?> existing) =>
    (_int(incoming['updated_at']) ?? 0) > (_int(existing['updated_at']) ?? 0);

bool _isPersonalTruthy(Object? value) {
  if (value == null) return true;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return true;
}

Object? _normalizeInitStatus(Object? value) =>
    value == InitializationStatus.queued.wire ||
        value == InitializationStatus.running.wire
    ? InitializationStatus.pending.wire
    : value;

Iterable<List<T>> _batchOf<T>(List<T> items) sync* {
  for (var start = 0; start < items.length; start += lanSyncSqlBatchSize) {
    final end = start + lanSyncSqlBatchSize;
    yield items.sublist(start, end > items.length ? items.length : end);
  }
}

int? _int(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String _str(Object? value) => value is String ? value : '';

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
