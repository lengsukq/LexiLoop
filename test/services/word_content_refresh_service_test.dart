/// 有道内容预览与应用服务的测试。
///
/// 钉住四件事：预览**只查有道且不写库**、`FORCE_OVERWRITE` 保留用户资产、
/// `FILL_MISSING_FIELDS` 只做并集、改词条文本的三条校验与审计写入。
/// 全程用假词典，不发任何网络请求。
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/dictionary/content.dart';
import 'package:lexiloop/data/dictionary/provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/dictionary/pipeline.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_content_refresh_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

/// 记录调用参数并返回预置结果的假词典。
class FakeWordLookup implements WordLookup {
  /// 预置结果；为 `null` 时返回一份空内容。
  DictionaryLookupResult? result;

  /// 最近一次调用的入参。
  Map<String, Object?>? lastCall;

  /// 被调用的次数。
  int calls = 0;

  @override
  Future<DictionaryLookupResult> lookup({
    required AppSettings settings,
    required ProviderRequest request,
    required List<String> selectedProviders,
    required ProviderStrategy strategy,
  }) async {
    calls += 1;
    lastCall = <String, Object?>{
      'term': request.term,
      'contentType': request.contentType,
      'sourceLanguage': request.sourceLanguage,
      'targetLanguage': request.targetLanguage,
      'selectedProviders': selectedProviders,
      'strategy': strategy,
    };
    return result ??
        DictionaryLookupResult(
          content: emptyDictionaryContent(),
          attempts: const <ProviderAttemptRecord>[],
          hasTransientFailure: false,
          contentSource: ContentSource.dictionaryOnly,
        );
  }
}

/// 一条释义。
Map<String, Object?> definition(
  String text, {
  String language = 'zh',
  String? partOfSpeech,
  bool isUserEdited = false,
}) => <String, Object?>{
  'language': language,
  'text': text,
  'partOfSpeech': partOfSpeech,
  'source': isUserEdited ? 'manual' : 'youdao',
  'isUserEdited': isUserEdited,
};

/// 一条例句。
Map<String, Object?> example(
  String sentence, {
  String? translation,
  bool isUserAdded = false,
}) => <String, Object?>{
  'sentence': sentence,
  'translation': translation,
  'source': isUserAdded ? 'manual' : 'youdao',
  'isUserAdded': isUserAdded,
};

/// 构造一份抓取结果。
DictionaryLookupResult lookupResult({
  required Map<String, Object?> fields,
  List<ProviderAttemptRecord> attempts = const <ProviderAttemptRecord>[],
}) => DictionaryLookupResult(
  content: DictionaryContent(fields),
  attempts: attempts,
  hasTransientFailure: false,
  contentSource: ContentSource.dictionaryOnly,
);

void main() {
  late AppDatabase db;
  late FakeWordLookup dictionary;
  late WordContentRefreshService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dictionary = FakeWordLookup();
    service = WordContentRefreshService(
      db,
      SettingsService(SettingsDao(db)),
      dictionary,
      WordEditService(db),
    );
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 插入一个词条（含内容），返回 ID。
  Future<int> insertWord({
    String term = 'apple',
    String definitionsJson = '[]',
    String examplesJson = '[]',
    String pronunciationsJson = '[]',
    LexicalContentType contentType = LexicalContentType.word,
    String sourceLanguage = 'en',
    String targetLanguage = 'zh',
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            entryType: EntryType.word,
            contentType: Value<LexicalContentType>(contentType),
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.pending,
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
            pronunciationsJson: Value<String>(pronunciationsJson),
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<WordRow> wordOf(int id) =>
      (db.select(db.words)..where((row) => row.id.equals(id))).getSingle();

  Future<WordContentRow> contentOf(int id) => (db.select(
    db.wordContents,
  )..where((row) => row.wordId.equals(id))).getSingle();

  group('preview', () {
    test('只查有道、走优先回退，且不写库', () async {
      final id = await insertWord();
      final before = await contentOf(id);
      dictionary.result = lookupResult(
        fields: <String, Object?>{
          'definitions': <Object?>[definition('苹果')],
        },
      );

      final preview = await service.preview(wordId: id);

      expect(dictionary.lastCall!['selectedProviders'], <String>['youdao']);
      expect(
        dictionary.lastCall!['strategy'],
        ProviderStrategy.priorityFallback,
      );
      expect(preview.hasContent, isTrue);
      final after = await contentOf(id);
      expect(after.definitionsJson, before.definitionsJson);
      expect(after.contentVersion, before.contentVersion);
      expect(await db.select(db.providerAttempts).get(), isEmpty);
    });

    test('termOverride 非空时用它查询，空串时用库里的文本', () async {
      final id = await insertWord();

      await service.preview(wordId: id, termOverride: '  pear  ');
      expect(dictionary.lastCall!['term'], 'pear');

      await service.preview(wordId: id, termOverride: '   ');
      expect(dictionary.lastCall!['term'], 'apple');
    });

    test('没有内容时 hasContent 为假并带回各次尝试', () async {
      final id = await insertWord();
      dictionary.result = lookupResult(
        fields: <String, Object?>{},
        attempts: <ProviderAttemptRecord>[
          const ProviderAttemptRecord(
            providerId: 'youdao',
            status: ProviderAttemptStatus.failed,
            durationMs: 12,
            fieldsReturned: <String>[],
            errorMessage: '有道返回了空页面',
          ),
        ],
      );

      final preview = await service.preview(wordId: id);

      expect(preview.hasContent, isFalse);
      expect(preview.attempts.single.errorMessage, '有道返回了空页面');
    });

    test('词条不存在时抛「词条不存在」', () async {
      await expectLater(
        service.preview(wordId: 999),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.wordNotFound,
          ),
        ),
      );
      expect(dictionary.calls, 0);
    });
  });

  group('apply', () {
    test('FORCE_OVERWRITE 保留手动编辑的释义与手动添加的例句', () async {
      final id = await insertWord(
        definitionsJson: jsonEncode(<Object?>[
          <String, Object?>{
            'language': 'zh',
            'text': '苹果',
            'isUserEdited': true,
          },
          <String, Object?>{'language': 'zh', 'text': '旧释义'},
        ]),
        examplesJson: jsonEncode(<Object?>[
          <String, Object?>{'sentence': 'I ate an apple.', 'isUserAdded': true},
          <String, Object?>{'sentence': 'Old sentence.'},
        ]),
      );
      dictionary.result = lookupResult(
        fields: <String, Object?>{
          'definitions': <Object?>[definition('新鲜苹果')],
          'examples': <Object?>[example('Fresh sentence.')],
        },
      );
      final preview = await service.preview(wordId: id);

      await service.apply(
        wordId: id,
        fetched: preview.content,
        mode: InitializationMode.forceOverwrite,
        attempts: preview.attempts,
        now: now,
      );

      final content = await contentOf(id);
      expect(content.definitionsJson, contains('苹果'));
      expect(content.definitionsJson, contains('新鲜苹果'));
      expect(
        content.definitionsJson,
        isNot(contains('旧释义')),
        reason: '非用户编辑的旧释义应被覆盖掉',
      );
      expect(content.examplesJson, contains('I ate an apple.'));
      expect(content.examplesJson, contains('Fresh sentence.'));
      expect(content.examplesJson, isNot(contains('Old sentence.')));
    });

    test('FILL_MISSING_FIELDS 保留已有内容并只做并集', () async {
      final id = await insertWord(
        definitionsJson: '[{"language":"zh","text":"旧释义"}]',
        examplesJson: '[{"sentence":"Old sentence."}]',
      );
      dictionary.result = lookupResult(
        fields: <String, Object?>{
          'definitions': <Object?>[definition('新释义')],
          'examples': <Object?>[example('New sentence.')],
        },
      );
      final preview = await service.preview(wordId: id);

      await service.apply(
        wordId: id,
        fetched: preview.content,
        mode: InitializationMode.fillMissingFields,
        attempts: preview.attempts,
        now: now,
      );

      final content = await contentOf(id);
      expect(content.definitionsJson, contains('旧释义'));
      expect(content.definitionsJson, contains('新释义'));
      expect(content.examplesJson, contains('Old sentence.'));
      expect(content.examplesJson, contains('New sentence.'));
    });

    test('改词条文本时同时写入 term 与 normalized_term', () async {
      final id = await insertWord();

      await service.apply(
        wordId: id,
        fetched: emptyDictionaryContent(),
        mode: InitializationMode.fillMissingFields,
        attempts: const <ProviderAttemptRecord>[],
        now: now,
        newTerm: '  Apples  ',
      );

      final word = await wordOf(id);
      expect(word.term, 'apples');
      expect(word.normalizedTerm, 'apples');
      expect(word.updatedAt, now);
    });

    test('空词条文本被拒绝', () async {
      final id = await insertWord();
      await expectLater(
        service.apply(
          wordId: id,
          fetched: emptyDictionaryContent(),
          mode: InitializationMode.fillMissingFields,
          attempts: const <ProviderAttemptRecord>[],
          now: now,
          newTerm: '   ',
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.termRequired,
          ),
        ),
      );
      expect((await wordOf(id)).term, 'apple');
    });

    test('超长词条文本被拒绝', () async {
      final id = await insertWord();
      await expectLater(
        service.apply(
          wordId: id,
          fetched: emptyDictionaryContent(),
          mode: InitializationMode.fillMissingFields,
          attempts: const <ProviderAttemptRecord>[],
          now: now,
          newTerm: 'a' * (termMaxLength + 1),
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

    test('改成已有词条时被拒绝且不落库', () async {
      final id = await insertWord();
      await insertWord(term: 'banana');

      await expectLater(
        service.apply(
          wordId: id,
          fetched: emptyDictionaryContent(),
          mode: InitializationMode.fillMissingFields,
          attempts: const <ProviderAttemptRecord>[],
          now: now,
          newTerm: 'Banana',
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

    test('newTerm 为 null 时不改词条文本', () async {
      final id = await insertWord();
      await service.apply(
        wordId: id,
        fetched: emptyDictionaryContent(),
        mode: InitializationMode.fillMissingFields,
        attempts: const <ProviderAttemptRecord>[],
        now: now,
      );
      expect((await wordOf(id)).term, 'apple');
    });

    test('数据源调用记录写入 provider_attempts 且不挂任务', () async {
      final id = await insertWord();
      dictionary.result = lookupResult(
        fields: <String, Object?>{
          'definitions': <Object?>[definition('苹果')],
        },
        attempts: <ProviderAttemptRecord>[
          const ProviderAttemptRecord(
            providerId: 'youdao',
            status: ProviderAttemptStatus.success,
            durationMs: 88,
            fieldsReturned: <String>['definitions'],
          ),
        ],
      );
      final preview = await service.preview(wordId: id);

      await service.apply(
        wordId: id,
        fetched: preview.content,
        mode: InitializationMode.fillMissingFields,
        attempts: preview.attempts,
        now: now,
      );

      final attempts = await db.select(db.providerAttempts).get();
      expect(attempts, hasLength(1));
      expect(attempts.single.providerId, 'youdao');
      expect(attempts.single.initializationJobId, isNull);
      expect(attempts.single.wordId, id);
      final content = await contentOf(id);
      expect(content.providerMetadataJson, contains('youdao'));
      expect(content.contentSource, ContentSource.dictionaryOnly);
      expect(content.initializedAt, now);
    });

    test('按内容重算初始化状态：有释义有例句为 READY', () async {
      final id = await insertWord();
      await service.apply(
        wordId: id,
        fetched: DictionaryContent(<String, Object?>{
          'definitions': <Object?>[definition('苹果')],
          'examples': <Object?>[example('An apple.')],
        }),
        mode: InitializationMode.fillMissingFields,
        attempts: const <ProviderAttemptRecord>[],
        now: now,
      );
      expect(
        (await wordOf(id)).initializationStatus,
        InitializationStatus.ready,
      );
    });

    test('按内容重算初始化状态：只有释义为 PARTIAL', () async {
      final id = await insertWord();
      await service.apply(
        wordId: id,
        fetched: DictionaryContent(<String, Object?>{
          'definitions': <Object?>[definition('苹果')],
        }),
        mode: InitializationMode.fillMissingFields,
        attempts: const <ProviderAttemptRecord>[],
        now: now,
      );
      expect(
        (await wordOf(id)).initializationStatus,
        InitializationStatus.partial,
      );
    });

    test('按内容重算初始化状态：什么都没有为 FAILED', () async {
      final id = await insertWord();
      await service.apply(
        wordId: id,
        fetched: emptyDictionaryContent(),
        mode: InitializationMode.fillMissingFields,
        attempts: const <ProviderAttemptRecord>[],
        now: now,
      );
      expect(
        (await wordOf(id)).initializationStatus,
        InitializationStatus.failed,
      );
    });
  });

  group('hasAnyDictionaryContent', () {
    test('摘要译文也算内容', () {
      expect(
        hasAnyDictionaryContent(
          const DictionaryContent(<String, Object?>{
            'summary': <String, Object?>{'translation': '苹果'},
          }),
        ),
        isTrue,
      );
    });

    test('只有易混词不算内容（与旧版 hasAnyContent 一致）', () {
      expect(
        hasAnyDictionaryContent(
          const DictionaryContent(<String, Object?>{
            'confusedWords': <Object?>[
              <String, Object?>{'word': 'apply'},
            ],
          }),
        ),
        isFalse,
      );
    });

    test('空内容为假', () {
      expect(hasAnyDictionaryContent(emptyDictionaryContent()), isFalse);
    });
  });
}
