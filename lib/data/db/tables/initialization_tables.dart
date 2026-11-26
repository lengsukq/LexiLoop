// 列 getter 是 schema 本身，语义由表级文档说明。
// ignore_for_file: public_member_api_docs

/// 初始化任务与数据源调用记录两张表。
///
/// 对应旧版 PostgreSQL 迁移 `0000_pg_initial.ts` 的
/// `initialization_jobs` / `provider_attempts`。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/converters.dart';
import 'package:lexiloop/data/db/tables/word_tables.dart';
import 'package:lexiloop/domain/enums.dart';

/// 词条初始化任务队列。
///
/// **部分唯一索引**：`(word_id, task_type) WHERE status IN ('QUEUED','RUNNING')`
/// 保证同一词条同一任务类型最多只有一个活跃任务。Drift 的 `uniqueKeys`
/// 只能表达全表唯一，无法表达带 WHERE 的部分索引，因此该索引在
/// `AppDatabase.beforeOpen` 中用 `customStatement` 手工创建。
/// 插入冲突时捕获 UNIQUE 并退化为「升级已有任务」。
///
/// `locked_at` / `locked_by` 在单进程下主要用于崩溃恢复：
/// 应用启动时把所有 `RUNNING` 重置为 `QUEUED`。
@DataClassName('InitializationJobRow')
class InitializationJobs extends Table {
  @override
  String get tableName => 'initialization_jobs';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();
  TextColumn get taskType => text()
      .map(const WireEnumConverter<JobTaskType>(JobTaskType.values))
      .withDefault(const Constant('INITIALIZE'))();
  TextColumn get mode => text().map(
    const WireEnumConverter<InitializationMode>(InitializationMode.values),
  )();
  TextColumn get requestedFieldsJson => text().nullable()();
  TextColumn get requestedProvidersJson => text().nullable()();
  TextColumn get providerStrategy => text()
      .map(const WireEnumConverter<ProviderStrategy>(ProviderStrategy.values))
      .withDefault(const Constant('PARALLEL_MERGE'))();
  TextColumn get status => text()
      .map(
        const WireEnumConverter<InitializationStatus>(
          InitializationStatus.values,
        ),
      )
      .withDefault(const Constant('QUEUED'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get maxAttempts => integer().withDefault(const Constant(5))();
  IntColumn get availableAt => integer().nullable()();
  IntColumn get lockedAt => integer().nullable()();
  TextColumn get lockedBy => text().nullable()();
  TextColumn get lastError => text().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get completedAt => integer().nullable()();
}

/// 数据源单次调用的审计记录。
///
/// `metadata_json` 记录模型、提示词版本、Schema 版本、token 用量与质量分，
/// 用于排查「AI 返回了内容但被质量门丢弃」这类问题。
///
/// `provider_id` **不加 CHECK**：值域随接入的数据源变化，
/// 且 AI 类记录带 `ai:<model>` 前缀。
@DataClassName('ProviderAttemptRow')
class ProviderAttempts extends Table {
  @override
  String get tableName => 'provider_attempts';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get initializationJobId => integer().nullable().references(
    InitializationJobs,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get wordId =>
      integer().references(Words, #id, onDelete: KeyAction.cascade)();
  TextColumn get providerId => text()();
  TextColumn get status => text().map(
    const WireEnumConverter<ProviderAttemptStatus>(
      ProviderAttemptStatus.values,
    ),
  )();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get fieldsReturnedJson => text().nullable()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get metadataJson => text().nullable()();
  IntColumn get createdAt => integer()();
}
