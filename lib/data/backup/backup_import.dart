/// 旧版 JSON 备份的导入。
///
/// 备份由旧版 `/api/backups/json` 导出，格式为 `lexiloop-json-backup` v3，
/// 含 12 张表（不含 `word_review_stats` / `game_high_scores` /
/// `daily_ai_suggestions`）。
///
/// **列映射为什么是直接对应**：Drift 默认把驼峰列名转成下划线
/// （`normalizedTerm` → `normalized_term`），与旧版 PostgreSQL 的列名一致；
/// 枚举也存同样的大写下划线标识。少数例外（如 `recent_again_30d`）已在
/// 表定义里用 `.named()` 显式对齐，并由 `column_names_test.dart` 守卫。
///
/// **未知列的处理**：按目标表的实际列做交集过滤，忽略备份中多余的列。
/// 这比旧版「从首行 keys 推导列名」更稳——后者在行间 key 不一致时会出错。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

/// 备份文件的格式标识。
const String backupFormat = 'lexiloop-json-backup';

/// 由 `review_logs` 重算 `word_review_stats` 的 SQL。
///
/// 备份不含这张物化统计表，必须重算——否则学习队列的排序权重
/// （`recent_wrong_14d` 等）全是 0，复习优先级会完全失效。
///
/// 参数顺序：30 天前、14 天前 ×3、当前时间。
const String _recomputeStatsSql = '''
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
GROUP BY word_id
''';

/// 各表中存枚举的列，导入时按 wire 值校验。
///
/// **为什么必须校验**：导入走原始 SQL，绕过了 Drift 的 TypeConverter。
/// 若不校验，备份里一个拼错的枚举值会被静默写入，直到某次读取时才抛错——
/// 那时已经很难定位来源。
const Map<String, Map<String, List<WireEnum>>> _enumColumns =
    <String, Map<String, List<WireEnum>>>{
      'words': <String, List<WireEnum>>{
        'entry_type': EntryType.values,
        'content_type': LexicalContentType.values,
        'initialization_status': InitializationStatus.values,
        'mastery_level': MasteryLevel.values,
      },
      'word_contents': <String, List<WireEnum>>{
        'content_source': ContentSource.values,
      },
      'study_sessions': <String, List<WireEnum>>{
        'session_type': StudyMode.values,
      },
      'study_session_items': <String, List<WireEnum>>{
        'task_type': StudyTaskType.values,
        'question_type': QuestionType.values,
        'status': StudyItemStatus.values,
      },
      'review_logs': <String, List<WireEnum>>{
        'rating': ReviewRating.values,
        'question_type': QuestionType.values,
      },
      'import_batches': <String, List<WireEnum>>{
        'import_mode': ImportMode.values,
        'status': ImportBatchStatus.values,
      },
      'import_rows': <String, List<WireEnum>>{'status': ImportRowStatus.values},
      'initialization_jobs': <String, List<WireEnum>>{
        'task_type': JobTaskType.values,
        'mode': InitializationMode.values,
        'provider_strategy': ProviderStrategy.values,
        'status': InitializationStatus.values,
      },
      'provider_attempts': <String, List<WireEnum>>{
        'status': ProviderAttemptStatus.values,
      },
      'daily_ai_suggestions': <String, List<WireEnum>>{
        'generator': SuggestionGenerator.values,
      },
    };

/// 导入结果。
class BackupImportResult {
  /// 以各表导入行数与重算的统计数构造。
  const new({required this.rowCounts, required this.recomputedStats});

  /// 各表实际导入的行数。
  final Map<String, int> rowCounts;

  /// 由 `review_logs` 重算回填的 `word_review_stats` 行数。
  final int recomputedStats;

  /// 导入的总行数。
  int get totalRows => rowCounts.values.fold(0, (sum, count) => sum + count);
}

/// 解析一份备份的原始文本，返回「表名 → 行」。
///
/// **为什么把解析与写入拆开**：导入（全量替换）与合并同步都需要这份解析，
/// 而它们对「写进去什么」有完全不同的打算。解析只负责「这份文件是不是
/// 一份合法备份」，写库由 [BackupImporter.replaceAll] 负责。
///
/// 表集合恒为 [BackupImporter.tableOrder]；备份里缺的表返回空列表，
/// 备份里多的表被忽略（前进兼容）。
Map<String, List<Map<String, Object?>>> parseBackupPayload(String raw) {
  if (raw.length > maxBackupBytes) {
    throw const ValidationError(AppErrorCode.backupTooLarge);
  }
  final decoded = _decodeBackupJson(raw);
  _assertBackupHeader(decoded);

  final result = <String, List<Map<String, Object?>>>{};
  for (final table in BackupImporter.tableOrder) {
    result[table] = _parseBackupTable(
      table,
      decoded is Map<String, Object?> ? decoded[table] : null,
    );
  }
  return result;
}

Object? _decodeBackupJson(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException catch (error) {
    throw ValidationError(
      AppErrorCode.backupInvalidJson,
      details: error.message,
    );
  }
}

void _assertBackupHeader(Object? decoded) {
  if (decoded is! Map<String, Object?>) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  if (decoded['format'] != backupFormat) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
  if (decoded['version'] is! num) {
    throw const ValidationError(AppErrorCode.backupInvalidFormat);
  }
}

List<Map<String, Object?>> _parseBackupTable(String table, Object? value) {
  if (value == null) return const <Map<String, Object?>>[];
  if (value is! List) {
    throw ValidationError(
      AppErrorCode.backupInvalidFormat,
      details: '表 $table 不是数组',
    );
  }

  final rows = <Map<String, Object?>>[];
  for (final row in value) {
    if (row is! Map<String, Object?>) {
      throw ValidationError(
        AppErrorCode.backupInvalidFormat,
        details: '表 $table 含非法行',
      );
    }
    rows.add(row);
  }
  return rows;
}

/// 旧版备份的导入器。
class BackupImporter {
  /// 以数据库构造导入器。
  const new(this._db);

  final AppDatabase _db;

  /// 备份中的表，按**父表优先**顺序排列（插入顺序）。
  ///
  /// 顺序不能随意调整：子表有外键指向父表，SQLite 开启外键后
  /// 先插子表会直接失败。
  static const List<String> tableOrder = <String>[
    'words',
    'word_contents',
    'study_sessions',
    'study_session_items',
    'review_cards',
    'review_logs',
    'wrong_word_states',
    'import_batches',
    'import_rows',
    'initialization_jobs',
    'provider_attempts',
    'settings',
    'word_packs',
    'word_pack_items',
  ];

  /// 解析并导入备份，返回各表行数。
  ///
  /// 整个过程在**单个事务**内完成：要么全部替换成功，要么原数据不变。
  /// 导入前会清空这 12 张表——旧版的语义就是「全量替换」。
  ///
  /// 用 `Future.sync` 而不是裸调用：解析是同步的，它的异常必须变成
  /// **Future 的失败**而不是同步抛出——本地导入、远端恢复、局域网拉取三条
  /// 链路都把它当 Future 处理（`on AppError catch` 挂在 await 上）。
  Future<BackupImportResult> import(String raw) =>
      Future<BackupImportResult>.sync(
        () => replaceAll(parseBackupPayload(raw)),
      );

  /// 用一批**已经解析好的行**整体替换这 12 张表。
  ///
  /// **为什么单独暴露这一层**：合并同步先在自己的数据结构里算出「合并后的 12 张表」，
  /// 再交给这里落库。让合并自己重新实现一遍「清表 + 按父表序插入 + 重算统计」，
  /// 就是又一处需要与这里同步维护、且更难测的写事务。
  ///
  /// 传入的映射里缺少某张表时按空表处理（与「备份里没有这张表」同义）。
  Future<BackupImportResult> replaceAll(
    Map<String, List<Map<String, Object?>>> tables,
  ) async {
    final rowCounts = <String, int>{};

    await _db.transaction(() async {
      await _clearTables();
      for (final table in tableOrder) {
        final rows = tables[table] ?? const <Map<String, Object?>>[];
        rowCounts[table] = rows.length;
        if (rows.isEmpty) continue;
        await _insertRows(table, rows);
      }
      await _recomputeWordReviewStats();
    });

    final stats = await _db
        .customSelect('SELECT count(*) AS c FROM word_review_stats')
        .getSingle();

    return BackupImportResult(
      rowCounts: rowCounts,
      recomputedStats: stats.read<int>('c'),
    );
  }

  /// 清空待导入的表（子表在前，避免外键报错）。
  Future<void> _clearTables() async {
    for (final table in tableOrder.reversed) {
      await _db.customStatement('DELETE FROM $table');
    }
  }

  /// 批量插入某张表的全部行。
  Future<void> _insertRows(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    final columns = await _actualColumns(table);
    // 只保留目标表真实存在的列，忽略备份中多余的列。
    final usable = columns
        .where((column) => rows.first.containsKey(column))
        .toList(growable: false);
    if (usable.isEmpty) return;

    _assertEnumValues(table, rows, usable);

    final placeholders = List<String>.filled(usable.length, '?').join(', ');
    final sql =
        'INSERT INTO $table (${usable.join(', ')}) '
        'VALUES ($placeholders)';

    await _db.batch((batch) {
      for (final row in rows) {
        batch.customStatement(
          sql,
          usable.map((column) => row[column]).toList(growable: false),
        );
      }
    });
  }

  /// 校验枚举列取值合法。
  void _assertEnumValues(
    String table,
    List<Map<String, Object?>> rows,
    List<String> usable,
  ) => assertBackupEnumValues(table, rows, usable);

  /// 读取目标表的实际列名。
  Future<List<String>> _actualColumns(String table) async {
    final rows = await _db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((row) => row.read<String>('name')).toList(growable: false);
  }

  Future<void> _recomputeWordReviewStats() async {
    const dayMs = 24 * 60 * 60 * 1000;
    final now = DateTime.now().millisecondsSinceEpoch;
    final since14 = now - 14 * dayMs;
    final since30 = now - 30 * dayMs;

    await _db.customStatement(_recomputeStatsSql, <Object?>[
      since30,
      since14,
      since14,
      since14,
      now,
    ]);
  }
}

/// 校验备份或增量载荷里 [table] 的枚举列取值合法（SSOT，供全量导入与增量合用）。
void assertBackupEnumValues(
  String table,
  List<Map<String, Object?>> rows,
  List<String> usable,
) {
  final enumColumns = _enumColumns[table];
  if (enumColumns == null) return;

  for (final entry in enumColumns.entries) {
    if (!usable.contains(entry.key)) continue;
    for (final row in rows) {
      final value = row[entry.key];
      if (value == null) continue;
      if (value is! String || wireLookup(entry.value, value) == null) {
        throw ValidationError(
          AppErrorCode.backupInvalidFormat,
          details: '表 $table 的 ${entry.key} 含未知取值：$value',
        );
      }
    }
  }
}
