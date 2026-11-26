/// 复习相关的读写。
///
/// 对应旧版 `modules/reviews/repository.ts`。
///
/// **与旧版的差异（有意）**：旧版把「更新卡片 + 插入日志」「更新熟练度 +
/// 收尾会话」各自塞进一条 PostgreSQL 数据修改 CTE，目的是省一次
/// 服务端→数据库的往返。本地 SQLite 没有网络往返，这类合并只带来
/// 难以调试的 SQL；此处改为事务内的多条简单语句。
///
/// **SQL 一律写成三引号字符串**：拆成多个相邻单引号片段时，任何一段
/// 不含单引号都会触发 `prefer_single_quotes`，且换行位置由格式器决定，
/// 与 SQL 的语义分行无关。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/review/duration.dart';
import 'package:lexiloop/domain/review/wrong_state.dart';

/// 已存在的复习日志（幂等命中时回显）。
class ExistingReviewLog {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.wordId,
    required this.studySessionId,
    required this.studySessionItemId,
    required this.rating,
    required this.isCorrect,
    required this.expectedAnswer,
  });

  /// 日志 ID。
  final int id;

  /// 词条 ID。
  final int wordId;

  /// 学习会话 ID。
  final int? studySessionId;

  /// 会话题目 ID。
  final int? studySessionItemId;

  /// 生效等级。
  final ReviewRating rating;

  /// 是否判定为正确。
  final bool isCorrect;

  /// 期望答案。
  final String? expectedAnswer;
}

/// 词条当前的熟练度（幂等回显时读取）。
class MasterySnapshot {
  /// 以各字段构造。
  const new({required this.score, required this.level});

  /// 熟练分。
  final int score;

  /// 掌握等级。
  final MasteryLevel level;
}

/// 一次复习所需的全部上下文。
class ReviewContext {
  /// 以各字段构造。
  const new({this.word, this.card, this.wrongState});

  /// 词条。
  final ReviewWord? word;

  /// FSRS 卡片状态（从未复习过时为 `null`）。
  final ReviewCardState? card;

  /// 错词状态（从未答错或答模糊时为 `null`）。
  final WrongStateSnapshot? wrongState;
}

/// 复习读写入口。
class ReviewDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 按幂等键查找已有日志。
  Future<ExistingReviewLog?> findExistingLog(String clientAnswerId) async {
    final row = await _db
        .customSelect(
          '''
SELECT id, word_id, study_session_id, study_session_item_id,
       rating, is_correct, expected_answer
FROM review_logs WHERE client_answer_id = ?''',
          variables: <Variable<Object>>[Variable<String>(clientAnswerId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return ExistingReviewLog(
      id: row.read<int>('id'),
      wordId: row.read<int>('word_id'),
      studySessionId: row.readNullable<int>('study_session_id'),
      studySessionItemId: row.readNullable<int>('study_session_item_id'),
      rating:
          wireLookup(ReviewRating.values, row.read<String>('rating')) ??
          ReviewRating.good,
      isCorrect: row.read<bool>('is_correct'),
      expectedAnswer: row.readNullable<String>('expected_answer'),
    );
  }

  /// 一次性取回词条、卡片与错词状态。
  Future<ReviewContext> findContext(int wordId) async {
    final row = await _db
        .customSelect(
          '''
SELECT w.id, w.term, w.normalized_term, w.source_language,
       w.target_language, w.content_type, w.initialization_status,
       w.is_suspended, c.definitions_json,
       rc.due_at, rc.stability, rc.difficulty, rc.elapsed_days,
       rc.scheduled_days, rc.reps, rc.lapses, rc.fsrs_state,
       rc.last_review_at, rc.learning_steps,
       x.active AS wrong_active, x.wrong_count, x.hard_count,
       x.consecutive_correct, x.last_wrong_at, x.last_correct_at
FROM words w
LEFT JOIN word_contents c ON c.word_id = w.id
LEFT JOIN review_cards rc ON rc.word_id = w.id
LEFT JOIN wrong_word_states x ON x.word_id = w.id
WHERE w.id = ?''',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingleOrNull();
    if (row == null) return const ReviewContext();

    return ReviewContext(
      word: _mapWord(row),
      card: row.readNullable<int>('due_at') == null ? null : _mapCard(row),
      wrongState: row.readNullable<int>('wrong_active') == null
          ? null
          : _mapWrongState(row),
    );
  }

  /// 读取单个词条的 FSRS 卡片（用于预览四个等级的间隔）。
  Future<ReviewCardState?> findCard(int wordId) async {
    final row = await _db
        .customSelect(
          '''
SELECT due_at, stability, difficulty, elapsed_days, scheduled_days,
       reps, lapses, fsrs_state, last_review_at, learning_steps
FROM review_cards WHERE word_id = ?''',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingleOrNull();
    return row == null ? null : _mapCard(row);
  }

  /// 认领会话题目：把 PENDING 置为 ANSWERED。
  ///
  /// 所有有效性校验都折进 `WHERE`，使常见成功路径只需一条语句；
  /// 失败时再补一次诊断查询，给出**具体**的冲突原因——
  /// 旧版在这里只返回一个笼统的失败，排查成本很高。
  Future<void> claimStudyItem({
    required int sessionId,
    required int itemId,
    required int wordId,
    required QuestionType questionType,
    required int now,
  }) async {
    final claimed = await _db.customUpdate(
      '''
UPDATE study_session_items SET status = 'ANSWERED', answered_at = ?
WHERE id = ? AND study_session_id = ? AND status = 'PENDING'
  AND word_id = ? AND question_type = ?
  AND EXISTS (SELECT 1 FROM study_sessions s
              WHERE s.id = ? AND s.completed_at IS NULL)''',
      variables: <Variable<Object>>[
        Variable<int>(now),
        Variable<int>(itemId),
        Variable<int>(sessionId),
        Variable<int>(wordId),
        Variable<String>(questionType.wire),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{
        _db.studySessionItems,
      },
    );
    if (claimed == 1) return;
    await _diagnoseClaimFailure(sessionId, itemId, wordId, questionType);
  }

  /// 写入 FSRS 卡片与复习日志，返回日志 ID。
  Future<int> insertCardAndLog({
    required AnswerInput answer,
    required int reviewedAt,
    required ReviewRating rating,
    required String presentedPrompt,
    required String expectedAnswer,
    required bool isCorrect,
    required ReviewCardState before,
    required ReviewCardState after,
    required int now,
  }) async {
    await _upsertCard(answer.wordId, after, now);
    return await _insertLog(
      answer: answer,
      reviewedAt: reviewedAt,
      rating: rating,
      presentedPrompt: presentedPrompt,
      expectedAnswer: expectedAnswer,
      isCorrect: isCorrect,
      before: before,
      after: after,
    );
  }

  /// 累加并重算词条统计，返回最新统计。
  ///
  /// 生命周期计数直接累加；14/30 天的窗口计数按 `(word_id, reviewed_at)`
  /// 索引重算——单个词的历史很短，重算比维护增量更不容易出错。
  Future<ReviewStatistics> upsertWordReviewStats({
    required int wordId,
    required int reviewedAt,
    required bool isCorrect,
    required int? durationMs,
  }) async {
    final duration = durationMs != null && durationMs > 0 ? durationMs : 0;
    await _db.customUpdate(
      '''
INSERT INTO word_review_stats
  (word_id, total_reviews, correct_reviews, recent_again_30d,
   recent_again_14d, recent_wrong_14d, recent_hard_14d, total_duration_ms,
   duration_count, last_reviewed_at, updated_at)
VALUES (?, 1, ?, 0, 0, 0, 0, ?, ?, ?, ?)
ON CONFLICT(word_id) DO UPDATE SET
  total_reviews = word_review_stats.total_reviews + 1,
  correct_reviews = word_review_stats.correct_reviews
    + excluded.correct_reviews,
  total_duration_ms = word_review_stats.total_duration_ms
    + excluded.total_duration_ms,
  duration_count = word_review_stats.duration_count
    + excluded.duration_count,
  last_reviewed_at = excluded.last_reviewed_at,
  updated_at = excluded.updated_at''',
      variables: <Variable<Object>>[
        Variable<int>(wordId),
        Variable<int>(isCorrect ? 1 : 0),
        Variable<int>(duration),
        Variable<int>(duration > 0 ? 1 : 0),
        Variable<int>(reviewedAt),
        Variable<int>(reviewedAt),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.wordReviewStats},
    );
    await _recomputeStatWindows(wordId, reviewedAt);
    return await loadStatistics(wordId);
  }

  /// 读取词条统计；无记录时按 `review_logs` 现算。
  Future<ReviewStatistics> loadStatistics(int wordId) async {
    final row = await _db
        .customSelect(
          '''
SELECT total_reviews, correct_reviews, recent_again_30d,
       total_duration_ms, duration_count
FROM word_review_stats WHERE word_id = ?''',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingleOrNull();
    if (row == null) return await _computeStatisticsFromLogs(wordId);
    final durationCount = row.read<int>('duration_count');
    return ReviewStatistics(
      total: row.read<int>('total_reviews'),
      correct: row.read<int>('correct_reviews'),
      recentAgain: row.read<int>('recent_again_30d'),
      averageDurationMs: durationCount > 0
          ? row.read<int>('total_duration_ms') / durationCount
          : null,
    );
  }

  /// 读取词条的熟练度；词条不存在时返回 `null`。
  Future<MasterySnapshot?> findMastery(int wordId) async {
    final row = await _db
        .customSelect(
          'SELECT mastery_score, mastery_level FROM words WHERE id = ?',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return MasterySnapshot(
      score: row.read<int>('mastery_score'),
      level:
          wireLookup(MasteryLevel.values, row.read<String>('mastery_level')) ??
          MasteryLevel.newWord,
    );
  }

  /// 写入错词状态（不存在则插入）。
  Future<void> saveWrongState(
    int wordId,
    WrongStateTransition transition,
    int now,
  ) async {
    await _db.customInsert(
      '''
INSERT INTO wrong_word_states
  (word_id, active, wrong_count, hard_count, consecutive_correct,
   last_wrong_at, last_correct_at, resolved_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(word_id) DO UPDATE SET
  active = excluded.active,
  wrong_count = excluded.wrong_count,
  hard_count = excluded.hard_count,
  consecutive_correct = excluded.consecutive_correct,
  last_wrong_at = excluded.last_wrong_at,
  last_correct_at = excluded.last_correct_at,
  resolved_at = excluded.resolved_at,
  updated_at = excluded.updated_at''',
      variables: <Variable<Object>>[
        Variable<int>(wordId),
        Variable<int>(transition.active ? 1 : 0),
        Variable<int>(transition.wrongCount),
        Variable<int>(transition.hardCount),
        Variable<int>(transition.consecutiveCorrect),
        Variable<int>(transition.lastWrongAt),
        Variable<int>(transition.lastCorrectAt),
        Variable<int>(transition.resolvedAt),
        Variable<int>(now),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.wrongWordStates},
    );
  }

  /// 更新熟练分与掌握等级。
  Future<void> updateMastery(
    int wordId,
    int score,
    MasteryLevel level,
    int now,
  ) async {
    await (_db.update(_db.words)..where((row) => row.id.equals(wordId))).write(
      WordsCompanion(
        masteryScore: Value<int>(score),
        masteryLevel: Value<MasteryLevel>(level),
        updatedAt: Value<int>(now),
      ),
    );
  }

  /// 累加会话计数，并在没有 PENDING 题目时收尾会话。
  ///
  /// 收尾时用 [sumActiveDurations] 重算有效时长，避免挂机时间污染统计。
  Future<void> finalizeSession({
    required int sessionId,
    required bool isCorrect,
    required int now,
  }) async {
    await _db.customUpdate(
      '''
UPDATE study_sessions SET
  completed_count = completed_count + 1,
  correct_count = correct_count + ?,
  wrong_count = wrong_count + ?
WHERE id = ?''',
      variables: <Variable<Object>>[
        Variable<int>(isCorrect ? 1 : 0),
        Variable<int>(isCorrect ? 0 : 1),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.studySessions},
    );
    if (await pendingItemCount(sessionId) == 0) {
      await closeSession(sessionId, now);
    }
  }

  /// 待作答题目数。
  Future<int> pendingItemCount(int sessionId) async {
    final row = await _db
        .customSelect(
          """
SELECT count(*) AS c FROM study_session_items
WHERE study_session_id = ? AND status = 'PENDING'""",
          variables: <Variable<Object>>[Variable<int>(sessionId)],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// 收尾会话：标记完成并回填有效学习时长。
  Future<void> closeSession(int sessionId, int completedAt) async {
    final durations = await _db
        .customSelect(
          'SELECT duration_ms FROM review_logs WHERE study_session_id = ?',
          variables: <Variable<Object>>[Variable<int>(sessionId)],
        )
        .get();
    final total = sumActiveDurations(
      durations.map((row) => row.readNullable<int>('duration_ms')),
    );
    await (_db.update(
      _db.studySessions,
    )..where((row) => row.id.equals(sessionId))).write(
      StudySessionsCompanion(
        completedAt: Value<int>(completedAt),
        durationMs: Value<int>(total),
      ),
    );
  }

  /// 按当前时间重算 14/30 天窗口计数。
  Future<void> _recomputeStatWindows(int wordId, int reviewedAt) async {
    await _db.customUpdate(
      '''
UPDATE word_review_stats SET
  recent_again_30d = (SELECT count(*) FROM review_logs
    WHERE word_id = ? AND rating = ? AND reviewed_at >= ?),
  recent_again_14d = (SELECT count(*) FROM review_logs
    WHERE word_id = ? AND rating = ? AND reviewed_at >= ?),
  recent_wrong_14d = (SELECT count(*) FROM review_logs
    WHERE word_id = ? AND is_correct = 0 AND reviewed_at >= ?),
  recent_hard_14d = (SELECT count(*) FROM review_logs
    WHERE word_id = ? AND rating = ? AND reviewed_at >= ?)
WHERE word_id = ?''',
      variables: <Variable<Object>>[
        Variable<int>(wordId),
        Variable<String>(ReviewRating.again.wire),
        Variable<int>(reviewedAt - masteryWindowMs),
        Variable<int>(wordId),
        Variable<String>(ReviewRating.again.wire),
        Variable<int>(reviewedAt - performanceWindowMs),
        Variable<int>(wordId),
        Variable<int>(reviewedAt - performanceWindowMs),
        Variable<int>(wordId),
        Variable<String>(ReviewRating.hard.wire),
        Variable<int>(reviewedAt - performanceWindowMs),
        Variable<int>(wordId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.wordReviewStats},
    );
  }

  Future<ReviewStatistics> _computeStatisticsFromLogs(int wordId) async {
    final row = await _db
        .customSelect(
          '''
SELECT count(*) AS total,
       COALESCE(SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0)
         AS correct,
       COALESCE(SUM(CASE WHEN duration_ms > 0 THEN duration_ms ELSE 0 END), 0)
         AS total_duration,
       COALESCE(SUM(CASE WHEN duration_ms > 0 THEN 1 ELSE 0 END), 0)
         AS duration_count
FROM review_logs WHERE word_id = ?''',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingle();
    final durationCount = row.read<int>('duration_count');
    return ReviewStatistics(
      total: row.read<int>('total'),
      correct: row.read<int>('correct'),
      recentAgain: 0,
      averageDurationMs: durationCount > 0
          ? row.read<int>('total_duration') / durationCount
          : null,
    );
  }

  Future<void> _diagnoseClaimFailure(
    int sessionId,
    int itemId,
    int wordId,
    QuestionType questionType,
  ) async {
    final row = await _db
        .customSelect(
          '''
SELECT i.word_id, i.question_type, i.status, s.completed_at
FROM study_session_items i
JOIN study_sessions s ON s.id = i.study_session_id
WHERE i.id = ? AND i.study_session_id = ?''',
          variables: <Variable<Object>>[
            Variable<int>(itemId),
            Variable<int>(sessionId),
          ],
        )
        .getSingleOrNull();
    if (row == null) throw const NotFoundError(AppErrorCode.studyItemNotFound);
    if (row.read<int>('word_id') != wordId) {
      throw const ConflictError(AppErrorCode.studyItemWordMismatch);
    }
    if (row.read<String>('question_type') != questionType.wire) {
      throw const ConflictError(AppErrorCode.studyItemQuestionMismatch);
    }
    throw const ConflictError(AppErrorCode.studyItemAlreadyProcessed);
  }

  Future<void> _upsertCard(int wordId, ReviewCardState card, int now) async {
    await _db.customInsert(
      '''
INSERT INTO review_cards
  (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days,
   reps, lapses, fsrs_state, learning_steps, last_review_at,
   created_at, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(word_id) DO UPDATE SET
  due_at = excluded.due_at,
  stability = excluded.stability,
  difficulty = excluded.difficulty,
  elapsed_days = excluded.elapsed_days,
  scheduled_days = excluded.scheduled_days,
  reps = excluded.reps,
  lapses = excluded.lapses,
  fsrs_state = excluded.fsrs_state,
  learning_steps = excluded.learning_steps,
  last_review_at = excluded.last_review_at,
  updated_at = excluded.updated_at''',
      variables: <Variable<Object>>[
        Variable<int>(wordId),
        Variable<int>(card.dueAt),
        Variable<double>(card.stability),
        Variable<double>(card.difficulty),
        Variable<int>(card.elapsedDays),
        Variable<int>(card.scheduledDays),
        Variable<int>(card.reps),
        Variable<int>(card.lapses),
        Variable<int>(card.fsrsState),
        Variable<int>(card.learningSteps),
        Variable<int>(now),
        Variable<int>(now),
        Variable<int>(now),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.reviewCards},
    );
  }

  Future<int> _insertLog({
    required AnswerInput answer,
    required int reviewedAt,
    required ReviewRating rating,
    required String presentedPrompt,
    required String expectedAnswer,
    required bool isCorrect,
    required ReviewCardState before,
    required ReviewCardState after,
  }) {
    return _db.customInsert(
      '''
INSERT INTO review_logs
  (client_answer_id, word_id, study_session_id, study_session_item_id,
   reviewed_at, rating, question_type, presented_prompt, user_answer,
   expected_answer, is_correct, duration_ms, card_before_json,
   card_after_json, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      variables: <Variable<Object>>[
        Variable<String>(answer.clientAnswerId),
        Variable<int>(answer.wordId),
        Variable<int>(answer.studySessionId),
        Variable<int>(answer.studySessionItemId),
        Variable<int>(reviewedAt),
        Variable<String>(rating.wire),
        Variable<String>(answer.questionType.wire),
        Variable<String>(presentedPrompt),
        Variable<String>(answer.userAnswer),
        Variable<String>(expectedAnswer),
        Variable<int>(isCorrect ? 1 : 0),
        Variable<int>(boundedActiveDurationMs(answer.durationMs)),
        Variable<String>(before.toJson()),
        Variable<String>(after.toJson()),
        Variable<int>(reviewedAt),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.reviewLogs},
    );
  }

  ReviewWord _mapWord(QueryRow row) => ReviewWord(
    id: row.read<int>('id'),
    term: row.read<String>('term'),
    normalizedTerm: row.read<String>('normalized_term'),
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
    isSuspended: row.read<bool>('is_suspended'),
    definitionsJson: row.readNullable<String>('definitions_json'),
  );

  ReviewCardState _mapCard(QueryRow row) => ReviewCardState(
    dueAt: row.read<int>('due_at'),
    stability: row.read<double>('stability'),
    difficulty: row.read<double>('difficulty'),
    elapsedDays: row.read<int>('elapsed_days'),
    scheduledDays: row.read<int>('scheduled_days'),
    reps: row.read<int>('reps'),
    lapses: row.read<int>('lapses'),
    fsrsState: row.read<int>('fsrs_state'),
    learningSteps: row.readNullable<int>('learning_steps') ?? 0,
    lastReviewAt: row.readNullable<int>('last_review_at'),
  );

  WrongStateSnapshot _mapWrongState(QueryRow row) => WrongStateSnapshot(
    active: row.read<bool>('wrong_active'),
    wrongCount: row.read<int>('wrong_count'),
    hardCount: row.read<int>('hard_count'),
    consecutiveCorrect: row.read<int>('consecutive_correct'),
    lastWrongAt: row.readNullable<int>('last_wrong_at'),
    lastCorrectAt: row.readNullable<int>('last_correct_at'),
  );
}
