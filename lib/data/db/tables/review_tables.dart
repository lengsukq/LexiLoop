// 列 getter 是 schema 本身，语义由表级文档说明。
// ignore_for_file: public_member_api_docs

/// 复习卡片、复习日志与错词状态三张表。
///
/// 对应旧版 PostgreSQL 迁移 `0000_pg_initial.ts` 的
/// `review_cards` / `review_logs` / `wrong_word_states`。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/converters.dart';
import 'package:lexiloop/data/db/tables/study_tables.dart';
import 'package:lexiloop/data/db/tables/word_tables.dart';
import 'package:lexiloop/domain/enums.dart';

/// FSRS 复习卡片（与 [Words] 一对一）。
///
/// `fsrs_state` 存 ts-fsrs / `package:fsrs` 的 `State` 枚举序号（0–3），
/// 保持与旧版一致以便备份直接导入。
@DataClassName('ReviewCardRow')
class ReviewCards extends Table {
  @override
  String get tableName => 'review_cards';

  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();
  IntColumn get dueAt => integer()();
  RealColumn get stability => real()();
  RealColumn get difficulty => real()();
  IntColumn get elapsedDays => integer()();
  IntColumn get scheduledDays => integer()();
  IntColumn get reps => integer()();
  IntColumn get lapses => integer()();
  IntColumn get fsrsState => integer()();
  IntColumn get learningSteps => integer().withDefault(const Constant(0))();
  IntColumn get lastReviewAt => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{wordId};
}

/// 复习流水（每次作答一行）。
///
/// `client_answer_id` 上的唯一索引是**离线幂等**的核心保证：
/// 网络重试或重复提交时，同一题目不会二次更新 FSRS。
/// 无服务端后这条约束比旧版更重要。
///
/// `card_before_json` / `card_after_json` 保留卡片快照，便于回放与排错。
@DataClassName('ReviewLogRow')
class ReviewLogs extends Table {
  @override
  String get tableName => 'review_logs';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get clientAnswerId => text()();
  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();
  IntColumn get studySessionId => integer().nullable().references(
    StudySessions,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get studySessionItemId => integer().nullable().references(
    StudySessionItems,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get reviewedAt => integer()();
  TextColumn get rating =>
      text().map(const WireEnumConverter<ReviewRating>(ReviewRating.values))();
  TextColumn get questionType =>
      text().map(const WireEnumConverter<QuestionType>(QuestionType.values))();
  TextColumn get presentedPrompt => text().nullable()();
  TextColumn get userAnswer => text().nullable()();
  TextColumn get expectedAnswer => text().nullable()();
  BoolColumn get isCorrect => boolean()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get cardBeforeJson => text().nullable()();
  TextColumn get cardAfterJson => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{clientAnswerId},
  ];
}

/// 错词状态（与 [Words] 一对一）。
///
/// 解除条件为「连续正确 ≥3 个**自然日** 且距上次答错 ≥2 天」，
/// 防止同一天刷题快速解除。`consecutive_correct` 因此按日序数递增，
/// 而非按作答次数。
@DataClassName('WrongWordStateRow')
class WrongWordStates extends Table {
  @override
  String get tableName => 'wrong_word_states';

  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();
  BoolColumn get active => boolean().withDefault(const Constant(false))();
  IntColumn get wrongCount => integer().withDefault(const Constant(0))();
  IntColumn get hardCount => integer().withDefault(const Constant(0))();
  IntColumn get consecutiveCorrect =>
      integer().withDefault(const Constant(0))();
  IntColumn get lastWrongAt => integer().nullable()();
  IntColumn get lastCorrectAt => integer().nullable()();
  IntColumn get resolvedAt => integer().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{wordId};
}
