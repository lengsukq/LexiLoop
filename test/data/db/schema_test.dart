/// 数据库 schema 测试。
///
/// 验证三件在旧版容易出错、且出错后很难发现的事：
/// 1. 15 张表全部建立；
/// 2. **部分唯一索引**真的生效（Drift 表达不了，靠手工 DDL）；
/// 3. **外键级联**真的生效（SQLite 默认关闭外键，忘了开就会留孤儿行）。
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一条最小可用的词条，返回其 id。
  Future<int> insertWord(String term) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  group('schema', () {
    test('17 张业务表全部建立', () async {
      const expected = <String>{
        'words',
        'word_contents',
        'word_review_stats',
        'word_packs',
        'word_pack_items',
        'study_sessions',
        'study_session_items',
        'review_cards',
        'review_logs',
        'wrong_word_states',
        'import_batches',
        'import_rows',
        'initialization_jobs',
        'provider_attempts',
        'daily_ai_suggestions',
        'game_high_scores',
        'settings',
      };

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final actual = rows.map((row) => row.read<String>('name')).toSet();

      expect(actual, containsAll(expected));
      expect(actual.length, expected.length, reason: '不应有预期之外的表');
    });

    test('部分唯一索引已建立', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name = 'initialization_jobs_active_word_task_unique'",
          )
          .get();

      expect(rows, hasLength(1));
    });

    test('外键约束已开启', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.data.values.first, 1);
    });
  });

  group('部分唯一索引语义', () {
    test('同一词条同一任务类型不能有两个活跃任务', () async {
      final wordId = await insertWord('alpha');
      final now = DateTime.now().millisecondsSinceEpoch;

      Future<int> enqueue(InitializationStatus status) {
        return db
            .into(db.initializationJobs)
            .insert(
              InitializationJobsCompanion.insert(
                wordId: wordId,
                mode: InitializationMode.fillMissingFields,
                status: Value<InitializationStatus>(status),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      await enqueue(InitializationStatus.queued);

      // 第二个 QUEUED 应被部分唯一索引拒绝。
      await expectLater(
        enqueue(InitializationStatus.queued),
        throwsA(isA<SqliteException>()),
      );

      // RUNNING 同样算活跃。
      await expectLater(
        enqueue(InitializationStatus.running),
        throwsA(isA<SqliteException>()),
      );
    });

    test('已完成的任务不占用唯一槽位', () async {
      final wordId = await insertWord('beta');
      final now = DateTime.now().millisecondsSinceEpoch;

      Future<int> enqueue(InitializationStatus status) {
        return db
            .into(db.initializationJobs)
            .insert(
              InitializationJobsCompanion.insert(
                wordId: wordId,
                mode: InitializationMode.fillMissingFields,
                status: Value<InitializationStatus>(status),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      // 终态可以重复存在，索引的 WHERE 把它们排除在外。
      await enqueue(InitializationStatus.ready);
      await enqueue(InitializationStatus.failed);
      await enqueue(InitializationStatus.queued);

      final count = await db.initializationJobs.count().getSingle();
      expect(count, 3);
    });
  });

  group('外键级联', () {
    test('删除词条会级联删除内容、卡片与任务', () async {
      final wordId = await insertWord('gamma');
      final now = DateTime.now().millisecondsSinceEpoch;

      await db
          .into(db.wordContents)
          .insert(
            WordContentsCompanion.insert(
              wordId: Value<int>(wordId),
              updatedAt: now,
            ),
          );
      await db
          .into(db.reviewCards)
          .insert(
            ReviewCardsCompanion.insert(
              wordId: Value<int>(wordId),
              dueAt: now,
              stability: 0,
              difficulty: 0,
              elapsedDays: 0,
              scheduledDays: 0,
              reps: 0,
              lapses: 0,
              fsrsState: 0,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.initializationJobs)
          .insert(
            InitializationJobsCompanion.insert(
              wordId: wordId,
              mode: InitializationMode.fillMissingFields,
              createdAt: now,
              updatedAt: now,
            ),
          );

      await (db.delete(db.words)..where((t) => t.id.equals(wordId))).go();

      expect(await db.wordContents.count().getSingle(), 0);
      expect(await db.reviewCards.count().getSingle(), 0);
      expect(await db.initializationJobs.count().getSingle(), 0);
    });
  });

  group('枚举映射', () {
    test('枚举按数据库大写标识往返', () async {
      final wordId = await insertWord('delta');

      await (db.update(db.words)..where((t) => t.id.equals(wordId))).write(
        const WordsCompanion(
          initializationStatus: Value(InitializationStatus.partial),
          masteryLevel: Value(MasteryLevel.proficient),
          contentType: Value(LexicalContentType.sentence),
          entryType: Value(EntryType.phrase),
        ),
      );

      // 直接读原始列，确认落库的是大写下划线而非枚举名。
      final raw = await db
          .customSelect(
            'SELECT initialization_status, mastery_level, content_type, '
            'entry_type FROM words WHERE id = ?',
            variables: <Variable<int>>[Variable<int>(wordId)],
          )
          .getSingle();

      expect(raw.read<String>('initialization_status'), 'PARTIAL');
      expect(raw.read<String>('mastery_level'), 'PROFICIENT');
      expect(raw.read<String>('content_type'), 'SENTENCE');
      expect(raw.read<String>('entry_type'), 'PHRASE');

      final word = await (db.select(
        db.words,
      )..where((t) => t.id.equals(wordId))).getSingle();
      expect(word.initializationStatus, InitializationStatus.partial);
      expect(word.masteryLevel, MasteryLevel.proficient);
      expect(word.contentType, LexicalContentType.sentence);
      expect(word.entryType, EntryType.phrase);
    });

    test('全部枚举的 wire 值唯一且非空', () {
      // wire 是备份导入的映射依据，重复或为空会导致静默写错数据。
      void assertUnique<T extends WireEnum>(List<T> values) {
        final wires = values.map((v) => v.wire).toList();
        expect(wires.toSet(), hasLength(wires.length), reason: '$T 存在重复 wire');
        for (final wire in wires) {
          expect(wire, isNotEmpty);
          expect(wire, wire.toUpperCase(), reason: '$T 的 wire 应为大写');
        }
      }

      assertUnique(InitializationStatus.values);
      assertUnique(InitializationMode.values);
      assertUnique(ImportMode.values);
      assertUnique(MasteryLevel.values);
      assertUnique(ReviewRating.values);
      assertUnique(StudyMode.values);
      assertUnique(QuestionType.values);
      assertUnique(EntryType.values);
      assertUnique(LexicalContentType.values);
      assertUnique(StudyTaskType.values);
      assertUnique(StudyItemStatus.values);
      assertUnique(JobTaskType.values);
      assertUnique(ProviderStrategy.values);
      assertUnique(ImportBatchStatus.values);
      assertUnique(ImportRowStatus.values);
      assertUnique(ProviderAttemptStatus.values);
      assertUnique(ContentSource.values);
      assertUnique(SuggestionGenerator.values);
      assertUnique(Accent.values);
    });

    test('MasteryLevel.newWord 映射到 NEW 而非 NEWWORD', () {
      // Dart 保留字 `new` 不能作枚举名，这是显式 wire 存在的主要原因。
      expect(MasteryLevel.newWord.wire, 'NEW');
      expect(StudyTaskType.newWord.wire, 'NEW');
      expect(ImportRowStatus.newWord.wire, 'NEW');
    });
  });

  group('常量一致性', () {
    test('学习会话支持全部 8 种模式', () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final mode in StudyMode.values) {
        await db
            .into(db.studySessions)
            .insert(
              StudySessionsCompanion.insert(
                sessionType: mode,
                startedAt: now,
                createdAt: now,
              ),
            );
      }

      // 旧版 PG 的 CHECK 只有 6 个值，SENTENCE_REVIEW 与 AI_RECOMMENDED
      // 会被拒绝——这里必须全部写入成功。
      expect(await db.studySessions.count().getSingle(), 8);
    });

    test('会话恢复有效期与跳过冷却符合常量', () {
      expect(sessionResumeTtlMs, dayMs);
      expect(skipCooldownMs, 12 * hourMs);
    });
  });
}
