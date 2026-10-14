/// 列名一致性守卫。
///
/// **为什么需要这个测试**：备份导入依赖「Drift 列名 == 旧版 PostgreSQL 列名」
/// 这一前提。但 Drift 的驼峰转下划线规则与手写 SQL 并不总是一致——
/// 例如 `recentAgain30d` 会被转成 `recent_again30d`，而旧版写的是
/// `recent_again_30d`（数字前也有下划线）。这类不一致**不会报错**，
/// 只会让备份里的那几列被静默忽略，导致学习队列的排序权重全是 0。
///
/// 期望列名直接抄自旧版迁移
/// `src/db/migrations/pg/0000_pg_initial.ts` 与 `0001_word_review_stats.ts`。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/database.dart';

/// 旧版 PostgreSQL 各表的列名（顺序无关，仅比对集合）。
const Map<String, Set<String>> expectedColumns = <String, Set<String>>{
  'words': <String>{
    'id',
    'term',
    'normalized_term',
    'source_language',
    'target_language',
    'source_language_name',
    'target_language_name',
    'entry_type',
    'content_type',
    'source_created_at',
    'initialization_status',
    'mastery_level',
    'mastery_score',
    'is_suspended',
    'user_note',
    'created_at',
    'updated_at',
  },
  'word_contents': <String>{
    'word_id',
    'definitions_json',
    'pronunciations_json',
    'examples_json',
    'phrases_json',
    'forms_json',
    'synonyms_json',
    'antonyms_json',
    'word_family_json',
    'confused_words_json',
    'roots_json',
    'affixes_json',
    'summary_json',
    'learning_json',
    'sentence_analysis_json',
    'tags_json',
    'provider_metadata_json',
    'content_source',
    'content_version',
    'initialized_at',
    'updated_at',
  },
  'word_review_stats': <String>{
    'word_id',
    'total_reviews',
    'correct_reviews',
    'recent_again_30d',
    'recent_again_14d',
    'recent_wrong_14d',
    'recent_hard_14d',
    'total_duration_ms',
    'duration_count',
    'last_reviewed_at',
    'updated_at',
  },
  'study_sessions': <String>{
    'id',
    'session_type',
    'source_type',
    'started_at',
    'completed_at',
    'planned_count',
    'completed_count',
    'correct_count',
    'wrong_count',
    'skipped_count',
    'duration_ms',
    'created_at',
  },
  'study_session_items': <String>{
    'id',
    'study_session_id',
    'position',
    'word_id',
    'task_type',
    'question_type',
    'status',
    'answered_at',
    'skip_reason',
    'created_at',
  },
  'review_cards': <String>{
    'word_id',
    'due_at',
    'stability',
    'difficulty',
    'elapsed_days',
    'scheduled_days',
    'reps',
    'lapses',
    'fsrs_state',
    'learning_steps',
    'last_review_at',
    'created_at',
    'updated_at',
  },
  'review_logs': <String>{
    'id',
    'client_answer_id',
    'word_id',
    'study_session_id',
    'study_session_item_id',
    'reviewed_at',
    'rating',
    'question_type',
    'presented_prompt',
    'user_answer',
    'expected_answer',
    'is_correct',
    'duration_ms',
    'card_before_json',
    'card_after_json',
    'created_at',
  },
  'wrong_word_states': <String>{
    'word_id',
    'active',
    'wrong_count',
    'hard_count',
    'consecutive_correct',
    'last_wrong_at',
    'last_correct_at',
    'resolved_at',
    'updated_at',
  },
  'import_batches': <String>{
    'id',
    'filename',
    'file_hash',
    'import_mode',
    'reset_learning_progress',
    'total_rows',
    'valid_rows',
    'invalid_rows',
    'duplicate_rows',
    'created_words',
    'existing_words',
    'queued_initializations',
    'status',
    'created_at',
    'completed_at',
    'rolled_back_at',
  },
  'import_rows': <String>{
    'id',
    'import_batch_id',
    'row_number',
    'raw_json',
    'normalized_term',
    'word_id',
    'status',
    'error_code',
    'error_message',
    'metadata_json',
    'created_at',
  },
  'initialization_jobs': <String>{
    'id',
    'word_id',
    'task_type',
    'mode',
    'requested_fields_json',
    'requested_providers_json',
    'provider_strategy',
    'status',
    'priority',
    'attempt_count',
    'max_attempts',
    'available_at',
    'locked_at',
    'locked_by',
    'last_error',
    'last_error_code',
    'created_at',
    'updated_at',
    'completed_at',
  },
  'provider_attempts': <String>{
    'id',
    'initialization_job_id',
    'word_id',
    'provider_id',
    'status',
    'duration_ms',
    'fields_returned_json',
    'error_code',
    'error_message',
    'metadata_json',
    'created_at',
  },
  'daily_ai_suggestions': <String>{
    'date_key',
    'source_date_key',
    'quality_score',
    'metrics_json',
    'content_json',
    'recommended_items_json',
    'generator',
    'provider_id',
    'model',
    'generation_warning',
    'generated_at',
    'updated_at',
  },
  'game_high_scores': <String>{
    'id',
    'game_mode',
    'score',
    'max_combo',
    'accuracy',
    'elapsed_ms',
    'played_at',
    'created_at',
  },
  'settings': <String>{'key', 'value_json', 'updated_at'},
};

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<Set<String>> columnsOf(String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  for (final entry in expectedColumns.entries) {
    test('${entry.key} 的列名与旧版 PostgreSQL 一致', () async {
      final actual = await columnsOf(entry.key);

      final missing = entry.value.difference(actual);
      final unexpected = actual.difference(entry.value);

      expect(
        missing,
        isEmpty,
        reason: <String>[
          '以下列在旧版备份中存在但 Drift 未生成，',
          '备份导入时会静默丢弃：$missing',
        ].join(),
      );
      expect(
        unexpected,
        isEmpty,
        reason: '以下列不在旧版 schema 中，可能是命名漂移：$unexpected',
      );
    });
  }
}
