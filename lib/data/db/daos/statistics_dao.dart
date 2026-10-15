/// 统计查询。
///
/// 只读聚合，全部走 SQL：把按天分组的活儿交给 SQLite，避免把几万条
/// `review_logs` 拉进内存再在 Dart 里分组。
///
/// **日界**：SQL 里用 `date(reviewed_at / 1000, 'unixepoch', 'localtime')`，
/// 与 `core/date_key.dart` 的「设备本地时区」语义一致。**不要**改成
/// `dayMs` 相减——那会把跨夏令时的日子算错。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

/// 一天的复习统计。
///
/// 字段口径逐条对应旧版 `modules/statistics/service.ts` 的 `getStatistics(days)`
/// 里那条 `daily` 记录。**注意 `skipped` 与 `reviewed` 来自两张不同的表**：
/// 前者是学习会话自身的 `skipped_count` 字段，后者是 `review_logs` 的条数——
/// 旧版就是这么算的，不要改成「逐条数 `study_session_items`」。
class DailyReviewStat {
  /// 以各字段构造。
  const new({
    required this.dateKey,
    required this.reviewed,
    required this.correct,
    required this.again,
    required this.skipped,
    required this.sessions,
    required this.durationMs,
    required this.newWords,
  });

  /// 日期键，形如 `2026-03-01`。
  final String dateKey;

  /// 当天作答次数。
  final int reviewed;

  /// 当天答对次数。
  final int correct;

  /// 当天评级为 `AGAIN`（完全忘记）的作答次数。
  final int again;

  /// 当天「已完成会话」的 `skipped_count` 之和。
  ///
  /// 只统计 `completed_count > 0` 的会话——旧版把一条题都没做的空会话整条跳过，
  /// 它的 `skipped_count` 也就不该出现。
  final int skipped;

  /// 当天 `completed_count > 0` 的学习会话条数。
  final int sessions;

  /// 当天有效学习时长（毫秒）。
  final int durationMs;

  /// 当天首次接触的词条数。
  final int newWords;

  /// 当天正确率（0–1）；无作答时为 0。
  ///
  /// **旧版的 `accuracy` 在无作答时是 `null`，这里压成了 0**：界面上要区分
  /// 「没作答」与「全错」时必须再判一次 [reviewed]（见
  /// `features/statistics/widgets/recent_daily_detail_card.dart` 的 `accuracyText`），
  /// 不能直接显示 0%。
  double get accuracy => reviewed == 0 ? 0 : correct / reviewed;
}

/// 全局统计概览。
class StatisticsOverview {
  /// 以各字段构造。
  const new({
    required this.totalWords,
    required this.byMastery,
    required this.totalReviews,
    required this.totalCorrect,
    required this.totalDurationMs,
    required this.streakDays,
    required this.activeDays,
  });

  /// 词条总数。
  final int totalWords;

  /// 各掌握等级的词条数。
  final Map<MasteryLevel, int> byMastery;

  /// 累计作答次数。
  final int totalReviews;

  /// 累计答对次数。
  final int totalCorrect;

  /// 累计有效学习时长（毫秒）。
  final int totalDurationMs;

  /// 当前连续学习天数。
  final int streakDays;

  /// 有复习记录的自然日总数。
  final int activeDays;

  /// 累计正确率（0–1）；无作答时为 0。
  double get accuracy => totalReviews == 0 ? 0 : totalCorrect / totalReviews;
}

/// 某个题型的正确率。
class QuestionTypeAccuracy {
  /// 以各字段构造。
  const new({
    required this.questionType,
    required this.attempts,
    required this.correct,
  });

  /// 题型。
  final QuestionType questionType;

  /// 作答次数。
  final int attempts;

  /// 答对次数。
  final int correct;

  /// 正确率（0–1）。
  double get accuracy => attempts == 0 ? 0 : correct / attempts;
}

/// 一天里「已完成会话」的聚合。
///
/// 单独一个类型而不是两个平行的 `Map<String, int>`：条数与跳过数来自同一条
/// SQL 的同一行，拆成两张表迟早会有一处忘了同步。
class _DailySessionStat {
  /// 以各字段构造。
  const new({required this.sessions, required this.skipped});

  /// 当天 `completed_count > 0` 的会话条数。
  final int sessions;

  /// 当天这些会话的 `skipped_count` 之和。
  final int skipped;
}

/// 统计查询入口。
class StatisticsDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 最近 [days] 天的逐日复习统计（按日期升序，缺失的日子补 0）。
  ///
  /// 口径与旧版 `modules/statistics/service.ts` 的 `getStatistics(days)` 一致：
  /// - 复习类字段来自 `review_logs`：`reviewed` / `correct` / `again` /
  ///   `durationMs`（单题时长按 [maxActiveAnswerDurationMs] 夹取）；
  /// - 会话类字段来自 `study_sessions`：`sessions` 只数 `completed_count > 0`
  ///   的会话，`skipped` 取这些会话的 `skipped_count` 之和；
  /// - `newWords` 是当天「首次接触」的词条数。
  Future<List<DailyReviewStat>> dailyTrend({
    required int now,
    int days = defaultTrendDays,
  }) async {
    final from = startOfLocalDay(now - (days - 1) * dayMs);
    final byDay = await _reviewStatsByDay(from);
    final sessionsByDay = await _sessionStatsByDay(from);
    final newWordsByDay = await _newWordsByDay(from);

    final result = <DailyReviewStat>[];
    for (var offset = days - 1; offset >= 0; offset -= 1) {
      final key = dateKey(now - offset * dayMs);
      result.add(
        _mergeDay(
          key: key,
          review: byDay[key],
          session: sessionsByDay[key],
          newWords: newWordsByDay[key] ?? 0,
        ),
      );
    }
    return result;
  }

  /// 全局概览。
  Future<StatisticsOverview> overview(int now) async {
    final wordRow = await _db
        .customSelect('SELECT count(*) AS c FROM words')
        .getSingle();
    final logRow = await _db
        .customSelect(
          '''
SELECT count(*) AS total,
       COALESCE(SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0) AS correct,
       COALESCE(SUM(
         CASE WHEN duration_ms IS NULL OR duration_ms <= 0 THEN 0
              WHEN duration_ms > ? THEN ?
              ELSE duration_ms END
       ), 0) AS duration_ms
FROM review_logs''',
          variables: <Variable<Object>>[
            const Variable<int>(maxActiveAnswerDurationMs),
            const Variable<int>(maxActiveAnswerDurationMs),
          ],
        )
        .getSingle();

    return StatisticsOverview(
      totalWords: wordRow.read<int>('c'),
      byMastery: await _masteryCounts(),
      totalReviews: logRow.read<int>('total'),
      totalCorrect: logRow.read<int>('correct'),
      totalDurationMs: logRow.read<int>('duration_ms'),
      streakDays: await streakDays(now),
      activeDays: await _activeDayCount(),
    );
  }

  /// 各题型的作答与正确次数。
  Future<List<QuestionTypeAccuracy>> accuracyByQuestionType() async {
    final rows = await _db.customSelect('''
SELECT question_type,
       count(*) AS attempts,
       COALESCE(SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0) AS correct
FROM review_logs
GROUP BY question_type
ORDER BY attempts DESC''').get();

    final result = <QuestionTypeAccuracy>[];
    for (final row in rows) {
      final type = wireLookup(
        QuestionType.values,
        row.read<String>('question_type'),
      );
      if (type == null) continue;
      result.add(
        QuestionTypeAccuracy(
          questionType: type,
          attempts: row.read<int>('attempts'),
          correct: row.read<int>('correct'),
        ),
      );
    }
    return result;
  }

  /// 当前连续学习天数。
  ///
  /// 从今天往前数：今天没记录时允许从昨天起算（当天还没开始学不算断签），
  /// 再往前必须逐日连续。
  Future<int> streakDays(int now) async {
    final days = await _activeDayOrdinals();
    if (days.isEmpty) return 0;

    final today = localDayOrdinal(now);
    final sorted = days.toList()..sort((a, b) => b.compareTo(a));
    var expected = sorted.first == today ? today : today - 1;
    if (sorted.first < expected) return 0;

    var streak = 0;
    for (final day in sorted) {
      if (day != expected) break;
      streak += 1;
      expected -= 1;
    }
    return streak;
  }

  /// 最近 [limit] 次作答的原始时间与正误（用于迷你趋势条）。
  Future<List<bool>> recentResults({required int limit}) async {
    final rows = await _db
        .customSelect(
          'SELECT is_correct FROM review_logs '
          'ORDER BY reviewed_at DESC LIMIT ?',
          variables: <Variable<Object>>[Variable<int>(limit)],
        )
        .get();
    return rows.map((row) => row.read<bool>('is_correct')).toList();
  }

  Future<Map<MasteryLevel, int>> _masteryCounts() async {
    final rows = await _db
        .customSelect(
          'SELECT mastery_level, count(*) AS c FROM words '
          'GROUP BY mastery_level',
        )
        .get();
    final result = <MasteryLevel, int>{
      for (final level in MasteryLevel.values) level: 0,
    };
    for (final row in rows) {
      final level = wireLookup(
        MasteryLevel.values,
        row.read<String>('mastery_level'),
      );
      if (level != null) result[level] = row.read<int>('c');
    }
    return result;
  }

  /// 每个日期键上的复习聚合。
  ///
  /// 会话相关字段（`skipped` / `sessions`）在这里恒为 0，由 [_mergeDay]
  /// 用 [_sessionStatsByDay] 的结果补齐。
  Future<Map<String, DailyReviewStat>> _reviewStatsByDay(int from) async {
    final rows = await _db
        .customSelect(
          '''
SELECT date(reviewed_at / 1000, 'unixepoch', 'localtime') AS day,
       count(*) AS reviewed,
       COALESCE(SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0) AS correct,
       COALESCE(SUM(CASE WHEN rating = ? THEN 1 ELSE 0 END), 0) AS again,
       COALESCE(SUM(
         CASE WHEN duration_ms IS NULL OR duration_ms <= 0 THEN 0
              WHEN duration_ms > ? THEN ?
              ELSE duration_ms END
       ), 0) AS duration_ms
FROM review_logs
WHERE reviewed_at >= ?
GROUP BY day
ORDER BY day ASC''',
          variables: <Variable<Object>>[
            Variable<String>(ReviewRating.again.wire),
            const Variable<int>(maxActiveAnswerDurationMs),
            const Variable<int>(maxActiveAnswerDurationMs),
            Variable<int>(from),
          ],
        )
        .get();

    return <String, DailyReviewStat>{
      for (final row in rows)
        row.read<String>('day'): DailyReviewStat(
          dateKey: row.read<String>('day'),
          reviewed: row.read<int>('reviewed'),
          correct: row.read<int>('correct'),
          again: row.read<int>('again'),
          skipped: 0,
          sessions: 0,
          durationMs: row.read<int>('duration_ms'),
          newWords: 0,
        ),
    };
  }

  /// 每个日期键上「已完成会话」的条数与跳过数。
  ///
  /// **一次查完窗口内的全部会话再在 Dart 里按日期归并**，而不是逐日查一次：
  /// 365 天档位下逐日查就是 365 条 SQL。
  ///
  /// `completed_count > 0` 这个条件不能省：旧版把「一条题都没做」的空会话
  /// 整条跳过（既不计数也不计跳过），否则用户在统计页会看到一堆空会话。
  Future<Map<String, _DailySessionStat>> _sessionStatsByDay(int from) async {
    final rows = await _db
        .customSelect(
          '''
SELECT date(started_at / 1000, 'unixepoch', 'localtime') AS day,
       count(*) AS sessions,
       COALESCE(SUM(skipped_count), 0) AS skipped
FROM study_sessions
WHERE started_at >= ? AND completed_count > 0
GROUP BY day
ORDER BY day ASC''',
          variables: <Variable<Object>>[Variable<int>(from)],
        )
        .get();
    return <String, _DailySessionStat>{
      for (final row in rows)
        row.read<String>('day'): _DailySessionStat(
          sessions: row.read<int>('sessions'),
          skipped: row.read<int>('skipped'),
        ),
    };
  }

  /// 把两次查询的结果按同一个日期键合成一条逐日统计。
  ///
  /// **某天只有会话、没有复习记录时也必须产出这一天**，否则「跳过 3 道题」
  /// 会凭空消失——旧版是按补齐后的日期键去查 Map，天然有这个性质。
  DailyReviewStat _mergeDay({
    required String key,
    required DailyReviewStat? review,
    required _DailySessionStat? session,
    required int newWords,
  }) => DailyReviewStat(
    dateKey: key,
    reviewed: review?.reviewed ?? 0,
    correct: review?.correct ?? 0,
    again: review?.again ?? 0,
    skipped: session?.skipped ?? 0,
    sessions: session?.sessions ?? 0,
    durationMs: review?.durationMs ?? 0,
    newWords: newWords,
  );

  /// 每个日期键上「首次出现」的词条数。
  Future<Map<String, int>> _newWordsByDay(int from) async {
    final rows = await _db
        .customSelect(
          '''
SELECT date(first_review / 1000, 'unixepoch', 'localtime') AS day,
       count(*) AS c
FROM (
  SELECT word_id, MIN(reviewed_at) AS first_review
  FROM review_logs
  GROUP BY word_id
)
WHERE first_review >= ?
GROUP BY day''',
          variables: <Variable<Object>>[Variable<int>(from)],
        )
        .get();
    return <String, int>{
      for (final row in rows) row.read<String>('day'): row.read<int>('c'),
    };
  }

  Future<int> _activeDayCount() async {
    final row = await _db.customSelect('''
SELECT count(DISTINCT date(reviewed_at / 1000, 'unixepoch', 'localtime')) AS c
FROM review_logs''').getSingle();
    return row.read<int>('c');
  }

  /// 有复习记录的自然日序数集合。
  Future<Set<int>> _activeDayOrdinals() async {
    final rows = await _db.customSelect('''
SELECT DISTINCT date(reviewed_at / 1000, 'unixepoch', 'localtime') AS day
FROM review_logs''').get();
    final result = <int>{};
    for (final row in rows) {
      final parsed = DateTime.tryParse(row.read<String>('day'));
      if (parsed == null) continue;
      result.add(
        DateTime.utc(
              parsed.year,
              parsed.month,
              parsed.day,
            ).millisecondsSinceEpoch ~/
            dayMs,
      );
    }
    return result;
  }
}
