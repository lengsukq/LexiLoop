/// LexiLoop 本地数据库。
///
/// 15 张表，对应旧版 PostgreSQL 的 18 张减去 3 张服务端专用表
/// （`worker_heartbeats`、`import_previews`、`manual_previews`）。
///
/// **索引与约束的创建位置**：常规索引与那条 Drift 无法表达的部分唯一索引
/// 统一在 `beforeOpen` 里用 `customStatement` 建立。集中一处便于与旧版迁移
/// 逐条对照审计，且 `IF NOT EXISTS` 保证重复打开幂等。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/converters.dart';
import 'package:lexiloop/data/db/database_connection.dart';
import 'package:lexiloop/data/db/tables/import_tables.dart';
import 'package:lexiloop/data/db/tables/initialization_tables.dart';
import 'package:lexiloop/data/db/tables/misc_tables.dart';
import 'package:lexiloop/data/db/tables/review_tables.dart';
import 'package:lexiloop/data/db/tables/study_tables.dart';
import 'package:lexiloop/data/db/tables/word_tables.dart';
// 生成的 part 文件会引用这些枚举类型，必须在此导入。
import 'package:lexiloop/domain/enums.dart';

part 'database.g.dart';

/// 原生端数据库文件名。
///
/// Web 端不用它：浏览器存储（IndexedDB / OPFS）的条目名见
/// `database_connection_web.dart` 的 `webDatabaseName`。
const String databaseFileName = 'lexiloop.sqlite';

/// 索引与约束的 DDL。
///
/// 与旧版 `src/db/migrations/pg/*.ts` 的索引逐条对应；
/// PostgreSQL 特有语法已按 SQLite 调整。
///
/// 写成单块 DDL 再按 `;` 拆分（而非字符串列表），是为了与原始迁移
/// 保持同一形态，便于逐条对照审计。
const String _indexDdl = """
CREATE INDEX IF NOT EXISTS words_status_idx ON words(initialization_status);
CREATE INDEX IF NOT EXISTS words_mastery_idx ON words(mastery_level);
CREATE INDEX IF NOT EXISTS words_created_idx ON words(created_at);
CREATE INDEX IF NOT EXISTS study_sessions_started_idx ON study_sessions(started_at);
CREATE INDEX IF NOT EXISTS study_sessions_completed_idx ON study_sessions(completed_at, started_at);
CREATE INDEX IF NOT EXISTS study_sessions_source_idx ON study_sessions(source_type, completed_at, started_at);
CREATE INDEX IF NOT EXISTS study_session_items_session_idx ON study_session_items(study_session_id, status);
CREATE INDEX IF NOT EXISTS study_session_items_word_status_idx ON study_session_items(word_id, status);
CREATE INDEX IF NOT EXISTS study_session_items_status_answered_idx ON study_session_items(status, answered_at);
CREATE INDEX IF NOT EXISTS study_session_items_word_idx ON study_session_items(word_id, status, answered_at);
CREATE INDEX IF NOT EXISTS review_cards_due_idx ON review_cards(due_at);
CREATE INDEX IF NOT EXISTS review_logs_word_idx ON review_logs(word_id, reviewed_at);
CREATE INDEX IF NOT EXISTS review_logs_session_idx ON review_logs(study_session_id);
CREATE INDEX IF NOT EXISTS review_logs_reviewed_idx ON review_logs(reviewed_at);
CREATE INDEX IF NOT EXISTS wrong_word_states_active_idx ON wrong_word_states(active, updated_at);
CREATE INDEX IF NOT EXISTS wrong_word_states_decay_idx ON wrong_word_states(active, last_wrong_at);
CREATE INDEX IF NOT EXISTS import_batches_created_idx ON import_batches(created_at);
CREATE INDEX IF NOT EXISTS import_rows_batch_idx ON import_rows(import_batch_id, row_number);
CREATE INDEX IF NOT EXISTS initialization_jobs_status_idx ON initialization_jobs(status, available_at, priority);
CREATE INDEX IF NOT EXISTS initialization_jobs_word_idx ON initialization_jobs(word_id);
CREATE INDEX IF NOT EXISTS initialization_jobs_task_type_idx ON initialization_jobs(task_type, status, available_at, priority);
CREATE INDEX IF NOT EXISTS provider_attempts_job_idx ON provider_attempts(initialization_job_id);
CREATE INDEX IF NOT EXISTS provider_attempts_word_idx ON provider_attempts(word_id);
CREATE INDEX IF NOT EXISTS daily_ai_suggestions_generated_idx ON daily_ai_suggestions(generated_at);
CREATE INDEX IF NOT EXISTS game_high_scores_mode_score_idx ON game_high_scores(game_mode, score DESC, played_at ASC);
-- ★ 部分唯一索引：Drift 的 uniqueKeys 只能表达全表唯一，无法表达带 WHERE
--   的部分索引，必须手工建立。语义：同一词条的同一任务类型最多一个活跃任务。
CREATE UNIQUE INDEX IF NOT EXISTS initialization_jobs_active_word_task_unique
  ON initialization_jobs(word_id, task_type) WHERE status IN ('QUEUED','RUNNING');
""";

/// 拆出可逐条执行的语句。
List<String> get _indexStatements => _indexDdl
    .split(';')
    .map((statement) => statement.trim())
    .where((statement) => statement.isNotEmpty)
    .toList(growable: false);

/// LexiLoop 的本地数据库。
@DriftDatabase(
  tables: <Type>[
    Words,
    WordContents,
    WordReviewStats,
    StudySessions,
    StudySessionItems,
    ReviewCards,
    ReviewLogs,
    WrongWordStates,
    ImportBatches,
    ImportRows,
    InitializationJobs,
    ProviderAttempts,
    DailyAiSuggestions,
    GameHighScores,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 以给定的查询执行器打开数据库。
  new(super.e);

  /// 打开默认位置的数据库。
  ///
  /// 连接本身由 `database_connection.dart` 按平台条件导入：原生端是应用支持
  /// 目录下的 SQLite 文件（`LazyDatabase`），Web 端是 drift 的 WASM 实现
  /// （`DatabaseConnection.delayed`）。两者都是延迟打开，因此本工厂保持同步。
  factory open() => AppDatabase(openAppDatabaseExecutor());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        await m.createAll();
        await _createIndexes();
      },
      onUpgrade: (m, from, to) async {
        // 尚无历史版本；后续 schema 变更在此按版本分支迁移。
        await _createIndexes();
      },
      beforeOpen: (details) async {
        // SQLite 默认**不开启**外键约束，不显式打开会导致
        // 删除 words 时留下孤儿的 initialization_jobs / provider_attempts。
        await customStatement('PRAGMA foreign_keys = ON');
        // 索引与部分唯一索引放在这里：onCreate 只在建库时跑一次，
        // 而 beforeOpen 每次打开都会执行，能覆盖旧库补索引的场景。
        await _createIndexes();
      },
    );
  }

  Future<void> _createIndexes() async {
    for (final statement in _indexStatements) {
      await customStatement(statement);
    }
  }
}
