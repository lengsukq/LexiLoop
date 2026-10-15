/// 小游戏、配对与音标训练的数据访问。
///
/// 对应旧版 `modules/leaderboard/service.ts`（高分榜）、
/// `modules/practice/candidates.ts`（候选词条选取）与
/// `modules/practice/sessions.ts` 的 `closeOpenPracticeSessions`。
///
/// **为什么候选查询放在这里而不是复用 `StudyDao`**：`StudyDao.loadPools`
/// 返回的 `StudyCandidate` 不带释义与音标，而游戏出题必须有释义
/// （否则选项里会出现空字符串）。旧版的做法也是独立的
/// `selectPracticeCandidates`，一次查询同时取回释义、音标与优先级，
/// 避免逐条再查 `word_contents`。本文件把这套查询与高分榜放在一起，
/// 因为两者都只服务于「游戏」这一条业务线。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';

/// 候选查询的公共投影。
///
/// SQL 写成顶层 raw 字符串而不是内联在函数里：一是函数体行数有 40 行的
/// 硬上限（架构守卫），二是 raw 字符串里 JSON 路径的 `$.text` 无需转义。
const String _candidateSelectSql = r'''
SELECT w.id, w.term, w.target_language,
       COALESCE(w.content_type, w.entry_type) AS lexical_type,
       c.definitions_json, c.pronunciations_json,
       COALESCE(x.active, 0) AS wrong_active,
       COALESCE(x.wrong_count, 0) AS wrong_count,
       COALESCE(x.hard_count, 0) AS hard_count,
       rc.due_at,
       COALESCE(recent.recent_again_14d, 0) AS recent_again,
       COALESCE(recent.recent_hard_14d, 0) AS recent_hard
FROM words w
JOIN word_contents c ON c.word_id = w.id
LEFT JOIN wrong_word_states x ON x.word_id = w.id
LEFT JOIN review_cards rc ON rc.word_id = w.id
LEFT JOIN word_review_stats recent ON recent.word_id = w.id
WHERE w.is_suspended = 0
  AND w.initialization_status IN ('READY', 'PARTIAL')
  AND json_valid(c.definitions_json)
  AND json_type(c.definitions_json) = 'array'
  AND EXISTS (
    SELECT 1 FROM json_each(c.definitions_json) d
    WHERE trim(json_extract(d.value, '$.text')) <> ''
  )''';

/// 「正在别的会话里等作答」的排除条件。
///
/// 小游戏与配对会话不算「占用」——与 `StudyDao._availabilitySql` 同一口径，
/// 否则一局没做完的游戏会让这些词条在配对里消失。
const String _activeSessionExclusionSql = '''
  AND NOT EXISTS (
    SELECT 1 FROM study_session_items active_item
    JOIN study_sessions active_session
      ON active_session.id = active_item.study_session_id
    WHERE active_item.word_id = w.id
      AND active_item.status = 'PENDING'
      AND active_session.completed_at IS NULL
      AND active_session.started_at >= ?
      AND COALESCE(active_session.source_type, '') <> 'MATCH_GAME'
      AND COALESCE(active_session.source_type, '') NOT LIKE 'GAME_%'
  )''';

/// 候选排序：错词 → 近期失误 → 到期 → 错误次数 → 掌握分升序。
///
/// 末位用 `w.id ASC` 而不是旧版的 `RANDOM()`：随机性由调用方的可注入
/// 随机源负责（打乱候选与选项），SQL 只保证**确定性**，测试才能断言顺序。
const String _candidateOrderSql = '''
ORDER BY COALESCE(x.active, 0) DESC,
         COALESCE(recent.recent_again_14d, 0) DESC,
         COALESCE(recent.recent_hard_14d, 0) DESC,
         CASE WHEN rc.due_at IS NOT NULL AND rc.due_at <= ? THEN 1 ELSE 0 END
           DESC,
         COALESCE(x.wrong_count, 0) DESC,
         COALESCE(x.hard_count, 0) DESC,
         COALESCE(w.mastery_score, 0) ASC,
         w.id ASC
LIMIT ?''';

/// 一个可用于游戏出题的候选词条。
class GameCandidate {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.term,
    required this.definition,
    required this.priority,
    this.pronunciationsJson,
  });

  /// 词条 ID。
  final int id;

  /// 展示用文本。
  final String term;

  /// 目标语言的首选释义。
  final String definition;

  /// 候选优先级。
  final GamePriority priority;

  /// 发音 JSON 原文（仅音标训练需要）。
  ///
  /// 保留原文而不是解析后的音标：解析与口音选择属于领域规则
  /// （`domain/phonetics/pronunciation.dart`），DAO 不做业务判断。
  final String? pronunciationsJson;
}

/// 一条高分记录的明细。
class GameScoreDetail {
  /// 以各字段构造。
  const new({
    required this.maxCombo,
    required this.accuracy,
    required this.elapsedMs,
  });

  /// 最高连击。
  final int maxCombo;

  /// 正确率（百分比）。
  final int accuracy;

  /// 用时（毫秒）。
  final int elapsedMs;
}

/// 一条高分记录。
class GameHighScore {
  /// 以各字段构造。
  const new({
    required this.mode,
    required this.score,
    required this.detail,
    required this.playedAt,
  });

  /// 游戏模式。
  final GameMode mode;

  /// 得分。
  final int score;

  /// 明细。
  final GameScoreDetail detail;

  /// 游玩时间（epoch 毫秒）。
  final int playedAt;
}

/// 游戏与音标训练的数据访问入口。
class GameDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  // ── 高分榜 ──

  /// 写入一条高分记录。
  Future<void> saveHighScore({
    required GameMode mode,
    required int score,
    required int maxCombo,
    required int accuracy,
    required int elapsedMs,
    required int now,
  }) async {
    await _db
        .into(_db.gameHighScores)
        .insert(
          GameHighScoresCompanion.insert(
            gameMode: mode.wire,
            score: score,
            maxCombo: Value<int>(maxCombo),
            accuracy: Value<int>(accuracy),
            elapsedMs: Value<int>(elapsedMs),
            playedAt: now,
            createdAt: now,
          ),
        );
  }

  /// 某模式的历史最高分；没有记录时返回 0。
  Future<int> bestScore(GameMode mode) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(MAX(score), 0) AS best FROM game_high_scores '
          'WHERE game_mode = ?',
          variables: <Variable<Object>>[Variable<String>(mode.wire)],
        )
        .getSingle();
    return row.read<int>('best');
  }

  /// 某模式的前 [limit] 名；同分按时间早的在前（与旧版一致）。
  Future<List<GameHighScore>> topScores({
    required GameMode mode,
    required int limit,
  }) async {
    final rows = await _db
        .customSelect(
          '''
SELECT game_mode, score, max_combo, accuracy, elapsed_ms, played_at
FROM game_high_scores WHERE game_mode = ?
ORDER BY score DESC, played_at ASC LIMIT ?''',
          variables: <Variable<Object>>[
            Variable<String>(mode.wire),
            Variable<int>(limit),
          ],
        )
        .get();
    return _toHighScores(rows);
  }

  /// 最近 [limit] 条记录（跨模式，按时间倒序）。
  Future<List<GameHighScore>> recentScores({required int limit}) async {
    final rows = await _db
        .customSelect(
          '''
SELECT game_mode, score, max_combo, accuracy, elapsed_ms, played_at
FROM game_high_scores ORDER BY played_at DESC, id DESC LIMIT ?''',
          variables: <Variable<Object>>[Variable<int>(limit)],
        )
        .get();
    return _toHighScores(rows);
  }

  /// 某模式里比 [score] 更高的记录数 + 1，即本轮名次。
  Future<int> rankOf({required GameMode mode, required int score}) async {
    final row = await _db
        .customSelect(
          'SELECT count(*) AS c FROM game_high_scores '
          'WHERE game_mode = ? AND score > ?',
          variables: <Variable<Object>>[
            Variable<String>(mode.wire),
            Variable<int>(score),
          ],
        )
        .getSingle();
    return row.read<int>('c') + 1;
  }

  // ── 候选词条 ──

  /// 取出可用于出题的候选词条（已按优先级排序、已去重）。
  ///
  /// [wordsOnly] 为真时只取单词（单词拼图题要求 3–14 个纯字母的词条）；
  /// [excludeWordsInActiveSessions] 为真时排除「正在别的会话里等作答」的词条
  /// （配对游戏用，与旧版 `excludeWordsInActiveSessions: true` 一致）。
  Future<List<GameCandidate>> loadCandidates({
    required int now,
    required int limit,
    bool wordsOnly = false,
    bool excludeWordsInActiveSessions = false,
  }) async {
    final rows = await _queryCandidateRows(
      now: now,
      limit: limit,
      excludeWordsInActiveSessions: excludeWordsInActiveSessions,
    );
    final selected = <GameCandidate>[];
    final seenTerms = <String>{};
    final seenDefinitions = <String>{};

    for (final row in rows) {
      final candidate = _toCandidate(row, now);
      if (candidate == null) continue;
      if (wordsOnly && !_isPlainWord(row)) continue;
      if (!seenTerms.add(candidate.term.trim().toLowerCase())) continue;
      final key = candidate.definition.trim().toLowerCase();
      if (!seenDefinitions.add(key)) continue;
      selected.add(candidate);
      if (selected.length >= limit) break;
    }
    return selected;
  }

  Future<List<QueryRow>> _queryCandidateRows({
    required int now,
    required int limit,
    required bool excludeWordsInActiveSessions,
  }) {
    final sql =
        _candidateSelectSql +
        (excludeWordsInActiveSessions ? _activeSessionExclusionSql : '') +
        _candidateOrderSql;
    final variables = <Variable<Object>>[
      if (excludeWordsInActiveSessions) Variable<int>(now - sessionResumeTtlMs),
      Variable<int>(now),
      Variable<int>(limit),
    ];
    return _db.customSelect(sql, variables: variables).get();
  }

  GameCandidate? _toCandidate(QueryRow row, int now) {
    final definitions = parseDefinitionsJson(
      row.read<String?>('definitions_json'),
    );
    final definition = preferredDefinitionText(
      definitions,
      row.read<String>('target_language'),
    );
    if (definition == null || definition.trim().isEmpty) return null;
    return GameCandidate(
      id: row.read<int>('id'),
      term: row.read<String>('term'),
      definition: definition.trim(),
      priority: _priorityOf(row, now),
      pronunciationsJson: row.read<String?>('pronunciations_json'),
    );
  }

  /// 计算候选优先级（与旧版 `practicePriority` 逐条对应）。
  ///
  /// 到期判定必须带 `due_at <= now`：只判「有 due_at」会把明天才到期的卡
  /// 也算成到期，配对会话的 `task_type` 就会从 NEW 错记成 REVIEW。
  GamePriority _priorityOf(QueryRow row, int now) {
    if (row.read<int>('wrong_active') != 0) return GamePriority.wrong;
    final recent = row.read<int>('recent_again') + row.read<int>('recent_hard');
    if (recent > 0) return GamePriority.recentMistake;
    final dueAt = row.readNullable<int>('due_at');
    if (dueAt != null && dueAt <= now) return GamePriority.due;
    return GamePriority.normal;
  }

  /// 词条是否是「纯字母单词」（旧版 `isWordBuilderCandidate` 的正则）。
  bool _isPlainWord(QueryRow row) =>
      row.read<String>('lexical_type') == 'WORD' &&
      RegExp(letterBankTermPattern).hasMatch(row.read<String>('term'));

  List<GameHighScore> _toHighScores(List<QueryRow> rows) {
    final result = <GameHighScore>[];
    for (final row in rows) {
      final score = _toHighScore(row);
      if (score != null) result.add(score);
    }
    return result;
  }

  /// 读取会话里「词条 ID → 题目 ID」的映射。
  ///
  /// 游戏出题需要题目 ID 作为幂等键与会话题目引用，而 `createSession`
  /// 只返回会话 ID；这里用一条查询补上，避免调用 `StudyDao.loadSession`
  /// 走一遍完整的选项构造（那会为每道题再跑几次干扰项查询）。
  Future<Map<int, int>> sessionItemIds(int sessionId) async {
    final rows = await _db
        .customSelect(
          '''
SELECT id, word_id FROM study_session_items
WHERE study_session_id = ? ORDER BY position ASC''',
          variables: <Variable<Object>>[Variable<int>(sessionId)],
        )
        .get();
    return <int, int>{
      for (final row in rows) row.read<int>('word_id'): row.read<int>('id'),
    };
  }

  // ── 会话收尾 ──

  /// 关闭同来源的未完成会话，返回被关闭的会话数。
  ///
  /// 对应旧版 `closeOpenPracticeSessions`：游戏会话是「一局一开」的，
  /// 用户中途退出后留下的未完成会话既不会被恢复（小游戏不参与恢复），
  /// 又会永远挂在统计里，因此开局前统一收尾。
  Future<int> closeOpenSessions({
    required String sourceTypePattern,
    required int now,
  }) async {
    final rows = await _db
        .customSelect(
          '''
SELECT id FROM study_sessions
WHERE COALESCE(source_type, '') LIKE ? AND completed_at IS NULL''',
          variables: <Variable<Object>>[Variable<String>(sourceTypePattern)],
        )
        .get();
    for (final row in rows) {
      await _closeSession(row.read<int>('id'), now);
    }
    return rows.length;
  }

  Future<void> _closeSession(int sessionId, int now) async {
    final pending = await _pendingCount(sessionId);
    await _markPendingSkipped(sessionId, now);
    await _db.customUpdate(
      '''
UPDATE study_sessions SET
  completed_at = ?,
  completed_count = completed_count + ?,
  skipped_count = skipped_count + ?,
  duration_ms = MAX(0, ? - started_at)
WHERE id = ?''',
      variables: <Variable<Object>>[
        Variable<int>(now),
        Variable<int>(pending),
        Variable<int>(pending),
        Variable<int>(now),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.studySessions},
    );
  }

  Future<int> _pendingCount(int sessionId) async {
    final row = await _db
        .customSelect(
          '''
SELECT count(*) AS c FROM study_session_items
WHERE study_session_id = ? AND status = 'PENDING' ''',
          variables: <Variable<Object>>[Variable<int>(sessionId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<void> _markPendingSkipped(int sessionId, int now) {
    return _db.customUpdate(
      '''
UPDATE study_session_items
SET status = 'SKIPPED', answered_at = ?, skip_reason = 'SESSION_EXPIRED'
WHERE study_session_id = ? AND status = 'PENDING' ''',
      variables: <Variable<Object>>[
        Variable<int>(now),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{
        _db.studySessionItems,
      },
    );
  }

  /// 收尾一次音标训练会话。
  ///
  /// **音标训练不写 `review_logs`**（见 `phonetic_service.dart` 的说明），
  /// 因此无法复用 `ReviewDao.closeSession` 的「按复习日志汇总时长」，
  /// 只能在这里显式记账：逐题状态、正确/错误/跳过计数与有效时长。
  ///
  /// [answeredItemIds] 是真正作答过的题目；其余题目记为
  /// `SESSION_EXPIRED` 跳过（超时结束时剩下的题）。
  Future<void> completePhoneticSession({
    required int sessionId,
    required List<GameAnswerRecord> answers,
    required Set<int> answeredItemIds,
    required int elapsedMs,
    required int now,
  }) async {
    await _db.transaction(() async {
      var correct = 0;
      var wrong = 0;
      var skipped = 0;
      for (final answer in answers) {
        final answered = answeredItemIds.contains(answer.itemId);
        if (!answered) {
          skipped += 1;
        } else if (answer.solved) {
          correct += 1;
        } else {
          wrong += 1;
        }
        await _saveItemOutcome(
          sessionId: sessionId,
          itemId: answer.itemId,
          answered: answered,
          now: now,
        );
      }
      await _closePhoneticSession(
        sessionId: sessionId,
        correct: correct,
        wrong: wrong,
        skipped: skipped,
        elapsedMs: elapsedMs,
        now: now,
      );
    });
  }

  /// 写入单题结果。
  ///
  /// 作答过的题目**不动** `skip_reason`（保持 NULL）；未作答的才写
  /// `SESSION_EXPIRED`——用空串表示「没有跳过原因」会让
  /// `COALESCE(skip_reason,'')` 这类既有判断失去区分度。
  Future<void> _saveItemOutcome({
    required int sessionId,
    required int itemId,
    required bool answered,
    required int now,
  }) {
    final sql = answered
        ? '''
UPDATE study_session_items SET status = 'ANSWERED', answered_at = ?
WHERE id = ? AND study_session_id = ?'''
        : '''
UPDATE study_session_items
SET status = 'SKIPPED', answered_at = ?, skip_reason = 'SESSION_EXPIRED'
WHERE id = ? AND study_session_id = ?''';
    return _db.customUpdate(
      sql,
      variables: <Variable<Object>>[
        Variable<int>(now),
        Variable<int>(itemId),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{
        _db.studySessionItems,
      },
    );
  }

  Future<void> _closePhoneticSession({
    required int sessionId,
    required int correct,
    required int wrong,
    required int skipped,
    required int elapsedMs,
    required int now,
  }) {
    return _db.customUpdate(
      '''
UPDATE study_sessions SET
  completed_at = ?,
  completed_count = ?,
  correct_count = ?,
  wrong_count = ?,
  skipped_count = ?,
  duration_ms = ?
WHERE id = ?''',
      variables: <Variable<Object>>[
        Variable<int>(now),
        Variable<int>(correct + wrong),
        Variable<int>(correct),
        Variable<int>(wrong),
        Variable<int>(skipped),
        Variable<int>(elapsedMs),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.studySessions},
    );
  }

  GameHighScore? _toHighScore(QueryRow row) {
    final mode = _modeFromWire(row.read<String>('game_mode'));
    if (mode == null) return null;
    return GameHighScore(
      mode: mode,
      score: row.read<int>('score'),
      detail: GameScoreDetail(
        maxCombo: row.read<int>('max_combo'),
        accuracy: row.read<int>('accuracy'),
        elapsedMs: row.read<int>('elapsed_ms'),
      ),
      playedAt: row.read<int>('played_at'),
    );
  }

  /// 未知的 `game_mode`（旧版遗留值或将来新增）返回 `null` 而不是抛错：
  /// 高分榜是只读展示，一条读不懂的历史记录不该让整页崩掉。
  GameMode? _modeFromWire(String wire) {
    for (final mode in GameMode.values) {
      if (mode.wire == wire) return mode;
    }
    return null;
  }
}
