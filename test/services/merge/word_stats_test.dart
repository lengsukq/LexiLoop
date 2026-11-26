/// **Dart 统计 ≡ SQL 统计**。
///
/// 合并时需要「立刻」拿到一个词的统计来算熟练度（`accuracy` / `recentAgain` /
/// 平均耗时），而流水线里这三个值来自 `word_review_stats` 的 SQL 聚合。
/// 两套口径一旦漂移，合并出来的熟练分就会和流水线写出来的不一样。
///
/// 这里让同一批日志分别走「导入器的 SQL 重算」与「Dart 重放统计」，逐字段对拍。
///
/// **时间戳刻意避开 14/30 天的边界**：导入器的 SQL 用 `DateTime.now()` 做窗口
/// 起点，无法注入；把日志放在离边界很远的位置，几毫秒的抖动就影响不到结果。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/merge/learning_replay.dart';

void main() {
  late AppDatabase db;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.now().millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 一条 `review_logs` 行。
  Map<String, Object?> logRow({
    required int id,
    required int wordId,
    required int reviewedAt,
    required ReviewRating rating,
    required bool isCorrect,
    int? durationMs,
  }) => <String, Object?>{
    'id': id,
    'client_answer_id': 'answer-$id',
    'word_id': wordId,
    'reviewed_at': reviewedAt,
    'rating': rating.wire,
    'question_type': QuestionType.zhToEnSpelling.wire,
    'is_correct': isCorrect ? 1 : 0,
    'duration_ms': durationMs,
    'created_at': reviewedAt,
  };

  /// 写入一批日志并让导入器做 SQL 重算，返回该词的统计行。
  Future<Map<String, Object?>> sqlStatsOf(
    List<Map<String, Object?>> logs,
  ) async {
    await BackupImporter(db).replaceAll(<String, List<Map<String, Object?>>>{
      'words': <Map<String, Object?>>[
        <String, Object?>{
          'id': 1,
          'term': 'apple',
          'normalized_term': 'apple',
          'source_language': 'en',
          'target_language': 'zh',
          'entry_type': EntryType.word.wire,
          'content_type': LexicalContentType.word.wire,
          'initialization_status': InitializationStatus.ready.wire,
          'mastery_level': MasteryLevel.newWord.wire,
          'mastery_score': 0,
          'is_suspended': 0,
          'created_at': now,
          'updated_at': now,
        },
      ],
      'review_logs': logs,
    });

    final row = await db
        .customSelect(
          'SELECT total_reviews, correct_reviews, recent_again_30d, '
          'recent_again_14d, recent_wrong_14d, recent_hard_14d, '
          'total_duration_ms, duration_count, last_reviewed_at '
          'FROM word_review_stats WHERE word_id = 1',
        )
        .getSingle();
    return row.data;
  }

  group('wordStatTotalsFrom 与 SQL 逐字段一致', () {
    test('累计次数、正确率、窗口计数、平均耗时', () async {
      final logs = <Map<String, Object?>>[
        // 30 天窗口外的 AGAIN：只进 total，不进 recentAgain。
        logRow(
          id: 1,
          wordId: 1,
          reviewedAt: now - 40 * dayMs,
          rating: ReviewRating.again,
          isCorrect: false,
          durationMs: 4000,
        ),
        // 窗口内的 AGAIN。
        logRow(
          id: 2,
          wordId: 1,
          reviewedAt: now - 20 * dayMs,
          rating: ReviewRating.again,
          isCorrect: false,
          durationMs: 6000,
        ),
        // 窗口内的 HARD。
        logRow(
          id: 3,
          wordId: 1,
          reviewedAt: now - 10 * dayMs,
          rating: ReviewRating.hard,
          isCorrect: true,
          durationMs: 2000,
        ),
        // 没有耗时的样本：不进平均，但进 total。
        logRow(
          id: 4,
          wordId: 1,
          reviewedAt: now - dayMs,
          rating: ReviewRating.good,
          isCorrect: true,
        ),
      ];

      final sql = await sqlStatsOf(logs);
      final replayLogs = logs.map(replayLogFromRow).toList();

      // 导入器用的是 `DateTime.now()`，这里也用同一时刻附近的「现在」。
      final stats = wordStatTotalsFrom(
        replayLogs,
        now: DateTime.now().millisecondsSinceEpoch,
      );

      expect(stats.total, sql['total_reviews'], reason: 'total');
      expect(stats.correct, sql['correct_reviews'], reason: 'correct');
      expect(
        stats.recentAgain,
        sql['recent_again_30d'],
        reason: 'recent_again_30d',
      );
      expect(
        stats.averageDurationMs,
        (sql['total_duration_ms']! as int) / (sql['duration_count']! as int),
        reason: '平均耗时',
      );
    });

    test('没有日志时统计全为 0、平均耗时为 null', () async {
      final stats = wordStatTotalsFrom(const <ReplayLog>[], now: now);
      expect(stats.total, isZero);
      expect(stats.correct, isZero);
      expect(stats.recentAgain, isZero);
      expect(stats.averageDurationMs, isNull);
      expect(stats.accuracy, isZero);
    });

    test('只有 0 耗时的日志时平均耗时仍为 null（SQL 用 > 0 作条件）', () async {
      final logs = <Map<String, Object?>>[
        logRow(
          id: 1,
          wordId: 1,
          reviewedAt: now - dayMs,
          rating: ReviewRating.good,
          isCorrect: true,
          durationMs: 0,
        ),
        logRow(
          id: 2,
          wordId: 1,
          reviewedAt: now,
          rating: ReviewRating.good,
          isCorrect: true,
        ),
      ];

      final sql = await sqlStatsOf(logs);
      final stats = wordStatTotalsFrom(
        logs.map(replayLogFromRow),
        now: DateTime.now().millisecondsSinceEpoch,
      );

      expect(sql['duration_count'], 0);
      expect(stats.averageDurationMs, isNull);
      expect(stats.total, sql['total_reviews']);
    });

    test('14 天内的答错与 HARD 计数与 SQL 一致', () async {
      final logs = <Map<String, Object?>>[
        logRow(
          id: 1,
          wordId: 1,
          reviewedAt: now - 20 * dayMs,
          rating: ReviewRating.hard,
          isCorrect: true,
        ),
        logRow(
          id: 2,
          wordId: 1,
          reviewedAt: now - 3 * dayMs,
          rating: ReviewRating.hard,
          isCorrect: true,
        ),
        logRow(
          id: 3,
          wordId: 1,
          reviewedAt: now - 2 * dayMs,
          rating: ReviewRating.good,
          isCorrect: false,
        ),
      ];

      final sql = await sqlStatsOf(logs);
      final replayLogs = logs.map(replayLogFromRow).toList();
      final stats = wordStatTotalsFrom(replayLogs, now: now);

      // 窗口外的 HARD 不计入 14 天，窗口内的 1 次 HARD 与 1 次答错计入。
      expect(sql['recent_hard_14d'], 1);
      expect(sql['recent_wrong_14d'], 1);
      // Dart 侧只镜像了熟练度需要的 recentAgain / accuracy / 平均耗时，
      // 这里确认它们与 SQL 的对应字段仍然一致。
      expect(stats.recentAgain, sql['recent_again_30d']);
      // 两次 HARD 答对了、最后一次 GOOD 答错了 → 2/3。
      expect(stats.accuracy, 2 / 3);
    });
  });

  group('重放的统计与 SQL 喂给熟练度的三个字段一致', () {
    test('accuracy / recentAgain / averageDurationMs 同源', () async {
      final logs = <Map<String, Object?>>[
        logRow(
          id: 1,
          wordId: 1,
          reviewedAt: now - 5 * dayMs,
          rating: ReviewRating.again,
          isCorrect: false,
          durationMs: 8000,
        ),
        logRow(
          id: 2,
          wordId: 1,
          reviewedAt: now - 2 * dayMs,
          rating: ReviewRating.good,
          isCorrect: true,
          durationMs: 2000,
        ),
      ];
      final sql = await sqlStatsOf(logs);
      final stats = wordStatTotalsFrom(
        logs.map(replayLogFromRow),
        now: DateTime.now().millisecondsSinceEpoch,
      );

      expect(
        stats.accuracy,
        (sql['correct_reviews']! as int) / (sql['total_reviews']! as int),
      );
      expect(stats.recentAgain, sql['recent_again_30d']);
      expect(
        stats.averageDurationMs,
        (sql['total_duration_ms']! as int) / (sql['duration_count']! as int),
      );
    });
  });
}
