// 列 getter 是 schema 本身，语义由表级文档说明。
// ignore_for_file: public_member_api_docs

/// 导入批次与导入行两张表。
///
/// 对应旧版 PostgreSQL 迁移 `0000_pg_initial.ts` 的
/// `import_batches` / `import_rows`。
///
/// **已删除的第三张表 `import_previews`**：旧版用它在「预览 → 提交」之间
/// 持久化 30 分钟有效的预览令牌。纯本地应用改存内存 `Map` + `Timer`——
/// 进程被杀后重新选文件即可，不值得为此留一张表。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/converters.dart';
import 'package:lexiloop/data/db/tables/word_tables.dart';
import 'package:lexiloop/domain/enums.dart';

/// 导入批次。
///
/// `rollback_eligibility` 的判定依赖 `import_mode`、`reset_learning_progress`
/// 与 `existing_words` 三列：只有「纯新增 + 未重置学习进度 + 未改动已有词条」
/// 的批次才允许无损撤销。
@DataClassName('ImportBatchRow')
class ImportBatches extends Table {
  @override
  String get tableName => 'import_batches';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get filename => text()();
  TextColumn get fileHash => text().nullable()();
  TextColumn get importMode =>
      text().map(const WireEnumConverter<ImportMode>(ImportMode.values))();
  BoolColumn get resetLearningProgress =>
      boolean().withDefault(const Constant(false))();
  IntColumn get totalRows => integer().withDefault(const Constant(0))();
  IntColumn get validRows => integer().withDefault(const Constant(0))();
  IntColumn get invalidRows => integer().withDefault(const Constant(0))();
  IntColumn get duplicateRows => integer().withDefault(const Constant(0))();
  IntColumn get createdWords => integer().withDefault(const Constant(0))();
  IntColumn get existingWords => integer().withDefault(const Constant(0))();
  IntColumn get queuedInitializations =>
      integer().withDefault(const Constant(0))();
  TextColumn get status => text()
      .map(const WireEnumConverter<ImportBatchStatus>(ImportBatchStatus.values))
      .withDefault(const Constant('PENDING'))();
  IntColumn get createdAt => integer()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get rolledBackAt => integer().nullable()();
}

/// 导入行（逐行留痕，用于统计与撤销）。
///
/// `word_id` 用 `ON DELETE SET NULL`：撤销批次会删除词条，
/// 但导入行的审计记录应当保留。
@DataClassName('ImportRowRow')
class ImportRows extends Table {
  @override
  String get tableName => 'import_rows';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get importBatchId =>
      integer().references(ImportBatches, #id, onDelete: KeyAction.cascade)();
  IntColumn get rowNumber => integer()();
  TextColumn get rawJson => text().nullable()();
  TextColumn get normalizedTerm => text().nullable()();
  IntColumn get wordId => integer().nullable().references(
    Words,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get status => text().map(
    const WireEnumConverter<ImportRowStatus>(ImportRowStatus.values),
  )();
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get metadataJson => text().nullable()();
  IntColumn get createdAt => integer()();
}
