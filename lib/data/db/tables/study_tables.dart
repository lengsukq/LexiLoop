// 列 getter 是 schema 本身，语义由表级文档说明。
// ignore_for_file: public_member_api_docs

/// 学习会话与会话题目两张表。
///
/// 对应旧版 PostgreSQL 迁移 `0000_pg_initial.ts` 的
/// `study_sessions` / `study_session_items`。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/converters.dart';
import 'package:lexiloop/data/db/tables/word_tables.dart';
import 'package:lexiloop/domain/enums.dart';

/// 学习会话。
///
/// **与旧版的差异**：旧版 PG 的 CHECK 只允许 6 个 `session_type`，
/// 但代码实际会写入 `SENTENCE_REVIEW` 与 `AI_RECOMMENDED`，属源端缺陷
/// （在 PostgreSQL 上会被约束拒绝）。本版按 [StudyMode] 的 8 个值实现。
///
/// `source_type` **不加 CHECK**：它承载动态值（如 `GAME_${mode}` 前缀），
/// 值域会随游戏模式增加而变。
@DataClassName('StudySessionRow')
class StudySessions extends Table {
  @override
  String get tableName => 'study_sessions';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionType =>
      text().map(const WireEnumConverter<StudyMode>(StudyMode.values))();
  TextColumn get sourceType => text().nullable()();
  IntColumn get startedAt => integer()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get plannedCount => integer().withDefault(const Constant(0))();
  IntColumn get completedCount => integer().withDefault(const Constant(0))();
  IntColumn get correctCount => integer().withDefault(const Constant(0))();
  IntColumn get wrongCount => integer().withDefault(const Constant(0))();
  IntColumn get skippedCount => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get createdAt => integer()();
}

/// 会话题目项。
///
/// `position` **必须是 double**：自适应插题会在两项之间取中点插入，
/// 整数位置无法表达。对应旧版迁移 `0001_position_float`。
///
/// 浮点位置配合 `UNIQUE(study_session_id, position)` 有相等冲突的隐患，
/// 因此位置生成统一走 `sessionItemPositionStep`（确定性步长 0.5），
/// 不再使用中点法。
///
/// `skip_reason` **不加 CHECK**：新增原因会改变历史数据的语义，
/// 旧版 `NOT IN ('SESSION_EXPIRED','PROGRESS_RESET')` 这类判断依赖它。
@DataClassName('StudySessionItemRow')
class StudySessionItems extends Table {
  @override
  String get tableName => 'study_session_items';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get studySessionId =>
      integer().references(StudySessions, #id, onDelete: KeyAction.cascade)();
  RealColumn get position => real()();
  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();
  TextColumn get taskType => text().map(
    const WireEnumConverter<StudyTaskType>(StudyTaskType.values),
  )();
  TextColumn get questionType =>
      text().map(const WireEnumConverter<QuestionType>(QuestionType.values))();
  TextColumn get status => text()
      .map(const WireEnumConverter<StudyItemStatus>(StudyItemStatus.values))
      .withDefault(const Constant('PENDING'))();
  IntColumn get answeredAt => integer().nullable()();
  TextColumn get skipReason => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
    <Column<Object>>{studySessionId, position},
  ];
}
