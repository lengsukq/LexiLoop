/// 词库列表查询的 DAO 级测试。
///
/// 这一层承载的是「用户点哪个筛选、排序、搜索词之后，SQL 返回什么」。
/// 词库列表页曾经只有 `term` 一个搜索列、三个筛选和一个写死的排序，
/// 而界面层什么都看不见——测试先在这里把行为钉住，界面才有东西可接。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/words/word_csv_export.dart';

void main() {
  late AppDatabase db;
  late WordDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = WordDao(db);
  });

  // 必须包成闭包：`tearDown(db.close)` 会在注册期就求值 `db.close`，
  // 而 `late db` 此时还没被 `setUp` 初始化，整个测试文件会在加载阶段
  // 抛 LateError（表现为 "Local 'db' has not been initialized"）。
  tearDown(() => db.close());

  /// 给词条挂一张复习卡（其余 FSRS 字段对本组用例无意义，取中性值）。
  Future<void> insertCard(int wordId, int dueAt) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.reviewCards)
        .insert(
          ReviewCardsCompanion.insert(
            wordId: Value<int>(wordId),
            dueAt: dueAt,
            stability: 1,
            difficulty: 5,
            elapsedDays: 0,
            scheduledDays: 1,
            reps: 1,
            lapses: 0,
            fsrsState: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 建一个词条并挂上可选的错词状态与复习卡，返回它的 id。
  Future<int> insertWord({
    String term = 'word',
    String? normalizedTerm,
    String? note,
    InitializationStatus status = InitializationStatus.pending,
    MasteryLevel mastery = MasteryLevel.newWord,
    int score = 0,
    bool suspended = false,
    int? createdAt,
    int? sourceCreatedAt,
    bool wrongActive = false,
    int? dueAt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: normalizedTerm ?? term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: Value<InitializationStatus>(status),
            masteryLevel: Value<MasteryLevel>(mastery),
            masteryScore: Value<int>(score),
            isSuspended: Value<bool>(suspended),
            userNote: Value<String?>(note),
            sourceCreatedAt: Value<int?>(sourceCreatedAt),
            createdAt: createdAt ?? now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wrongWordStates)
        .insert(
          WrongWordStatesCompanion.insert(
            wordId: Value<int>(id),
            active: Value<bool>(wrongActive),
            updatedAt: now,
          ),
        );
    if (dueAt != null) await insertCard(id, dueAt);
    return id;
  }

  /// 按当前顺序取出词形，便于断言排序。
  Future<List<String>> terms(WordQuery query) async {
    final rows = await dao.list(query);
    return rows.map((row) => row.term).toList();
  }

  Future<int> countOf(WordQuery query) => dao.count(query);

  group('筛选', () {
    test('初始化状态', () async {
      await insertWord(term: 'ready-word', status: InitializationStatus.ready);
      await insertWord(
        term: 'failed-word',
        status: InitializationStatus.failed,
      );

      final rows = await terms(
        const WordQuery(initializationStatus: InitializationStatus.ready),
      );

      expect(rows, <String>['ready-word']);
    });

    test('掌握等级', () async {
      await insertWord(term: 'new');
      await insertWord(term: 'mastered', mastery: MasteryLevel.mastered);

      final rows = await terms(
        const WordQuery(masteryLevel: MasteryLevel.mastered),
      );

      expect(rows, <String>['mastered']);
    });

    test('只显示错词：已解除的错词与普通词条都不该出现', () async {
      await insertWord(term: 'wrong-active', wrongActive: true);
      await insertWord(term: 'wrong-resolved');
      await insertWord(term: 'plain');

      final rows = await terms(const WordQuery(wrongOnly: true));

      expect(rows, <String>['wrong-active']);
    });

    test('只看到期：未来到期的卡片不出现，没有卡片的词条也不出现', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertWord(term: 'overdue', dueAt: now - dayMs);
      await insertWord(term: 'upcoming', dueAt: now + 7 * dayMs);
      await insertWord(term: 'no-card');

      final rows = await terms(const WordQuery(dueOnly: true));

      expect(rows, <String>['overdue']);
    });

    test('只显示已暂停', () async {
      await insertWord(term: 'paused', suspended: true);
      await insertWord(term: 'running');

      final rows = await terms(const WordQuery(suspendedOnly: true));

      expect(rows, <String>['paused']);
    });

    test('筛选条件叠加时取交集', () async {
      await insertWord(term: 'both', suspended: true, wrongActive: true);
      await insertWord(term: 'only-suspended', suspended: true);
      await insertWord(term: 'only-wrong', wrongActive: true);

      final rows = await terms(
        const WordQuery(wrongOnly: true, suspendedOnly: true),
      );

      expect(rows, <String>['both']);
    });

    test('count 与 list 用同一组条件', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertWord(term: 'a', wrongActive: true, dueAt: now - dayMs);
      await insertWord(term: 'b', wrongActive: true);
      await insertWord(term: 'c');

      const query = WordQuery(wrongOnly: true, dueOnly: true);

      expect(await countOf(query), 1);
      expect(await terms(query), <String>['a']);
    });
  });

  group('搜索', () {
    test('匹配词形，且大小写不敏感', () async {
      await insertWord(term: 'Apple');
      await insertWord(term: 'banana');

      expect(await terms(const WordQuery(search: 'app')), <String>['Apple']);
    });

    test('匹配归一化文本', () async {
      // 词形带重音、归一化文本是 ASCII：小写化后两者不再互相命中，
      // 于是这一条只能靠 normalized_term 命中。
      await insertWord(term: 'Café', normalizedTerm: 'cafe');

      expect(await terms(const WordQuery(search: 'cafe')), <String>['Café']);
    });

    test('匹配用户备注', () async {
      await insertWord(term: 'alpha', note: '容易和 beta 混淆');
      await insertWord(term: 'beta');

      expect(await terms(const WordQuery(search: '混淆')), <String>['alpha']);
    });

    test('备注为空的词条不会被搜索排除在结果之外', () async {
      await insertWord(term: 'alpha');
      await insertWord(term: 'beta', note: '备注');

      expect(await countOf(const WordQuery(search: '备注')), 1);
    });

    test('% 是字面量而不是通配符', () async {
      await insertWord(term: '100% pure');
      await insertWord(term: '100x pure');

      expect(await terms(const WordQuery(search: '100%')), <String>[
        '100% pure',
      ]);
      // 单独搜 '%' 只会命中真正含百分号的那一条；
      // 不转义时它是「匹配任意串」，两条都会出来。
      expect(await terms(const WordQuery(search: '%')), <String>['100% pure']);
    });

    test('_ 是字面量而不是单字符通配符', () async {
      await insertWord(term: 'a_b');
      await insertWord(term: 'axb');

      expect(await terms(const WordQuery(search: '_')), <String>['a_b']);
    });

    test(r'\'
        ' 是字面量而不是转义前缀', () async {
      await insertWord(term: r'a\b');
      await insertWord(term: 'ab');

      expect(await terms(const WordQuery(search: r'\')), <String>[r'a\b']);
    });

    test('空白关键词视为没有搜索', () async {
      await insertWord(term: 'alpha');

      expect(await countOf(const WordQuery(search: '   ')), 1);
    });
  });

  group('排序', () {
    test('默认按创建时间倒序', () async {
      await insertWord(term: 'older', createdAt: 1000);
      await insertWord(term: 'newer', createdAt: 2000);

      expect(await terms(const WordQuery()), <String>['newer', 'older']);
    });

    test('创建时间相同时按 id 倒序收尾', () async {
      await insertWord(term: 'first', createdAt: 1000);
      await insertWord(term: 'second', createdAt: 1000);

      // 排序键完全重复时页序未定义；`id DESC` 这条兜底规则让翻页不会漏词。
      expect(await terms(const WordQuery()), <String>['second', 'first']);
    });

    test('按来源时间排序，缺失来源时间时回落到创建时间', () async {
      // 三档键值必须两两不等，否则断言落在 `id DESC` 兜底规则上，
      // 「回落到创建时间」这条性质根本没被验到。
      await insertWord(
        term: 'from-source',
        createdAt: 5000,
        sourceCreatedAt: 4000,
      );
      await insertWord(term: 'no-source', createdAt: 9000);
      await insertWord(
        term: 'old-source',
        createdAt: 100,
        sourceCreatedAt: 100,
      );

      expect(
        await terms(const WordQuery(sort: WordSort.sourceCreatedAt)),
        <String>['no-source', 'from-source', 'old-source'],
      );
    });

    test('按词形升序', () async {
      await insertWord(term: 'banana');
      await insertWord(term: 'apple');

      expect(await terms(const WordQuery(sort: WordSort.term)), <String>[
        'apple',
        'banana',
      ]);
    });

    test('按掌握度倒序，分数相同的按 id 倒序', () async {
      await insertWord(term: 'low', score: 10);
      await insertWord(term: 'tie-first', score: 50);
      await insertWord(term: 'tie-second', score: 50);

      expect(
        await terms(const WordQuery(sort: WordSort.masteryScore)),
        <String>['tie-second', 'tie-first', 'low'],
      );
    });

    test('按到期时间倒序，没有复习卡的排到最后', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertWord(term: 'later', dueAt: now + 2 * dayMs);
      await insertWord(term: 'sooner', dueAt: now + dayMs);
      await insertWord(term: 'no-card');

      expect(await terms(const WordQuery(sort: WordSort.dueAt)), <String>[
        'later',
        'sooner',
        'no-card',
      ]);
    });

    test('每一档排序都以 id 倒序收尾', () {
      for (final sort in WordSort.values) {
        expect(sort.orderBy.endsWith('w.id DESC'), isTrue, reason: '$sort');
      }
    });
  });

  group('分页', () {
    test('limit 与 offset 切出互不重叠的两页', () async {
      for (var i = 0; i < 3; i += 1) {
        await insertWord(term: 'w$i', createdAt: 1000);
      }

      final first = await terms(const WordQuery(limit: 2));
      final second = await terms(const WordQuery(limit: 2, offset: 2));

      expect(first, <String>['w2', 'w1']);
      expect(second, <String>['w0']);
    });

    test('count 不受 limit 与 offset 影响', () async {
      for (var i = 0; i < 3; i += 1) {
        await insertWord(term: 'w$i', createdAt: 1000);
      }

      expect(await countOf(const WordQuery(limit: 1, offset: 2)), 3);
    });

    test('默认页大小是 wordListPageSize', () {
      expect(const WordQuery().limit, wordListPageSize);
      expect(const WordQuery().offset, 0);
      expect(const WordQuery().page, 1);
      expect(const WordQuery(offset: 40).page, 2);
    });
  });

  group('计数与概览', () {
    test('countByMastery 只统计实际出现过的等级', () async {
      await insertWord(term: 'a');
      await insertWord(term: 'b', mastery: MasteryLevel.mastered);
      await insertWord(term: 'c', mastery: MasteryLevel.mastered);

      final summary = await dao.countByMastery();

      expect(summary[MasteryLevel.newWord], 1);
      expect(summary[MasteryLevel.mastered], 2);
      expect(summary[MasteryLevel.familiar], isNull);
    });
  });

  group('行数据', () {
    test('带出错词状态、到期时间与来源时间', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await insertWord(
        term: 'full',
        wrongActive: true,
        dueAt: now + dayMs,
        sourceCreatedAt: 42,
      );

      final entry = (await dao.list(const WordQuery())).single;

      expect(entry.wrongWordActive, isTrue);
      expect(entry.dueAt, now + dayMs);
      expect(entry.sourceCreatedAt, 42);
    });

    test('没有复习卡与错词状态时字段为 null / false', () async {
      await insertWord(term: 'plain');

      final entry = (await dao.list(const WordQuery())).single;

      expect(entry.dueAt, isNull);
      expect(entry.sourceCreatedAt, isNull);
      expect(entry.wrongWordActive, isFalse);
    });
  });

  group('activeFilterCount', () {
    test('关键词不计入筛选数', () {
      expect(const WordQuery(search: 'abc').activeFilterCount, 0);
    });

    test('逐项累加', () {
      expect(
        const WordQuery(
          masteryLevel: MasteryLevel.learning,
          wrongOnly: true,
          dueOnly: true,
          suspendedOnly: true,
        ).activeFilterCount,
        4,
      );
    });
  });

  group('escapeLikePattern', () {
    test('转义反斜杠、百分号与下划线', () {
      expect(escapeLikePattern(r'a%b_c\d'), r'a\%b\_c\\d');
    });

    test('普通文本原样返回', () {
      expect(escapeLikePattern('plain text'), 'plain text');
    });
  });

  group('中文释义搜索、类型/标签筛选与导出', () {
    Future<int> insertWithContent({
      required String term,
      LexicalContentType contentType = LexicalContentType.word,
      String definitionsJson = '[]',
      String tagsJson = '[]',
      String examplesJson = '[]',
    }) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await db
          .into(db.words)
          .insert(
            WordsCompanion.insert(
              term: term,
              normalizedTerm: term.toLowerCase(),
              sourceLanguage: 'en',
              targetLanguage: 'zh-CN',
              entryType: contentType == LexicalContentType.word
                  ? EntryType.word
                  : EntryType.phrase,
              contentType: Value<LexicalContentType>(contentType),
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
              definitionsJson: Value<String>(definitionsJson),
              tagsJson: Value<String>(tagsJson),
              examplesJson: Value<String>(examplesJson),
              updatedAt: now,
            ),
          );
      return id;
    }

    test('搜索关键词能命中中文释义与标签，且 count 与 list 一致', () async {
      await insertWithContent(
        term: 'resilient',
        definitionsJson: '[{"language":"zh-CN","text":"有弹性的；适应力强的"}]',
        tagsJson: '["IELTS","阅读"]',
      );
      await insertWithContent(
        term: 'apple',
        definitionsJson: '[{"language":"zh-CN","text":"苹果"}]',
        tagsJson: '["日常"]',
      );

      expect(await terms(const WordQuery(search: '适应力')), <String>[
        'resilient',
      ]);
      expect(await countOf(const WordQuery(search: '适应力')), 1);
      expect(await terms(const WordQuery(search: 'IELTS')), <String>[
        'resilient',
      ]);
    });

    test('按内容类型与标签精确筛选，distinctTags 返回去重排序列表', () async {
      await insertWithContent(term: 'apple', tagsJson: '["IELTS","高频"]');
      await insertWithContent(
        term: 'take off',
        contentType: LexicalContentType.phrase,
        tagsJson: '["CET4","高频"]',
      );
      await insertWithContent(term: 'IEL', tagsJson: '["IELTS-2026"]');

      expect(
        await terms(const WordQuery(contentType: LexicalContentType.phrase)),
        <String>['take off'],
      );
      expect(await terms(const WordQuery(tag: 'IELTS')), <String>['apple']);
      expect(await dao.distinctTags(), <String>[
        'CET4',
        'IELTS',
        'IELTS-2026',
        '高频',
      ]);
    });

    test('exportRows 与 encodeWordsCsv 输出带 UTF-8 BOM 的标准表头 CSV', () async {
      await insertWithContent(
        term: 'resilient',
        definitionsJson: '[{"language":"zh-CN","text":"有韧性的, 适应力强"}]',
        tagsJson: '["IELTS","阅读"]',
        examplesJson: '[{"sentence":"Cities are resilient."}]',
      );
      final rows = await dao.exportRows(const WordQuery(tag: 'IELTS'));
      expect(rows, hasLength(1));
      final csv = encodeWordsCsv(rows);
      expect(csv.startsWith('\uFEFF单词,音标,释义,例句,标签,备注'), isTrue);
      expect(
        csv,
        contains('resilient,,"有韧性的, 适应力强",Cities are resilient.,IELTS;阅读,'),
      );
    });
  });
}
