// 列 getter 是 schema 本身，其语义由表级文档与 docs/ARCHITECTURE_BASELINE.md
// 的原始迁移共同说明；逐列写 `/// 创建时间。` 属于「注释复述代码」的反模式。
// ignore_for_file: public_member_api_docs

/// 词条、词条内容与复习统计三张表。
///
/// 对应旧版 PostgreSQL 迁移 `0000_pg_initial.ts` 的 `words` / `word_contents`
/// 与 `0001_word_review_stats.ts` 的 `word_review_stats`。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/converters.dart';
import 'package:lexiloop/domain/enums.dart';

/// 词条主表。
///
/// 唯一身份是 `(normalized_term, source_language, target_language)`，
/// 与旧版的 `words_identity_unique` 一致。
///
/// `entry_type` 只有 WORD/PHRASE 两值（旧版如此，句子在 `content_type` 中区分），
/// 因此句子的 `entry_type` 存为 PHRASE、`content_type` 存为 SENTENCE。
@DataClassName('WordRow')
class Words extends Table {
  @override
  String get tableName => 'words';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get term => text()();
  TextColumn get normalizedTerm => text()();
  TextColumn get sourceLanguage => text()();
  TextColumn get targetLanguage => text()();
  TextColumn get sourceLanguageName => text().nullable()();
  TextColumn get targetLanguageName => text().nullable()();
  TextColumn get entryType =>
      text().map(const WireEnumConverter<EntryType>(EntryType.values))();
  TextColumn get contentType => text()
      .map(
        const WireEnumConverter<LexicalContentType>(LexicalContentType.values),
      )
      .withDefault(const Constant('WORD'))();
  IntColumn get sourceCreatedAt => integer().nullable()();
  TextColumn get initializationStatus => text()
      .map(
        const WireEnumConverter<InitializationStatus>(
          InitializationStatus.values,
        ),
      )
      .withDefault(const Constant('PENDING'))();
  TextColumn get masteryLevel => text()
      .map(const WireEnumConverter<MasteryLevel>(MasteryLevel.values))
      .withDefault(const Constant('NEW'))();
  IntColumn get masteryScore => integer().withDefault(const Constant(0))();
  BoolColumn get isSuspended => boolean().withDefault(const Constant(false))();
  TextColumn get userNote => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{normalizedTerm, sourceLanguage, targetLanguage},
  ];
}

/// 词条内容扩展表（与 [Words] 一对一）。
///
/// 16 个 `*_json` 列**保持 TEXT 不拆表**：这些数组是低基数、写多读少、
/// 不被 SQL 检索的载荷；真正需要检索的字段（语言、状态、掌握度）已全部
/// 是独立列。保持整块 JSON 也让旧备份导入退化为 `jsonDecode` 直接写列。
///
/// `content_version` 在每次写入时自增，用于本地并发冲突提示——
/// 因此**不能用 `insertOrReplace`**，会丢掉自增语义。
@DataClassName('WordContentRow')
class WordContents extends Table {
  @override
  String get tableName => 'word_contents';

  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();
  TextColumn get definitionsJson => text().withDefault(const Constant('[]'))();
  TextColumn get pronunciationsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get examplesJson => text().withDefault(const Constant('[]'))();
  TextColumn get phrasesJson => text().withDefault(const Constant('[]'))();
  TextColumn get formsJson => text().withDefault(const Constant('[]'))();
  TextColumn get synonymsJson => text().withDefault(const Constant('[]'))();
  TextColumn get antonymsJson => text().withDefault(const Constant('[]'))();
  TextColumn get wordFamilyJson => text().withDefault(const Constant('[]'))();
  TextColumn get confusedWordsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get rootsJson => text().withDefault(const Constant('[]'))();
  TextColumn get affixesJson => text().withDefault(const Constant('[]'))();
  TextColumn get summaryJson => text().withDefault(
    const Constant(
      '{"shortDefinition":null,"translation":null,'
      '"cefrLevel":null,"frequency":null}',
    ),
  )();
  TextColumn get learningJson => text().withDefault(
    const Constant(
      '{"pronunciationTip":null,"mnemonic":null,"commonMistakes":[]}',
    ),
  )();
  TextColumn get sentenceAnalysisJson => text().withDefault(
    const Constant(
      '{"grammarPattern":null,"grammarExplanation":null,"grammarNotes":[],'
      '"keyExpressions":[],"similarExamples":[],"variations":[]}',
    ),
  )();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get providerMetadataJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get contentSource => text()
      .map(const WireEnumConverter<ContentSource>(ContentSource.values))
      .withDefault(const Constant('MIXED'))();
  IntColumn get contentVersion => integer().withDefault(const Constant(1))();
  IntColumn get initializedAt => integer().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{wordId};
}

/// 词条复习统计（物化计数，避免每次聚合 `review_logs`）。
///
/// `recent_*` 三列是队列排序的加权输入，窗口固定为 14 天。
@DataClassName('WordReviewStatRow')
class WordReviewStats extends Table {
  @override
  String get tableName => 'word_review_stats';

  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();
  IntColumn get totalReviews => integer().withDefault(const Constant(0))();
  IntColumn get correctReviews => integer().withDefault(const Constant(0))();

  // 这四列必须显式指定列名：Drift 的驼峰转下划线不会在数字前插下划线
  // （`recentAgain30d` → `recent_again30d`），而旧版 PG 用的是
  // `recent_again_30d`。不一致会破坏备份的直接列映射。
  IntColumn get recentAgain30d =>
      integer().named('recent_again_30d').withDefault(const Constant(0))();
  IntColumn get recentAgain14d =>
      integer().named('recent_again_14d').withDefault(const Constant(0))();
  IntColumn get recentWrong14d =>
      integer().named('recent_wrong_14d').withDefault(const Constant(0))();
  IntColumn get recentHard14d =>
      integer().named('recent_hard_14d').withDefault(const Constant(0))();

  IntColumn get totalDurationMs => integer().withDefault(const Constant(0))();
  IntColumn get durationCount => integer().withDefault(const Constant(0))();
  IntColumn get lastReviewedAt => integer().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{wordId};
}
