/// 学习会话的数据访问。
///
/// 对应旧版 `modules/study/candidates.ts`（候选查询）、`modules/study/view.ts`
/// （会话视图）、`modules/study/service.ts`（会话收尾与恢复）与
/// `modules/study/adaptive.ts`（会话内追问题）。
///
/// **PostgreSQL → SQLite 的语义调整**（逐条理由见对应 SQL 上方注释）：
/// 1. `json_typeof(x::json)` → `json_valid(x) AND json_type(x) = 'array'`；
/// 2. `json_array_elements(x::json)` → `json_each(x)`；
/// 3. `d->>'text'` → `json_extract(d.value, '$.text')`；
/// 4. `LEAST(a, b)` → `MIN(a, b)`（SQLite 两参 `MIN` 就是标量函数）；
/// 5. `CAST(? AS REAL)` → 用 `Variable<double>` 绑定，除法自然是实数除法。
///
/// **为什么 SQL 写成 raw 三引号字符串**：拆成多个相邻单引号片段会触发
/// `prefer_single_quotes`，且换行位置由格式器决定、与 SQL 的语义分行无关；
/// raw 字符串里 `$` 天然是字面量，JSON 路径无需逐处转义。
library;

import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/review_dao.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/dictionary/content_parse.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/candidate_selection.dart';
import 'package:lexiloop/domain/review/distractors.dart';
import 'package:lexiloop/domain/review/question_payload.dart';
import 'package:lexiloop/services/question_builder.dart';

// ═══════════════════════════════════════════════════════════════
// SQL 片段
// ═══════════════════════════════════════════════════════════════

/// 系统收尾写入的跳过原因：会话过期。
///
/// 这类跳过不是用户意愿，因此**不**进入候选排除，也不推高跳过统计。
const String _sessionExpiredReason = 'SESSION_EXPIRED';

/// 系统收尾写入的跳过原因：学习进度被重置。
const String _progressResetReason = 'PROGRESS_RESET';

/// 候选查询的公共列。
///
/// `content_type` 与 `entry_type` 并存是历史包袱：旧版句子的
/// `entry_type` 存为 `PHRASE`，因此范围判断一律用
/// `COALESCE(content_type, entry_type)`。
const String _candidateColumns = '''
  w.id, w.term, w.normalized_term, w.source_language, w.target_language,
  w.content_type, w.mastery_score''';

/// 可学习词条的固定条件：未暂停，且内容已就绪或部分就绪。
const String _learnableSql = '''
AND w.is_suspended = 0
AND w.initialization_status IN ('READY', 'PARTIAL')
''';

/// 只取句子。
const String _scopeSentenceSql = '''
AND COALESCE(w.content_type, w.entry_type) = 'SENTENCE'
''';

/// 只取单词与短语。
const String _scopeLexicalSql = '''
AND COALESCE(w.content_type, w.entry_type) <> 'SENTENCE'
''';

/// 「存在非空释义」条件。
///
/// **SQLite 语义调整**：旧版是
/// `json_typeof(wc.definitions_json::json) = 'array'` +
/// `json_array_elements(...)`；SQLite 必须先 `json_valid` 再 `json_type`，
/// 否则「合法 JSON 但不是数组」的脏数据（旧导入留下的对象）会让整条
/// 候选查询直接报 `malformed JSON` 而不是被过滤掉。
/// `json_extract(d.value, '$.text')` 对应 PG 的 `d->>'text'`，
/// `trim(...) <> ''` 与旧版 `btrim(...) <> ''` 一致地排除空释义。
const String _meaningSql = r'''
AND EXISTS (
  SELECT 1 FROM word_contents wc
  WHERE wc.word_id = w.id
    AND json_valid(wc.definitions_json)
    AND json_type(wc.definitions_json) = 'array'
    AND EXISTS (
      SELECT 1 FROM json_each(wc.definitions_json) d
      WHERE trim(json_extract(d.value, '$.text')) <> ''
    )
)
''';

/// 句子范围的「有可用内容」：释义或 `summary.translation` 任一非空。
///
/// 句子类词条常常只有整句翻译、没有逐词释义，只认释义会把它们全挡在
/// 句子复习之外。
const String _sentenceMeaningSql = r'''
AND EXISTS (
  SELECT 1 FROM word_contents wc
  WHERE wc.word_id = w.id
    AND (
      (
        json_valid(wc.definitions_json)
        AND json_type(wc.definitions_json) = 'array'
        AND EXISTS (
          SELECT 1 FROM json_each(wc.definitions_json) d
          WHERE trim(json_extract(d.value, '$.text')) <> ''
        )
      )
      OR (
        json_valid(wc.summary_json)
        AND json_type(wc.summary_json) = 'object'
        AND trim(json_extract(wc.summary_json, '$.translation')) <> ''
      )
    )
)
''';

/// 「当前可进入学习队列」条件（对应旧版 `availabilitySql`）。
///
/// 排除两类词条：
/// (a) 近 [skipCooldownMs] 内被用户**主动**跳过——`SESSION_EXPIRED` 与
///     `PROGRESS_RESET` 是系统收尾，不算用户意愿，故排除在外；
/// (b) 近 [sessionResumeTtlMs] 内已有 PENDING 题目且所属会话未完成——
///     该词条正在别的会话里等着作答，重复出题会打断恢复体验。
/// 小游戏（`MATCH_GAME` / `GAME_*`）的题目不算「占用」。
///
/// `NOT LIKE 'GAME_%'` 里的 `_` 在 SQL 中是单字符通配符，与 PG 行为一致，
/// 保留旧版写法以便逐条对照。
const String _availabilitySql =
    '''
NOT EXISTS (
  SELECT 1 FROM study_session_items skipped
  WHERE skipped.word_id = w.id
    AND skipped.status = 'SKIPPED'
    AND skipped.answered_at IS NOT NULL
    AND skipped.answered_at >= ?
    AND COALESCE(skipped.skip_reason, '')
        NOT IN ('$_sessionExpiredReason', '$_progressResetReason')
)
AND NOT EXISTS (
  SELECT 1 FROM study_session_items active_item
  JOIN study_sessions active_session
    ON active_session.id = active_item.study_session_id
  WHERE active_item.word_id = w.id
    AND active_item.status = 'PENDING'
    AND active_session.completed_at IS NULL
    AND COALESCE(active_session.source_type, '') <> 'MATCH_GAME'
    AND COALESCE(active_session.source_type, '') NOT LIKE 'GAME_%'
    AND active_session.started_at >= ?
)
''';

/// 按 `source_type` 恢复会话（AI 推荐 / 句子复习）。
///
/// 这两种模式的 `session_type` 被落成 `WRONG_WORDS` / `DUE_REVIEW`，
/// 只有 `source_type` 能区分，故单独一条查询。
const String _resumableSpecialSql = '''
SELECT s.id FROM study_sessions s
WHERE s.source_type = ?
  AND s.completed_at IS NULL
  AND s.started_at >= ?
  AND EXISTS (SELECT 1 FROM study_session_items i
              WHERE i.study_session_id = s.id AND i.status = 'PENDING')
ORDER BY s.started_at DESC
LIMIT 1''';

/// 按 `session_type` 精确恢复；排除小游戏与句子复习会话。
const String _resumableExactSql = '''
SELECT s.id FROM study_sessions s
WHERE s.session_type = ?
  AND s.completed_at IS NULL
  AND s.started_at >= ?
  AND COALESCE(s.source_type, '') <> 'MATCH_GAME'
  AND COALESCE(s.source_type, '') <> 'SENTENCE_REVIEW'
  AND COALESCE(s.source_type, '') NOT LIKE 'GAME_%'
  AND EXISTS (SELECT 1 FROM study_session_items i
              WHERE i.study_session_id = s.id AND i.status = 'PENDING')
ORDER BY s.started_at DESC
LIMIT 1''';

/// 退回按题目任务类型恢复：每日队列里混着各类任务，用户在「每日」里
/// 做到一半切到「仅新词」也应能接着做。
const String _resumableTaskSql = '''
SELECT s.id FROM study_sessions s
WHERE s.completed_at IS NULL
  AND s.started_at >= ?
  AND COALESCE(s.source_type, '') <> 'MATCH_GAME'
  AND COALESCE(s.source_type, '') <> 'SENTENCE_REVIEW'
  AND COALESCE(s.source_type, '') NOT LIKE 'GAME_%'
  AND EXISTS (SELECT 1 FROM study_session_items i
              WHERE i.study_session_id = s.id AND i.status = 'PENDING'
                AND i.task_type = ?)
ORDER BY s.started_at DESC
LIMIT 1''';

// ═══════════════════════════════════════════════════════════════
// 内部类型
// ═══════════════════════════════════════════════════════════════

/// 一段 SQL 条件及其绑定参数。
///
/// 条件与参数必须一起传递：候选查询有 4 处（due/wrong/fresh/leastRecent）
/// 共用同一套 scope + 释义 + 可用性条件，分两处维护必然漂移。
class _Clause {
  const new(this.sql, this.variables);

  final String sql;
  final List<Variable<Object>> variables;
}

/// 会话行的内部视图（比 [SessionHead] 多出计数与时长）。
class _SessionRow {
  const new({
    required this.id,
    required this.mode,
    required this.sourceType,
    required this.startedAt,
    required this.completedAt,
    required this.plannedCount,
    required this.completedCount,
    required this.correctCount,
    required this.wrongCount,
    required this.skippedCount,
    required this.durationMs,
  });

  final int id;
  final StudyMode mode;
  final String? sourceType;
  final int startedAt;
  final int? completedAt;
  final int plannedCount;
  final int completedCount;
  final int correctCount;
  final int wrongCount;
  final int skippedCount;
  final int? durationMs;
}

/// 会话题目行的内部视图。
///
/// 词条部分已在 SQL 里 JOIN 出来并解析成 [StudyWordView]，
/// 避免逐题再查一次 `word_contents`。
class _ItemRow {
  const new({
    required this.itemId,
    required this.position,
    required this.taskType,
    required this.questionType,
    required this.status,
    required this.skipReason,
    required this.word,
    required this.confusedWordsJson,
  });

  final int itemId;
  final double position;
  final StudyTaskType taskType;
  final QuestionType questionType;
  final StudyItemStatus status;
  final String? skipReason;
  final StudyWordView word;
  final String confusedWordsJson;
}

/// 今日 AI 推荐的一条原始条目。
class _RecommendedItem {
  const new({required this.wordId, required this.questionType});

  final int wordId;
  final QuestionType? questionType;
}

/// 按题型生成的选项（空集合表示该题型不需要选项）。
typedef _ChoiceSet = ({
  List<String> choices,
  Map<String, String> choiceDefinitions,
});

// ═══════════════════════════════════════════════════════════════
// 公开 API
// ═══════════════════════════════════════════════════════════════

/// 创建题目时的草稿。
class StudySessionItemDraft {
  /// 以各字段构造。
  const new({
    required this.wordId,
    required this.taskType,
    required this.questionType,
  });

  /// 词条 ID。
  final int wordId;

  /// 任务类型。
  final StudyTaskType taskType;

  /// 题型。
  final QuestionType questionType;
}

/// 会话头部信息。
class SessionHead {
  /// 以各字段构造。
  const new({
    required this.completedAt,
    required this.sourceType,
    required this.sessionType,
    required this.startedAt,
  });

  /// 完成时间；未完成时为 `null`。
  final int? completedAt;

  /// 特殊来源（`AI_RECOMMENDED` / `SENTENCE_REVIEW`）。
  final String? sourceType;

  /// 落库的会话类型（`StudyMode` 的 wire 值）。
  final String sessionType;

  /// 开始时间（epoch 毫秒）。
  final int startedAt;
}

/// 学习会话读写入口。
class StudyDao implements DistractorSource {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  // ── 候选查询 ──

  /// 到期复习候选，按紧迫度加权排序。
  ///
  /// 排序表达式与旧版逐项对应：逾期天数（封顶 [dueOverdueCapDays]）乘
  /// FSRS 难度加成，再加近 14 天的答错 / AGAIN / 模糊次数。
  /// 四个权重全部取自 `core/constants.dart`，便于调参与对照。
  ///
  /// **SQLite 语义调整**：PG 的 `LEAST(a, b)` 换成 `MIN(a, b)`——
  /// SQLite 的两参 `MIN` 就是标量函数（单参才是聚合函数）。
  /// `CAST(? - c.due_at AS REAL)` 换成绑定 `Variable<double>`：
  /// SQLite 的 `/` 只要任一侧是实数就做实数除法，无需显式 CAST。
  Future<List<StudyCandidate>> dueCandidates({
    required int limit,
    required int now,
    required CandidateScope scope,
  }) {
    final conditions = _candidateConditions(scope, now);
    return _queryCandidates(
      '''
SELECT $_candidateColumns,
  MIN((? - c.due_at) / ?, ?) * (1.0 + c.difficulty * ?)
    + COALESCE(s.recent_wrong_14d, 0) * ?
    + COALESCE(s.recent_again_14d, 0) * ?
    + COALESCE(s.recent_hard_14d, 0) * ? AS urgency
FROM review_cards c
JOIN words w ON w.id = c.word_id
LEFT JOIN word_review_stats s ON s.word_id = w.id
WHERE c.due_at <= ?
${conditions.sql}
ORDER BY urgency DESC, c.due_at ASC
LIMIT ?''',
      <Variable<Object>>[
        Variable<int>(now),
        Variable<double>(dayMs.toDouble()),
        const Variable<double>(dueOverdueCapDays),
        const Variable<double>(dueDifficultyWeight),
        const Variable<double>(dueRecentWrongWeight),
        const Variable<double>(dueRecentAgainWeight),
        const Variable<double>(dueRecentHardWeight),
        Variable<int>(now),
        ...conditions.variables,
        Variable<int>(limit),
      ],
    );
  }

  /// 错词候选，按错误次数与最近答错时间排序。
  Future<List<StudyCandidate>> wrongCandidates({
    required int limit,
    required int now,
    required CandidateScope scope,
  }) {
    final conditions = _candidateConditions(scope, now);
    return _queryCandidates(
      '''
SELECT $_candidateColumns
FROM wrong_word_states x
JOIN words w ON w.id = x.word_id
WHERE x.active = 1
${conditions.sql}
ORDER BY x.wrong_count DESC, x.hard_count DESC,
         COALESCE(x.last_wrong_at, x.updated_at) DESC
LIMIT ?''',
      <Variable<Object>>[...conditions.variables, Variable<int>(limit)],
    );
  }

  /// 新词候选（从未复习过，即没有 `review_cards` 行）。
  ///
  /// 排序按「入库先后」而非随机：新词应按导入顺序推进，否则同一批
  /// 导入的 500 个词会以不可复现的顺序出现，用户无法预期。
  /// 末尾追加 `w.id ASC` 作为确定性兜底——`created_at` 同毫秒时
  /// 只按时间排序会让结果不稳定，测试也就无法断言。
  Future<List<StudyCandidate>> newCandidates({
    required int limit,
    required int now,
    required CandidateScope scope,
  }) {
    final conditions = _candidateConditions(scope, now);
    return _queryCandidates(
      '''
SELECT $_candidateColumns
FROM words w
LEFT JOIN review_cards c ON c.word_id = w.id
WHERE c.word_id IS NULL
${conditions.sql}
ORDER BY COALESCE(w.source_created_at, w.created_at) ASC, w.id ASC
LIMIT ?''',
      <Variable<Object>>[...conditions.variables, Variable<int>(limit)],
    );
  }

  /// 最久未复习的候选，用于补齐题量；[excludedIds] 需排除。
  Future<List<StudyCandidate>> leastRecentlyReviewedCandidates({
    required int limit,
    required int now,
    required CandidateScope scope,
    required Set<int> excludedIds,
  }) {
    final conditions = _candidateConditions(scope, now);
    final exclusion = _excludeIds(excludedIds);
    return _queryCandidates(
      '''
SELECT $_candidateColumns
FROM words w
LEFT JOIN word_review_stats s ON s.word_id = w.id
WHERE 1 = 1
${conditions.sql}
${exclusion.sql}
ORDER BY COALESCE(s.last_reviewed_at, w.source_created_at, w.created_at) ASC,
         w.id ASC
LIMIT ?''',
      <Variable<Object>>[
        ...conditions.variables,
        ...exclusion.variables,
        Variable<int>(limit),
      ],
    );
  }

  /// 各池可用数量。
  ///
  /// 三个计数合成一条语句：条件片段与参数完全一致，分三次查询只会让
  /// 「某一池漏加了释义过滤」这类不一致更难发现。
  Future<CandidateAvailability> countAvailable({
    required int now,
    required CandidateScope scope,
  }) async {
    final conditions = _candidateConditions(scope, now);
    final row = await _db
        .customSelect(
          '''
SELECT
  (SELECT count(*) FROM review_cards c JOIN words w ON w.id = c.word_id
    WHERE c.due_at <= ?
${conditions.sql}) AS due,
  (SELECT count(*) FROM wrong_word_states x JOIN words w ON w.id = x.word_id
    WHERE x.active = 1
${conditions.sql}) AS wrong,
  (SELECT count(*) FROM words w LEFT JOIN review_cards c ON c.word_id = w.id
    WHERE c.word_id IS NULL
${conditions.sql}) AS fresh''',
          variables: <Variable<Object>>[
            Variable<int>(now),
            ...conditions.variables,
            ...conditions.variables,
            ...conditions.variables,
          ],
        )
        .getSingle();
    return CandidateAvailability(
      due: row.read<int>('due'),
      wrong: row.read<int>('wrong'),
      fresh: row.read<int>('fresh'),
    );
  }

  /// 组装三个候选池与配额。
  ///
  /// 配额来自设置（缺省即 `core/constants.dart` 的默认值）；
  /// `applyDailySoftQuota` 只在 [CandidateScope.lexical] 下生效，与旧版
  /// 一致——句子复习走独立配额，不该被每日单词计划挤掉。
  ///
  /// 每池查询量取「配额 + 三池配额之和」：候选在三池之间会互相去重、
  /// 抽题时又会按 [categoryLookahead] 加权，只按配额取会让实际可抽题数
  /// 低于配额。多取的部分不进 `limits`，因此不会放大计划题数。
  Future<StudyPools> loadPools({
    required int now,
    required CandidateScope scope,
    bool applyDailySoftQuota = false,
  }) async {
    final configured = await _configuredLimits();
    final soft = applyDailySoftQuota && scope == CandidateScope.lexical;
    final limits = soft
        ? _softLimits(configured, await dailyProgress(now))
        : configured;
    final buffer = configured.due + configured.wrong + configured.fresh;
    return StudyPools(
      due: await dueCandidates(
        limit: limits.due + buffer,
        now: now,
        scope: scope,
      ),
      wrong: await wrongCandidates(
        limit: limits.wrong + buffer,
        now: now,
        scope: scope,
      ),
      fresh: await newCandidates(
        limit: limits.fresh + buffer,
        now: now,
        scope: scope,
      ),
      limits: limits,
    );
  }

  /// 今日各任务类型已消耗的配额。
  ///
  /// 已作答 / 已跳过的按 `answered_at` 落在今天算，待作答的按会话
  /// `started_at` 落在今天算——否则「今天开的会话还没做完」会被漏计，
  /// 用户重开会话时又会拿到一份完整配额。
  ///
  /// 只统计 `session_type = 'DAILY'` 的会话：专项模式（听力、拼写、
  /// 错词本）有自己的入口，不该挤占每日计划的额度。
  Future<PoolLimits> dailyProgress(int now) async {
    final today = startOfLocalDay(now);
    final rows = await _db
        .customSelect(
          '''
SELECT i.task_type AS task_type, count(*) AS c
FROM study_session_items i
JOIN study_sessions s ON s.id = i.study_session_id
WHERE s.session_type = ?
  AND (
    (i.status IN ('ANSWERED', 'SKIPPED') AND i.answered_at >= ?)
    OR (i.status = 'PENDING' AND s.started_at >= ?)
  )
GROUP BY i.task_type''',
          variables: <Variable<Object>>[
            Variable<String>(StudyMode.daily.wire),
            Variable<int>(today),
            Variable<int>(today),
          ],
        )
        .get();
    return _accumulateProgress(rows);
  }

  /// 把「任务类型 -> 今日题数」的分组结果折算成三池配额。
  ///
  /// 听力 / 拼写题目不占三池配额（旧版同样忽略），只认
  /// REVIEW / WRONG / NEW 三类。
  PoolLimits _accumulateProgress(List<QueryRow> rows) {
    var due = 0;
    var wrong = 0;
    var fresh = 0;
    for (final row in rows) {
      final count = row.read<int>('c');
      switch (wireLookup(StudyTaskType.values, row.read<String>('task_type'))) {
        case StudyTaskType.newWord:
          fresh += count;
        case StudyTaskType.wrong:
          wrong += count;
        case StudyTaskType.review:
          due += count;
        case StudyTaskType.listening:
        case StudyTaskType.spelling:
        case null:
          break;
      }
    }
    return PoolLimits(due: due, wrong: wrong, fresh: fresh);
  }

  /// 统计「未完成会话里已存在的 PENDING 题目」按任务类别分布。
  ///
  /// 每日计划要把已开会话里没答的题一起算进去，否则首页显示
  /// 「计划 30 题」而实际要做 40 题。
  ///
  /// 类别判定沿用旧版 `study/plan.ts`：到期卡片算 REVIEW，活跃错词算
  /// WRONG，其余算 NEW——与 [_candidateConditions] 的三池口径保持一致。
  /// 句子类词条被排除：句子复习有独立入口与独立配额。
  Future<PoolLimits> activePendingPlan(int now) async {
    final rows = await _db
        .customSelect(
          '''
SELECT CASE
         WHEN c.due_at IS NOT NULL AND c.due_at <= ? THEN 'REVIEW'
         WHEN COALESCE(x.active, 0) = 1 THEN 'WRONG'
         ELSE 'NEW'
       END AS category, count(*) AS c
FROM study_session_items i
JOIN study_sessions s ON s.id = i.study_session_id
JOIN words w ON w.id = i.word_id
LEFT JOIN review_cards c ON c.word_id = w.id
LEFT JOIN wrong_word_states x ON x.word_id = w.id
WHERE i.status = 'PENDING'
  AND s.completed_at IS NULL
  AND s.started_at >= ?
  AND COALESCE(w.content_type, w.entry_type) <> 'SENTENCE'
  AND COALESCE(s.source_type, '') <> 'MATCH_GAME'
  AND COALESCE(s.source_type, '') NOT LIKE 'GAME_%'
GROUP BY category''',
          variables: <Variable<Object>>[
            Variable<int>(now),
            Variable<int>(now - sessionResumeTtlMs),
          ],
        )
        .get();
    return _accumulatePendingPlan(rows);
  }

  /// 统计未完成的「句子复习」会话里还剩多少 PENDING 题目。
  ///
  /// 单独一条查询而不是复用 [activePendingPlan]：句子复习的进度要按
  /// `source_type = 'SENTENCE_REVIEW'` 精确匹配，且不能被算进单词计划。
  Future<int> activePendingSentenceCount(int now) async {
    final row = await _db
        .customSelect(
          '''
SELECT count(*) AS c
FROM study_session_items i
JOIN study_sessions s ON s.id = i.study_session_id
JOIN words w ON w.id = i.word_id
WHERE i.status = 'PENDING'
  AND s.completed_at IS NULL
  AND s.started_at >= ?
  AND COALESCE(w.content_type, w.entry_type) = 'SENTENCE'
  AND s.source_type = ?''',
          variables: <Variable<Object>>[
            Variable<int>(now - sessionResumeTtlMs),
            Variable<String>(StudyMode.sentenceReview.wire),
          ],
        )
        .getSingle();
    return row.read<int>('c');
  }

  /// 把「类别 -> 待答题数」的分组结果折算成三池配额。
  PoolLimits _accumulatePendingPlan(List<QueryRow> rows) {
    var due = 0;
    var wrong = 0;
    var fresh = 0;
    for (final row in rows) {
      final count = row.read<int>('c');
      switch (row.read<String>('category')) {
        case 'REVIEW':
          due += count;
        case 'WRONG':
          wrong += count;
        case 'NEW':
          fresh += count;
      }
    }
    return PoolLimits(due: due, wrong: wrong, fresh: fresh);
  }

  /// 今日 AI 推荐候选（读 `daily_ai_suggestions` 表）。
  ///
  /// 与普通候选不同：只排除「近 [skipCooldownMs] 内被主动跳过」与
  /// 「今天已在 AI 推荐会话里做过」的词条，**不**排除其他会话里
  /// PENDING 的词条——今日必做题的优先级高于普通队列。
  ///
  /// 返回顺序沿用建议列表自身的顺序（AI 已排过序），
  /// 而不是数据库返回顺序。
  Future<List<StudyCandidate>> aiRecommendedCandidates(int now) async {
    final recommended = await _loadRecommendedItems(now);
    if (recommended.isEmpty) return const <StudyCandidate>[];
    final found = <int, StudyCandidate>{};
    final ids = recommended.map((item) => item.wordId).toList(growable: false);
    for (final chunk in _chunks(ids)) {
      for (final candidate in await _aiCandidateChunk(chunk, now)) {
        found[candidate.id] = candidate;
      }
    }
    return <StudyCandidate>[
      for (final item in recommended)
        if (found[item.wordId] case final candidate?)
          _withRecommendedType(candidate, item.questionType),
    ];
  }

  // ── 会话 ──

  /// 创建会话与题目，返回会话 ID。
  ///
  /// `items` 的顺序即 `position` 顺序，位置按 [sessionItemPositionStep]
  /// 递增（0, 0.5, 1.0…）而非 0, 1, 2：自适应插题要在相邻两项之间取
  /// 位置，整数步长插入一次后就再无空隙可用。
  ///
  /// 空会话立即标记完成（与旧版一致）：没有题目的会话没有恢复价值，
  /// 留成「未完成」只会污染统计与恢复查询。
  Future<int> createSession({
    required StudyMode mode,
    required String? sourceType,
    required List<StudySessionItemDraft> items,
    required int now,
  }) {
    return _db.transaction(() async {
      final sessionId = await _db
          .into(_db.studySessions)
          .insert(
            StudySessionsCompanion.insert(
              sessionType: mode,
              sourceType: Value<String?>(sourceType),
              startedAt: now,
              completedAt: Value<int?>(items.isEmpty ? now : null),
              plannedCount: Value<int>(items.length),
              createdAt: now,
            ),
          );
      await _insertItems(sessionId, items, now);
      return sessionId;
    });
  }

  /// 加载会话完整视图（含每题选项/填空/字母块）。
  ///
  /// 会话不存在时抛 [AppErrorCode.sessionNotFound]。选项生成委托给
  /// [QuestionBuilder]（`StudyDao` 自己就是它的 [DistractorSource]），
  /// 本题型需要什么就只构造什么，避免为 30 道题各跑一次无用的随机池查询。
  Future<StudySessionView> loadSession(
    int sessionId, {
    bool resumed = false,
  }) async {
    final session = await _loadSessionRow(sessionId);
    final rows = await _loadItemRows(sessionId);
    final builder = QuestionBuilder(this);
    final random = math.Random();
    final items = <StudyItemView>[];
    for (final row in rows) {
      items.add(await _buildItemView(row, builder, random.nextDouble));
    }
    return _sessionView(session, items, resumed: resumed);
  }

  /// 查找可恢复的会话 ID。
  ///
  /// `AI_RECOMMENDED` / `SENTENCE_REVIEW` 直接按 `source_type` 找；其余模式
  /// 先按 `session_type` 精确匹配，再退回「任意未完成会话里还有该任务类型
  /// 的待答题目」。只认 [sessionResumeTtlMs] 内开始的会话——更早的会话
  /// 应由 [expireStaleSessions] 收尾，恢复它们等于把过期题目塞回用户面前。
  Future<int?> findResumableSession(StudyMode mode, int now) async {
    final ttl = now - sessionResumeTtlMs;
    if (mode == StudyMode.aiRecommended || mode == StudyMode.sentenceReview) {
      return await _resumableId(_resumableSpecialSql, <Variable<Object>>[
        Variable<String>(mode.wire),
        Variable<int>(ttl),
      ]);
    }
    final exact = await _resumableId(_resumableExactSql, <Variable<Object>>[
      Variable<String>(mode.wire),
      Variable<int>(ttl),
    ]);
    if (exact != null) return exact;
    final taskType = _taskTypeFor(mode);
    if (taskType == null) return null;
    return await _resumableId(_resumableTaskSql, <Variable<Object>>[
      Variable<int>(ttl),
      Variable<String>(taskType.wire),
    ]);
  }

  /// 把超过 [sessionResumeTtlMs] 未完成的会话标记过期并收尾，
  /// 返回被标记过期的题目数。
  ///
  /// 过期题目记 `skip_reason = 'SESSION_EXPIRED'`，因此既不会被候选排除
  /// （见 `_availabilitySql`），也不推高 `skipped_count`——只累加
  /// `completed_count`，与旧版一致。
  Future<int> expireStaleSessions(int now) {
    return _db.transaction(() async {
      final rows = await _db
          .customSelect(
            'SELECT id FROM study_sessions '
            'WHERE completed_at IS NULL AND started_at < ?',
            variables: <Variable<Object>>[
              Variable<int>(now - sessionResumeTtlMs),
            ],
          )
          .get();
      var expired = 0;
      for (final row in rows) {
        expired += await _expireSession(row.read<int>('id'), now);
      }
      return expired;
    });
  }

  /// 跳过一道题，返回更新后的会话视图。
  ///
  /// 先读一次状态再更新：只靠 `UPDATE ... WHERE status = 'PENDING'` 的
  /// 影响行数无法区分「题目不存在」与「已经处理过」，而这两者对应
  /// 不同的错误码。全部动作在一个事务里，避免计数与状态错位。
  Future<StudySessionView> skipItem({
    required int sessionId,
    required int itemId,
    required String reason,
    required int now,
  }) async {
    await _db.transaction(() async {
      final row = await _db
          .customSelect(
            '''
SELECT i.status, s.completed_at
FROM study_session_items i
JOIN study_sessions s ON s.id = i.study_session_id
WHERE i.id = ? AND i.study_session_id = ?''',
            variables: <Variable<Object>>[
              Variable<int>(itemId),
              Variable<int>(sessionId),
            ],
          )
          .getSingleOrNull();
      if (row == null) {
        throw const NotFoundError(AppErrorCode.studyItemNotFound);
      }
      if (row.readNullable<int>('completed_at') != null ||
          row.read<String>('status') != StudyItemStatus.pending.wire) {
        throw const ConflictError(AppErrorCode.studyItemAlreadyProcessed);
      }
      await _markSkipped(sessionId, itemId, reason, now);
      await incrementSkippedCount(sessionId);
      if (await _pendingItemCount(sessionId) == 0) {
        await ReviewDao(_db).closeSession(sessionId, now);
      }
    });
    return await loadSession(sessionId);
  }

  /// 在会话内插入一道追问题（自适应插题），返回插入位置。
  ///
  /// [position] 由调用方算好（按 [sessionItemPositionStep] 在相邻两项之间
  /// 取中点），本方法只负责落库并把 `planned_count` 加一。
  ///
  /// `task_type` 固定为 [StudyTaskType.wrong]（与旧版 `adaptive.ts` 一致）：
  /// 追问题由答错触发，统计上应计入错词任务，而不是原题的任务类型。
  Future<double> insertFollowUpItem({
    required int sessionId,
    required int wordId,
    required QuestionType questionType,
    required double position,
    required int now,
  }) async {
    await _db
        .into(_db.studySessionItems)
        .insert(
          StudySessionItemsCompanion.insert(
            studySessionId: sessionId,
            position: position,
            wordId: wordId,
            taskType: StudyTaskType.wrong,
            questionType: questionType,
            createdAt: now,
          ),
        );
    await incrementPlannedCount(sessionId);
    return position;
  }

  /// 统计某词在会话内已作答的题目数。
  Future<int> answeredCountInSession({
    required int sessionId,
    required int wordId,
  }) => _countItems(sessionId, wordId, StudyItemStatus.answered);

  /// 统计某词在会话内待作答的题目数。
  Future<int> pendingCountInSession({
    required int sessionId,
    required int wordId,
  }) => _countItems(sessionId, wordId, StudyItemStatus.pending);

  /// 读取一道题的位置；不存在返回 null。
  Future<double?> findItemPosition({
    required int sessionId,
    required int itemId,
  }) async {
    final row = await _db
        .customSelect(
          '''
SELECT position FROM study_session_items
WHERE id = ? AND study_session_id = ?''',
          variables: <Variable<Object>>[
            Variable<int>(itemId),
            Variable<int>(sessionId),
          ],
        )
        .getSingleOrNull();
    return row?.read<double>('position');
  }

  /// 会话内最后一个位置；无题目时返回 null。
  Future<double?> lastItemPosition(int sessionId) async {
    final row = await _db
        .customSelect(
          'SELECT MAX(position) AS p FROM study_session_items '
          'WHERE study_session_id = ?',
          variables: <Variable<Object>>[Variable<int>(sessionId)],
        )
        .getSingle();
    return row.readNullable<double>('p');
  }

  /// 读取 [afterPosition] 之后第 [offset] 项（offset 从 0 起）的 position。
  ///
  /// 按 position 升序，只取严格大于 [afterPosition] 的项；
  /// 不足 `offset + 1` 项时返回 `null`。自适应插题用它找「隔 N 题之后」
  /// 的落点，从而让追问既不复现得太快、也不落到会话末尾。
  ///
  /// SQLite 的 `LIMIT 1 OFFSET ?` 与 PG 语义一致，无需改写。
  Future<double?> positionAtOffset({
    required int sessionId,
    required double afterPosition,
    required int offset,
  }) async {
    final row = await _db
        .customSelect(
          '''
SELECT position FROM study_session_items
WHERE study_session_id = ? AND position > ?
ORDER BY position ASC
LIMIT 1 OFFSET ?''',
          variables: <Variable<Object>>[
            Variable<int>(sessionId),
            Variable<double>(afterPosition),
            Variable<int>(offset),
          ],
        )
        .getSingleOrNull();
    return row?.read<double>('position');
  }

  /// 读取严格小于 [position] 的最后一项的 position；没有则返回 `null`。
  ///
  /// 与 [positionAtOffset] 配对：拿到目标落点后再取它的前一项，
  /// 两者之间取中点即可插入而不破坏
  /// `UNIQUE(study_session_id, position)`。
  Future<double?> previousPositionBefore({
    required int sessionId,
    required double position,
  }) async {
    final row = await _db
        .customSelect(
          '''
SELECT position FROM study_session_items
WHERE study_session_id = ? AND position < ?
ORDER BY position DESC
LIMIT 1''',
          variables: <Variable<Object>>[
            Variable<int>(sessionId),
            Variable<double>(position),
          ],
        )
        .getSingleOrNull();
    return row?.read<double>('position');
  }

  /// 读取会话的 completed_at 与 source_type；不存在返回 null。
  Future<SessionHead?> findSessionHead(int sessionId) async {
    final row = await _db
        .customSelect(
          '''
SELECT completed_at, source_type, session_type, started_at
FROM study_sessions WHERE id = ?''',
          variables: <Variable<Object>>[Variable<int>(sessionId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return SessionHead(
      completedAt: row.readNullable<int>('completed_at'),
      sourceType: row.readNullable<String>('source_type'),
      sessionType: row.read<String>('session_type'),
      startedAt: row.read<int>('started_at'),
    );
  }

  /// 增加会话的计划题数。
  Future<void> incrementPlannedCount(int sessionId) =>
      _incrementSession(sessionId, 'planned_count = planned_count + 1');

  /// 增加会话的跳过计数与完成计数。
  ///
  /// 跳过也算「处理过」：会话的完成判定看的是还有没有 PENDING 题目，
  /// `completed_count` 必须跟着涨，否则进度条永远差一截。
  Future<void> incrementSkippedCount(int sessionId) => _incrementSession(
    sessionId,
    'completed_count = completed_count + 1, '
    'skipped_count = skipped_count + 1',
  );

  // ── DistractorSource 实现 ──

  /// 按词条文本批量取候选（用于「易混词」优先）。
  ///
  /// 命中上限 [specificDistractorLimit]。与旧版一致地**不**过滤暂停 /
  /// 未就绪词条：干扰项只是选项文本，它本身不会被学习。
  @override
  Future<List<DistractorRow>> byTerms(List<String> terms, int excludedWordId) {
    if (terms.isEmpty) {
      return Future<List<DistractorRow>>.value(const <DistractorRow>[]);
    }
    return _queryDistractors(
      '''
SELECT w.id AS word_id, w.term, c.definitions_json
FROM words w
JOIN word_contents c ON c.word_id = w.id
WHERE w.term IN (${_placeholders(terms.length)})
  AND w.id != ?
  AND c.definitions_json IS NOT NULL
  AND c.definitions_json != '[]'
LIMIT ?''',
      <Variable<Object>>[
        ...terms.map(Variable<String>.new),
        Variable<int>(excludedWordId),
        const Variable<int>(specificDistractorLimit),
      ],
    );
  }

  /// 取用户错词本中的候选（按错误次数降序）。
  ///
  /// 加 `hard_count DESC` 作为次级排序：只按 `wrong_count` 排序时，
  /// 同分词的顺序由 SQLite 的扫描顺序决定，同一道题的选项会随
  /// 索引状态漂移。
  @override
  Future<List<DistractorRow>> activeWrongWords(int excludedWordId) =>
      _queryDistractors(
        '''
SELECT w.id AS word_id, w.term, c.definitions_json
FROM wrong_word_states x
JOIN words w ON w.id = x.word_id
JOIN word_contents c ON c.word_id = w.id
WHERE x.active = 1
  AND w.id != ?
  AND w.is_suspended = 0
  AND c.definitions_json IS NOT NULL
  AND c.definitions_json != '[]'
ORDER BY x.wrong_count DESC, x.hard_count DESC
LIMIT ?''',
        <Variable<Object>>[
          Variable<int>(excludedWordId),
          const Variable<int>(activeWrongDistractorLimit),
        ],
      );

  /// 从全局池中随机取候选。
  ///
  /// 旧版在模块级缓存一个 [distractorPoolSize] 条的池反复消费；本版不做
  /// 跨调用缓存——`docs/CLEAN_CODE_BASELINE.md` 指出全局可变缓存会跨请求
  /// 共享状态、并发测试不友好，而本地 SQLite 上 `ORDER BY RANDOM()` 的
  /// 代价本就很低。
  ///
  /// 取 `max(count, distractorTakeSize)` 条：释义可能大量重复，
  /// 多取一些才够挑出 [meaningDistractorCount] 个不重复的干扰项；
  /// 上限 [distractorPoolSize] 防止一次拉太多。
  @override
  Future<List<DistractorRow>> randomPool(Set<int> excludedWordIds, int count) {
    final exclusion = _excludeIds(excludedWordIds);
    return _queryDistractors(
      '''
SELECT w.id AS word_id, w.term, c.definitions_json
FROM word_contents c
JOIN words w ON w.id = c.word_id
WHERE w.is_suspended = 0
  AND w.initialization_status IN ('READY', 'PARTIAL')
  AND c.definitions_json IS NOT NULL
  AND c.definitions_json != '[]'
${exclusion.sql}
ORDER BY RANDOM()
LIMIT ?''',
      <Variable<Object>>[
        ...exclusion.variables,
        Variable<int>(
          math.min(distractorPoolSize, math.max(count, distractorTakeSize)),
        ),
      ],
    );
  }

  /// 按词条 ID 批量读取「是否有可用例句」。
  ///
  /// 缺行的词条显式记为 `false` 而不是漏键：调用方据此决定能否出
  /// 填空题，漏键会退化成 `?? false` 的隐式约定，读代码时看不出来。
  Future<Map<int, bool>> hasExampleMap(List<int> wordIds) async {
    final result = <int, bool>{for (final id in wordIds) id: false};
    for (final chunk in _chunks(wordIds)) {
      final rows = await _db
          .customSelect(
            'SELECT word_id, examples_json FROM word_contents '
            'WHERE word_id IN (${_placeholders(chunk.length)})',
            variables: <Variable<Object>>[...chunk.map(Variable<int>.new)],
          )
          .get();
      for (final row in rows) {
        result[row.read<int>('word_id')] = hasExampleIn(
          row.readNullable<String>('examples_json'),
        );
      }
    }
    return result;
  }

  // ── 内部实现 ──

  Future<List<StudyCandidate>> _queryCandidates(
    String sql,
    List<Variable<Object>> variables,
  ) async {
    final rows = await _db.customSelect(sql, variables: variables).get();
    return rows.map(_mapCandidate).toList(growable: false);
  }

  Future<List<DistractorRow>> _queryDistractors(
    String sql,
    List<Variable<Object>> variables,
  ) async {
    final rows = await _db.customSelect(sql, variables: variables).get();
    return rows.map(_mapDistractor).toList(growable: false);
  }

  Future<void> _insertItems(
    int sessionId,
    List<StudySessionItemDraft> items,
    int now,
  ) async {
    await _db.batch((batch) {
      for (var index = 0; index < items.length; index += 1) {
        final draft = items[index];
        batch.insert(
          _db.studySessionItems,
          StudySessionItemsCompanion.insert(
            studySessionId: sessionId,
            position: index * sessionItemPositionStep,
            wordId: draft.wordId,
            taskType: draft.taskType,
            questionType: draft.questionType,
            createdAt: now,
          ),
        );
      }
    });
  }

  Future<_SessionRow> _loadSessionRow(int sessionId) async {
    final row = await _db
        .customSelect(
          '''
SELECT id, session_type, source_type, started_at, completed_at,
       planned_count, completed_count, correct_count, wrong_count,
       skipped_count, duration_ms
FROM study_sessions WHERE id = ?''',
          variables: <Variable<Object>>[Variable<int>(sessionId)],
        )
        .getSingleOrNull();
    if (row == null) throw const NotFoundError(AppErrorCode.sessionNotFound);
    return _SessionRow(
      id: row.read<int>('id'),
      mode: _modeOf(
        row.read<String>('session_type'),
        row.readNullable<String>('source_type'),
      ),
      sourceType: row.readNullable<String>('source_type'),
      startedAt: row.read<int>('started_at'),
      completedAt: row.readNullable<int>('completed_at'),
      plannedCount: row.read<int>('planned_count'),
      completedCount: row.read<int>('completed_count'),
      correctCount: row.read<int>('correct_count'),
      wrongCount: row.read<int>('wrong_count'),
      skippedCount: row.read<int>('skipped_count'),
      durationMs: row.readNullable<int>('duration_ms'),
    );
  }

  Future<List<_ItemRow>> _loadItemRows(int sessionId) async {
    final rows = await _db
        .customSelect(
          '''
SELECT i.id AS item_id, i.position, i.task_type, i.question_type, i.status,
       i.skip_reason, w.id AS word_id, w.term, w.source_language,
       w.target_language, w.content_type, c.definitions_json,
       c.pronunciations_json, c.examples_json, c.confused_words_json,
       c.summary_json
FROM study_session_items i
JOIN words w ON w.id = i.word_id
LEFT JOIN word_contents c ON c.word_id = w.id
WHERE i.study_session_id = ?
ORDER BY i.position ASC''',
          variables: <Variable<Object>>[Variable<int>(sessionId)],
        )
        .get();
    return rows.map(_mapItemRow).toList(growable: false);
  }

  Future<StudyItemView> _buildItemView(
    _ItemRow row,
    QuestionBuilder builder,
    double Function() random,
  ) async {
    final choices = await _choicesFor(row, builder);
    return StudyItemView(
      itemId: row.itemId,
      position: row.position,
      taskType: row.taskType,
      questionType: row.questionType,
      status: row.status,
      skipReason: row.skipReason,
      word: row.word,
      choices: choices.choices,
      choiceDefinitions: choices.choiceDefinitions,
      cloze: row.questionType == QuestionType.clozeSentence
          ? buildCloze(row.word.term, row.word.examples)
          : null,
      letters: row.questionType == QuestionType.letterBank
          ? buildLetterTiles(row.word.term, random: random)
          : const <LetterTile>[],
    );
  }

  /// 按题型生成选项；非选择题返回空集合。
  Future<_ChoiceSet> _choicesFor(_ItemRow row, QuestionBuilder builder) async {
    final confused = _parseConfusedTerms(row.confusedWordsJson);
    switch (row.questionType) {
      case QuestionType.enToZhChoice:
        final choices = await builder.meaningChoices(
          wordId: row.word.id,
          targetLanguage: row.word.targetLanguage,
          definitions: row.word.definitions,
          confusedTerms: confused,
        );
        return (choices: choices, choiceDefinitions: const <String, String>{});
      case QuestionType.zhToEnChoice:
      case QuestionType.listeningChoice:
        final payload = await builder.wordChoices(
          wordId: row.word.id,
          term: row.word.term,
          targetLanguage: row.word.targetLanguage,
          definitions: row.word.definitions,
          confusedTerms: confused,
        );
        return (
          choices: payload.choices,
          choiceDefinitions: payload.choiceDefinitions,
        );
      case QuestionType.enToZh:
      case QuestionType.zhToEnSpelling:
      case QuestionType.listeningSpelling:
      case QuestionType.clozeSentence:
      case QuestionType.letterBank:
        return (
          choices: const <String>[],
          choiceDefinitions: const <String, String>{},
        );
    }
  }

  Future<int> _expireSession(int sessionId, int now) async {
    final changes = await _db.customUpdate(
      '''
UPDATE study_session_items
SET status = 'SKIPPED', answered_at = ?, skip_reason = ?
WHERE study_session_id = ? AND status = 'PENDING' ''',
      variables: <Variable<Object>>[
        Variable<int>(now),
        const Variable<String>(_sessionExpiredReason),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{
        _db.studySessionItems,
      },
    );
    await _db.customUpdate(
      'UPDATE study_sessions SET completed_count = completed_count + ? '
      'WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<int>(changes),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.studySessions},
    );
    await ReviewDao(_db).closeSession(sessionId, now);
    return changes;
  }

  Future<void> _markSkipped(
    int sessionId,
    int itemId,
    String reason,
    int now,
  ) async {
    final updated = await _db.customUpdate(
      '''
UPDATE study_session_items
SET status = 'SKIPPED', answered_at = ?, skip_reason = ?
WHERE id = ? AND study_session_id = ? AND status = 'PENDING' ''',
      variables: <Variable<Object>>[
        Variable<int>(now),
        Variable<String>(reason),
        Variable<int>(itemId),
        Variable<int>(sessionId),
      ],
      updates: <ResultSetImplementation<dynamic, dynamic>>{
        _db.studySessionItems,
      },
    );
    if (updated != 1) {
      throw const ConflictError(AppErrorCode.studyItemAlreadyProcessed);
    }
  }

  Future<int> _pendingItemCount(int sessionId) async {
    final row = await _db
        .customSelect(
          '''
SELECT count(*) AS c FROM study_session_items
WHERE study_session_id = ? AND status = ?''',
          variables: <Variable<Object>>[
            Variable<int>(sessionId),
            Variable<String>(StudyItemStatus.pending.wire),
          ],
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<int> _countItems(
    int sessionId,
    int wordId,
    StudyItemStatus status,
  ) async {
    final row = await _db
        .customSelect(
          '''
SELECT count(*) AS c FROM study_session_items
WHERE study_session_id = ? AND word_id = ? AND status = ?''',
          variables: <Variable<Object>>[
            Variable<int>(sessionId),
            Variable<int>(wordId),
            Variable<String>(status.wire),
          ],
        )
        .getSingle();
    return row.read<int>('c');
  }

  Future<void> _incrementSession(int sessionId, String assignments) async {
    await _db.customUpdate(
      'UPDATE study_sessions SET $assignments WHERE id = ?',
      variables: <Variable<Object>>[Variable<int>(sessionId)],
      updates: <ResultSetImplementation<dynamic, dynamic>>{_db.studySessions},
    );
  }

  Future<int?> _resumableId(
    String sql,
    List<Variable<Object>> variables,
  ) async {
    final row = await _db
        .customSelect(sql, variables: variables)
        .getSingleOrNull();
    return row?.read<int>('id');
  }

  Future<PoolLimits> _configuredLimits() async {
    final settings = appSettingsFromRaw(await SettingsDao(_db).loadRaw());
    final plan = settings.studyPlan;
    return PoolLimits(
      due: plan.dailyDueReviewLimit,
      wrong: plan.dailyWrongWordLimit,
      fresh: plan.dailyNewWords,
    );
  }

  PoolLimits _softLimits(PoolLimits configured, PoolLimits used) => PoolLimits(
    due: dailySoftLimit(configured.due, used.due),
    wrong: dailySoftLimit(configured.wrong, used.wrong),
    fresh: dailySoftLimit(configured.fresh, used.fresh),
  );

  Future<List<_RecommendedItem>> _loadRecommendedItems(int now) async {
    final row = await _db
        .customSelect(
          'SELECT recommended_items_json FROM daily_ai_suggestions '
          'WHERE date_key = ?',
          variables: <Variable<Object>>[Variable<String>(dateKey(now))],
        )
        .getSingleOrNull();
    if (row == null) return const <_RecommendedItem>[];
    return _parseRecommendedItems(row.read<String>('recommended_items_json'));
  }

  Future<List<StudyCandidate>> _aiCandidateChunk(List<int> ids, int now) async {
    final rows = await _db
        .customSelect(
          '''
SELECT $_candidateColumns
FROM words w
WHERE w.id IN (${_placeholders(ids.length)})
$_learnableSql$_meaningSql
  AND NOT EXISTS (
    SELECT 1 FROM study_session_items skipped
    WHERE skipped.word_id = w.id
      AND skipped.status = 'SKIPPED'
      AND skipped.answered_at IS NOT NULL
      AND skipped.answered_at >= ?
      AND COALESCE(skipped.skip_reason, '')
          NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET')
  )
  AND NOT EXISTS (
    SELECT 1 FROM study_session_items done
    JOIN study_sessions ds ON ds.id = done.study_session_id
    WHERE done.word_id = w.id
      AND ds.source_type = ?
      AND ds.started_at >= ?
      AND done.status IN ('ANSWERED', 'SKIPPED')
      AND COALESCE(done.skip_reason, '')
          NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET')
  )''',
          variables: <Variable<Object>>[
            ...ids.map(Variable<int>.new),
            Variable<int>(now - skipCooldownMs),
            Variable<String>(StudyMode.aiRecommended.wire),
            Variable<int>(startOfLocalDay(now)),
          ],
        )
        .get();
    return rows.map(_mapCandidate).toList(growable: false);
  }

  StudyCandidate _mapCandidate(QueryRow row) => StudyCandidate(
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
    masteryScore: row.readNullable<int>('mastery_score'),
  );

  DistractorRow _mapDistractor(QueryRow row) => DistractorRow(
    wordId: row.read<int>('word_id'),
    term: row.read<String>('term'),
    definitionsJson: row.read<String>('definitions_json'),
  );

  _ItemRow _mapItemRow(QueryRow row) => _ItemRow(
    itemId: row.read<int>('item_id'),
    position: row.read<double>('position'),
    taskType:
        wireLookup(StudyTaskType.values, row.read<String>('task_type')) ??
        StudyTaskType.review,
    questionType:
        wireLookup(QuestionType.values, row.read<String>('question_type')) ??
        QuestionType.enToZh,
    status:
        wireLookup(StudyItemStatus.values, row.read<String>('status')) ??
        StudyItemStatus.pending,
    skipReason: row.readNullable<String>('skip_reason'),
    word: _mapWordView(row),
    confusedWordsJson: row.readNullable<String>('confused_words_json') ?? '',
  );

  /// 把 JOIN 出来的一行映射为学习视图需要的词条字段。
  ///
  /// 只解析学习与朗读必需的 4 个 JSON 列；详情页要用的词根、词族等
  /// 不在这里加载，避免一次会话把整张 `word_contents` 拖进内存。
  StudyWordView _mapWordView(QueryRow row) => StudyWordView(
    id: row.read<int>('word_id'),
    term: row.read<String>('term'),
    sourceLanguage: row.read<String>('source_language'),
    targetLanguage: row.read<String>('target_language'),
    contentType:
        wireLookup(
          LexicalContentType.values,
          row.read<String>('content_type'),
        ) ??
        LexicalContentType.word,
    definitions: parseDefinitionsJson(
      row.readNullable<String>('definitions_json'),
    ),
    pronunciations: parsePronunciations(
      row.readNullable<String>('pronunciations_json'),
    ),
    examples: parseExamples(row.readNullable<String>('examples_json')),
    translation: summaryTranslationOf(row.readNullable<String>('summary_json')),
  );
}

// ═══════════════════════════════════════════════════════════════
// 顶层工具
// ═══════════════════════════════════════════════════════════════

/// 候选查询的公共条件：可学习 + 范围 + 有内容 + 可用。
///
/// 参数顺序必须与 SQL 文本里的 `?` 顺序一致：可用性条件的两个占位符
/// （跳过冷却、会话恢复期）排在最前，因为它们出现在 WHERE 子句里，
/// 而 `LIMIT ?` 永远在最后。
_Clause _candidateConditions(CandidateScope scope, int now) => _Clause(
  '$_learnableSql${_scopeSql(scope)}${_meaningSqlFor(scope)}'
  'AND $_availabilitySql',
  <Variable<Object>>[
    Variable<int>(now - skipCooldownMs),
    Variable<int>(now - sessionResumeTtlMs),
  ],
);

/// 范围条件。
String _scopeSql(CandidateScope scope) => switch (scope) {
  CandidateScope.sentence => _scopeSentenceSql,
  CandidateScope.lexical => _scopeLexicalSql,
  CandidateScope.all => '',
};

/// 「有可用内容」条件。
///
/// 按**范围**而非按词条类型选择：`all` 走释义-only 变体，与旧版
/// `hasMeaningSql(scope)` 的行为逐字对应。
String _meaningSqlFor(CandidateScope scope) =>
    scope == CandidateScope.sentence ? _sentenceMeaningSql : _meaningSql;

/// 排除指定词条 ID。
///
/// 按 [sqlBatchChunkSize] 分批拼成多个 `NOT IN`：SQLite 的绑定变量上限
/// 在旧版本上只有 999，一次性拼进去会在低版本设备上直接失败。
_Clause _excludeIds(Set<int> ids) {
  if (ids.isEmpty) return const _Clause('', <Variable<Object>>[]);
  final list = ids.toList(growable: false);
  final conditions = <String>[];
  final variables = <Variable<Object>>[];
  for (var start = 0; start < list.length; start += sqlBatchChunkSize) {
    final end = math.min(start + sqlBatchChunkSize, list.length);
    final chunk = list.sublist(start, end);
    conditions.add('AND w.id NOT IN (${_placeholders(chunk.length)})');
    variables.addAll(chunk.map(Variable<int>.new));
  }
  return _Clause(conditions.join('\n'), variables);
}

/// 生成 `?, ?, ?` 形式的占位符列表。
String _placeholders(int count) => List<String>.filled(count, '?').join(', ');

/// 把 ID 列表按 [sqlBatchChunkSize] 切块。
Iterable<List<int>> _chunks(List<int> ids) sync* {
  for (var start = 0; start < ids.length; start += sqlBatchChunkSize) {
    yield ids.sublist(start, math.min(start + sqlBatchChunkSize, ids.length));
  }
}

/// 会话模式：`AI_RECOMMENDED` / `SENTENCE_REVIEW` 以 `source_type` 为准。
///
/// 旧版把这两种模式的 `session_type` 落成 `WRONG_WORDS` / `DUE_REVIEW`
/// （源端的枚举约束不接受它们），只有 `source_type` 能还原真实模式。
StudyMode _modeOf(String sessionType, String? sourceType) {
  if (sourceType == StudyMode.aiRecommended.wire) {
    return StudyMode.aiRecommended;
  }
  if (sourceType == StudyMode.sentenceReview.wire) {
    return StudyMode.sentenceReview;
  }
  return wireLookup(StudyMode.values, sessionType) ?? StudyMode.daily;
}

/// 学习模式到题目任务类型的映射（用于在每日队列里恢复会话）。
StudyTaskType? _taskTypeFor(StudyMode mode) => switch (mode) {
  StudyMode.dueReview => StudyTaskType.review,
  StudyMode.wrongWords => StudyTaskType.wrong,
  StudyMode.newWords => StudyTaskType.newWord,
  StudyMode.listening => StudyTaskType.listening,
  StudyMode.spelling => StudyTaskType.spelling,
  StudyMode.daily ||
  StudyMode.sentenceReview ||
  StudyMode.aiRecommended => null,
};

/// 组装会话视图，并定位第一道待作答题目。
StudySessionView _sessionView(
  _SessionRow session,
  List<StudyItemView> items, {
  required bool resumed,
}) {
  final resumeIndex = items.indexWhere(
    (item) => item.status == StudyItemStatus.pending,
  );
  return StudySessionView(
    id: session.id,
    mode: session.mode,
    sourceType: session.sourceType,
    startedAt: session.startedAt,
    completedAt: session.completedAt,
    plannedCount: session.plannedCount,
    completedCount: session.completedCount,
    correctCount: session.correctCount,
    wrongCount: session.wrongCount,
    skippedCount: session.skippedCount,
    durationMs: session.durationMs,
    items: items,
    resumeIndex: resumeIndex < 0 ? items.length : resumeIndex,
    resumed: resumed,
  );
}

/// 把 AI 推荐指定的题型附加到候选上。
///
/// [StudyCandidate] 没有覆盖该字段的 `copyWith`，只能整体重建。
StudyCandidate _withRecommendedType(
  StudyCandidate candidate,
  QuestionType? questionType,
) => StudyCandidate(
  id: candidate.id,
  term: candidate.term,
  normalizedTerm: candidate.normalizedTerm,
  sourceLanguage: candidate.sourceLanguage,
  targetLanguage: candidate.targetLanguage,
  contentType: candidate.contentType,
  masteryScore: candidate.masteryScore,
  continuousTaskType: candidate.continuousTaskType,
  recommendedQuestionType: questionType,
);

/// 解析 `recommended_items_json`。
///
/// 元素形如 `wordId` + `questionType` 的对象；未知题型记为 `null`，
/// 由调用方回退到常规题型选择，而不是丢弃整条推荐。
List<_RecommendedItem> _parseRecommendedItems(String raw) {
  final result = <_RecommendedItem>[];
  for (final item in decodeJsonList(raw)) {
    if (item is! Map) continue;
    final wordId = item['wordId'];
    if (wordId is! num) continue;
    final type = item['questionType'];
    result.add(
      _RecommendedItem(
        wordId: wordId.toInt(),
        questionType: type is String
            ? wireLookup(QuestionType.values, type)
            : null,
      ),
    );
  }
  return result;
}

/// 从 `confused_words_json` 解析易混词文本。
///
/// 元素既可能是带 `word` 字段的对象，也可能是纯字符串——旧版
/// `normalizeRelatedItems` 同时接受两种形态，历史数据里两种都有。
List<String> _parseConfusedTerms(String? raw) {
  final result = <String>[];
  for (final item in decodeJsonList(raw)) {
    final term = item is String
        ? item.trim()
        : (item is Map ? _cleanText(item['word']) : '');
    if (term.isNotEmpty) result.add(term);
  }
  return result;
}

/// 取字符串字段并 trim；非字符串返回空串。
String _cleanText(Object? value) => value is String ? value.trim() : '';
