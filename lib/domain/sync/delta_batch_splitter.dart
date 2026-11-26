/// 将本机增量同步载荷按父表依赖切分为自包含分片（纯 Dart）。
///
/// Vercel Serverless 单次请求体上限为 4.5 MB。本拆分器保证：
/// 1. 日常增量（整体原始 JSON ≤ `maxBatchBytes`）走单批快速路径，零额外往返；
/// 2. 大词库首次同步时严格按父表优先切分：
///    `words` → `word_contents` → `study_sessions + study_session_items`
///    → `review_logs` → `settings + word_packs + word_pack_items`；
/// 3. 每个分片自动携带最小化的 `word_refs` / `session_refs` / `item_refs`，
///    使服务端每批都可独立幂等合并且体积远低于 4.5 MB 上限。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/backup/incremental_sync_payload.dart';

/// 一批可独立推送给 `/api/sync/push` 的增量数据。
class CloudSyncPushBatch {
  /// 以表数据、身份引用表与估算字节数构造。
  const new({
    required this.tables,
    this.wordRefs = const <Map<String, Object?>>[],
    this.sessionRefs = const <Map<String, Object?>>[],
    this.itemRefs = const <Map<String, Object?>>[],
    this.estimatedRawBytes = 0,
  });

  /// 按表名索引的本批行数据。
  final Map<String, List<Map<String, Object?>>> tables;

  /// 本批引用的词条最小身份存根。
  final List<Map<String, Object?>> wordRefs;

  /// 本批引用的会话最小身份存根（供跨批 `review_logs` 还原会话外键）。
  final List<Map<String, Object?>> sessionRefs;

  /// 本批引用的会话题目最小身份存根（供跨批 `review_logs` 还原题目外键）。
  final List<Map<String, Object?>> itemRefs;

  /// 估算的原始 JSON 字节数。
  final int estimatedRawBytes;

  /// 本批包含的有效业务行数。
  int get rowCount => tables.values.fold(0, (sum, rows) => sum + rows.length);
}

/// 将 [payload] 切分为若干体积受控的自包含推送分片。
List<CloudSyncPushBatch> splitDeltaIntoPushBatches(
  IncrementalSyncPayload payload, {
  int maxBatchBytes = cloudSyncMaxBatchRawBytes,
}) {
  if (payload.totalRows == 0) return const <CloudSyncPushBatch>[];
  final fullBytes = utf8.encode(jsonEncode(payload.toEnvelope())).length;
  if (fullBytes <= maxBatchBytes) {
    return <CloudSyncPushBatch>[
      CloudSyncPushBatch(
        tables: payload.tables,
        wordRefs: payload.wordRefs,
        estimatedRawBytes: fullBytes,
      ),
    ];
  }
  return _BatchSplitter(payload, maxBatchBytes).split();
}

class _BatchSplitter {
  new(this.payload, this.maxBatchBytes) {
    _indexRefs();
  }

  final IncrementalSyncPayload payload;
  final int maxBatchBytes;

  final Map<int, Map<String, Object?>> _wordRefById =
      <int, Map<String, Object?>>{};
  final Map<int, Map<String, Object?>> _sessionRefById =
      <int, Map<String, Object?>>{};
  final Map<int, Map<String, Object?>> _itemRefById =
      <int, Map<String, Object?>>{};

  List<CloudSyncPushBatch> split() {
    final batches = <CloudSyncPushBatch>[];
    _splitSimpleTable('words', batches);
    _splitSimpleTable('word_contents', batches, attachWordRefs: true);
    _splitSessions(batches);
    _splitReviewLogs(batches);
    _splitSimpleTable('settings', batches);
    _splitSimpleTable('word_packs', batches);
    _splitSimpleTable('word_pack_items', batches, attachWordRefs: true);
    return batches;
  }

  void _indexRefs() {
    for (final ref in payload.wordRefs) {
      final id = _intOf(ref['id']);
      if (id != null) _wordRefById[id] = ref;
    }
    for (final word in _rows('words')) {
      final id = _intOf(word['id']);
      if (id == null) continue;
      _wordRefById[id] = <String, Object?>{
        'id': id,
        'normalized_term': word['normalized_term'],
        'source_language': word['source_language'],
        'target_language': word['target_language'],
      };
    }
    for (final session in _rows('study_sessions')) {
      final id = _intOf(session['id']);
      if (id == null) continue;
      _sessionRefById[id] = <String, Object?>{
        'id': id,
        'started_at': session['started_at'],
        'session_type': session['session_type'],
        'source_type': session['source_type'],
      };
    }
    for (final item in _rows('study_session_items')) {
      final id = _intOf(item['id']);
      if (id == null) continue;
      _itemRefById[id] = <String, Object?>{
        'id': id,
        'study_session_id': item['study_session_id'],
        'position': item['position'],
      };
    }
  }

  void _splitSimpleTable(
    String table,
    List<CloudSyncPushBatch> out, {
    bool attachWordRefs = false,
  }) {
    final rows = _rows(table);
    if (rows.isEmpty) return;
    var bucket = <Map<String, Object?>>[];
    var bytes = 0;

    void flush() {
      if (bucket.isEmpty) return;
      final refs = attachWordRefs
          ? _collectWordRefs(bucket)
          : const <Map<String, Object?>>[];
      out.add(
        CloudSyncPushBatch(
          tables: <String, List<Map<String, Object?>>>{table: bucket},
          wordRefs: refs,
          estimatedRawBytes: bytes,
        ),
      );
      bucket = <Map<String, Object?>>[];
      bytes = 0;
    }

    for (final row in rows) {
      final rowBytes = _estimateRowBytes(row);
      if (bucket.isNotEmpty && bytes + rowBytes > maxBatchBytes) flush();
      bucket.add(row);
      bytes += rowBytes;
    }
    flush();
  }

  void _splitSessions(List<CloudSyncPushBatch> out) {
    final sessions = _rows('study_sessions');
    if (sessions.isEmpty) return;
    final itemsBySession = _groupBySession(_rows('study_session_items'));
    var batchSessions = <Map<String, Object?>>[];
    var batchItems = <Map<String, Object?>>[];
    var bytes = 0;

    void flush() {
      if (batchSessions.isEmpty) return;
      out.add(
        CloudSyncPushBatch(
          tables: <String, List<Map<String, Object?>>>{
            'study_sessions': batchSessions,
            'study_session_items': batchItems,
          },
          wordRefs: _collectWordRefs(batchItems),
          estimatedRawBytes: bytes,
        ),
      );
      batchSessions = <Map<String, Object?>>[];
      batchItems = <Map<String, Object?>>[];
      bytes = 0;
    }

    for (final session in sessions) {
      final items =
          itemsBySession[_intOf(session['id'])] ??
          const <Map<String, Object?>>[];
      final unitBytes = _estimateRowBytes(session) + _estimateListBytes(items);
      if (batchSessions.isNotEmpty && bytes + unitBytes > maxBatchBytes) {
        flush();
      }
      batchSessions.add(session);
      batchItems.addAll(items);
      bytes += unitBytes;
    }
    flush();
  }

  void _splitReviewLogs(List<CloudSyncPushBatch> out) {
    final logs = _rows('review_logs');
    if (logs.isEmpty) return;
    var bucket = <Map<String, Object?>>[];
    var bytes = 0;

    void flush() {
      if (bucket.isEmpty) return;
      out.add(
        CloudSyncPushBatch(
          tables: <String, List<Map<String, Object?>>>{'review_logs': bucket},
          wordRefs: _collectWordRefs(bucket),
          sessionRefs: _collectSessionRefs(bucket),
          itemRefs: _collectItemRefs(bucket),
          estimatedRawBytes: bytes,
        ),
      );
      bucket = <Map<String, Object?>>[];
      bytes = 0;
    }

    for (final row in logs) {
      final rowBytes = _estimateRowBytes(row);
      if (bucket.isNotEmpty && bytes + rowBytes > maxBatchBytes) flush();
      bucket.add(row);
      bytes += rowBytes;
    }
    flush();
  }

  List<Map<String, Object?>> _collectWordRefs(List<Map<String, Object?>> rows) {
    final seen = <int>{};
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final wid = _intOf(row['word_id']);
      if (wid == null || !seen.add(wid)) continue;
      final ref = _wordRefById[wid];
      if (ref != null) result.add(ref);
    }
    return result;
  }

  List<Map<String, Object?>> _collectSessionRefs(
    List<Map<String, Object?>> logs,
  ) {
    final seen = <int>{};
    final result = <Map<String, Object?>>[];
    for (final row in logs) {
      final sid = _intOf(row['study_session_id']);
      if (sid == null || !seen.add(sid)) continue;
      final ref = _sessionRefById[sid];
      if (ref != null) result.add(ref);
    }
    return result;
  }

  List<Map<String, Object?>> _collectItemRefs(List<Map<String, Object?>> logs) {
    final seen = <int>{};
    final result = <Map<String, Object?>>[];
    for (final row in logs) {
      final itemId = _intOf(row['study_session_item_id']);
      if (itemId == null || !seen.add(itemId)) continue;
      final ref = _itemRefById[itemId];
      if (ref != null) result.add(ref);
    }
    return result;
  }

  List<Map<String, Object?>> _rows(String table) =>
      payload.tables[table] ?? const <Map<String, Object?>>[];
}

Map<int, List<Map<String, Object?>>> _groupBySession(
  List<Map<String, Object?>> items,
) {
  final grouped = <int, List<Map<String, Object?>>>{};
  for (final item in items) {
    final sid = _intOf(item['study_session_id']);
    if (sid == null) continue;
    grouped.putIfAbsent(sid, () => <Map<String, Object?>>[]).add(item);
  }
  return grouped;
}

int _estimateRowBytes(Map<String, Object?> row) =>
    utf8.encode(jsonEncode(row)).length + cloudSyncRowOverheadBytes;

int _estimateListBytes(List<Map<String, Object?>> rows) =>
    rows.fold(0, (sum, row) => sum + _estimateRowBytes(row));

int? _intOf(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}
