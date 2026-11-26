/// 把一份对端备份**合并**进本机的行数据（纯函数，不碰数据库）。
///
/// **为什么是「合并两张表」而不是「一条条 SQL」**：合并的难点全在
/// 「这两个 id 是不是同一个东西」上。把本机行与远端行摆在一起、用纯函数算出
/// 一份完整的新表，再交给已经测过 30 多个用例的导入事务写库，
/// 比手写十几条 INSERT/UPDATE 容易审查得多——后者每一条都是一次可能写坏
/// 学习数据的机会。
///
/// **就地修改传入的 `local`**：本机可能有几万行，复制一份整库只为「干净」
/// 不值得。
/// 调用方（合并服务）把 `readAllTables()` 的结果直接交进来，之后不再使用它。
///
/// 合并规则见 `docs/LAN_SYNC.md`。三条不变量：
/// 1. **不删除**本机任何词条、作答、会话或设置键；
/// 2. 派生状态（卡片 / 错词 / 熟练度）只对「本次收到新作答的词」重算，
///    其余词一行不动；
/// 3. 产物覆盖 `BackupImporter.tableOrder` 的全部表——本机专属的那几张
///    原样带走（导入事务会先清表，漏掉哪张就等于把那批数据删了）。
library;

import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';
import 'package:lexiloop/domain/review/wrong_state.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/services/merge/learning_replay.dart';

/// **不参与合并**的设置键。
///
/// 两类东西刻意不搬：
/// - **本机属性**（`lanSync` 的设备名与端口）：搬过来会让两台设备同名；
/// - **凭据**（WebDAV 密码、LLM API Key、Merriam-Webster Key）：
///   合并是日常动作，不是换机动作。静默把它们换成对方的，用户只会在某天
///   发现「AI 不能用了 / WebDAV 401 了」却找不到原因。
///
/// 其余设置（学习计划、题型、播放、词汇档位…）按 `updated_at` 逐键取新。
/// 两个 Merriam-Webster 键名与 `features/settings/providers_section.dart`
/// 的常量一致，由 `test/services/merge/backup_merge_test.dart` 断言。
const Set<String> mergeExcludedSettingKeys = <String>{
  lanSyncSettingsKey,
  webdavSettingsKey,
  llmConfigSettingsKey,
  'merriamWebsterDictionaryKey',
  'merriamWebsterThesaurusKey',
};

/// 合并时可以跟着远端走的 `words` 列。
///
/// **刻意排除的四类**：
/// - 身份列（`normalized_term` / 两个语言列）——它们就是匹配依据；
/// - 派生列（`mastery_score` / `mastery_level`）——由重放算出，取远端会立刻过期；
/// - `initialization_status`——已有词的任务队列是设备本地状态，不能由远端覆盖；
/// - `created_at`——"这条词最早什么时候进来"是本机视角的事实，取更早的那个
///   没有意义，取远端的反而会让排序跳变。
const List<String> _mergeableWordColumns = <String>[
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

/// 表名（与 `BackupImporter.tableOrder` 一一对应）。
const String _wordsTable = 'words';
const String _contentsTable = 'word_contents';
const String _sessionsTable = 'study_sessions';
const String _itemsTable = 'study_session_items';
const String _cardsTable = 'review_cards';
const String _logsTable = 'review_logs';
const String _wrongTable = 'wrong_word_states';
const String _settingsTable = 'settings';
const String _packsTable = 'word_packs';
const String _packItemsTable = 'word_pack_items';

/// 一次合并新增/更新了多少东西。
class MergeCounts {
  /// 以各计数构造。
  const new({
    this.addedWords = 0,
    this.updatedWords = 0,
    this.addedSessions = 0,
    this.addedLogs = 0,
    this.rebuiltWords = 0,
    this.droppedLogs = 0,
  });

  /// 新增的词条数。
  final int addedWords;

  /// 元数据被远端更新的词条数。
  final int updatedWords;

  /// 新增的会话数。
  final int addedSessions;

  /// 新增的作答条数。
  final int addedLogs;

  /// 被重算了卡片/错词/熟练度的词条数。
  final int rebuiltWords;

  /// 因为找不到对应词条而被丢弃的作答条数（防御性，正常为 0）。
  final int droppedLogs;
}

/// 合并产物。
class MergeOutcome {
  /// 以完整的 12 张表与计数构造。
  const new({required this.tables, required this.counts});

  /// 合并后的全部表（父表在前，可直接交给 `replaceAll`）。
  final Map<String, List<Map<String, Object?>>> tables;

  /// 本次合并的计数。
  final MergeCounts counts;
}

/// 合并 [remote] 到 [local]。
///
/// [scheduler] 用**本机**的目标保持率：合并之后这些词按本机的策略排期。
/// [now] 是 14/30 天窗口的基准，也是重算行的 `updated_at`。
MergeOutcome mergeBackupTables({
  required Map<String, List<Map<String, Object?>>> local,
  required Map<String, List<Map<String, Object?>>> remote,
  required FsrsScheduler scheduler,
  required int now,
  Set<String> excludedSettingKeys = const <String>{},
}) => _MergeRun(
  local: local,
  remote: remote,
  scheduler: scheduler,
  now: now,
  excludedSettingKeys: excludedSettingKeys.isEmpty
      ? mergeExcludedSettingKeys
      : excludedSettingKeys,
).execute();

/// 词条的身份键。
///
/// 与 `words_identity_unique` 同构：归一化词形 + 源语言 + 目标语言。
/// 用 `\u0000` 分隔而不是 `|`：词条文本里可能出现任何可见字符。
String wordIdentityOf(Map<String, Object?> row) =>
    '${_stringOf(row['normalized_term'])}\u0000'
    '${_stringOf(row['source_language'])}\u0000'
    '${_stringOf(row['target_language'])}';

/// 会话的身份键。
///
/// 会话没有天然键，而自增 id 在两台设备上必然撞车（各自从 1 开始）。
/// `(开始时间, 类型, 来源)` 足以区分两台设备各自开的会话：同一毫秒用同一种
/// 类型开两个会话是不可能的。
String sessionIdentityOf(Map<String, Object?> row) =>
    '${_intOf(row['started_at']) ?? 0}\u0000'
    '${_stringOf(row['session_type'])}\u0000'
    '${_stringOf(row['source_type'])}';

/// 一次合并的运行时状态。
///
/// 写成类而不是一串长参数：十来个游标与映射在各步之间共享，
/// 逐层传参会让每个小函数都长到触发架构守卫。
class _MergeRun {
  new({
    required this.local,
    required this.remote,
    required this.scheduler,
    required this.now,
    required this.excludedSettingKeys,
  });

  final Map<String, List<Map<String, Object?>>> local;
  final Map<String, List<Map<String, Object?>>> remote;
  final FsrsScheduler scheduler;
  final int now;
  final Set<String> excludedSettingKeys;

  late final Map<String, List<Map<String, Object?>>> _tables;
  final Map<int, int> _wordIdMap = <int, int>{};
  final Map<int, int> _sessionIdMap = <int, int>{};
  final Map<int, int> _itemIdMap = <int, int>{};
  final Set<int> _touchedWordIds = <int>{};

  int _nextWordId = 0;
  int _nextSessionId = 0;
  int _nextItemId = 0;
  int _nextLogId = 0;
  int _addedWords = 0;
  int _updatedWords = 0;
  int _addedSessions = 0;
  int _addedLogs = 0;
  int _droppedLogs = 0;

  /// 依次合并各表，返回完整产物。
  MergeOutcome execute() {
    // **以本机行起步**：任何一张我忘了合并的表都会原样落库，
    // 而不是被导入事务清空。这是「合并绝不删数据」的兜底。
    _tables = local;
    for (final table in BackupImporter.tableOrder) {
      _tables.putIfAbsent(table, () => <Map<String, Object?>>[]);
    }
    _nextWordId = _nextIdOf(_rows(_wordsTable));
    _nextSessionId = _nextIdOf(_rows(_sessionsTable));
    _nextItemId = _nextIdOf(_rows(_itemsTable));
    _nextLogId = _nextIdOf(_rows(_logsTable));

    _mergeWords();
    _mergeContents();
    _mergeSessions();
    _mergeLogs();
    _rebuildDerived();
    _mergeSettings();
    _mergeWordPacks();
    _mergeWordPackItems();

    return MergeOutcome(
      tables: _tables,
      counts: MergeCounts(
        addedWords: _addedWords,
        updatedWords: _updatedWords,
        addedSessions: _addedSessions,
        addedLogs: _addedLogs,
        rebuiltWords: _touchedWordIds.length,
        droppedLogs: _droppedLogs,
      ),
    );
  }

  /// 词条：按身份合并，身份不存在则插入。
  void _mergeWords() {
    final rows = _rows(_wordsTable);
    final byIdentity = <String, Map<String, Object?>>{
      for (final row in rows) wordIdentityOf(row): row,
    };
    for (final incoming in _incoming(_wordsTable)) {
      final existing = byIdentity[wordIdentityOf(incoming)];
      final remoteId = _intOf(incoming['id']);
      if (existing == null) {
        final row = <String, Object?>{
          ...incoming,
          'id': _nextWordId,
          'is_personal': _isPersonalTruthy(incoming['is_personal']) ? 1 : 0,
          if (incoming.containsKey('initialization_status'))
            'initialization_status': _localInitializationStatus(
              incoming['initialization_status'],
            ),
        };
        _nextWordId += 1;
        rows.add(row);
        byIdentity[wordIdentityOf(row)] = row;
        if (remoteId != null) _wordIdMap[remoteId] = _intOf(row['id'])!;
        _addedWords += 1;
        continue;
      }
      if (remoteId != null) _wordIdMap[remoteId] = _intOf(existing['id'])!;
      if (_isPersonalTruthy(existing['is_personal']) ||
          _isPersonalTruthy(incoming['is_personal'])) {
        existing['is_personal'] = 1;
      }
      if (_isNewerThan(incoming, existing)) {
        for (final column in _mergeableWordColumns) {
          if (incoming.containsKey(column)) existing[column] = incoming[column];
        }
        _updatedWords += 1;
      }
    }
  }

  /// 词典内容：整行取新。
  void _mergeContents() {
    final rows = _rows(_contentsTable);
    final byWord = <int, Map<String, Object?>>{
      for (final row in rows) _intOf(row['word_id'])!: row,
    };
    for (final incoming in _incoming(_contentsTable)) {
      final wordId = _wordIdMap[_intOf(incoming['word_id'])];
      if (wordId == null) continue;
      final row = <String, Object?>{...incoming, 'word_id': wordId};
      final existing = byWord[wordId];
      if (existing == null) {
        rows.add(row);
        byWord[wordId] = row;
      } else if (_isNewerThan(incoming, existing)) {
        existing
          ..clear()
          ..addAll(row);
      }
    }
  }

  /// 会话与题目：按身份合并会话，并推进已有会话的新进度（如已完成或新作答题目）。
  void _mergeSessions() {
    final sessions = _rows(_sessionsTable);
    final byIdentity = <String, Map<String, Object?>>{
      for (final row in sessions) sessionIdentityOf(row): row,
    };
    final itemsBySession = _groupItemsBySession(_incoming(_itemsTable));
    final localItemsByPos = _indexLocalItemsByPosition(_rows(_itemsTable));

    for (final incoming in _incoming(_sessionsTable)) {
      final remoteId = _intOf(incoming['id']);
      final existing = byIdentity[sessionIdentityOf(incoming)];
      if (existing != null) {
        final localSessionId = _intOf(existing['id'])!;
        if (remoteId != null) _sessionIdMap[remoteId] = localSessionId;
        _advanceExistingSession(existing, incoming);
        _mergeSessionItems(
          localSessionId,
          itemsBySession[remoteId],
          localItemsByPos,
        );
        continue;
      }
      final row = <String, Object?>{...incoming, 'id': _nextSessionId};
      _nextSessionId += 1;
      sessions.add(row);
      byIdentity[sessionIdentityOf(row)] = row;
      if (remoteId != null) _sessionIdMap[remoteId] = _intOf(row['id'])!;
      _addedSessions += 1;
      _appendSessionItems(row, itemsBySession[remoteId]);
    }
  }

  /// 按 `study_session_id` 分组远端题目项。
  Map<int, List<Map<String, Object?>>> _groupItemsBySession(
    List<Map<String, Object?>> items,
  ) {
    final grouped = <int, List<Map<String, Object?>>>{};
    for (final item in items) {
      final sessionId = _intOf(item['study_session_id']);
      if (sessionId == null) continue;
      grouped.putIfAbsent(sessionId, () => <Map<String, Object?>>[]).add(item);
    }
    return grouped;
  }

  /// 以 `(study_session_id, position)` 建立本机题目索引，供已有会话合入新进度。
  Map<String, Map<String, Object?>> _indexLocalItemsByPosition(
    List<Map<String, Object?>> items,
  ) => <String, Map<String, Object?>>{
    for (final item in items)
      _sessionItemKey(_intOf(item['study_session_id']) ?? 0, item['position']):
          item,
  };

  /// 若远端同一场会话推进到了更晚状态（如已完成或答完更多题），同步汇总列。
  void _advanceExistingSession(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    final incomingDone = _intOf(incoming['completed_at']);
    final existingDone = _intOf(existing['completed_at']);
    final incomingProgress = _sessionProgressCount(incoming);
    final existingProgress = _sessionProgressCount(existing);
    final shouldAdvance =
        (incomingDone != null && existingDone == null) ||
        incomingProgress > existingProgress;
    if (!shouldAdvance) return;
    for (final column in _sessionProgressColumns) {
      if (incoming.containsKey(column)) existing[column] = incoming[column];
    }
  }

  /// 对已存在会话合并题目项：建立 id 映射，并用远端已作答/跳过状态推进本机 PENDING 项。
  void _mergeSessionItems(
    int localSessionId,
    List<Map<String, Object?>>? incoming,
    Map<String, Map<String, Object?>> localByPos,
  ) {
    if (incoming == null) return;
    for (final item in incoming) {
      final remoteId = _intOf(item['id']);
      final key = _sessionItemKey(localSessionId, item['position']);
      final existing = localByPos[key];
      if (existing != null) {
        if (remoteId != null) _itemIdMap[remoteId] = _intOf(existing['id'])!;
        if (_stringOf(existing['status']) == StudyItemStatus.pending.wire &&
            _stringOf(item['status']) != StudyItemStatus.pending.wire) {
          existing['status'] = item['status'];
          existing['answered_at'] = item['answered_at'];
          existing['skip_reason'] = item['skip_reason'];
        }
        continue;
      }
      final wordId = _wordIdMap[_intOf(item['word_id'])];
      if (wordId == null) continue;
      final row = <String, Object?>{
        ...item,
        'id': _nextItemId,
        'study_session_id': localSessionId,
        'word_id': wordId,
      };
      _nextItemId += 1;
      _rows(_itemsTable).add(row);
      localByPos[key] = row;
      if (remoteId != null) _itemIdMap[remoteId] = _intOf(row['id'])!;
    }
  }

  /// 把一场新会话的题目一并插入（`word_id` 同样要重映射）。
  void _appendSessionItems(
    Map<String, Object?> session,
    List<Map<String, Object?>>? incoming,
  ) {
    if (incoming == null) return;
    for (final item in incoming) {
      final wordId = _wordIdMap[_intOf(item['word_id'])];
      if (wordId == null) continue;
      final remoteId = _intOf(item['id']);
      final row = <String, Object?>{
        ...item,
        'id': _nextItemId,
        'study_session_id': session['id'],
        'word_id': wordId,
      };
      _nextItemId += 1;
      _rows(_itemsTable).add(row);
      if (remoteId != null) _itemIdMap[remoteId] = _intOf(row['id'])!;
    }
  }

  /// 作答流水：按 `client_answer_id` 去重取并集。
  void _mergeLogs() {
    final rows = _rows(_logsTable);
    final seen = <String>{
      for (final row in rows) _stringOf(row['client_answer_id']),
    };
    for (final incoming in _incoming(_logsTable)) {
      final answerId = _stringOf(incoming['client_answer_id']);
      if (seen.contains(answerId)) continue;
      final wordId = _wordIdMap[_intOf(incoming['word_id'])];
      if (wordId == null) {
        _droppedLogs += 1;
        continue;
      }
      rows.add(<String, Object?>{
        ...incoming,
        'id': _nextLogId,
        'word_id': wordId,
        'study_session_id': _sessionIdMap[_intOf(incoming['study_session_id'])],
        'study_session_item_id':
            _itemIdMap[_intOf(incoming['study_session_item_id'])],
      });
      _nextLogId += 1;
      seen.add(answerId);
      _touchedWordIds.add(wordId);
      _addedLogs += 1;
    }
  }

  /// 只给「收到了新作答」的词重算卡片、错词与熟练度。
  void _rebuildDerived() {
    if (_touchedWordIds.isEmpty) return;
    final existingCards = <int, Map<String, Object?>>{
      for (final row in _rows(_cardsTable)) _intOf(row['word_id'])!: row,
    };
    final cards = <Map<String, Object?>>[];
    final wrongs = <Map<String, Object?>>[];
    final mastery = <int, ReplayedLearningState>{};

    for (final entry in _logsByTouchedWord().entries) {
      final replayed = replayWordHistory(
        logs: entry.value,
        scheduler: scheduler,
        now: now,
      );
      mastery[entry.key] = replayed;
      cards.add(_cardRow(entry.key, replayed.card, existingCards[entry.key]));
      final wrong = _wrongRow(
        entry.key,
        replayed.wrong,
        fallbackUpdatedAt: replayed.card.lastReviewAt ?? now,
      );
      if (wrong != null) wrongs.add(wrong);
    }

    _tables[_cardsTable] = <Map<String, Object?>>[
      ..._rows(_cardsTable).where((row) => !_isTouched(row)),
      ...cards,
    ];
    _tables[_wrongTable] = <Map<String, Object?>>[
      ..._rows(_wrongTable).where((row) => !_isTouched(row)),
      ...wrongs,
    ];
    _applyMastery(mastery);
  }

  /// 把被合并词的日志按 `(reviewed_at, client_answer_id)` 排好序再交给重放。
  Map<int, List<ReplayLog>> _logsByTouchedWord() {
    final grouped = <int, List<Map<String, Object?>>>{};
    for (final row in _rows(_logsTable)) {
      final wordId = _intOf(row['word_id']);
      if (wordId == null || !_touchedWordIds.contains(wordId)) continue;
      grouped.putIfAbsent(wordId, () => <Map<String, Object?>>[]).add(row);
    }
    final result = <int, List<ReplayLog>>{};
    for (final entry in grouped.entries) {
      final rows = entry.value..sort(_compareLogs);
      result[entry.key] = rows.map(replayLogFromRow).toList(growable: false);
    }
    return result;
  }

  /// 把重算出的熟练度写回词条行（留作下一轮展示与排序）。
  void _applyMastery(Map<int, ReplayedLearningState> mastery) {
    final byId = <int, Map<String, Object?>>{
      for (final row in _rows(_wordsTable)) _intOf(row['id'])!: row,
    };
    for (final entry in mastery.entries) {
      final row = byId[entry.key];
      if (row == null) continue;
      row['mastery_score'] = entry.value.masteryScore;
      row['mastery_level'] = entry.value.masteryLevel.wire;
    }
  }

  /// 设置：逐键取新，凭据与本机属性除外。
  void _mergeSettings() {
    final rows = _rows(_settingsTable);
    final byKey = <String, Map<String, Object?>>{
      for (final row in rows) _stringOf(row['key']): row,
    };
    for (final incoming in _incoming(_settingsTable)) {
      final key = _stringOf(incoming['key']);
      if (excludedSettingKeys.contains(key)) continue;
      final existing = byKey[key];
      if (existing == null) {
        final row = <String, Object?>{...incoming};
        rows.add(row);
        byKey[key] = row;
        continue;
      }
      if (!_isNewerThan(incoming, existing)) continue;
      existing['value_json'] = incoming['value_json'];
      existing['updated_at'] = incoming['updated_at'];
    }
  }

  /// 词书包元信息：按 ID 合并并取较新更新时间。
  void _mergeWordPacks() {
    final rows = _rows(_packsTable);
    final byId = <String, Map<String, Object?>>{
      for (final row in rows) _stringOf(row['id']): row,
    };
    for (final incoming in _incoming(_packsTable)) {
      final id = _stringOf(incoming['id']);
      if (id.isEmpty) continue;
      final existing = byId[id];
      if (existing == null) {
        final row = <String, Object?>{...incoming};
        rows.add(row);
        byId[id] = row;
        continue;
      }
      if (_isNewerThan(incoming, existing)) {
        existing
          ..clear()
          ..addAll(incoming);
      }
    }
  }

  /// 词书包词条关联：按 `(pack_id, mapped_word_id)` 取并集。
  void _mergeWordPackItems() {
    final rows = _rows(_packItemsTable);
    final validPacks = <String>{
      for (final row in _rows(_packsTable)) _stringOf(row['id']),
    };
    final seen = <String>{
      for (final row in rows)
        '${_stringOf(row['pack_id'])}\u0000${_intOf(row['word_id'])}',
    };
    for (final incoming in _incoming(_packItemsTable)) {
      final packId = _stringOf(incoming['pack_id']);
      final wordId = _wordIdMap[_intOf(incoming['word_id'])];
      if (packId.isEmpty || wordId == null || !validPacks.contains(packId)) {
        continue;
      }
      final key = '$packId\u0000$wordId';
      if (!seen.add(key)) continue;
      rows.add(<String, Object?>{
        ...incoming,
        'pack_id': packId,
        'word_id': wordId,
      });
    }
  }

  /// 是否属于本次被重建的词。
  bool _isTouched(Map<String, Object?> row) =>
      _touchedWordIds.contains(_intOf(row['word_id']));

  /// 本机某张表的行。
  List<Map<String, Object?>> _rows(String table) => _tables[table]!;

  /// 远端某张表的行。
  List<Map<String, Object?>> _incoming(String table) =>
      remote[table] ?? const <Map<String, Object?>>[];
}

/// 一张卡片的新行。
Map<String, Object?> _cardRow(
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
  // 卡片"出生"的时间不是派生值，沿用原有行；新词从这次合并开始算。
  'created_at': existing?['created_at'] ?? card.dueAt,
  'updated_at': existing?['updated_at'] ?? card.dueAt,
};

/// 一条错词状态的新行；重放认为没有错词记录时返回 `null`。
Map<String, Object?>? _wrongRow(
  int wordId,
  WrongStateTransition? transition, {
  required int fallbackUpdatedAt,
}) => transition == null
    ? null
    : <String, Object?>{
        'word_id': wordId,
        'active': transition.active ? 1 : 0,
        'wrong_count': transition.wrongCount,
        'hard_count': transition.hardCount,
        'consecutive_correct': transition.consecutiveCorrect,
        'last_wrong_at': transition.lastWrongAt,
        'last_correct_at': transition.lastCorrectAt,
        'resolved_at': transition.resolvedAt,
        'updated_at':
            transition.lastCorrectAt ??
            transition.lastWrongAt ??
            fallbackUpdatedAt,
      };

/// 日志的稳定排序：先按时间，再按幂等键。
///
/// 同一毫秒内的两条作答必须有一个确定顺序，否则两台设备各算出不同的卡片。
int _compareLogs(Map<String, Object?> a, Map<String, Object?> b) {
  final byTime = (_intOf(a['reviewed_at']) ?? 0).compareTo(
    _intOf(b['reviewed_at']) ?? 0,
  );
  if (byTime != 0) return byTime;
  return _stringOf(a['client_answer_id'])
      .compareTo(_stringOf(b['client_answer_id']));
}

/// 下一个可用 id。
int _nextIdOf(List<Map<String, Object?>> rows) {
  var max = 0;
  for (final row in rows) {
    final id = _intOf(row['id']);
    if (id != null && id > max) max = id;
  }
  return max + 1;
}

/// 远端的 `updated_at` 是否比本机新。
bool _isNewerThan(
  Map<String, Object?> incoming,
  Map<String, Object?> existing,
) =>
    (_intOf(incoming['updated_at']) ?? 0) >
    (_intOf(existing['updated_at']) ?? 0);

/// 宽容地读一个整数。
int? _intOf(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

/// 宽容地读一个字符串。
String _stringOf(Object? value) => value is String ? value : '';

/// 判断 `words.is_personal` 是否为真（旧备份缺列默认视作个人词条）。
bool _isPersonalTruthy(Object? value) {
  if (value == null) return true;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return true;
}

/// 会话可推进的进度汇总列。
const List<String> _sessionProgressColumns = <String>[
  'completed_at',
  'planned_count',
  'completed_count',
  'correct_count',
  'wrong_count',
  'skipped_count',
  'duration_ms',
];

int _sessionProgressCount(Map<String, Object?> row) =>
    (_intOf(row['completed_count']) ?? 0) + (_intOf(row['skipped_count']) ?? 0);

String _sessionItemKey(int sessionId, Object? position) =>
    '$sessionId\u0000${position is num ? position.toDouble() : position}';

/// 远端瞬态任务状态无法在本机恢复，新增词将其回退到可重新初始化的状态。
Object? _localInitializationStatus(Object? value) =>
    value == InitializationStatus.queued.wire ||
        value == InitializationStatus.running.wire
    ? InitializationStatus.pending.wire
    : value;
