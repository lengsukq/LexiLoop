/// 关联词预览与加入服务的测试。
///
/// 钉住四件事：预览从父词条内容里取关系信息、与父词条相同被拒、
/// 重复加入不建重复词条、`needsInitialization` 的入队与优先级。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/word_content_models.dart';
import 'package:lexiloop/services/related_word_service.dart';

void main() {
  late AppDatabase db;
  late RelatedWordService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = RelatedWordService(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 插入父词条（含内容），返回 ID。
  Future<int> insertParent({
    String term = 'apple',
    String synonymsJson = '[]',
    String antonymsJson = '[]',
    String wordFamilyJson = '[]',
    String confusedWordsJson = '[]',
    String? sourceLanguageName = '英语',
    String? targetLanguageName = '中文',
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            sourceLanguageName: Value<String?>(sourceLanguageName),
            targetLanguageName: Value<String?>(targetLanguageName),
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            synonymsJson: Value<String>(synonymsJson),
            antonymsJson: Value<String>(antonymsJson),
            wordFamilyJson: Value<String>(wordFamilyJson),
            confusedWordsJson: Value<String>(confusedWordsJson),
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 插入一个普通词条，返回 ID。
  Future<int> insertWord({
    required String term,
    InitializationStatus status = InitializationStatus.pending,
    MasteryLevel mastery = MasteryLevel.newWord,
    int score = 0,
  }) => db
      .into(db.words)
      .insert(
        WordsCompanion.insert(
          term: term,
          normalizedTerm: term.toLowerCase(),
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          entryType: EntryType.word,
          initializationStatus: Value<InitializationStatus>(status),
          masteryLevel: Value<MasteryLevel>(mastery),
          masteryScore: Value<int>(score),
          createdAt: now,
          updatedAt: now,
        ),
      );

  Future<List<InitializationJobRow>> jobsOf(int wordId) => (db.select(
    db.initializationJobs,
  )..where((row) => row.wordId.equals(wordId))).get();

  group('preview', () {
    test('从父词条内容里取关系、译文、词性与区别', () async {
      final parentId = await insertParent(
        confusedWordsJson:
            '[{"word":"apply","relation":"CONFUSED_WITH",'
            '"translation":"申请","partOfSpeech":"v.",'
            '"difference":"apply 强调申请，apple 是苹果。","source":"ai"}]',
      );

      final preview = await service.preview(
        parentWordId: parentId,
        rawTerm: ' Apply ',
      );

      expect(preview.term, 'Apply');
      expect(preview.normalizedTerm, 'apply');
      expect(preview.relation, RelationType.confusedWith);
      expect(preview.translation, '申请');
      expect(preview.partOfSpeech, 'v.');
      expect(preview.difference, 'apply 强调申请，apple 是苹果。');
      expect(preview.source, 'ai');
      expect(preview.sourceLanguage, 'en');
      expect(preview.targetLanguage, 'zh');
      expect(preview.existing, isNull);
      expect(preview.canAdd, isTrue);
    });

    test('父词条内容里没有该词时退回近义词且字段为空', () async {
      final parentId = await insertParent();
      final preview = await service.preview(
        parentWordId: parentId,
        rawTerm: 'pear',
      );
      expect(preview.relation, RelationType.synonym);
      expect(preview.translation, isNull);
      expect(preview.difference, isNull);
    });

    test('已在词库时带回状态与掌握分', () async {
      final parentId = await insertParent();
      final existingId = await insertWord(
        term: 'pear',
        status: InitializationStatus.ready,
        mastery: MasteryLevel.familiar,
        score: 42,
      );

      final preview = await service.preview(
        parentWordId: parentId,
        rawTerm: 'pear',
      );

      expect(preview.existing!.id, existingId);
      expect(
        preview.existing!.initializationStatus,
        InitializationStatus.ready,
      );
      expect(preview.existing!.masteryLevel, MasteryLevel.familiar);
      expect(preview.existing!.masteryScore, 42);
      expect(preview.canAdd, isFalse, reason: '内容已就绪的词条不该再给加入按钮');
    });

    test('与父词条相同被拒', () async {
      final parentId = await insertParent();
      await expectLater(
        service.preview(parentWordId: parentId, rawTerm: 'Apple'),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.relatedWordSameAsParent,
          ),
        ),
      );
    });

    test('空文本与超长文本被拒', () async {
      final parentId = await insertParent();
      await expectLater(
        service.preview(parentWordId: parentId, rawTerm: '  '),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.termRequired,
          ),
        ),
      );
      await expectLater(
        service.preview(
          parentWordId: parentId,
          rawTerm: 'a' * (termMaxLength + 1),
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.termTooLong,
          ),
        ),
      );
    });

    test('父词条不存在时抛「词条不存在」', () async {
      await expectLater(
        service.preview(parentWordId: 999, rawTerm: 'pear'),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.wordNotFound,
          ),
        ),
      );
    });
  });

  group('add', () {
    test('新建词条并入队初始化任务', () async {
      final parentId = await insertParent();

      final result = await service.add(
        parentWordId: parentId,
        rawTerm: '  Pears ',
        relation: RelationType.synonym,
        now: now,
      );

      expect(result.created, isTrue);
      expect(result.queued, isTrue);
      expect(result.term, 'pears');
      expect(result.relation, RelationType.synonym);
      expect(result.initializationStatus, InitializationStatus.queued);

      final word = await (db.select(
        db.words,
      )..where((row) => row.id.equals(result.wordId))).getSingle();
      expect(word.normalizedTerm, 'pears');
      expect(word.initializationStatus, InitializationStatus.queued);
      expect(word.masteryLevel, MasteryLevel.newWord);
      expect(word.masteryScore, 0);
      expect(word.isSuspended, isFalse);
      expect(word.sourceCreatedAt, now);
      expect(word.sourceLanguageName, '英语');
      expect(word.targetLanguageName, '中文');

      final jobs = await jobsOf(result.wordId);
      expect(jobs, hasLength(1));
      expect(jobs.single.taskType, JobTaskType.initialize);
      expect(jobs.single.mode, InitializationMode.skipInitialized);
      expect(jobs.single.priority, jobPriorityRelatedWord);
      expect(jobs.single.status, InitializationStatus.queued);
      expect(result.jobId, jobs.single.id);
    });

    test('词条已存在时不建重复词条，并按「只补空缺」入队', () async {
      final parentId = await insertParent();
      final existingId = await insertWord(term: 'pear');

      final result = await service.add(
        parentWordId: parentId,
        rawTerm: 'pear',
        relation: RelationType.antonym,
        now: now,
      );

      expect(result.created, isFalse);
      expect(result.wordId, existingId);
      expect(result.queued, isTrue);
      expect(await db.select(db.words).get(), hasLength(2));
      final jobs = await jobsOf(existingId);
      expect(jobs.single.mode, InitializationMode.fillMissingFields);
    });

    test('内容已就绪时不入队', () async {
      final parentId = await insertParent();
      final existingId = await insertWord(
        term: 'pear',
        status: InitializationStatus.partial,
      );

      final result = await service.add(
        parentWordId: parentId,
        rawTerm: 'pear',
        relation: RelationType.synonym,
        now: now,
      );

      expect(result.created, isFalse);
      expect(result.queued, isFalse);
      expect(result.jobId, isNull);
      expect(
        result.initializationStatus,
        InitializationStatus.partial,
        reason: '已就绪的词条状态不该被改写成 QUEUED',
      );
      expect(await jobsOf(existingId), isEmpty);
      final word = await (db.select(
        db.words,
      )..where((row) => row.id.equals(existingId))).getSingle();
      expect(word.initializationStatus, InitializationStatus.partial);
    });

    test('已有活跃任务时升级它而不是再建一个', () async {
      final parentId = await insertParent();
      final existingId = await insertWord(term: 'pear');
      final jobId = await db
          .into(db.initializationJobs)
          .insert(
            InitializationJobsCompanion.insert(
              wordId: existingId,
              mode: InitializationMode.skipInitialized,
              priority: const Value<int>(jobPriorityManualBulk),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final result = await service.add(
        parentWordId: parentId,
        rawTerm: 'pear',
        relation: RelationType.synonym,
        now: now + 1000,
      );

      expect(result.jobId, jobId);
      final jobs = await jobsOf(existingId);
      expect(jobs, hasLength(1));
      expect(jobs.single.priority, jobPriorityManualBulk, reason: '优先级只升不降');
      expect(jobs.single.mode, InitializationMode.fillMissingFields);
      expect(jobs.single.updatedAt, now + 1000);
    });

    test('与父词条相同被拒且不建词条', () async {
      final parentId = await insertParent();
      await expectLater(
        service.add(
          parentWordId: parentId,
          rawTerm: 'APPLE',
          relation: RelationType.synonym,
          now: now,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.relatedWordSameAsParent,
          ),
        ),
      );
      expect(await db.select(db.words).get(), hasLength(1));
    });
  });
}
