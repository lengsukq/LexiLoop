/// CSV 导入服务的集成测试。
///
/// 覆盖预览落库、三种导入模式的差异、初始化任务入队、撤销的依赖检查
/// 与过期预览清理。这些是「导入之后数据对不对」的全部验收点。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/import/content_payload.dart';
import 'package:lexiloop/data/import/csv_parser.dart';
import 'package:lexiloop/data/import/import_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/csv_import_service.dart';
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

  Future<int> countOf(String table) async {
    final row = await db
        .customSelect('SELECT count(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  Future<ImportPreview> preview(String content, {int? at}) {
    return service.previewFromContent(
      content,
      filename: 'easydict.csv',
      sourceLanguage: 'en',
      targetLanguage: 'zh',
      now: at ?? now,
    );
  }

  /// 造一个已存在的词条（含内容行）。
  Future<int> insertWord({
    String term = 'apple',
    String definitionsJson = '[]',
    String examplesJson = '[]',
    int contentVersion = 1,
  }) async {
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
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: Value<String>(definitionsJson),
            examplesJson: Value<String>(examplesJson),
            contentVersion: Value<int>(contentVersion),
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> insertReviewLog(int wordId) async {
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            clientAnswerId: 'answer-$wordId',
            wordId: wordId,
            reviewedAt: now,
            rating: ReviewRating.good,
            questionType: QuestionType.enToZh,
            isCorrect: true,
            createdAt: now,
          ),
        );
  }

  Future<WordContentRow> contentOf(int wordId) async {
    final query = db.select(db.wordContents)
      ..where((table) => table.wordId.equals(wordId));
    return query.getSingle();
  }

  group('预览', () {
    test('落批次与行，并标出重复与已存在', () async {
      await insertWord(term: 'banana');
      const content = '单词,释义\napple,苹果\napple,苹果\nbanana,香蕉\n,空词条\n';

      final result = await preview(content);

      expect(result.batchId, greaterThan(0));
      expect(result.filename, 'easydict.csv');
      expect(result.totalRows, 4);
      expect(result.newRows, 1);
      expect(result.duplicateRows, 1);
      expect(result.existingRows, 1);
      expect(result.invalidRows, 1);
      expect(result.expiresAt, now + importPreviewTtlMs);

      final batch = await db.select(db.importBatches).getSingle();
      expect(batch.status, ImportBatchStatus.pending);
      expect(batch.totalRows, 4);
      expect(batch.invalidRows, 1);
      expect(batch.duplicateRows, 1);
      expect(await countOf('import_rows'), 4);
      // 预览阶段绝不能写词条。
      expect(await countOf('words'), 1);
    });

    test('空行不落库但计入 skippedCount', () async {
      final result = await preview('单词,释义\ncat,猫\n\n');
      expect(result.skippedCount, 1);
      expect(await countOf('import_rows'), 1);
    });
  });

  group('提交', () {
    test('新词条写入词条、内容与初始化任务', () async {
      const content =
          '单词,释义,音标,例句,易混词,标签\n'
          'apple,苹果,/ˈæpl/,"An apple a day.",apply,水果;食物\n';
      final result = await preview(content);

      final committed = await service.commit(
        batchId: result.batchId,
        mode: ImportMode.skipExisting,
        now: now,
      );

      expect(committed.created, 1);
      expect(committed.existing, 0);
      expect(committed.queuedInitializations, 1);

      final word = await db.select(db.words).getSingle();
      expect(word.term, 'apple');
      expect(word.normalizedTerm, 'apple');
      expect(word.contentType, LexicalContentType.word);
      expect(word.entryType, EntryType.word);
      expect(word.initializationStatus, InitializationStatus.queued);

      final content0 = await contentOf(word.id);
      expect(jsonDecode(content0.definitionsJson), <Object?>[
        <String, Object?>{
          'language': 'zh',
          'text': '苹果',
          'source': easydictCsvSource,
        },
      ]);
      expect(jsonDecode(content0.examplesJson), <Object?>[
        <String, Object?>{
          'sentence': 'An apple a day.',
          'translation': null,
          'source': easydictCsvSource,
        },
      ]);
      expect(jsonDecode(content0.confusedWordsJson), <Object?>[
        <String, Object?>{
          'word': 'apply',
          'relation': confusedWithRelation,
          'source': easydictCsvSource,
        },
      ]);
      expect(jsonDecode(content0.tagsJson), <Object?>['水果', '食物']);
      expect(content0.contentSource, ContentSource.dictionaryOnly);

      final job = await db.select(db.initializationJobs).getSingle();
      expect(job.wordId, word.id);
      expect(job.taskType, JobTaskType.initialize);
      expect(job.status, InitializationStatus.queued);
      expect(job.priority, jobPriorityManualBulk);
      expect(job.maxAttempts, importJobMaxAttempts);
      expect(job.availableAt, now);
      // 默认设置下 4 个数据源启用。
      expect(job.requestedProvidersJson, isNotNull);

      final batch = await db.select(db.importBatches).getSingle();
      expect(batch.status, ImportBatchStatus.committed);
      expect(batch.importMode, ImportMode.skipExisting);
      expect(batch.createdWords, 1);
      expect(batch.completedAt, now);

      final rows = await service.batchRows(
        result.batchId,
        limit: importRowPageSize,
        offset: 0,
      );
      expect(rows.single.status, ImportRowStatus.imported);
      expect(rows.single.term, 'apple');
      expect(rows.single.wordId, word.id);
    });

    test('句子写入 content_type=SENTENCE、entry_type=PHRASE', () async {
      final result = await preview('单词,释义\nI love you.,我爱你。\n');
      await service.commit(
        batchId: result.batchId,
        mode: ImportMode.skipExisting,
        now: now,
      );

      final word = await db.select(db.words).getSingle();
      expect(word.contentType, LexicalContentType.sentence);
      expect(word.entryType, EntryType.phrase);
    });

    test('非法行与重复行只留痕，不写词条', () async {
      const content = '单词,释义\n,空\ncat,猫\ncat,猫\n';
      final result = await preview(content);

      final committed = await service.commit(
        batchId: result.batchId,
        mode: ImportMode.skipExisting,
        now: now,
      );

      expect(committed.created, 1);
      expect(committed.invalid, 1);
      expect(committed.duplicate, 1);
      expect(await countOf('words'), 1);
      final rows = await service.batchRows(
        result.batchId,
        limit: importRowPageSize,
        offset: 0,
      );
      expect(rows.map((row) => row.status), <ImportRowStatus>[
        ImportRowStatus.invalid,
        ImportRowStatus.imported,
        ImportRowStatus.duplicate,
      ]);
      expect(rows.first.errorMessage, '词条文本不能为空。');
    });

    test('过期预览不能提交', () async {
      final result = await preview('单词,释义\ncat,猫\n');
      await expectLater(
        service.commit(
          batchId: result.batchId,
          mode: ImportMode.skipExisting,
          now: now + importPreviewTtlMs + 1,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.importPreviewExpired,
          ),
        ),
      );
    });

    test('同一批次不能提交两次', () async {
      final result = await preview('单词,释义\ncat,猫\n');
      await service.commit(
        batchId: result.batchId,
        mode: ImportMode.skipExisting,
        now: now,
      );
      await expectLater(
        service.commit(
          batchId: result.batchId,
          mode: ImportMode.skipExisting,
          now: now,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.importPreviewExpired,
          ),
        ),
      );
    });

    test('批次 ID 非法时抛 importBatchIdInvalid', () async {
      await expectLater(
        service.commit(batchId: 0, mode: ImportMode.skipExisting, now: now),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.importBatchIdInvalid,
          ),
        ),
      );
    });
  });

  group('三种导入模式', () {
    const content = '单词,释义,例句\napple,苹果（CSV）,A new example.\n';

    Future<(String definitions, String examples)> run(ImportMode mode) async {
      final result = await preview(content);
      final committed = await service.commit(
        batchId: result.batchId,
        mode: mode,
        now: now,
      );
      expect(committed.existing, 1);
      final row = await db.select(db.words).getSingle();
      final content0 = await contentOf(row.id);
      return (content0.definitionsJson, content0.examplesJson);
    }

    test('SKIP_EXISTING 完全不覆盖', () async {
      await insertWord(
        definitionsJson: '[{"language":"zh","text":"苹果","source":"ai"}]',
      );
      final (definitions, examples) = await run(ImportMode.skipExisting);

      expect(definitions, contains('苹果'));
      expect(definitions, isNot(contains('苹果（CSV）')));
      expect(examples, '[]');
    });

    test('FILL_MISSING 只补空字段', () async {
      await insertWord(
        definitionsJson: '[{"language":"zh","text":"苹果","source":"ai"}]',
      );
      final (definitions, examples) = await run(ImportMode.fillMissing);

      // 已有中文释义 → 不覆盖。
      expect(definitions, contains('"source":"ai"'));
      expect(definitions, isNot(contains('苹果（CSV）')));
      // 例句为空 → 补上。
      expect(examples, contains('A new example.'));
    });

    test('FILL_MISSING 会补上缺失的目标语言释义', () async {
      await insertWord(
        definitionsJson: '[{"language":"en","text":"a fruit","source":"ai"}]',
      );
      final (definitions, _) = await run(ImportMode.fillMissing);
      expect(definitions, contains('苹果（CSV）'));
    });

    test('FORCE_DICTIONARY_REFRESH 覆盖词典内容', () async {
      await insertWord(
        definitionsJson: '[{"language":"zh","text":"苹果","source":"ai"}]',
      );
      final (definitions, examples) = await run(
        ImportMode.forceDictionaryRefresh,
      );

      expect(definitions, contains('苹果（CSV）'));
      expect(examples, contains('A new example.'));
      final row = await db.select(db.words).getSingle();
      final content0 = await contentOf(row.id);
      // 覆盖时要自增内容版本，便于并发冲突提示。
      expect(content0.contentVersion, 2);
    });

    test('已有词条不会被重新入队初始化任务', () async {
      await insertWord();
      final result = await preview(content);
      await service.commit(
        batchId: result.batchId,
        mode: ImportMode.fillMissing,
        now: now,
      );
      expect(await countOf('initialization_jobs'), 0);
    });
  });

  group('撤销', () {
    test('无依赖时删干净并标记 ROLLED_BACK', () async {
      final result = await preview('单词,释义\ncat,猫\ndog,狗\n');
      await service.commit(
        batchId: result.batchId,
        mode: ImportMode.skipExisting,
        now: now,
      );
      expect(await countOf('words'), 2);

      await service.rollback(batchId: result.batchId, now: now + 1);

      expect(await countOf('words'), 0);
      expect(await countOf('word_contents'), 0);
      expect(await countOf('initialization_jobs'), 0);
      final batch = await db.select(db.importBatches).getSingle();
      expect(batch.status, ImportBatchStatus.rolledBack);
      expect(batch.rolledBackAt, now + 1);
      // 行留痕保留，但不再指向已删除的词条。
      final rows = await service.batchRows(
        result.batchId,
        limit: importRowPageSize,
        offset: 0,
      );
      expect(rows, hasLength(2));
      expect(rows.every((row) => row.wordId == null), isTrue);
    });

    test('词条有复习日志时抛 importBatchNotRollbackable 并带出词条', () async {
      final result = await preview('单词,释义\ncat,猫\ndog,狗\n');
      await service.commit(
        batchId: result.batchId,
        mode: ImportMode.skipExisting,
        now: now,
      );
      final words = await db.select(db.words).get();
      await insertReviewLog(words.firstWhere((word) => word.term == 'cat').id);

      await expectLater(
        service.rollback(batchId: result.batchId, now: now + 1),
        throwsA(
          isA<AppError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.importBatchNotRollbackable,
              )
              .having((error) => error.details, 'details', <String>['cat']),
        ),
      );
      // 拒绝之后数据必须原样保留。
      expect(await countOf('words'), 2);
    });

    test('词条有错词记录时同样拒绝', () async {
      final result = await preview('单词,释义\ncat,猫\n');
      await service.commit(
        batchId: result.batchId,
        mode: ImportMode.skipExisting,
        now: now,
      );
      final word = await db.select(db.words).getSingle();
      await db
          .into(db.wrongWordStates)
          .insert(
            WrongWordStatesCompanion.insert(
              wordId: Value<int>(word.id),
              active: const Value<bool>(true),
              wrongCount: const Value<int>(2),
              updatedAt: now,
            ),
          );

      await expectLater(
        service.rollback(batchId: result.batchId, now: now + 1),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.importBatchNotRollbackable,
          ),
        ),
      );
    });

    test('改动过已有词条的批次不可无损撤销', () async {
      await insertWord();
      final result = await preview('单词,释义\napple,苹果\n');
      await service.commit(
        batchId: result.batchId,
        mode: ImportMode.fillMissing,
        now: now,
      );

      await expectLater(
        service.rollback(batchId: result.batchId, now: now + 1),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.importBatchNotRollbackable,
          ),
        ),
      );
    });

    test('未提交的批次不能撤销', () async {
      final result = await preview('单词,释义\ncat,猫\n');
      await expectLater(
        service.rollback(batchId: result.batchId, now: now + 1),
        throwsA(isA<AppError>()),
      );
    });

    test('批次不存在时抛 notFound', () async {
      await expectLater(
        service.rollback(batchId: 999, now: now),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.notFound,
          ),
        ),
      );
    });
  });

  group('批次查询与清理', () {
    test('recentBatches 按创建时间倒序', () async {
      await preview('单词,释义\ncat,猫\n');
      await preview('单词,释义\ndog,狗\n', at: now + 1000);

      final batches = await service.recentBatches();

      expect(batches, hasLength(2));
      expect(batches.first.createdAt, now + 1000);
    });

    test('batchRows 支持分页', () async {
      final result = await preview('单词,释义\na,1\nb,2\nc,3\n');
      final page = await service.batchRows(result.batchId, limit: 2, offset: 1);
      expect(page.map((row) => row.term), <String>['b', 'c']);
    });

    test('purgeExpiredPreviews 只清过期的未提交批次', () async {
      final stale = await preview('单词,释义\ncat,猫\n');
      final fresh = await preview(
        '单词,释义\ndog,狗\n',
        at: now + importBatchExpiryMs + 1000,
      );
      final committed = await preview('单词,释义\nbird,鸟\n', at: now);
      await service.commit(
        batchId: committed.batchId,
        mode: ImportMode.skipExisting,
        now: now,
      );

      final purged = await service.purgeExpiredPreviews(
        now + importBatchExpiryMs + 2000,
      );

      expect(purged, 1);
      final remaining = await db.select(db.importBatches).get();
      final ids = remaining.map((batch) => batch.id).toSet();
      expect(ids, contains(fresh.batchId));
      expect(ids, contains(committed.batchId));
      expect(ids, isNot(contains(stale.batchId)));
      // 级联删除：过期批次的明细行一并清掉。
      expect(await countOf('import_rows'), 2);
    });
  });
}
