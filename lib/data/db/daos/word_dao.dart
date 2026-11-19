/// 词条查询。
///
/// 只读查询集中在此，便于统计与调试；写入走各自的 service。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/dictionary/content_parse.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 列表查询的 SQL。
///
/// `meaning` 用相关子查询取目标语言的第一条释义作为列表摘要——
/// 比逐条再查一次 `word_contents` 少 N 次往返。
/// 注意 SQL 里的 `$` 必须转义，否则会被 Dart 当作字符串插值。
///
/// 三张 LEFT JOIN 表的主键都是 `word_id`，因此不会放大行数：
/// `count()` 可以原样复用同一组 JOIN 与 WHERE。
const String _listSql = r'''
SELECT
  w.id, w.term, w.source_language, w.target_language, w.content_type,
  w.initialization_status, w.mastery_level, w.mastery_score,
  w.is_suspended, w.created_at, w.source_created_at,
  rc.due_at, COALESCE(ws.active, 0) AS wrong_active,
  wc.pronunciations_json,
  (
    SELECT json_extract(value, '$.text')
    FROM json_each(wc.definitions_json)
    WHERE json_extract(value, '$.language') = w.target_language
    LIMIT 1
  ) AS meaning
FROM words w
LEFT JOIN word_contents wc ON wc.word_id = w.id
LEFT JOIN review_cards rc ON rc.word_id = w.id
LEFT JOIN wrong_word_states ws ON ws.word_id = w.id
''';

/// 总数查询的 SQL：与 [_listSql] 共用同一组 JOIN 与 WHERE 片段。
///
/// 缺 `word_contents` 的 JOIN——`count(*)` 不需要释义摘要，
/// 而 `LEFT JOIN` 一张 TEXT 大表对纯计数毫无帮助。
const String _countSql = '''
SELECT count(*) AS c
FROM words w
LEFT JOIN review_cards rc ON rc.word_id = w.id
LEFT JOIN wrong_word_states ws ON ws.word_id = w.id
''';

/// 关键词命中的列数（`term` / `normalized_term` / `user_note`）。
///
/// 三个列共用同一个转义后的模式串，因此占位符个数必须与模式串个数一致；
/// 写成常量是为了让「加一列搜索」时编译期就暴露忘了补的占位符。
const int _searchColumnCount = 3;

/// 关键词条件：匹配词条文本、归一化文本与用户备注。
///
/// 用 `LIKE ... ESCAPE '\'` 而不是 `ILIKE`：SQLite 的 `LIKE` 本身对 ASCII
/// 大小写不敏感，少一层方言依赖，也少一个需要单独测试的大小写分支。
/// `user_note` 外面套 `COALESCE`：备注可空，直接比较会把整行变成 NULL。
const String _searchCondition = r"""
(w.term LIKE ? ESCAPE '\'
 OR w.normalized_term LIKE ? ESCAPE '\'
 OR COALESCE(w.user_note, '') LIKE ? ESCAPE '\')
""";

/// 转义 `LIKE` 模式里的通配符。
///
/// 用户在搜索框里打 `%`、`_` 或 `\` 时想要的是**字面匹配**，而不是
/// 「匹配任意串」——不转义的话搜索 `100%` 会把整张表都捞出来。
/// 反斜杠必须第一个替换：它自己补出来的 `\%` 会被后续替换再转义一次。
String escapeLikePattern(String value) =>
    value.replaceAllMapped(RegExp(r'[\\%_]'), (match) => '\\${match[0]}');

/// 词条列表的排序方式。
enum WordSort {
  /// 按词条进入本地库的时间（默认，与旧版一致）。
  createdAt('创建时间'),

  /// 按词条的「收藏时间」（导入源自带的创建时间）。
  sourceCreatedAt('来源时间'),

  /// 按词形字典序。
  term('词形'),

  /// 按掌握分。
  masteryScore('掌握度'),

  /// 按复习卡的到期时间。
  dueAt('到期时间');

  new(this.label);

  /// 界面上的排序名。
  final String label;

  /// `ORDER BY` 片段。
  ///
  /// **每一档都以 `w.id DESC` 收尾**，这是本页分页正确的前提：
  /// 排序键（时间、词形、分数、到期）大量重复，单靠它排序时 SQLite
  /// 对相同键的行不保证稳定顺序，翻页会出现同一行既在第一页又在第二页。
  /// `id` 唯一且随插入递增，因此「同键按 id 倒序」既稳定又符合
  /// 「新导入的排前面」的心智。
  String get orderBy => switch (this) {
    WordSort.createdAt => 'w.created_at DESC, w.id DESC',
    WordSort.sourceCreatedAt =>
      'COALESCE(w.source_created_at, w.created_at) DESC, w.id DESC',
    WordSort.term => 'w.normalized_term ASC, w.id DESC',
    WordSort.masteryScore => 'w.mastery_score DESC, w.id DESC',
    WordSort.dueAt =>
      'CASE WHEN rc.due_at IS NULL THEN 1 ELSE 0 END ASC, '
          'rc.due_at DESC, w.id DESC',
  };
}

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
    required this.sourceCreatedAt,
    required this.dueAt,
    required this.wrongWordActive,
    required this.meaning,
    required this.pronunciations,
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

  /// 来源时间（导入源自带的创建时间，epoch 毫秒）；源数据没有时为 `null`。
  final int? sourceCreatedAt;

  /// 复习卡到期时间（epoch 毫秒）；尚未建立卡片时为 `null`。
  final int? dueAt;

  /// 是否处于活跃错词状态。
  final bool wrongWordActive;

  /// 目标语言的第一条释义文本，用于列表摘要；无内容时为 `null`。
  final String? meaning;

  /// 发音列表（`pronunciations_json`）。
  ///
  /// 列表页的朗读按钮要用它取真人录音地址：`WordSpeaker` 优先播放词典
  /// 提供的 mp3，拿不到才回落到系统朗读。逐条再查一次 `word_contents`
  /// 会让一页 40 张卡片多 40 次往返，因此随列表一次取回。
  final List<PronunciationView> pronunciations;
}

/// 列表查询条件。
class WordQuery {
  /// 以筛选条件构造。
  const new({
    this.search = '',
    this.masteryLevel,
    this.initializationStatus,
    this.wrongOnly = false,
    this.dueOnly = false,
    this.suspendedOnly = false,
    this.sort = WordSort.createdAt,
    this.limit = wordListPageSize,
    this.offset = 0,
  });

  /// 关键词（匹配词条文本、归一化文本与用户备注，大小写不敏感）。
  final String search;

  /// 按掌握等级筛选。
  final MasteryLevel? masteryLevel;

  /// 按初始化状态筛选。
  final InitializationStatus? initializationStatus;

  /// 只看活跃错词（`wrong_word_states.active`）。
  final bool wrongOnly;

  /// 只看今天已经到期的复习卡。
  final bool dueOnly;

  /// 只看已暂停学习的词条。
  final bool suspendedOnly;

  /// 排序方式。
  final WordSort sort;

  /// 每页条数。
  final int limit;

  /// 偏移量。
  final int offset;

  /// 当前页（1 起）。
  int get page => limit < 1 ? 1 : offset ~/ limit + 1;

  /// 生效中的筛选个数（不含关键词）。
  ///
  /// 关键词不算「筛选」：它有自己的清除按钮，而这里的计数要回答的是
  /// 「我的结果为什么变少了」。与旧版 `activeFilterCount` 的口径一致。
  int get activeFilterCount =>
      (masteryLevel != null ? 1 : 0) +
      (initializationStatus != null ? 1 : 0) +
      (wrongOnly ? 1 : 0) +
      (dueOnly ? 1 : 0) +
      (suspendedOnly ? 1 : 0);

  /// 复制并覆盖部分字段。
  ///
  /// **不复位页码**：页码复位由界面侧的通知器统一做，因为它还要区分
  /// 「改筛选」与「翻页」两种意图，在这里一刀切会让 `goToPage` 无效。
  WordQuery copyWith({
    String? search,
    MasteryLevel? masteryLevel,
    bool clearMasteryLevel = false,
    InitializationStatus? initializationStatus,
    bool clearInitializationStatus = false,
    bool? wrongOnly,
    bool? dueOnly,
    bool? suspendedOnly,
    WordSort? sort,
    int? limit,
    int? offset,
  }) => WordQuery(
    search: search ?? this.search,
    masteryLevel: clearMasteryLevel
        ? null
        : (masteryLevel ?? this.masteryLevel),
    initializationStatus: clearInitializationStatus
        ? null
        : (initializationStatus ?? this.initializationStatus),
    wrongOnly: wrongOnly ?? this.wrongOnly,
    dueOnly: dueOnly ?? this.dueOnly,
    suspendedOnly: suspendedOnly ?? this.suspendedOnly,
    sort: sort ?? this.sort,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
  );
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

_Filter _buildFilter(WordQuery query) {
  final conditions = <String>[];
  final variables = <Variable<Object>>[];

  final search = query.search.trim();
  if (search.isNotEmpty) {
    final pattern = '%${escapeLikePattern(search)}%';
    conditions.add(_searchCondition);
    variables.addAll(<Variable<Object>>[
      for (var i = 0; i < _searchColumnCount; i += 1) Variable<String>(pattern),
    ]);
  }
  if (query.masteryLevel != null) {
    conditions.add('w.mastery_level = ?');
    variables.add(Variable<String>(query.masteryLevel!.wire));
  }
  if (query.initializationStatus != null) {
    conditions.add('w.initialization_status = ?');
    variables.add(Variable<String>(query.initializationStatus!.wire));
  }
  // 错词是 LEFT JOIN 来的，没有对应行时 COALESCE 才能把它排除掉；
  // 写成 `ws.active = 1` 会让 LEFT JOIN 退化成 INNER JOIN 的效果。
  if (query.wrongOnly) conditions.add('COALESCE(ws.active, 0) = 1');
  if (query.suspendedOnly) conditions.add('w.is_suspended = 1');
  if (query.dueOnly) {
    conditions.add('rc.due_at <= ?');
    variables.add(Variable<int>(DateTime.now().millisecondsSinceEpoch));
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
    final filter = _buildFilter(query);
    final rows = await _db
        .customSelect(
          '$_listSql ${filter.whereClause} '
          'ORDER BY ${query.sort.orderBy} LIMIT ? OFFSET ?',
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
    final filter = _buildFilter(query);
    final row = await _db
        .customSelect(
          '$_countSql ${filter.whereClause}',
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
      sourceCreatedAt: row.read<int?>('source_created_at'),
      dueAt: row.read<int?>('due_at'),
      wrongWordActive: row.read<int>('wrong_active') != 0,
      meaning: row.read<String?>('meaning'),
      pronunciations: parsePronunciations(
        row.read<String?>('pronunciations_json'),
      ),
    );
  }
}
