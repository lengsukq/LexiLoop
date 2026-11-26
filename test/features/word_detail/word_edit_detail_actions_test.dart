/// 详情页写操作的服务层测试。
///
/// 覆盖三件「界面上看不出错、但数据已经错了」的事：
/// 1. 手工释义**替换**而不是追加——追加会让用户每保存一次就多一条自己
///    写的释义，选项列表被自己的草稿淹没；
/// 2. 删除例句的下标必须按「界面可见顺序」换算——`examples_json` 里有
///    脏条目时两者会错位，错位就是删掉了隔壁那条；
/// 3. AI 按钮重复点击不得产生第二个任务——重复任务会让 worker 对同一个
///    词条跑两遍 AI，token 与配额都是白花。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
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

  /// 插入词条并写入内容；返回词条 ID。
  Future<int> insertWord({
    String definitionsJson = '[]',
    String examplesJson = '[]',
    String targetLanguage = 'zh',
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: 'raise',
            normalizedTerm: 'raise',
            sourceLanguage: 'en',
            targetLanguage: targetLanguage,
            entryType: EntryType.word,
            contentType: const Value<LexicalContentType>(
              LexicalContentType.word,
            ),
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
            examplesJson: Value<String>(examplesJson),
            updatedAt: now,
          ),
        );
    return id;
  }

  group('updateManualDefinition', () {
    test('前置新释义、摘掉旧的、保留数据源释义并自增版本号', () async {
      final id = await insertWord(
        definitionsJson:
            '[{"language":"en","text":"词典释义",'
            '"source":"ecdict","isUserEdited":false},'
            '{"language":"zh","text":"我上次写的","source":"user",'
            '"isUserEdited":true}]',
      );
      final before = await contentVersionOf(db, id);

      await service.updateManualDefinition(
        wordId: id,
        definition: '我现在写的',
        now: now,
      );

      final definitions = await definitionsOf(db, id);
      expect(definitions, hasLength(2));
      final head = definitions.first! as Map<String, Object?>;
      expect(head['text'], '我现在写的');
      expect(head['language'], 'zh');
      expect(head['source'], userAuthoredDefinitionSource);
      expect(head['isUserEdited'], true);
      final kept = definitions.last! as Map<String, Object?>;
      expect(kept['text'], '词典释义');
      expect(kept['source'], 'ecdict');
      expect(await contentVersionOf(db, id), before + 1);
    });

    test('认的是 isUserEdited 标记而不是 source 字面量', () async {
      // 判据是 `isUserEdited == true`（与合并层 isUserProtectedItem 同一套），
      // 而不是 `source` 的字面量。这里刻意给一条 `source: "ecdict"` 但带
      // 标记的释义：若哪天有人把判据改回按 source 匹配，这条就删不掉，
      // 每保存一次多一条自己写的释义。
      final id = await insertWord(
        definitionsJson:
            '[{"language":"zh","text":"录入的","source":"ecdict",'
            '"isUserEdited":true},'
            '{"language":"en","text":"词典释义","source":"ecdict"}]',
      );

      await service.updateManualDefinition(
        wordId: id,
        definition: '改过的',
        now: now,
      );

      final definitions = await definitionsOf(db, id);
      expect(definitions, hasLength(2));
      expect((definitions.first! as Map<String, Object?>)['text'], '改过的');
      expect((definitions.last! as Map<String, Object?>)['text'], '词典释义');
    });

    test('手工录入但没打 isUserEdited 标记的释义不算用户资产', () async {
      // 反向用例：`source: manual` 但缺标记 → 不是用户资产，必须原样保留。
      // 与上一条合起来才说明判据既不是"看 source"也不是"看有没有来源"。
      final id = await insertWord(
        definitionsJson:
            '[{"language":"zh","text":"录入的",'
            '"source":"$manualContentSource"}]',
      );

      await service.updateManualDefinition(
        wordId: id,
        definition: '改过的',
        now: now,
      );

      final definitions = await definitionsOf(db, id);
      expect(definitions, hasLength(2));
      expect((definitions.last! as Map<String, Object?>)['text'], '录入的');
    });

    test('释义写完把内容状态重算为部分完成', () async {
      final id = await insertWord();

      await service.updateManualDefinition(
        wordId: id,
        definition: '只有释义没有例句',
        now: now,
      );

      expect(await statusOf(db, id), InitializationStatus.partial);
    });

    test('传空白撤掉手工释义且不动数据源释义', () async {
      final id = await insertWord(
        definitionsJson:
            '[{"language":"zh","text":"我的","isUserEdited":true},'
            '{"language":"en","text":"词典释义"}]',
      );
      final before = await contentVersionOf(db, id);

      await service.updateManualDefinition(
        wordId: id,
        definition: '  ',
        now: now,
      );

      final definitions = await definitionsOf(db, id);
      expect(definitions, hasLength(1));
      expect((definitions.single! as Map<String, Object?>)['text'], '词典释义');
      expect(await contentVersionOf(db, id), before + 1);
    });

    test('没有手工释义且传空白时不写库', () async {
      final id = await insertWord(
        definitionsJson: '[{"language":"en","text":"词典释义"}]',
      );
      final before = await contentVersionOf(db, id);

      await service.updateManualDefinition(
        wordId: id,
        definition: '',
        now: now,
      );

      expect(await contentVersionOf(db, id), before);
    });

    test('释义过长被拒', () async {
      final id = await insertWord();

      expect(
        () => service.updateManualDefinition(
          wordId: id,
          definition: 'x' * (manualDefinitionMaxLength + 1),
          now: now,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('词条不存在时抛 NotFoundError', () async {
      expect(
        () => service.updateManualDefinition(
          wordId: 4242,
          definition: '孤儿释义',
          now: now,
        ),
        throwsA(
          isA<NotFoundError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.wordNotFound,
          ),
        ),
      );
    });
  });

  group('deleteExample', () {
    test('按下标删掉那一条并自增版本号', () async {
      final id = await insertWord(
        examplesJson: '[{"sentence":"A"},{"sentence":"B"},{"sentence":"C"}]',
      );
      final before = await contentVersionOf(db, id);

      await service.deleteExample(wordId: id, index: 1, now: now);

      final examples = await examplesOf(db, id);
      expect(examples, hasLength(2));
      expect((examples.first! as Map<String, Object?>)['sentence'], 'A');
      expect((examples.last! as Map<String, Object?>)['sentence'], 'C');
      expect(await contentVersionOf(db, id), before + 1);
    });

    test('下标按界面可见顺序换算，脏条目不会被误删', () async {
      // 原始数组：[null, A, "  ", B, C]，界面只渲染 A / B / C。
      // 可见下标 0 必须落到原始下标 1（A），而不是原始下标 0（null）。
      final id = await insertWord(
        examplesJson:
            '[null,{"sentence":"A"},{"sentence":"  "}, '
            '{"sentence":"B"},{"sentence":"C"}]',
      );

      await service.deleteExample(wordId: id, index: 0, now: now);

      final examples = await examplesOf(db, id);
      // 长度仍是 4：删掉的是一条**可见**例句，两条脏条目原样留在原位。
      expect(examples, hasLength(4));
      expect(examples[0], isNull);
      expect(
        (examples[1]! as Map<String, Object?>)['sentence'],
        '  ',
        reason: '被删的是 A，空句子那条必须原地不动',
      );
      expect((examples[2]! as Map<String, Object?>)['sentence'], 'B');
      expect((examples[3]! as Map<String, Object?>)['sentence'], 'C');
    });

    test('末尾的可见下标按脏条目数量整体后移', () async {
      // 尾部最容易暴露"忘了减去脏条目数量"的错位：可见下标 2 应落到原始 4。
      final id = await insertWord(
        examplesJson:
            '[null,{"sentence":"A"},{"sentence":"  "}, '
            '{"sentence":"B"},{"sentence":"C"}]',
      );

      await service.deleteExample(wordId: id, index: 2, now: now);

      final examples = await examplesOf(db, id);
      expect(examples, hasLength(4));
      expect((examples[1]! as Map<String, Object?>)['sentence'], 'A');
      expect((examples[3]! as Map<String, Object?>)['sentence'], 'B');
    });

    test('删掉最后一条例句后内容状态从就绪退到部分', () async {
      final id = await insertWord(
        definitionsJson: '[{"language":"en","text":"词典释义"}]',
        examplesJson: '[{"sentence":"唯一一条"}]',
      );

      await service.deleteExample(wordId: id, index: 0, now: now);

      expect(await statusOf(db, id), InitializationStatus.partial);
    });

    test('下标越界抛 AppError 而不是静默返回', () async {
      final id = await insertWord(examplesJson: '[{"sentence":"A"}]');

      for (final index in <int>[-1, 1, 99]) {
        expect(
          () => service.deleteExample(wordId: id, index: index, now: now),
          throwsA(
            isA<NotFoundError>().having(
              (error) => error.code,
              'code',
              AppErrorCode.exampleNotFound,
            ),
          ),
          reason: '下标 $index 越界必须被拒绝',
        );
      }
      expect(await examplesOf(db, id), hasLength(1));
    });
  });

  group('translateExample', () {
    test('入队一个 EXAMPLE_TRANSLATIONS 任务', () async {
      final id = await insertWord(examplesJson: '[{"sentence":"A"}]');

      await service.translateExample(wordId: id, index: 0, now: now);

      expect(await queuedTaskTypes(db, id), <JobTaskType>[
        JobTaskType.exampleTranslations,
      ]);
    });

    test('重复点击不会排出第二个任务', () async {
      final id = await insertWord(examplesJson: '[{"sentence":"A"}]');

      await service.translateExample(wordId: id, index: 0, now: now);
      await service.translateExample(wordId: id, index: 0, now: now);
      await service.translateExample(wordId: id, index: 0, now: now);

      expect(
        await queuedTaskTypes(db, id),
        hasLength(1),
        reason: '部分唯一索引 + ON CONFLICT DO NOTHING 应当让入队幂等',
      );
    });

    test('下标越界时不入队', () async {
      final id = await insertWord(examplesJson: '[{"sentence":"A"}]');

      expect(
        () => service.translateExample(wordId: id, index: 5, now: now),
        throwsA(isA<NotFoundError>()),
      );
      expect(await queuedTaskTypes(db, id), isEmpty);
    });

    test('翻译任务与助记任务各占一个名额，互不挤掉', () async {
      final id = await insertWord(examplesJson: '[{"sentence":"A"}]');

      await service.translateExample(wordId: id, index: 0, now: now);
      await service.enqueueInitialization(
        wordId: id,
        now: now,
        taskType: JobTaskType.mnemonic,
      );

      expect(await queuedTaskTypes(db, id), <JobTaskType>[
        JobTaskType.exampleTranslations,
        JobTaskType.mnemonic,
      ]);
    });
  });

  group('助记任务入队', () {
    test('重复请求助记只保留一个任务', () async {
      final id = await insertWord();

      await service.enqueueInitialization(
        wordId: id,
        now: now,
        taskType: JobTaskType.mnemonic,
      );
      await service.enqueueInitialization(
        wordId: id,
        now: now,
        taskType: JobTaskType.mnemonic,
      );

      expect(await queuedTaskTypes(db, id), <JobTaskType>[
        JobTaskType.mnemonic,
      ]);
    });
  });
}

/// 读回单个内容列的 JSON 数组。
Future<List<Object?>> definitionsOf(AppDatabase db, int wordId) =>
    _columnList(db, wordId, 'definitions_json');

/// 读回 `examples_json` 的原始数组。
Future<List<Object?>> examplesOf(AppDatabase db, int wordId) =>
    _columnList(db, wordId, 'examples_json');

Future<List<Object?>> _columnList(
  AppDatabase db,
  int wordId,
  String column,
) async {
  final rows = await db
      .customSelect(
        'SELECT $column FROM word_contents WHERE word_id = ?',
        variables: <Variable<Object>>[Variable<int>(wordId)],
      )
      .get();
  if (rows.isEmpty) return const <Object?>[];
  final decoded = jsonDecode(rows.first.read<String>(column));
  return decoded is List ? decoded : const <Object?>[];
}

/// 当前内容版本号。
Future<int> contentVersionOf(AppDatabase db, int wordId) async {
  final rows = await db
      .customSelect(
        'SELECT content_version FROM word_contents WHERE word_id = ?',
        variables: <Variable<Object>>[Variable<int>(wordId)],
      )
      .get();
  return rows.first.read<int>('content_version');
}

/// 当前内容状态。
///
/// 读原始 wire 字符串再用 [wireLookup] 归一化，而不是 `read<InitializationStatus>`：
/// `QueryRow.read<T>` 只支持 Drift 内建类型，枚举列经 TypeConverter 存的是
/// TEXT，直接 `read` 枚举会抛
/// 「Could not find a matching SQL type for InitializationStatus」。
/// 这也正是生产代码里 DAO 的读法。
Future<InitializationStatus> statusOf(AppDatabase db, int wordId) async {
  final rows = await db
      .customSelect(
        'SELECT initialization_status FROM words WHERE id = ?',
        variables: <Variable<Object>>[Variable<int>(wordId)],
      )
      .get();
  final raw = rows.first.read<String>('initialization_status');
  return wireLookup(InitializationStatus.values, raw) ??
      InitializationStatus.pending;
}

/// 该词条当前占着「活跃任务」名额的任务类型。
Future<List<JobTaskType>> queuedTaskTypes(AppDatabase db, int wordId) async {
  final rows = await db
      .customSelect(
        'SELECT task_type FROM initialization_jobs '
        "WHERE word_id = ? AND status IN ('QUEUED','RUNNING')",
        variables: <Variable<Object>>[Variable<int>(wordId)],
      )
      .get();
  return <JobTaskType>[
    for (final row in rows)
      ?wireLookup(JobTaskType.values, row.read<String>('task_type')),
  ];
}
