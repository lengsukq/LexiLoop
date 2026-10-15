/// 翻译补全链路（`EXAMPLE_TRANSLATIONS`）的测试。
///
/// 旧版 `translateMissingWordContent` 依次补释义 → 摘要 → 例句译文，本版
/// 把它接进同一个补充任务。这一组测试钉住三件事：
/// 三段的顺序、写库前**重新读一次最新 JSON**（不覆盖并发写入）、
/// 以及已经翻好的部分不再重复送模型。
///
/// 全部联网动作经由 `HttpFetcher` 注入假客户端，测试完全离线。
///
/// **为什么放在 `test/features/word_detail/`**：这一块属于「词条详情 / 词库」
/// 工作流的写操作（详情页的「AI 翻译释义」按钮触发它），而该工作流只被
/// 授权在 `test/features/word_detail/**`、`test/features/words/**` 与三个
/// 具名 service 测试文件下新建测试。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/http_fetcher.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/initialization/supplemental_tasks.dart';
import 'package:lexiloop/services/llm/llm_config.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../../data/dictionary/fake_http_fetcher.dart';

/// 构造一个 provider 的存储形状。
Map<String, Object?> providerJson({
  String id = 'p1',
  String baseUrl = 'https://a.example/v1',
  String apiKey = 'sk-test',
  List<String> models = const <String>['m1'],
  String defaultModel = 'm1',
}) => <String, Object?>{
  'id': id,
  'name': id,
  'apiType': 'openai',
  'baseUrl': baseUrl,
  'apiKey': apiKey,
  'models': models,
  'defaultModel': defaultModel,
};

/// 一份可用的 LLM 配置。
Map<String, Object?> llmConfig() => <String, Object?>{
  'providers': <Object?>[providerJson()],
  'ai': <String, Object?>{'enabled': true, 'providerId': 'p1', 'model': 'm1'},
};

/// 把一段文本包成 OpenAI 兼容的成功响应。
HttpFetchResponse chatResponse(Map<String, Object?> payload) =>
    HttpFetchResponse(
      statusCode: 200,
      body: jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': jsonEncode(payload)},
          },
        ],
      }),
    );

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late int now;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
    await settings.update(<String, Object?>{
      llmConfigSettingsKey: llmConfig(),
    }, now: now);
  });

  tearDown(() async {
    await db.close();
  });

  /// 插入一个待翻译的词条，返回 ID。
  Future<int> insertWord({
    String definitionsJson = '[{"language":"en","text":"a fruit"}]',
    String summaryJson = '{"shortDefinition":"a round fruit"}',
    String examplesJson = '[{"sentence":"An apple."}]',
    String sourceLanguage = 'en',
    String targetLanguage = 'zh',
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: 'apple',
            normalizedTerm: 'apple',
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            entryType: EntryType.word,
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
            summaryJson: Value<String>(summaryJson),
            examplesJson: Value<String>(examplesJson),
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<WordContentRow> contentOf(int id) => (db.select(
    db.wordContents,
  )..where((row) => row.wordId.equals(id))).getSingle();

  /// 释义、摘要、例句三段各自的假响应。
  FakeHttpFetcher threeStageFetcher({Future<void> Function()? onDefinitions}) {
    var call = 0;
    return FakeHttpFetcher((url, body) async {
      call += 1;
      if (call == 1) {
        await onDefinitions?.call();
        return chatResponse(<String, Object?>{
          'term': 'apple',
          'translations': <Object?>[
            <String, Object?>{'text': 'a fruit', 'translation': '一种水果'},
          ],
        });
      }
      if (call == 2) {
        return chatResponse(<String, Object?>{
          'term': 'apple',
          'translation': '苹果的短释义',
        });
      }
      return chatResponse(<String, Object?>{
        'term': 'apple',
        'translations': <Object?>[
          <String, Object?>{'sentence': 'An apple.', 'translation': '一个苹果。'},
        ],
      });
    });
  }

  test('依次补齐缺失的释义、摘要与例句译文', () async {
    final id = await insertWord();
    final fetcher = threeStageFetcher();
    final runner = LlmSupplementalTaskRunner(db, settings, fetcher);

    await runner.run(
      taskType: JobTaskType.exampleTranslations,
      wordId: id,
      now: now,
    );

    final content = await contentOf(id);
    expect(content.definitionsJson, contains('一种水果'));
    expect(content.summaryJson, contains('苹果的短释义'));
    expect(content.examplesJson, contains('一个苹果。'));
    expect(fetcher.calls, hasLength(3));
    // 顺序：definitions → summary → examples。
    expect(fetcher.bodies[0], contains('a fruit'));
    expect(fetcher.bodies[1], contains('a round fruit'));
    expect(fetcher.bodies[2], contains('An apple.'));
  });

  test('译文带上义项编号与来源标记', () async {
    final id = await insertWord(
      definitionsJson: jsonEncode(<Object?>[
        <String, Object?>{
          'language': 'en',
          'text': 'a fruit',
          'senseId': 'apple_n_fruit',
          'register': 'NEUTRAL',
          'usageNote': '可数',
        },
      ]),
    );
    final runner = LlmSupplementalTaskRunner(db, settings, threeStageFetcher());

    await runner.run(
      taskType: JobTaskType.exampleTranslations,
      wordId: id,
      now: now,
    );

    final definitions =
        jsonDecode((await contentOf(id)).definitionsJson) as List<Object?>;
    final translated = definitions.cast<Map<String, Object?>>().firstWhere(
      (item) => item['text'] == '一种水果',
    );
    expect(translated['language'], 'zh');
    expect(translated['isUserEdited'], isFalse);
    expect(translated['source'], 'ai:translation:m1');
    expect(translated['senseId'], 'apple_n_fruit');
    expect(translated['register'], 'NEUTRAL');
    expect(translated['usageNote'], '可数');
  });

  test('写库前重读最新 JSON，不覆盖并发写入的释义', () async {
    final id = await insertWord();
    // 模型还在返回的路上时，用户手工加了一条释义（模拟并发写入）。
    final fetcher = threeStageFetcher(
      onDefinitions: () async {
        final concurrent = jsonEncode(<Object?>[
          <String, Object?>{'language': 'en', 'text': 'a fruit'},
          <String, Object?>{
            'language': 'zh',
            'text': '并发写入的释义',
            'isUserEdited': true,
          },
        ]);
        await db.customStatement(
          'UPDATE word_contents SET definitions_json = ? WHERE word_id = ?',
          <Object?>[concurrent, id],
        );
      },
    );
    final runner = LlmSupplementalTaskRunner(db, settings, fetcher);

    await runner.run(
      taskType: JobTaskType.exampleTranslations,
      wordId: id,
      now: now,
    );

    final content = await contentOf(id);
    expect(content.definitionsJson, contains('并发写入的释义'));
    expect(content.definitionsJson, contains('一种水果'));
  });

  test('释义已够数时不调用模型', () async {
    final id = await insertWord(
      definitionsJson: jsonEncode(<Object?>[
        <String, Object?>{'language': 'en', 'text': 'a fruit'},
        <String, Object?>{'language': 'zh', 'text': '水果'},
        <String, Object?>{'language': 'zh', 'text': '一种水果'},
      ]),
      summaryJson: '{"shortDefinition":"a round fruit","translation":"苹果"}',
      examplesJson: '[{"sentence":"An apple.","translation":"一个苹果。"}]',
    );
    final fetcher = threeStageFetcher();
    final runner = LlmSupplementalTaskRunner(db, settings, fetcher);

    await runner.run(
      taskType: JobTaskType.exampleTranslations,
      wordId: id,
      now: now,
    );

    expect(fetcher.calls, isEmpty);
  });

  test('目标语言与源语言相同时不做释义翻译', () async {
    final id = await insertWord(
      targetLanguage: 'en',
      summaryJson: '{"shortDefinition":"a round fruit","translation":"苹果"}',
      examplesJson: '[{"sentence":"An apple.","translation":"一个苹果。"}]',
    );
    final fetcher = threeStageFetcher();
    final runner = LlmSupplementalTaskRunner(db, settings, fetcher);

    await runner.run(
      taskType: JobTaskType.exampleTranslations,
      wordId: id,
      now: now,
    );

    expect(fetcher.calls, isEmpty);
  });

  test('模型返回的译文与原文对不上时丢弃该条', () async {
    final id = await insertWord();
    var call = 0;
    final fetcher = FakeHttpFetcher((url, body) async {
      call += 1;
      if (call == 1) {
        return chatResponse(<String, Object?>{
          'term': 'apple',
          'translations': <Object?>[
            <String, Object?>{'text': '对不上的原文', 'translation': '不该写进去'},
          ],
        });
      }
      if (call == 2) {
        return chatResponse(<String, Object?>{
          'term': 'apple',
          'translation': '苹果的短释义',
        });
      }
      return chatResponse(<String, Object?>{
        'term': 'apple',
        'translations': <Object?>[
          <String, Object?>{'sentence': 'An apple.', 'translation': '一个苹果。'},
        ],
      });
    });
    final runner = LlmSupplementalTaskRunner(db, settings, fetcher);

    await runner.run(
      taskType: JobTaskType.exampleTranslations,
      wordId: id,
      now: now,
    );

    final content = await contentOf(id);
    expect(content.definitionsJson, isNot(contains('不该写进去')));
    // 释义这一条配不上不影响后两步。
    expect(content.summaryJson, contains('苹果的短释义'));
    expect(content.examplesJson, contains('一个苹果。'));
  });
}
