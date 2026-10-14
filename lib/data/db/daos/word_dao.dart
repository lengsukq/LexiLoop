/// 词条查询。
///
/// 只读查询集中在此，便于统计与调试；写入走各自的 service。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

/// 列表查询的 SQL。
///
/// `meaning` 用相关子查询取目标语言的第一条释义作为列表摘要——
/// 比逐条再查一次 `word_contents` 少 N 次往返。
/// 注意 SQL 里的 `$` 必须转义，否则会被 Dart 当作字符串插值。
const String _listSql = r'''
SELECT
  w.id, w.term, w.source_language, w.target_language, w.content_type,
  w.initialization_status, w.mastery_level, w.mastery_score,
  w.is_suspended, w.created_at,
  (
    SELECT json_extract(value, '$.text')
    FROM json_each(wc.definitions_json)
    WHERE json_extract(value, '$.language') = w.target_language
    LIMIT 1
  ) AS meaning
FROM words w
LEFT JOIN word_contents wc ON wc.word_id = w.id
''';

/// 词条列表的一行（含内容摘要，避免逐条再查）。
class WordListEntry {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.term,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
    required this.initializationStatus,
    required this.masteryLevel,
    required this.masteryScore,
    required this.isSuspended,
    required this.createdAt,
    required this.meaning,
  });

  /// 词条 ID。
  final int id;

  /// 展示用文本（单词按语言规则归一化后的形态）。
  final String term;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 内容类型（单词 / 短语 / 句子）。
  final LexicalContentType contentType;

  /// 初始化状态。
  final InitializationStatus initializationStatus;

  /// 掌握等级。
  final MasteryLevel masteryLevel;

  /// 掌握分。
  final int masteryScore;

  /// 是否已暂停学习。
  final bool isSuspended;

  /// 创建时间（epoch 毫秒）。
  final int createdAt;

  /// 目标语言的第一条释义文本，用于列表摘要；无内容时为 `null`。
  final String? meaning;
}

/// 列表查询条件。
class WordQuery {
  /// 以筛选条件构造。
  const new({
    this.search = '',
    this.masteryLevel,
    this.initializationStatus,
    this.limit = 40,
    this.offset = 0,
  });

  /// 关键词（匹配词条文本，大小写不敏感）。
  final String search;

  /// 按掌握等级筛选。
  final MasteryLevel? masteryLevel;

  /// 按初始化状态筛选。
  final InitializationStatus? initializationStatus;

  /// 每页条数。
  final int limit;

  /// 偏移量。
  final int offset;
}

/// 组装后的筛选片段。
///
/// `list` 与 `count` 共用同一套条件构造，避免两处逻辑漂移——
/// 旧版就有「候选词 SQL 在两处各写一遍」的问题。
class _Filter {
  const new(this.whereClause, this.variables);

  final String whereClause;
  final List<Variable<Object>> variables;
}

_Filter _buildFilter(WordQuery query, {required String prefix}) {
  final conditions = <String>[];
  final variables = <Variable<Object>>[];

  final search = query.search.trim();
  if (search.isNotEmpty) {
    conditions.add('${prefix}term LIKE ?');
    variables.add(Variable<String>('%$search%'));
  }
  if (query.masteryLevel != null) {
    conditions.add('${prefix}mastery_level = ?');
    variables.add(Variable<String>(query.masteryLevel!.wire));
  }
  if (query.initializationStatus != null) {
    conditions.add('${prefix}initialization_status = ?');
    variables.add(Variable<String>(query.initializationStatus!.wire));
  }

  final clause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
  return _Filter(clause, variables);
}

/// 词条查询入口。
class WordDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 按条件分页查询词条。
  Future<List<WordListEntry>> list(WordQuery query) async {
    final filter = _buildFilter(query, prefix: 'w.');
    final rows = await _db
        .customSelect(
          '$_listSql ${filter.whereClause} '
          'ORDER BY w.created_at DESC, w.id DESC LIMIT ? OFFSET ?',
          variables: <Variable<Object>>[
            ...filter.variables,
            Variable<int>(query.limit),
            Variable<int>(query.offset),
          ],
        )
        .get();

    return rows.map(_mapRow).toList(growable: false);
  }

  /// 统计符合条件的词条总数。
  Future<int> count(WordQuery query) async {
    final filter = _buildFilter(query, prefix: '');
    final row = await _db
        .customSelect(
          'SELECT count(*) AS c FROM words ${filter.whereClause}',
          variables: filter.variables,
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// 按掌握等级统计词条数，用于概览。
  Future<Map<MasteryLevel, int>> countByMastery() async {
    final rows = await _db
        .customSelect(
          'SELECT mastery_level, count(*) AS c FROM words '
          'GROUP BY mastery_level',
        )
        .get();

    final result = <MasteryLevel, int>{};
    for (final row in rows) {
      final level = wireLookup(
        MasteryLevel.values,
        row.read<String>('mastery_level'),
      );
      if (level != null) result[level] = row.read<int>('c');
    }
    return result;
  }

  WordListEntry _mapRow(QueryRow row) {
    return WordListEntry(
      id: row.read<int>('id'),
      term: row.read<String>('term'),
      sourceLanguage: row.read<String>('source_language'),
      targetLanguage: row.read<String>('target_language'),
      contentType:
          wireLookup(
            LexicalContentType.values,
            row.read<String>('content_type'),
          ) ??
          LexicalContentType.word,
      initializationStatus:
          wireLookup(
            InitializationStatus.values,
            row.read<String>('initialization_status'),
          ) ??
          InitializationStatus.pending,
      masteryLevel:
          wireLookup(MasteryLevel.values, row.read<String>('mastery_level')) ??
          MasteryLevel.newWord,
      masteryScore: row.read<int>('mastery_score'),
      isSuspended: row.read<int>('is_suspended') != 0,
      createdAt: row.read<int>('created_at'),
      meaning: row.read<String?>('meaning'),
    );
  }
}
