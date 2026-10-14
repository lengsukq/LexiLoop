/// 备份导入测试。
///
/// 分两层：
/// 1. 合成备份（快、可进 CI）——验证格式校验、列交集过滤、统计重算；
/// 2. 真实备份（存在才跑）——用旧版导出的 27MB 文件做端到端验证。
///
/// 真实备份路径通过 `LEXILOOP_BACKUP_PATH` 环境变量指定，缺省时该用例跳过。
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/database.dart';

void main() {
  late AppDatabase db;
  late BackupImporter importer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    importer = BackupImporter(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 统计某张表的行数。
  Future<int> countOf(String table) async {
    final row = await db
        .customSelect('SELECT count(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  /// 构造一份最小合法备份。
  String buildBackup({Map<String, Object?> extra = const <String, Object?>{}}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return jsonEncode(<String, Object?>{
      'format': backupFormat,
      'version': 3,
      'database': 'postgresql',
      'appVersion': '1.0.0',
      'schemaVersion': '0002_new_question_types.sql',
      'migrations': <String>['0000_pg_initial.sql'],
      'exportedAt': DateTime.now().toIso8601String(),
      'words': <Map<String, Object?>>[
        <String, Object?>{
          'id': 1,
          'term': 'Cotton',
          'normalized_term': 'cotton',
          'source_language': 'en',
          'target_language': 'zh',
          'entry_type': 'WORD',
          'content_type': 'WORD',
          'initialization_status': 'READY',
          'mastery_level': 'FAMILIAR',
          'mastery_score': 55,
          'is_suspended': 0,
          'created_at': now,
          'updated_at': now,
        },
        <String, Object?>{
          'id': 2,
          'term': 'harvest',
          'normalized_term': 'harvest',
          'source_language': 'en',
          'target_language': 'zh',
          'entry_type': 'WORD',
          'content_type': 'WORD',
          'initialization_status': 'PARTIAL',
          'mastery_level': 'NEW',
          'mastery_score': 0,
          'is_suspended': 0,
          'created_at': now,
          'updated_at': now,
        },
      ],
      'word_contents': <Map<String, Object?>>[
        <String, Object?>{
          'word_id': 1,
          'definitions_json': '[{"text":"棉花"}]',
          'updated_at': now,
        },
      ],
      'review_cards': <Map<String, Object?>>[
        <String, Object?>{
          'word_id': 1,
          'due_at': now,
          'stability': 12.5,
          'difficulty': 4.2,
          'elapsed_days': 3,
          'scheduled_days': 12,
          'reps': 5,
          'lapses': 1,
          'fsrs_state': 2,
          'learning_steps': 0,
          'created_at': now,
          'updated_at': now,
        },
      ],
      'review_logs': <Map<String, Object?>>[
        <String, Object?>{
          'id': 1,
          'client_answer_id': 'answer-1',
          'word_id': 1,
          'reviewed_at': now,
          'rating': 'GOOD',
          'question_type': 'EN_TO_ZH',
          'is_correct': 1,
          'duration_ms': 4200,
          'created_at': now,
        },
        <String, Object?>{
          'id': 2,
          'client_answer_id': 'answer-2',
          'word_id': 1,
          'reviewed_at': now,
          'rating': 'AGAIN',
          'question_type': 'ZH_TO_EN_SPELLING',
          'is_correct': 0,
          'duration_ms': 9000,
          'created_at': now,
        },
      ],
      'wrong_word_states': <Map<String, Object?>>[
        <String, Object?>{
          'word_id': 1,
          'active': 1,
          'wrong_count': 2,
          'hard_count': 0,
          'consecutive_correct': 0,
          'updated_at': now,
        },
      ],
      'settings': <Map<String, Object?>>[
        <String, Object?>{
          'key': 'llmConfig',
          'value_json': '{"providers":[]}',
          'updated_at': now,
        },
      ],
      ...extra,
    });
  }

  group('格式校验', () {
    test('拒绝非 JSON', () async {
      await expectLater(
        importer.import('not json'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            AppErrorCode.backupInvalidJson,
          ),
        ),
      );
    });

    test('拒绝 format 不匹配', () async {
      await expectLater(
        importer.import('{"format":"something-else","version":3}'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            AppErrorCode.backupInvalidFormat,
          ),
        ),
      );
    });

    test('拒绝缺 version', () async {
      await expectLater(
        importer.import('{"format":"$backupFormat"}'),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('导入', () {
    test('导入后各表行数正确', () async {
      final result = await importer.import(buildBackup());

      expect(result.rowCounts['words'], 2);
      expect(result.rowCounts['word_contents'], 1);
      expect(result.rowCounts['review_cards'], 1);
      expect(result.rowCounts['review_logs'], 2);
      expect(result.rowCounts['wrong_word_states'], 1);
      expect(result.rowCounts['settings'], 1);

      expect(await countOf('words'), 2);
      expect(await countOf('review_logs'), 2);
    });

    test('枚举与布尔按原值落库', () async {
      await importer.import(buildBackup());

      final word = await (db.select(
        db.words,
      )..where((t) => t.id.equals(1))).getSingle();
      expect(word.initializationStatus.wire, 'READY');
      expect(word.masteryLevel.wire, 'FAMILIAR');
      expect(word.isSuspended, isFalse);

      final card = await db.select(db.reviewCards).getSingle();
      expect(card.stability, 12.5);
      expect(card.fsrsState, 2);
    });

    test('word_review_stats 由 review_logs 重算', () async {
      final result = await importer.import(buildBackup());

      expect(result.recomputedStats, 1);

      final stats = await db.select(db.wordReviewStats).getSingle();
      expect(stats.wordId, 1);
      expect(stats.totalReviews, 2);
      expect(stats.correctReviews, 1);
      expect(stats.recentAgain14d, 1, reason: '一条 AGAIN 在 14 天窗口内');
      expect(stats.recentWrong14d, 1, reason: '一条答错在 14 天窗口内');
      expect(stats.recentHard14d, 0);
      expect(stats.totalDurationMs, 13200);
      expect(stats.durationCount, 2);
    });

    test('重复导入是全量替换而非追加', () async {
      await importer.import(buildBackup());
      await importer.import(buildBackup());

      expect(await countOf('words'), 2, reason: '不应累积为 4');
    });

    test('忽略备份中目标表不存在的列', () async {
      final backup = buildBackup(
        extra: <String, Object?>{
          // 覆盖 words 后，原备份里引用 word_id=1 的子表会变成孤儿，
          // 因此一并清空——本用例只关心列交集过滤。
          'word_contents': <Map<String, Object?>>[],
          'review_cards': <Map<String, Object?>>[],
          'review_logs': <Map<String, Object?>>[],
          'wrong_word_states': <Map<String, Object?>>[],
          'words': <Map<String, Object?>>[
            <String, Object?>{
              'id': 9,
              'term': 'legacy',
              'normalized_term': 'legacy',
              'source_language': 'en',
              'target_language': 'zh',
              'entry_type': 'WORD',
              'content_type': 'WORD',
              'initialization_status': 'READY',
              'mastery_level': 'NEW',
              'mastery_score': 0,
              'is_suspended': 0,
              'created_at': 1,
              'updated_at': 1,
              // 未来版本新增、当前 schema 还没有的列
              'some_future_column': 'ignored',
            },
          ],
        },
      );

      await importer.import(backup);
      final word = await db.select(db.words).getSingle();
      expect(word.term, 'legacy');
    });

    test('失败时回滚，不破坏原有数据', () async {
      await importer.import(buildBackup());
      expect(await countOf('words'), 2);

      // 损坏的备份：session_type 是不存在的枚举值。
      // 导入走原始 SQL，绕过了 Drift 的 TypeConverter，
      // 因此必须由导入层校验并拒绝。
      final broken = buildBackup(
        extra: <String, Object?>{
          'study_sessions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 1,
              'session_type': 'NOT_A_VALID_MODE',
              'started_at': 1,
              'created_at': 1,
            },
          ],
        },
      );

      await expectLater(importer.import(broken), throwsA(anything));
      // 事务回滚后原数据仍在。
      expect(await countOf('words'), 2);
    });
  });

  group('真实备份', () {
    test('导入旧版导出的完整备份', () async {
      final path = Platform.environment['LEXILOOP_BACKUP_PATH'];
      if (path == null || !File(path).existsSync()) {
        markTestSkipped('未设置 LEXILOOP_BACKUP_PATH，跳过真实备份验证');
        return;
      }

      final raw = File(path).readAsStringSync();
      final result = await importer.import(raw);

      expect(result.rowCounts['words'], greaterThan(0));
      expect(result.rowCounts['word_contents'], result.rowCounts['words']);
      expect(result.recomputedStats, greaterThan(0));

      // 每条 review_log 都应聚合进 word_review_stats。
      final logs = await countOf('review_logs');
      final stats = await db
          .customSelect(
            'SELECT coalesce(sum(total_reviews), 0) AS c '
            'FROM word_review_stats',
          )
          .getSingle();
      expect(stats.read<int>('c'), logs);

      // 外键完整性：不应有孤儿内容行。
      final orphans = await db
          .customSelect(
            'SELECT count(*) AS c FROM word_contents wc '
            'LEFT JOIN words w ON w.id = wc.word_id WHERE w.id IS NULL',
          )
          .getSingle();
      expect(orphans.read<int>('c'), 0);
    });
  });
}
