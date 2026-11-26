/// 词条写入服务的单元测试。
///
/// 「创建词条」是用户唯一直接操作词库的入口，最容易出的问题是
/// **重复词条被静默合并**——用户以为新建了一个词，实际改的是旧的。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/word_edit_service.dart';

void main() {
  late AppDatabase db;
  late WordEditService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = WordEditService(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  WordDraft draft({
    String term = 'apple',
    LexicalContentType contentType = LexicalContentType.word,
    String sourceLanguage = 'en',
    String targetLanguage = 'zh',
    List<String> definitions = const <String>['苹果'],
    String? phonetic,
    List<WordExampleDraft> examples = const <WordExampleDraft>[],
    List<String> tags = const <String>[],
    String? note,
  }) => WordDraft(
    term: term,
    contentType: contentType,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    definitions: definitions,
    phonetic: phonetic,
    examples: examples,
    tags: tags,
    note: note,
  );

  Future<WordRow> wordOf(int id) =>
      (db.select(db.words)..where((row) => row.id.equals(id))).getSingle();

  Future<WordContentRow> contentOf(int id) => (db.select(
    db.wordContents,
  )..where((row) => row.wordId.equals(id))).getSingle();

  group('create', () {
    test('写入词条与内容', () async {
      final id = await service.create(draft: draft(), now: now);

      final word = await wordOf(id);
      expect(word.term, 'apple');
      expect(word.normalizedTerm, 'apple');
      expect(word.contentType, LexicalContentType.word);
      expect(word.entryType, EntryType.word);
      expect(word.initializationStatus, InitializationStatus.ready);

      final content = await contentOf(id);
      expect(content.definitionsJson, contains('苹果'));
      expect(content.contentSource, ContentSource.dictionaryOnly);
      expect(content.contentVersion, contentVersionWithContent);
    });

    test('词条文本按语言规则归一化并小写', () async {
      final id = await service.create(
        draft: draft(term: '  Apple  '),
        now: now,
      );
      final word = await wordOf(id);
      expect(word.normalizedTerm, 'apple');
      expect(word.term, 'apple', reason: '单词按小写语言族取小写');
    });

    test('短语与句子保留原始大小写', () async {
      final phraseId = await service.create(
        draft: draft(
          term: 'New York',
          contentType: LexicalContentType.phrase,
          definitions: const <String>['纽约'],
        ),
        now: now,
      );
      expect((await wordOf(phraseId)).term, 'New York');
      expect((await wordOf(phraseId)).entryType, EntryType.phrase);

      final sentenceId = await service.create(
        draft: draft(
          term: 'I am fine.',
          contentType: LexicalContentType.sentence,
          definitions: const <String>['我很好。'],
        ),
        now: now,
      );
      expect((await wordOf(sentenceId)).term, 'I am fine.');
      expect(
        (await wordOf(sentenceId)).entryType,
        EntryType.phrase,
        reason: 'entry_type 是旧的二值字段，句子归 PHRASE',
      );
      expect(
        (await wordOf(sentenceId)).contentType,
        LexicalContentType.sentence,
      );
    });

    test('没有释义时状态为 PENDING 且内容版本为 0', () async {
      final id = await service.create(
        draft: draft(definitions: const <String>['  ']),
        now: now,
      );
      final word = await wordOf(id);
      expect(word.initializationStatus, InitializationStatus.pending);
      expect((await contentOf(id)).contentVersion, contentVersionEmpty);
    });

    test('重复词条抛「已存在」，不静默合并', () async {
      await service.create(draft: draft(), now: now);
      await expectLater(
        service.create(draft: draft(), now: now),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.termAlreadyExists,
          ),
        ),
      );
      expect(await db.select(db.words).get(), hasLength(1));
    });

    test('大小写不同视为同一词条', () async {
      await service.create(draft: draft(), now: now);
      await expectLater(
        service.create(
          draft: draft(term: 'APPLE'),
          now: now,
        ),
        throwsA(isA<AppError>()),
      );
    });

    test('不同目标语言可以共存', () async {
      final en = await service.create(draft: draft(), now: now);
      final ja = await service.create(
        draft: draft(targetLanguage: 'ja', definitions: const <String>['りんご']),
        now: now,
      );
      expect(en, isNot(ja));
      expect(await db.select(db.words).get(), hasLength(2));
    });

    test('空词条被拒绝', () async {
      await expectLater(
        service.create(
          draft: draft(term: '   '),
          now: now,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.termRequired,
          ),
        ),
      );
    });

    test('超长词条被拒绝', () async {
      await expectLater(
        service.create(
          draft: draft(term: 'a' * (termMaxLength + 1)),
          now: now,
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

    test('音标、例句、标签、笔记都被写入', () async {
      final id = await service.create(
        draft: draft(
          phonetic: '/ˈæpl/',
          examples: const <WordExampleDraft>[
            WordExampleDraft(
              sentence: 'I ate an apple.',
              translation: '我吃了一个苹果。',
            ),
            WordExampleDraft(sentence: 'An apple a day.'),
          ],
          tags: const <String>['水果', '基础词'],
          note: '注意复数',
        ),
        now: now,
      );

      final content = await contentOf(id);
      expect(content.pronunciationsJson, contains('/ˈæpl/'));
      expect(content.examplesJson, contains('I ate an apple.'));
      expect(content.examplesJson, contains('我吃了一个苹果。'));
      expect(content.tagsJson, contains('水果'));
      expect((await wordOf(id)).userNote, '注意复数');
    });

    test('空音标与空标签不写入噪声数据', () async {
      final id = await service.create(
        draft: draft(phonetic: '  ', tags: const <String>['', '  ']),
        now: now,
      );
      final content = await contentOf(id);
      expect(content.pronunciationsJson, '[]');
      expect(content.tagsJson, '[]');
    });

    test('空笔记存为 null', () async {
      final id = await service.create(
        draft: draft(note: '   '),
        now: now,
      );
      expect((await wordOf(id)).userNote, isNull);
    });
  });

  group('findByTerm', () {
    test('未创建时返回 null', () async {
      expect(
        await service.findByTerm(
          term: 'apple',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
        isNull,
      );
    });

    test('创建后能查到', () async {
      final id = await service.create(draft: draft(), now: now);
      expect(
        await service.findByTerm(
          term: 'Apple',
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
        id,
      );
    });
  });

  group('updateContent', () {
    test('覆盖内容并同步状态与版本', () async {
      final id = await service.create(
        draft: draft(definitions: const <String>[]),
        now: now,
      );
      expect(
        (await wordOf(id)).initializationStatus,
        InitializationStatus.pending,
      );

      await service.updateContent(
        wordId: id,
        draft: draft(
          definitions: const <String>['苹果', '苹果树'],
          phonetic: '/ˈæpl/',
        ),
        now: now + 1000,
      );

      final word = await wordOf(id);
      expect(word.initializationStatus, InitializationStatus.ready);
      expect(word.updatedAt, now + 1000);
      final content = await contentOf(id);
      expect(content.definitionsJson, contains('苹果树'));
      expect(content.contentVersion, contentVersionWithContent);
    });

    test('不会重复建内容行', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.updateContent(wordId: id, draft: draft(), now: now);
      expect(await db.select(db.wordContents).get(), hasLength(1));
    });
  });

  group('setSuspended 与 saveNote', () {
    test('暂停状态可切换', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.setSuspended(wordId: id, suspended: true, now: now);
      expect((await wordOf(id)).isSuspended, isTrue);
      await service.setSuspended(wordId: id, suspended: false, now: now);
      expect((await wordOf(id)).isSuspended, isFalse);
    });

    test('笔记可写入与清空', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.saveNote(wordId: id, note: '记得复习', now: now);
      expect((await wordOf(id)).userNote, '记得复习');
      await service.saveNote(wordId: id, note: null, now: now);
      expect((await wordOf(id)).userNote, isNull);
    });
  });

  group('delete', () {
    test('级联删除内容', () async {
      final id = await service.create(draft: draft(), now: now);
      expect(await db.select(db.wordContents).get(), hasLength(1));

      await service.delete(id);

      expect(await db.select(db.words).get(), isEmpty);
      expect(
        await db.select(db.wordContents).get(),
        isEmpty,
        reason: '外键级联应生效（beforeOpen 里开了 foreign_keys）',
      );
    });
  });

  group('enqueueInitialization', () {
    test('入队一条 INITIALIZE 任务', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.enqueueInitialization(wordId: id, now: now);

      final jobs = await db.select(db.initializationJobs).get();
      expect(jobs, hasLength(1));
      expect(jobs.single.taskType, JobTaskType.initialize);
      expect(jobs.single.mode, InitializationMode.fillMissingFields);
      expect(jobs.single.attemptCount, 0);
      expect(jobs.single.status, InitializationStatus.queued);
      expect(jobs.single.priority, jobPriorityDefault);
      expect(jobs.single.maxAttempts, importJobMaxAttempts);
    });

    test('重复入队被部分唯一索引挡下，保持幂等', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.enqueueInitialization(wordId: id, now: now);
      await service.enqueueInitialization(wordId: id, now: now + 1000);
      expect(await db.select(db.initializationJobs).get(), hasLength(1));
    });

    test('不同任务类型可以并存', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.enqueueInitialization(wordId: id, now: now);
      await service.enqueueInitialization(
        wordId: id,
        now: now,
        taskType: JobTaskType.mnemonic,
      );
      expect(await db.select(db.initializationJobs).get(), hasLength(2));
    });

    test('已有活跃任务时升级模式：补空 → 覆盖', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.enqueueInitialization(wordId: id, now: now);

      await service.enqueueInitialization(
        wordId: id,
        now: now + 1000,
        mode: InitializationMode.forceOverwrite,
      );

      final jobs = await db.select(db.initializationJobs).get();
      expect(jobs, hasLength(1));
      expect(jobs.single.mode, InitializationMode.forceOverwrite);
      expect(jobs.single.updatedAt, now + 1000);
    });

    test('已有活跃任务时模式不被削弱', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.enqueueInitialization(
        wordId: id,
        now: now,
        mode: InitializationMode.forceOverwrite,
      );

      await service.enqueueInitialization(
        wordId: id,
        now: now + 1000,
        mode: InitializationMode.skipInitialized,
      );

      final jobs = await db.select(db.initializationJobs).get();
      expect(jobs.single.mode, InitializationMode.forceOverwrite);
    });

    test('已有活跃任务时优先级只升不降', () async {
      final id = await service.create(draft: draft(), now: now);
      await service.enqueueInitialization(
        wordId: id,
        now: now,
        priority: jobPriorityManualBulk,
      );

      await service.enqueueInitialization(
        wordId: id,
        now: now + 1000,
        priority: jobPrioritySupplemental,
      );

      final jobs = await db.select(db.initializationJobs).get();
      expect(jobs.single.priority, jobPriorityManualBulk);
    });
  });

  group('strongerInitializationMode', () {
    test('覆盖强于补空强于跳过', () {
      expect(
        strongerInitializationMode(
          InitializationMode.fillMissingFields,
          InitializationMode.forceOverwrite,
        ),
        InitializationMode.forceOverwrite,
      );
      expect(
        strongerInitializationMode(
          InitializationMode.skipInitialized,
          InitializationMode.fillMissingFields,
        ),
        InitializationMode.fillMissingFields,
      );
      expect(
        strongerInitializationMode(
          InitializationMode.forceOverwrite,
          InitializationMode.skipInitialized,
        ),
        InitializationMode.forceOverwrite,
      );
      expect(
        strongerInitializationMode(
          InitializationMode.skipInitialized,
          InitializationMode.skipInitialized,
        ),
        InitializationMode.skipInitialized,
      );
    });
  });

  group('updateContent 改词条文本', () {
    test('文本变化时写入 term 与 normalized_term', () async {
      final id = await service.create(draft: draft(), now: now);

      await service.updateContent(
        wordId: id,
        draft: draft(term: 'Apples'),
        now: now + 1000,
      );

      final word = await wordOf(id);
      expect(word.term, 'apples');
      expect(word.normalizedTerm, 'apples');
      expect(word.updatedAt, now + 1000);
    });

    test('空文本抛「词条文本不能为空」', () async {
      final id = await service.create(draft: draft(), now: now);
      await expectLater(
        service.updateContent(
          wordId: id,
          draft: draft(term: '   '),
          now: now,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.termRequired,
          ),
        ),
      );
    });

    test('超长文本抛「词条文本过长」', () async {
      final id = await service.create(draft: draft(), now: now);
      await expectLater(
        service.updateContent(
          wordId: id,
          draft: draft(term: 'a' * (termMaxLength + 1)),
          now: now,
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

    test('与别的词条重复抛「已存在相同词条」', () async {
      await service.create(
        draft: draft(term: 'banana'),
        now: now,
      );
      final id = await service.create(draft: draft(), now: now);

      await expectLater(
        service.updateContent(
          wordId: id,
          draft: draft(term: 'Banana'),
          now: now,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.termAlreadyExists,
          ),
        ),
      );
      expect((await wordOf(id)).term, 'apple');
    });

    test('文本未变化时不触发查重（历史遗留的超长词条仍可改内容）', () async {
      final id = await service.create(draft: draft(), now: now);
      // 直接改库造一个超长历史词条：更新内容不该因为它而失败。
      await (db.update(db.words)..where((row) => row.id.equals(id))).write(
        WordsCompanion(term: Value<String>('a' * (termMaxLength + 10))),
      );

      await service.updateContent(
        wordId: id,
        draft: draft(term: 'a' * (termMaxLength + 10)),
        now: now,
      );

      expect((await wordOf(id)).term, 'a' * (termMaxLength + 10));
    });

    test('词条不存在抛「词条不存在」', () async {
      await expectLater(
        service.updateContent(wordId: 999, draft: draft(), now: now),
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

  group('updateContent 落库词典内容', () {
    /// 一份带结构字段的词典内容。
    DictionaryContent structuredContent() =>
        const DictionaryContent(<String, Object?>{
          'definitions': <Object?>[
            <String, Object?>{
              'language': 'zh',
              'text': '苹果',
              'partOfSpeech': 'n.',
              'isUserEdited': true,
              'senseId': 'apple_n_fruit',
            },
          ],
          'examples': <Object?>[
            <String, Object?>{
              'sentence': 'I ate an apple.',
              'translation': '我吃了一个苹果。',
              'isUserAdded': true,
            },
          ],
          'pronunciations': <Object?>[
            <String, Object?>{'accent': 'US', 'phonetic': 'ˈæpl'},
          ],
          'summary': <String, Object?>{'translation': '苹果'},
        });

    test('整份写入并保留结构字段', () async {
      final id = await service.create(draft: draft(), now: now);

      await service.updateContent(
        wordId: id,
        draft: WordDraft(
          term: 'apple',
          contentType: LexicalContentType.word,
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          content: structuredContent(),
        ),
        now: now + 1000,
      );

      final content = await contentOf(id);
      expect(content.definitionsJson, contains('senseId'));
      expect(content.definitionsJson, contains('isUserEdited'));
      expect(content.examplesJson, contains('isUserAdded'));
      expect(content.pronunciationsJson, contains('ˈæpl'));
      expect(content.summaryJson, contains('苹果'));
      expect(content.contentSource, ContentSource.dictionaryOnly);
      expect(content.initializedAt, now + 1000);
      expect(
        content.contentVersion,
        contentVersionWithContent + 1,
        reason: '词典内容走自增语义：创建时已写 1，这次应用后应为 2',
      );
    });

    test('数据源调用记录写入 provider_attempts 且不挂任务', () async {
      final id = await service.create(draft: draft(), now: now);

      await service.updateContent(
        wordId: id,
        draft: WordDraft(
          term: 'apple',
          contentType: LexicalContentType.word,
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          content: structuredContent(),
        ),
        now: now,
        attempts: const <ProviderAttemptRecord>[
          ProviderAttemptRecord(
            providerId: 'youdao',
            status: ProviderAttemptStatus.success,
            durationMs: 30,
            fieldsReturned: <String>['definitions'],
          ),
        ],
      );

      final attempts = await db.select(db.providerAttempts).get();
      expect(attempts, hasLength(1));
      expect(attempts.single.initializationJobId, isNull);
      expect((await contentOf(id)).providerMetadataJson, contains('youdao'));
    });

    test('同一事务里改名与写内容一起生效', () async {
      final id = await service.create(draft: draft(), now: now);

      await service.updateContent(
        wordId: id,
        draft: WordDraft(
          term: 'pear',
          contentType: LexicalContentType.word,
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          content: structuredContent(),
        ),
        now: now,
      );

      final word = await wordOf(id);
      expect(word.term, 'pear');
      expect(word.normalizedTerm, 'pear');
      expect((await contentOf(id)).definitionsJson, contains('苹果'));
    });
  });
}
