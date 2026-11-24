/// Schema v1 → v2 迁移验证：确保老用户词条自动保留为个人词库并创建新表。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/database.dart';

void main() {
  test('从 Schema v1 升级到 v2 保留既有个人词条并建立词书表', () async {
    final tempDir = await Directory.systemTemp.createTemp('lexiloop_mig_v2_');
    final file = File('${tempDir.path}/legacy_v1.sqlite');
    addTearDown(() async {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // 通过 NativeDatabase.setup 在 Drift 执行迁移前写入纯 v1 表结构与存量词条。
    final db = AppDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          final currentVersion = raw
              .select('PRAGMA user_version')
              .single
              .values
              .first;
          if (currentVersion != 0) return;
          raw.execute('''
CREATE TABLE words (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  term TEXT NOT NULL,
  normalized_term TEXT NOT NULL,
  source_language TEXT NOT NULL,
  target_language TEXT NOT NULL,
  source_language_name TEXT NULL,
  target_language_name TEXT NULL,
  entry_type TEXT NOT NULL,
  content_type TEXT NOT NULL DEFAULT 'WORD',
  source_created_at INTEGER NULL,
  initialization_status TEXT NOT NULL DEFAULT 'PENDING',
  mastery_level TEXT NOT NULL DEFAULT 'NEW',
  mastery_score INTEGER NOT NULL DEFAULT 0,
  is_suspended INTEGER NOT NULL DEFAULT 0,
  user_note TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(normalized_term, source_language, target_language)
);
CREATE TABLE word_contents (word_id INTEGER PRIMARY KEY);
CREATE TABLE word_review_stats (word_id INTEGER PRIMARY KEY);
CREATE TABLE study_sessions (id INTEGER PRIMARY KEY, started_at INTEGER, completed_at INTEGER, source_type TEXT);
CREATE TABLE study_session_items (id INTEGER PRIMARY KEY, study_session_id INTEGER, word_id INTEGER, status TEXT, answered_at INTEGER);
CREATE TABLE review_cards (word_id INTEGER PRIMARY KEY, due_at INTEGER);
CREATE TABLE review_logs (id INTEGER PRIMARY KEY, word_id INTEGER, study_session_id INTEGER, reviewed_at INTEGER);
CREATE TABLE wrong_word_states (word_id INTEGER PRIMARY KEY, active INTEGER, updated_at INTEGER, last_wrong_at INTEGER);
CREATE TABLE import_batches (id INTEGER PRIMARY KEY, created_at INTEGER);
CREATE TABLE import_rows (id INTEGER PRIMARY KEY, import_batch_id INTEGER, row_number INTEGER);
CREATE TABLE initialization_jobs (id INTEGER PRIMARY KEY, word_id INTEGER, task_type TEXT, status TEXT, available_at INTEGER, priority INTEGER);
CREATE TABLE provider_attempts (id INTEGER PRIMARY KEY, initialization_job_id INTEGER, word_id INTEGER);
CREATE TABLE daily_ai_suggestions (date_key TEXT PRIMARY KEY, generated_at INTEGER);
CREATE TABLE game_high_scores (id INTEGER PRIMARY KEY, game_mode TEXT, score INTEGER, played_at INTEGER);
CREATE TABLE settings (key TEXT PRIMARY KEY, value_json TEXT, updated_at INTEGER);
INSERT INTO words (term, normalized_term, source_language, target_language, entry_type, created_at, updated_at)
VALUES ('resilient', 'resilient', 'en', 'zh', 'WORD', 1000, 1000);
PRAGMA user_version = 1;
''');
        },
      ),
    );
    addTearDown(db.close);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 2);

    final word = await db
        .customSelect(
          "SELECT term, is_personal FROM words WHERE term = 'resilient'",
        )
        .getSingle();
    expect(word.read<int>('is_personal'), 1);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('word_packs', 'word_pack_items')",
        )
        .get();
    expect(tables, hasLength(2));
  });
}
