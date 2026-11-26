// 列 getter 是 schema 本身，语义由表级文档说明。
// ignore_for_file: public_member_api_docs

/// 每日建议、游戏高分与设置三张表。
///
/// 对应旧版 PostgreSQL 迁移 `0000_pg_initial.ts` 的
/// `daily_ai_suggestions` / `game_high_scores` / `settings`。
///
/// **已删除的 `worker_heartbeats`**：旧版用它做多 worker 心跳与失联剔除。
/// 纯本地单进程不存在「其他 worker」，该表无意义。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/converters.dart';
import 'package:lexiloop/domain/enums.dart';

/// 每日 AI 建议的缓存（每天一行）。
///
/// 生成一次成本较高（一次 LLM 调用），因此落库缓存；
/// 纯本地版在当天首次打开时按需生成，而非依赖定时任务。
@DataClassName('DailyAiSuggestionRow')
class DailyAiSuggestions extends Table {
  @override
  String get tableName => 'daily_ai_suggestions';

  TextColumn get dateKey => text()();
  TextColumn get sourceDateKey => text()();
  IntColumn get qualityScore => integer().nullable()();
  TextColumn get metricsJson => text().withDefault(const Constant('{}'))();
  TextColumn get contentJson => text().withDefault(const Constant('{}'))();
  TextColumn get recommendedItemsJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get generator => text()
      .map(
        const WireEnumConverter<SuggestionGenerator>(
          SuggestionGenerator.values,
        ),
      )
      .withDefault(const Constant('RULE_BASED'))();
  TextColumn get providerId => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get generationWarning => text().nullable()();
  IntColumn get generatedAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{dateKey};
}

/// 小游戏高分榜。
///
/// `game_mode` **不加 CHECK**：值域随新增游戏模式变化。
@DataClassName('GameHighScoreRow')
class GameHighScores extends Table {
  @override
  String get tableName => 'game_high_scores';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get gameMode => text()();
  IntColumn get score => integer()();
  IntColumn get maxCombo => integer().withDefault(const Constant(0))();
  IntColumn get accuracy => integer().withDefault(const Constant(0))();
  IntColumn get elapsedMs => integer().withDefault(const Constant(0))();
  IntColumn get playedAt => integer()();
  IntColumn get createdAt => integer()();
}

/// 键值式应用设置。
///
/// `value_json` 存完整 JSON（如 `llmConfig`、`questionTypeConfig`）。
/// **API Key 不存这里**——它属于凭据，存系统 Keychain / Keystore
/// （见 `lib/data/secure_store.dart`）。
@DataClassName('SettingRow')
class Settings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get valueJson => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{key};
}
