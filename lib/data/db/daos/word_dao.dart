/// 词条查询。
///
/// 只读查询集中在此，便于统计与调试；写入走各自的 service。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/dictionary/content_parse.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';

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
  w.is_suspended, w.is_personal, w.created_at, w.source_created_at,
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
/// 包含 `word_contents` 的 LEFT JOIN，以便关键词命中释义/标签以及按标签筛选时
/// `count()` 与 `list()` 共享完全同一组 WHERE 条件。
const String _countSql = '''
SELECT count(*) AS c
FROM words w
LEFT JOIN word_contents wc ON wc.word_id = w.id
LEFT JOIN review_cards rc ON rc.word_id = w.id
LEFT JOIN wrong_word_states ws ON ws.word_id = w.id
''';

/// 导出 CSV 用的查询 SQL（一次取回释义、音标、例句、标签与备注）。
const String _exportSql = '''
SELECT
  w.id, w.term, w.source_language, w.target_language, w.user_note,
  wc.definitions_json, wc.pronunciations_json, wc.examples_json, wc.tags_json
FROM words w
LEFT JOIN word_contents wc ON wc.word_id = w.id
LEFT JOIN review_cards rc ON rc.word_id = w.id
LEFT JOIN wrong_word_states ws ON ws.word_id = w.id
''';

/// 关键词命中的列数（`term` / `normalized_term` / `user_note` / 释义 / 标签）。
///
/// 五列共用同一个转义后的模式串，因此占位符个数必须与模式串个数一致；
/// 写成常量是为了让「加一列搜索」时编译期就暴露忘了补的占位符。
const int _searchColumnCount = 5;

/// 关键词条件：匹配词条文本、归一化文本、用户备注、中英释义与标签。
///
/// 用 `LIKE ... ESCAPE '\'` 而不是 `ILIKE`：SQLite 的 `LIKE` 本身对 ASCII
/// 大小写不敏感，少一层方言依赖，也少一个需要单独测试的大小写分支。
const String _searchCondition = r"""
(w.term LIKE ? ESCAPE '\'
 OR w.normalized_term LIKE ? ESCAPE '\'
 OR COALESCE(w.user_note, '') LIKE ? ESCAPE '\'
 OR COALESCE(wc.definitions_json, '') LIKE ? ESCAPE '\'
 OR COALESCE(wc.tags_json, '') LIKE ? ESCAPE '\')
""";

/// 标签精确命中条件：要求 `tags_json` 为合法数组且包含目标标签。
const String _tagCondition = '''
(json_valid(wc.tags_json)
 AND json_type(wc.tags_json) = 'array'
 AND EXISTS (SELECT 1 FROM json_each(wc.tags_json) t WHERE t.value = ?))
''';

/// 转义 `LIKE` 模式里的通配符。
///
/// 用户在搜索框里打 `%`、`_` 或 `\` 时想要的是**字面匹配**，而不是
/// 「匹配任意串」——不转义的话搜索 `100%` 会把整张表都捞出来。
/// 反斜杠必须第一个替换：它自己补出来的 `\%` 会被后续替换再转义一次。
String escapeLikePattern(String value) =>
    value.replaceAllMapped(RegExp(r'[\\%_]'), (match) => '\\${match[0]}');

/// 离线语音预缓存用的精简词条目标。
class AudioPrecacheWordTarget {
  /// 以词条文本、内容类型与发音列表构造。
  const new({
    required this.term,
    required this.contentType,
    required this.pronunciations,
  });

  /// 词条文本。
  final String term;

  /// 内容类型（用于过滤整句或走 Edge 补全）。
  final LexicalContentType contentType;

  /// 已存的词典发音条目。
  final List<PronunciationView> pronunciations;
}

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
    this.isPersonal = true,
    this.packNames = const <String>[],
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

  /// 是否属于个人词库（`words.is_personal`）。
  final bool isPersonal;

  /// 所属已安装词书的名称列表（可为空）。
  final List<String> packNames;
}

/// 列表查询条件。
class WordQuery {
  /// 以筛选条件构造。
  const new({
    this.search = '',
    this.masteryLevel,
    this.initializationStatus,
    this.contentType,
    this.tag,
    this.sourceScope = WordSourceScope.all,
    this.packId,
    this.wrongOnly = false,
    this.dueOnly = false,
    this.suspendedOnly = false,
    this.sort = WordSort.createdAt,
    this.limit = wordListPageSize,
    this.offset = 0,
  });

  /// 关键词（匹配词条文本、归一化文本、备注、释义与标签，大小写不敏感）。
  final String search;

  /// 按掌握等级筛选。
  final MasteryLevel? masteryLevel;

  /// 按初始化状态筛选。
  final InitializationStatus? initializationStatus;

  /// 按内容类型筛选（单词 / 短语 / 句子）。
  final LexicalContentType? contentType;

  /// 按标签精确筛选；`null` 或空串表示不筛标签。
  final String? tag;

  /// 来源作用域（全部 / 个人词库 / 词书包）。
  final WordSourceScope sourceScope;

  /// 按指定已安装词书筛选；`null` 表示不限定单本词书。
  final String? packId;

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
      (contentType != null ? 1 : 0) +
      ((tag?.trim().isNotEmpty ?? false) ? 1 : 0) +
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
    LexicalContentType? contentType,
    bool clearContentType = false,
    String? tag,
    bool clearTag = false,
    WordSourceScope? sourceScope,
    String? packId,
    bool clearPackId = false,
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
    contentType: clearContentType ? null : (contentType ?? this.contentType),
    tag: clearTag ? null : (tag ?? this.tag),
    sourceScope: sourceScope ?? this.sourceScope,
    packId: clearPackId ? null : (packId ?? this.packId),
    wrongOnly: wrongOnly ?? this.wrongOnly,
    dueOnly: dueOnly ?? this.dueOnly,
    suspendedOnly: suspendedOnly ?? this.suspendedOnly,
    sort: sort ?? this.sort,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
  );
}

/// 导出 CSV 的单行结构。
class WordExportRow {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.term,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.definitions,
    required this.phonetic,
    required this.examples,
    required this.tags,
    required this.note,
  });

  /// 词条 ID。
  final int id;

  /// 词条文本。
  final String term;

  /// 源语言。
  final String sourceLanguage;

  /// 目标语言。
  final String targetLanguage;

  /// 释义文本列表。
  final List<String> definitions;

  /// 首个音标（无则为空）。
  final String phonetic;

  /// 例句文本列表。
  final List<String> examples;

  /// 标签列表。
  final List<String> tags;

  /// 用户备注。
  final String note;
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
  _addSearchFilter(query.search, conditions, variables);
  _addExactFilters(query, conditions, variables);
  if (query.wrongOnly) conditions.add('COALESCE(ws.active, 0) = 1');
  if (query.suspendedOnly) conditions.add('w.is_suspended = 1');
  if (query.dueOnly) {
    conditions.add('rc.due_at <= ?');
    variables.add(Variable<int>(DateTime.now().millisecondsSinceEpoch));
  }
  final clause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
  return _Filter(clause, variables);
}

void _addSearchFilter(
  String rawSearch,
  List<String> conditions,
  List<Variable<Object>> variables,
) {
  final search = rawSearch.trim();
  if (search.isEmpty) return;
  final pattern = '%${escapeLikePattern(search)}%';
  conditions.add(_searchCondition);
  variables.addAll(<Variable<Object>>[
    for (var i = 0; i < _searchColumnCount; i += 1) Variable<String>(pattern),
  ]);
}

void _addExactFilters(
  WordQuery query,
  List<String> conditions,
  List<Variable<Object>> variables,
) {
  if (query.masteryLevel != null) {
    conditions.add('w.mastery_level = ?');
    variables.add(Variable<String>(query.masteryLevel!.wire));
  }
  if (query.initializationStatus != null) {
    conditions.add('w.initialization_status = ?');
    variables.add(Variable<String>(query.initializationStatus!.wire));
  }
  if (query.contentType != null) {
    conditions.add('w.content_type = ?');
    variables.add(Variable<String>(query.contentType!.wire));
  }
  final tag = query.tag?.trim();
  if (tag != null && tag.isNotEmpty) {
    conditions.add(_tagCondition);
    variables.add(Variable<String>(tag));
  }
  _addSourceScopeFilters(query, conditions, variables);
}

void _addSourceScopeFilters(
  WordQuery query,
  List<String> conditions,
  List<Variable<Object>> variables,
) {
  final packId = query.packId?.trim();
  final hasPackId = packId != null && packId.isNotEmpty;
  if (query.sourceScope == WordSourceScope.personal) {
    conditions.add('w.is_personal = 1');
  } else if (query.sourceScope == WordSourceScope.packs && !hasPackId) {
    conditions.add(
      'EXISTS (SELECT 1 FROM word_pack_items pi WHERE pi.word_id = w.id)',
    );
  }
  if (hasPackId) {
    conditions.add(
      'EXISTS (SELECT 1 FROM word_pack_items pi '
      'WHERE pi.word_id = w.id AND pi.pack_id = ?)',
    );
    variables.add(Variable<String>(packId));
  }
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

    final ids = <int>[for (final row in rows) row.read<int>('id')];
    final packsByWord = await WordPackDao(_db).packNamesByWordIds(ids);
    return rows
        .map(
          (row) => _mapRow(
            row,
            packsByWord[row.read<int>('id')] ?? const <String>[],
          ),
        )
        .toList(growable: false);
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

  /// 按掌握等级统计词条数，用于概览（可按来源作用域/词书过滤）。
  Future<Map<MasteryLevel, int>> countByMastery({
    WordSourceScope sourceScope = WordSourceScope.all,
    String? packId,
  }) async {
    final conditions = <String>[];
    final variables = <Variable<Object>>[];
    _addSourceScopeFilters(
      WordQuery(sourceScope: sourceScope, packId: packId),
      conditions,
      variables,
    );
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = await _db
        .customSelect(
          'SELECT w.mastery_level, count(*) AS c FROM words w $where '
          'GROUP BY w.mastery_level',
          variables: variables,
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

  /// 读取词库中出现过的全部去重标签（按字典序）。
  Future<List<String>> distinctTags() async {
    final rows = await _db.customSelect('''
SELECT DISTINCT trim(t.value) AS tag
FROM word_contents wc, json_each(wc.tags_json) t
WHERE json_valid(wc.tags_json)
  AND json_type(wc.tags_json) = 'array'
  AND trim(t.value) <> ''
ORDER BY tag ASC''').get();
    return <String>[for (final row in rows) row.read<String>('tag')];
  }

  /// 读取离线语音批量预缓存所需的精简词条目标（不加载释义/例句大字段）。
  Future<List<AudioPrecacheWordTarget>> listAudioPrecacheTargets({
    bool personalOnly = false,
    String? packId,
  }) async {
    final variables = <Variable<Object>>[];
    final joinPack = packId != null && packId.isNotEmpty
        ? 'INNER JOIN word_pack_items pi ON pi.word_id = w.id '
        : '';
    final filters = <String>[];
    if (packId != null && packId.isNotEmpty) {
      filters.add('pi.pack_id = ?');
      variables.add(Variable<String>(packId));
    } else if (personalOnly) {
      filters.add('w.is_personal = 1');
    }
    final where = filters.isEmpty ? '' : 'WHERE ${filters.join(' AND ')} ';
    final rows = await _db
        .customSelect(
          'SELECT w.term, w.content_type, wc.pronunciations_json '
          'FROM words w '
          '$joinPack'
          'LEFT JOIN word_contents wc ON wc.word_id = w.id '
          '$where'
          'ORDER BY w.id ASC',
          variables: variables,
        )
        .get();
    return <AudioPrecacheWordTarget>[
      for (final row in rows)
        AudioPrecacheWordTarget(
          term: row.read<String>('term'),
          contentType:
              wireLookup(
                LexicalContentType.values,
                row.read<String>('content_type'),
              ) ??
              LexicalContentType.word,
          pronunciations: parsePronunciations(
            row.readNullable<String>('pronunciations_json'),
          ),
        ),
    ];
  }

  /// 导出符合筛选条件（或指定 ID 集合）的词条明细，供生成 CSV。
  Future<List<WordExportRow>> exportRows(
    WordQuery query, {
    Set<int>? onlyIds,
  }) async {
    final filter = _buildFilter(query);
    final rows = await _db
        .customSelect(
          '$_exportSql ${filter.whereClause} '
          'ORDER BY ${query.sort.orderBy} LIMIT ?',
          variables: <Variable<Object>>[
            ...filter.variables,
            const Variable<int>(maxCsvRows),
          ],
        )
        .get();
    final out = <WordExportRow>[];
    for (final row in rows) {
      final id = row.read<int>('id');
      if (onlyIds != null && onlyIds.isNotEmpty && !onlyIds.contains(id)) {
        continue;
      }
      out.add(_mapExportRow(row));
    }
    return out;
  }

  WordExportRow _mapExportRow(QueryRow row) {
    final definitions = parseDefinitionsJson(
      row.readNullable<String>('definitions_json'),
    ).map((d) => d.text).where((t) => t.isNotEmpty).toList(growable: false);
    final pronunciations = parsePronunciations(
      row.readNullable<String>('pronunciations_json'),
    );
    final examples = parseExamples(row.readNullable<String>('examples_json'))
        .map((e) => e.sentence)
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final tags = parseTextList(
      decodeJsonList(row.readNullable<String>('tags_json')),
    );
    return WordExportRow(
      id: row.read<int>('id'),
      term: row.read<String>('term'),
      sourceLanguage: row.read<String>('source_language'),
      targetLanguage: row.read<String>('target_language'),
      definitions: definitions,
      phonetic: pronunciations.isEmpty ? '' : pronunciations.first.phonetic,
      examples: examples,
      tags: tags,
      note: row.readNullable<String>('user_note') ?? '',
    );
  }

  WordListEntry _mapRow(QueryRow row, List<String> packNames) {
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
      isPersonal: row.read<int>('is_personal') != 0,
      packNames: packNames,
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
