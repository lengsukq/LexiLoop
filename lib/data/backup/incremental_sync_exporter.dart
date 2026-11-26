/// 局域网同步的增量导出器：只查自水位线以来的变更行与最小词条引用。
///
/// 相比 `BackupExporter.exportToJson`：
/// 1. 永远跳过 4 张本机审计/任务表与 3 张可重放派生表；
/// 2. 在命中水位线时，仅查询 `updated_at` / `created_at` / `answered_at` 越过
///    水位线的增量行，并用极轻量的 `word_refs` 补齐引用老词的身份，避免把几万字
///    的 `word_contents` 反复导出。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/backup/incremental_sync_payload.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';

/// 默认不参与局域网/云端合并同步外发的设置键（与 `mergeExcludedSettingKeys` 对齐）。
const Set<String> defaultSyncExcludedSettingKeys = <String>{
  lanSyncSettingsKey,
  webdavSettingsKey,
  cloudSyncSettingsKey,
  cloudSyncServerSettingsKey,
  'llmConfig',
  'merriamWebsterDictionaryKey',
  'merriamWebsterThesaurusKey',
};

/// 增量同步数据导出器。
class IncrementalSyncExporter {
  /// 以数据库与可选时钟构造。
  const new(this._db, {int Function()? clock}) : _clock = clock ?? _wallClockMs;

  final AppDatabase _db;
  final int Function() _clock;

  /// 在单个只读事务快照内导出增量（或精简全量）载荷。
  Future<IncrementalSyncPayload> exportDelta({
    required String datasetEpoch,
    int? since,
    Set<String> excludedSettingKeys = defaultSyncExcludedSettingKeys,
  }) => _db.transaction(() async {
    final serverNow = _clock();
    final isIncremental = since != null && since > 0;
    if (!isIncremental) {
      return await _exportFull(
        serverNow: serverNow,
        datasetEpoch: datasetEpoch,
        excludedSettingKeys: excludedSettingKeys,
      );
    }
    final cutoff = (since - lanSyncDeltaLookbackMs).clamp(0, serverNow);
    return await _exportSince(
      cutoff: cutoff,
      since: since,
      serverNow: serverNow,
      datasetEpoch: datasetEpoch,
      excludedSettingKeys: excludedSettingKeys,
    );
  });

  Future<IncrementalSyncPayload> _exportFull({
    required int serverNow,
    required String datasetEpoch,
    required Set<String> excludedSettingKeys,
  }) async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in incrementalSyncTableOrder) {
      tables[table] = await _selectAll(table);
    }
    tables['settings'] = _filterSettings(
      tables['settings']!,
      excludedSettingKeys,
    );
    return IncrementalSyncPayload(
      isIncremental: false,
      serverNow: serverNow,
      datasetEpoch: datasetEpoch,
      wordRefs: const <Map<String, Object?>>[],
      tables: tables,
    );
  }

  Future<IncrementalSyncPayload> _exportSince({
    required int cutoff,
    required int since,
    required int serverNow,
    required String datasetEpoch,
    required Set<String> excludedSettingKeys,
  }) async {
    final words = await _query(
      'SELECT * FROM words WHERE updated_at >= ?',
      <Object>[cutoff],
    );
    final contents = await _query(
      'SELECT * FROM word_contents WHERE updated_at >= ?',
      <Object>[cutoff],
    );
    final logs = await _query(
      'SELECT * FROM review_logs WHERE created_at >= ? OR reviewed_at >= ?',
      <Object>[cutoff, cutoff],
    );
    final sessionsBundle = await _selectSessionsSince(cutoff, logs);
    final packsBundle = await _selectPacksSince(cutoff, words);
    final settings = _filterSettings(
      await _query('SELECT * FROM settings WHERE updated_at >= ?', <Object>[
        cutoff,
      ]),
      excludedSettingKeys,
    );
    final tables = <String, List<Map<String, Object?>>>{
      'words': words,
      'word_contents': contents,
      'study_sessions': sessionsBundle.sessions,
      'study_session_items': sessionsBundle.items,
      'review_logs': logs,
      'settings': settings,
      'word_packs': packsBundle.packs,
      'word_pack_items': packsBundle.items,
    };
    final wordRefs = await _loadWordRefs(tables);
    return IncrementalSyncPayload(
      isIncremental: true,
      serverNow: serverNow,
      datasetEpoch: datasetEpoch,
      since: since,
      wordRefs: wordRefs,
      tables: tables,
    );
  }

  Future<
    ({List<Map<String, Object?>> sessions, List<Map<String, Object?>> items})
  >
  _selectSessionsSince(int cutoff, List<Map<String, Object?>> logs) async {
    final sessions = await _query(
      'SELECT * FROM study_sessions '
      'WHERE started_at >= ? OR completed_at >= ? OR created_at >= ?',
      <Object>[cutoff, cutoff, cutoff],
    );
    final sessionIds = <int>{
      for (final row in sessions) ?_intOf(row['id']),
      for (final log in logs) ?_intOf(log['study_session_id']),
    };
    final changedItems = await _query(
      'SELECT * FROM study_session_items '
      'WHERE answered_at >= ? OR created_at >= ?',
      <Object>[cutoff, cutoff],
    );
    for (final item in changedItems) {
      final sid = _intOf(item['study_session_id']);
      if (sid != null) sessionIds.add(sid);
    }
    final allSessions = await _selectByIntIds(
      'study_sessions',
      'id',
      sessionIds,
    );
    final allItems = await _selectByIntIds(
      'study_session_items',
      'study_session_id',
      sessionIds,
    );
    return (sessions: allSessions, items: allItems);
  }

  Future<({List<Map<String, Object?>> packs, List<Map<String, Object?>> items})>
  _selectPacksSince(int cutoff, List<Map<String, Object?>> words) async {
    final packs = await _query(
      'SELECT * FROM word_packs WHERE updated_at >= ?',
      <Object>[cutoff],
    );
    final packIds = <String>{
      for (final row in packs)
        if (row['id'] is String) row['id']! as String,
    };
    final wordIds = <int>{for (final row in words) ?_intOf(row['id'])};
    final byPack = await _selectByStringIds(
      'word_pack_items',
      'pack_id',
      packIds,
    );
    final byWord = await _selectByIntIds('word_pack_items', 'word_id', wordIds);
    final items = _dedupePackItems(<Map<String, Object?>>[
      ...byPack,
      ...byWord,
    ]);
    for (final item in items) {
      if (item['pack_id'] is String) packIds.add(item['pack_id']! as String);
    }
    final fullPacks = await _selectByStringIds('word_packs', 'id', packIds);
    return (packs: fullPacks, items: items);
  }

  /// 查询所有被子表引用但不在本次 `words` 中的老词最小身份存根。
  Future<List<Map<String, Object?>>> _loadWordRefs(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    final present = <int>{
      for (final row in tables['words']!) ?_intOf(row['id']),
    };
    final needed = <int>{};
    for (final table in const <String>[
      'word_contents',
      'study_session_items',
      'review_logs',
      'word_pack_items',
    ]) {
      for (final row in tables[table]!) {
        final wid = _intOf(row['word_id']);
        if (wid != null && !present.contains(wid)) needed.add(wid);
      }
    }
    if (needed.isEmpty) return const <Map<String, Object?>>[];
    final result = <Map<String, Object?>>[];
    for (final chunk in _chunks(needed.toList(growable: false))) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      final rows = await _query(
        'SELECT id, normalized_term, source_language, target_language '
        'FROM words WHERE id IN ($marks)',
        chunk,
      );
      result.addAll(rows);
    }
    return result;
  }

  List<Map<String, Object?>> _filterSettings(
    List<Map<String, Object?>> rows,
    Set<String> excluded,
  ) {
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final key = row['key'];
      if (key is! String || excluded.contains(key)) continue;
      if (key == webdavSettingsKey) {
        final copy = Map<String, Object?>.from(row);
        final raw = copy['value_json'];
        if (raw is String && raw.isNotEmpty) {
          copy['value_json'] = jsonEncode(
            webdavValueForExport(jsonDecode(raw)),
          );
        }
        result.add(copy);
        continue;
      }
      result.add(row);
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _selectAll(String table) =>
      _query('SELECT * FROM $table', const <Object>[]);

  Future<List<Map<String, Object?>>> _selectByIntIds(
    String table,
    String column,
    Set<int> ids,
  ) async {
    if (ids.isEmpty) return const <Map<String, Object?>>[];
    final result = <Map<String, Object?>>[];
    for (final chunk in _chunks(ids.toList(growable: false))) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      result.addAll(
        await _query('SELECT * FROM $table WHERE $column IN ($marks)', chunk),
      );
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _selectByStringIds(
    String table,
    String column,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const <Map<String, Object?>>[];
    final result = <Map<String, Object?>>[];
    for (final chunk in _chunks(ids.toList(growable: false))) {
      final marks = List<String>.filled(chunk.length, '?').join(', ');
      result.addAll(
        await _query('SELECT * FROM $table WHERE $column IN ($marks)', chunk),
      );
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _query(
    String sql,
    List<Object> params,
  ) async {
    final rows = await _db
        .customSelect(
          sql,
          variables: params.map(Variable<Object>.new).toList(growable: false),
        )
        .get();
    return rows
        .map((row) => Map<String, Object?>.from(row.data))
        .toList(growable: false);
  }
}

List<Map<String, Object?>> _dedupePackItems(List<Map<String, Object?>> items) {
  final seen = <String>{};
  final result = <Map<String, Object?>>[];
  for (final item in items) {
    final key = '${item['pack_id']}\u0000${item['word_id']}';
    if (seen.add(key)) result.add(item);
  }
  return result;
}

Iterable<List<T>> _chunks<T>(List<T> items) sync* {
  for (var start = 0; start < items.length; start += lanSyncSqlBatchSize) {
    final end = start + lanSyncSqlBatchSize;
    yield items.sublist(start, end > items.length ? items.length : end);
  }
}

int? _intOf(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

int _wallClockMs() => DateTime.now().millisecondsSinceEpoch;
