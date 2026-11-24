/// 词书包安装、个人词库共存、学习队列隔离、安全卸载与按需有道补全测试。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/daos/word_pack_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/word_packs/pack_gzip.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';
import 'package:lexiloop/services/word_packs/word_pack_install_service.dart';

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late WordPackInstallService service;
  late WordPackDao packDao;
  late WordDao wordDao;
  late StudyDao studyDao;
  late WordEditService wordEdit;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    service = WordPackInstallService(db, settings);
    packDao = WordPackDao(db);
    wordDao = WordDao(db);
    studyDao = StudyDao(db);
    wordEdit = WordEditService(db);
  });

  tearDown(() async {
    await db.close();
  });

  String buildPackJson({
    required String id,
    required String name,
    required List<Map<String, Object?>> entries,
    String contentMode = 'ECDICT_BASE',
  }) => jsonEncode(<String, Object?>{
    'format': 'lexiloop-wordbook-pack',
    'formatVersion': 1,
    'pack': <String, Object?>{
      'id': id,
      'slug': id,
      'name': name,
      'category': 'EXAM_CN',
      'description': '测试词书',
      'version': '2026.1',
      'contentMode': contentMode,
    },
    'entries': entries,
  });

  Map<String, Object?> sampleEntry(
    String term,
    int rank,
    String meaning, {
    bool withExample = false,
  }) => <String, Object?>{
    'term': term,
    'rank': rank,
    'definitions': <Map<String, Object?>>[
      <String, Object?>{
        'language': 'zh',
        'partOfSpeech': 'v',
        'text': meaning,
        'source': 'ecdict',
        'isUserEdited': false,
      },
    ],
    'pronunciations': <Map<String, Object?>>[
      <String, Object?>{
        'accent': 'US',
        'phonetic': 'test',
        'audioUrl': 'https://dict.youdao.com/dictvoice?audio=$term&type=2',
        'source': 'ecdict',
        'isSynthetic': false,
      },
    ],
    if (withExample)
      'examples': <Map<String, Object?>>[
        <String, Object?>{
          'sentence': 'This uses $term naturally.',
          'translation': '这里自然地使用了该词。',
          'source': 'youdao:example',
          'isUserAdded': false,
        },
      ],
  };

  test('GZip 词书安装与个人词库共存：不覆盖个人归属与笔记，并补全待初始化词条', () async {
    const now = 1_700_000_000_000;
    final personalId = await wordEdit.create(
      draft: const WordDraft(
        term: 'abandon',
        contentType: LexicalContentType.word,
        sourceLanguage: 'en',
        targetLanguage: 'zh',
        note: '我的个人笔记',
      ),
      now: now,
    );

    final gz = encodeWordPackGzip(
      buildPackJson(
        id: 'cet4',
        name: '大学英语四级',
        entries: <Map<String, Object?>>[
          sampleEntry('abandon', 1, '放弃，抛弃'),
          sampleEntry('resilient', 2, '有韧性的'),
        ],
      ),
    );
    final result = await service.installFromBytes(bytes: gz, now: now + 100);

    expect(result.createdWords, 1);
    expect(result.linkedExistingWords, 1);
    expect(result.backfilledWords, 1);

    // 个人词条保持 is_personal = 1、保留笔记，同时关联到 CET-4。
    final all = await wordDao.list(const WordQuery());
    final abandon = all.firstWhere((e) => e.id == personalId);
    final resilient = all.firstWhere((e) => e.term == 'resilient');
    expect(abandon.isPersonal, isTrue);
    expect(abandon.packNames, <String>['大学英语四级']);
    expect(abandon.initializationStatus, InitializationStatus.partial);
    expect(resilient.isPersonal, isFalse);
    expect(resilient.packNames, <String>['大学英语四级']);

    // 作用域筛选：个人词库仅看到 abandon，词书包看到两者。
    final personalOnly = await wordDao.list(
      const WordQuery(sourceScope: WordSourceScope.personal),
    );
    expect(personalOnly.map((e) => e.term), <String>['abandon']);

    final packOnly = await wordDao.list(
      const WordQuery(sourceScope: WordSourceScope.packs, packId: 'cet4'),
    );
    expect(packOnly, hasLength(2));
  });

  test('手动添加命中词书词条时自动升格为个人词库，再次添加个人词才报重复', () async {
    const now = 1_700_000_000_000;
    final gz = encodeWordPackGzip(
      buildPackJson(
        id: 'ielts',
        name: '雅思核心',
        entries: <Map<String, Object?>>[sampleEntry('ubiquitous', 1, '无处不在的')],
      ),
    );
    await service.installFromBytes(bytes: gz, now: now);

    final promotedId = await wordEdit.create(
      draft: const WordDraft(
        term: 'ubiquitous',
        contentType: LexicalContentType.word,
        sourceLanguage: 'en',
        targetLanguage: 'zh',
        note: '阅读真题遇到',
      ),
      now: now + 10,
    );
    final entries = await wordDao.list(
      const WordQuery(sourceScope: WordSourceScope.personal),
    );
    expect(entries.single.id, promotedId);
    expect(entries.single.isPersonal, isTrue);

    await expectLater(
      wordEdit.create(
        draft: const WordDraft(
          term: 'ubiquitous',
          contentType: LexicalContentType.word,
          sourceLanguage: 'en',
          targetLanguage: 'zh',
        ),
        now: now + 20,
      ),
      throwsA(
        isA<ConflictError>().having(
          (e) => e.code,
          'code',
          AppErrorCode.termAlreadyExists,
        ),
      ),
    );
  });

  test('每日学习队列默认隔离词书，专项学习按 rank 排序，开启开关后纳入每日队列', () async {
    const now = 1_700_000_000_000;
    await wordEdit.create(
      draft: const WordDraft(
        term: 'apple',
        contentType: LexicalContentType.word,
        sourceLanguage: 'en',
        targetLanguage: 'zh',
        definitions: <String>['苹果'],
      ),
      now: now,
    );

    final gz = encodeWordPackGzip(
      buildPackJson(
        id: 'cet4',
        name: '四级',
        entries: <Map<String, Object?>>[
          sampleEntry('zebra', 1, '斑马'),
          sampleEntry('alpha', 2, '阿尔法'),
        ],
      ),
    );
    await service.installFromBytes(bytes: gz, now: now + 10);

    // 默认 include_in_daily_study = 0：每日候选仅含个人词 apple。
    final dailyBefore = await studyDao.newCandidates(
      limit: 20,
      now: now + 20,
      scope: CandidateScope.lexical,
    );
    expect(dailyBefore.map((c) => c.term), <String>['apple']);

    // 专项学习指定 packId：按词书 rank 顺序返回 zebra -> alpha。
    final packOnly = await studyDao.newCandidates(
      limit: 20,
      now: now + 20,
      scope: CandidateScope.lexical,
      packId: 'cet4',
    );
    expect(packOnly.map((c) => c.term), <String>['zebra', 'alpha']);

    // 开启「纳入每日计划」后，词书词条也进入每日候选。
    await packDao.setIncludeInDailyStudy('cet4', enabled: true, now: now + 30);
    final dailyAfter = await studyDao.newCandidates(
      limit: 20,
      now: now + 40,
      scope: CandidateScope.lexical,
    );
    expect(
      dailyAfter.map((c) => c.term),
      containsAll(<String>['apple', 'zebra', 'alpha']),
    );
  });

  test('安全卸载：保留个人词与其他词书共享词，清理未学词，已学词默认转个人词库', () async {
    const now = 1_700_000_000_000;
    await wordEdit.create(
      draft: const WordDraft(
        term: 'keep_personal',
        contentType: LexicalContentType.word,
        sourceLanguage: 'en',
        targetLanguage: 'zh',
        definitions: <String>['个人词'],
      ),
      now: now,
    );

    await service.installFromBytes(
      bytes: encodeWordPackGzip(
        buildPackJson(
          id: 'cet4',
          name: '四级',
          entries: <Map<String, Object?>>[
            sampleEntry('keep_personal', 1, '个人词'),
            sampleEntry('shared_word', 2, '共享词'),
            sampleEntry('learned_pack_word', 3, '已学词'),
            sampleEntry('fresh_pack_word', 4, '未学词'),
          ],
        ),
      ),
      now: now + 10,
    );
    await service.installFromBytes(
      bytes: encodeWordPackGzip(
        buildPackJson(
          id: 'cet6',
          name: '六级',
          entries: <Map<String, Object?>>[sampleEntry('shared_word', 1, '共享词')],
        ),
      ),
      now: now + 20,
    );

    // 给 learned_pack_word 建一张复习卡，模拟已学习。
    final learnedId = (await wordDao.list(
      const WordQuery(search: 'learned_pack_word'),
    )).single.id;
    await db
        .into(db.reviewCards)
        .insert(
          ReviewCardsCompanion.insert(
            wordId: Value<int>(learnedId),
            dueAt: now + 1000,
            stability: 1,
            difficulty: 5,
            elapsedDays: 0,
            scheduledDays: 1,
            reps: 1,
            lapses: 0,
            fsrsState: 2,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final impact = await packDao.inspectUninstallImpact('cet4');
    expect(impact, isNotNull);
    expect(impact!.personalKeptCount, 1);
    expect(impact.sharedOtherPackCount, 1);
    expect(impact.removableUnlearnedCount, 1);
    expect(impact.learnedOnlyInPackCount, 1);

    final uninstall = await service.uninstallPack(
      packId: 'cet4',
      now: now + 50,
    );
    expect(uninstall.removedWords, 1);
    expect(uninstall.promotedToPersonalWords, 1);
    expect(uninstall.keptPersonalOrSharedWords, 2);

    final remainingTerms = (await wordDao.list(const WordQuery()))
        .map((e) => e.term)
        .toSet();
    expect(remainingTerms, <String>{
      'keep_personal',
      'shared_word',
      'learned_pack_word',
    });

    final promoted = (await wordDao.list(
      const WordQuery(search: 'learned_pack_word'),
    )).single;
    expect(promoted.isPersonal, isTrue);
  });

  test('按需懒加载有道补全仅入队尚未 READY 的前 N 个词条', () async {
    const now = 1_700_000_000_000;
    await service.installFromBytes(
      bytes: encodeWordPackGzip(
        buildPackJson(
          id: 'ielts',
          name: '雅思',
          entries: <Map<String, Object?>>[
            sampleEntry('already_ready', 1, '已完整', withExample: true),
            sampleEntry('need_one', 2, '缺例句1'),
            sampleEntry('need_two', 3, '缺例句2'),
            sampleEntry('need_three', 4, '缺例句3'),
          ],
        ),
      ),
      now: now,
    );

    final enqueued = await service.enqueueLazyEnrichment(
      packId: 'ielts',
      now: now + 10,
      limit: 2,
    );
    expect(enqueued, 2);

    final jobs = await db.select(db.initializationJobs).get();
    expect(jobs, hasLength(2));
    expect(jobs.every((j) => j.requestedProvidersJson == '["youdao"]'), isTrue);
  });
}
