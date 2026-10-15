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
class DailyReviewStat {
  /// 以各字段构造。
  const new({
    required this.dateKey,
    required this.reviewed,
    required this.correct,
    required this.durationMs,
    required this.newWords,
  });

  /// 日期键，形如 `2026-03-01`。
  final String dateKey;

  /// 当天作答次数。
  final int reviewed;

  /// 当天答对次数。
  final int correct;

  /// 当天有效学习时长（毫秒）。
  final int durationMs;

  /// 当天首次接触的词条数。
  final int newWords;

  /// 当天正确率（0–1）；无作答时为 0。
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

/// 统计查询入口。
class StatisticsDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 最近 [days] 天的逐日复习统计（按日期升序，缺失的日子补 0）。
  Future<List<DailyReviewStat>> dailyTrend({
    required int now,
    int days = defaultTrendDays,
  }) async {
    final from = startOfLocalDay(now - (days - 1) * dayMs);
    final rows = await _db
        .customSelect(
          '''
SELECT date(reviewed_at / 1000, 'unixepoch', 'localtime') AS day,
       count(*) AS reviewed,
       COALESCE(SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0) AS correct,
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
            const Variable<int>(maxActiveAnswerDurationMs),
            const Variable<int>(maxActiveAnswerDurationMs),
            Variable<int>(from),
          ],
        )
        .get();

    final byDay = <String, DailyReviewStat>{};
    for (final row in rows) {
      final key = row.read<String>('day');
      byDay[key] = DailyReviewStat(
        dateKey: key,
        reviewed: row.read<int>('reviewed'),
        correct: row.read<int>('correct'),
        durationMs: row.read<int>('duration_ms'),
        newWords: 0,
      );
    }

    final newWordsByDay = await _newWordsByDay(from);
    final result = <DailyReviewStat>[];
    for (var offset = days - 1; offset >= 0; offset -= 1) {
      final key = dateKey(now - offset * dayMs);
      final stat = byDay[key];
      result.add(
        DailyReviewStat(
          dateKey: key,
          reviewed: stat?.reviewed ?? 0,
          correct: stat?.correct ?? 0,
          durationMs: stat?.durationMs ?? 0,
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
