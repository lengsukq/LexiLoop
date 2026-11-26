/// CSV「重置已有词条的学习进度」的验收测试。
///
/// 与 `csv_import_service_test.dart` 分开：本组要预置复习卡、错词状态、
/// 会话题目与物化统计一整套「已有进度」，塞进那个文件会让它同时承担两组
/// 关注点。
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/csv_import_service.dart';
import 'package:lexiloop/services/learning_progress_reset.dart';
import 'package:lexiloop/services/settings_service.dart';

void main() {
  late AppDatabase db;
  late CsvImportService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = CsvImportService(db, SettingsService(SettingsDao(db)));
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> countOf(String table, {int? wordId}) async {
    final where = wordId == null ? '' : ' WHERE word_id = $wordId';
    final row = await db
        .customSelect('SELECT count(*) AS c FROM $table$where')
        .getSingle();
    return row.read<int>('c');
  }

  /// 造一个学习历史齐全的已有词条，并返回它的 ID。
  Future<int> seedWordWithHistory(String term) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: const Value(InitializationStatus.ready),
            masteryLevel: const Value(MasteryLevel.mastered),
            masteryScore: const Value(90),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: const Value('[]'),
            updatedAt: now,
          ),
        );
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            clientAnswerId: 'answer-$term',
            wordId: id,
            reviewedAt: now,
            rating: ReviewRating.again,
            questionType: QuestionType.enToZh,
            isCorrect: false,
            createdAt: now,
          ),
        );
    await db
        .into(db.reviewCards)
        .insert(
          ReviewCardsCompanion.insert(
            wordId: Value<int>(id),
            dueAt: now,
            stability: 3,
            difficulty: 5,
            elapsedDays: 1,
            scheduledDays: 2,
            reps: 3,
            lapses: 1,
            fsrsState: 2,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wrongWordStates)
        .insert(
          WrongWordStatesCompanion.insert(
            wordId: Value<int>(id),
            active: const Value(true),
            wrongCount: const Value(2),
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordReviewStats)
        .insert(
          WordReviewStatsCompanion.insert(
            wordId: Value<int>(id),
            totalReviews: const Value(1),
            correctReviews: const Value(0),
            updatedAt: Value(now),
          ),
        );
    await _seedSessionItem(
      db,
      now,
      wordId: id,
      status: StudyItemStatus.pending,
    );
    await _seedSessionItem(
      db,
      now,
      wordId: id,
      status: StudyItemStatus.answered,
      position: 1,
    );
    return id;
  }

  /// 预览并提交一份 CSV。
  Future<ImportCommitResult> commitCsv(
    String content, {
    required ImportMode mode,
    required bool resetLearningProgress,
  }) async {
    final preview = await service.previewFromContent(
      content,
      filename: 'easydict.csv',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
      now: now,
    );
    return await service.commit(
      batchId: preview.batchId,
      mode: mode,
      resetLearningProgress: resetLearningProgress,
      now: now,
    );
  }

  group('重置已有词条的学习进度', () {
    test('清空复习日志、复习卡、错词状态与物化统计', () async {
      final wordId = await seedWordWithHistory('apple');

      await commitCsv(
        '单词,释义,例句\napple,苹果（CSV）,A red fruit.\n',
        mode: ImportMode.forceDictionaryRefresh,
        resetLearningProgress: true,
      );

      expect(await countOf('review_logs', wordId: wordId), 0);
      expect(await countOf('review_cards', wordId: wordId), 0);
      expect(await countOf('wrong_word_states', wordId: wordId), 0);
      expect(await countOf('word_review_stats', wordId: wordId), 0);
    });

    test('撤下未作答的会话题目，并记下 PROGRESS_RESET', () async {
      final wordId = await seedWordWithHistory('apple');

      await commitCsv(
        '单词,释义,例句\napple,苹果（CSV）,A red fruit.\n',
        mode: ImportMode.forceDictionaryRefresh,
        resetLearningProgress: true,
      );

      final items = await db.select(db.studySessionItems).get();
      final pending = items.singleWhere((i) => i.position == 0);
      final answered = items.singleWhere((i) => i.position == 1);
      expect(pending.wordId, wordId);
      expect(pending.status, StudyItemStatus.skipped);
      expect(pending.skipReason, progressResetSkipReason);
      expect(pending.answeredAt, now);
      expect(
        answered.status,
        StudyItemStatus.answered,
        reason: '已经作答的题属于学习历史，不该被改写',
      );
    });

    test('掌握度归零', () async {
      final wordId = await seedWordWithHistory('apple');

      await commitCsv(
        '单词,释义,例句\napple,苹果（CSV）,A red fruit.\n',
        mode: ImportMode.forceDictionaryRefresh,
        resetLearningProgress: true,
      );

      final word = await (db.select(
        db.words,
      )..where((t) => t.id.equals(wordId))).getSingle();
      expect(word.masteryLevel, MasteryLevel.newWord);
      expect(word.masteryScore, 0);
    });

    test('同批次里新增的词条不受影响', () async {
      final oldId = await seedWordWithHistory('apple');

      final result = await commitCsv(
        '单词,释义,例句\napple,苹果（CSV）,A red fruit.\n'
        'cat,猫（CSV）,A small pet.\n',
        mode: ImportMode.forceDictionaryRefresh,
        resetLearningProgress: true,
      );

      expect(result.existing, 1);
      expect(result.created, 1);
      expect(await countOf('review_logs', wordId: oldId), 0);

      final cat = await (db.select(
        db.words,
      )..where((t) => t.normalizedTerm.equals('cat'))).getSingle();
      for (final table in <String>[
        'review_logs',
        'review_cards',
        'wrong_word_states',
        'word_review_stats',
        'study_session_items',
      ]) {
        expect(
          await countOf(table, wordId: cat.id),
          0,
          reason: '新词条不该被重置逻辑碰到：$table',
        );
      }
    });

    test('默认关闭时不删任何学习记录', () async {
      final wordId = await seedWordWithHistory('apple');

      await commitCsv(
        '单词,释义,例句\napple,苹果（CSV）,A red fruit.\n',
        mode: ImportMode.forceDictionaryRefresh,
        resetLearningProgress: false,
      );

      expect(await countOf('review_logs', wordId: wordId), 1);
      expect(await countOf('review_cards', wordId: wordId), 1);
      expect(await countOf('wrong_word_states', wordId: wordId), 1);
      expect(await countOf('word_review_stats', wordId: wordId), 1);
      final items = await db.select(db.studySessionItems).get();
      expect(
        items.singleWhere((i) => i.position == 0).status,
        StudyItemStatus.pending,
      );
      final word = await (db.select(
        db.words,
      )..where((t) => t.id.equals(wordId))).getSingle();
      expect(word.masteryLevel, MasteryLevel.mastered);
    });

    test('SKIP_EXISTING 下即使勾选也不动已有词条', () async {
      final wordId = await seedWordWithHistory('apple');

      await commitCsv(
        '单词,释义,例句\napple,苹果（CSV）,A red fruit.\n',
        mode: ImportMode.skipExisting,
        resetLearningProgress: true,
      );

      expect(await countOf('review_logs', wordId: wordId), 1);
      expect(await countOf('review_cards', wordId: wordId), 1);
    });

    test('批次记录写入 reset_learning_progress，供撤销检查读', () async {
      await commitCsv(
        '单词,释义,例句\ncat,猫（CSV）,A small pet.\n',
        mode: ImportMode.skipExisting,
        resetLearningProgress: true,
      );

      final batch = await db.select(db.importBatches).getSingle();
      expect(batch.resetLearningProgress, isTrue);
      expect(batch.status, ImportBatchStatus.committed);
    });

    test('重置与词条写入同属一个事务：被拒绝时一条都不改', () async {
      final wordId = await seedWordWithHistory('apple');
      final preview = await service.previewFromContent(
        '单词,释义,例句\napple,苹果（CSV）,A red fruit.\n',
        filename: 'easydict.csv',
        sourceLanguage: 'en',
        targetLanguage: 'zh',
        now: now,
      );

      // 过期批次在进入事务之前就被拒绝，学习记录必须原封不动——
      // 否则「重置」就成了一句先删后报错的话。
      await expectLater(
        service.commit(
          batchId: preview.batchId,
          mode: ImportMode.forceDictionaryRefresh,
          resetLearningProgress: true,
          now: now + importPreviewTtlMs + 1,
        ),
        throwsA(isA<AppError>()),
      );
      expect(await countOf('review_logs', wordId: wordId), 1);
      expect(await countOf('review_cards', wordId: wordId), 1);
      expect(
        (await db.select(db.importBatches).getSingle()).status,
        ImportBatchStatus.pending,
      );

      // 同一个批次仍然可用：重置与内容写入一次提交。
      await service.commit(
        batchId: preview.batchId,
        mode: ImportMode.forceDictionaryRefresh,
        resetLearningProgress: true,
        now: now,
      );
      expect(await countOf('review_logs', wordId: wordId), 0);
      expect(
        (await db.select(db.importBatches).getSingle()).resetLearningProgress,
        isTrue,
      );
    });
  });
}

/// 造一条会话题目。
Future<void> _seedSessionItem(
  AppDatabase db,
  int now, {
  required int wordId,
  required StudyItemStatus status,
  double position = 0,
}) async {
  final session = await db.select(db.studySessions).getSingleOrNull();
  final sessionId =
      session?.id ??
      await db
          .into(db.studySessions)
          .insert(
            StudySessionsCompanion.insert(
              sessionType: StudyMode.daily,
              startedAt: now,
              createdAt: now,
            ),
          );
  await db
      .into(db.studySessionItems)
      .insert(
        StudySessionItemsCompanion.insert(
          studySessionId: sessionId,
          position: position,
          wordId: wordId,
          taskType: StudyTaskType.review,
          questionType: QuestionType.enToZh,
          status: Value(status),
          createdAt: now,
        ),
      );
}
