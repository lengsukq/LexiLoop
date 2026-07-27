import { index, integer, real, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";
import type {
  DictionaryContent,
  DefinitionItem,
  ExampleItem,
  PhraseItem,
  PronunciationItem,
  ProviderAttempt,
  WordFormItem,
  RelatedWordItem,
  RootItem,
  AffixItem,
  LexicalSummary,
  LearningContent,
  SentenceAnalysis,
  EntryType,
} from "@/lib/types";

export const words = sqliteTable("words", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  term: text("term").notNull(),
  normalizedTerm: text("normalized_term").notNull(),
  sourceLanguage: text("source_language").notNull(),
  targetLanguage: text("target_language").notNull(),
  sourceLanguageName: text("source_language_name"),
  targetLanguageName: text("target_language_name"),
  entryType: text("entry_type", { enum: ["WORD", "PHRASE"] }).notNull(),
  contentType: text("content_type", { enum: ["WORD", "PHRASE", "SENTENCE"] }).$type<EntryType>().notNull().default("WORD"),
  sourceCreatedAt: integer("source_created_at", { mode: "timestamp_ms" }),
  initializationStatus: text("initialization_status", { enum: ["PENDING", "QUEUED", "RUNNING", "READY", "PARTIAL", "FAILED", "DISABLED"] }).notNull().default("PENDING"),
  masteryLevel: text("mastery_level", { enum: ["NEW", "LEARNING", "FAMILIAR", "PROFICIENT", "MASTERED"] }).notNull().default("NEW"),
  masteryScore: integer("mastery_score").notNull().default(0),
  isSuspended: integer("is_suspended", { mode: "boolean" }).notNull().default(false),
  userNote: text("user_note"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
}, (table) => [
  uniqueIndex("words_identity_unique").on(table.normalizedTerm, table.sourceLanguage, table.targetLanguage),
  index("words_status_idx").on(table.initializationStatus),
  index("words_mastery_idx").on(table.masteryLevel),
]);

export const wordContents = sqliteTable("word_contents", {
  wordId: integer("word_id").primaryKey().references(() => words.id, { onDelete: "cascade" }),
  definitionsJson: text("definitions_json", { mode: "json" }).$type<DefinitionItem[]>().notNull().default([]),
  pronunciationsJson: text("pronunciations_json", { mode: "json" }).$type<PronunciationItem[]>().notNull().default([]),
  examplesJson: text("examples_json", { mode: "json" }).$type<ExampleItem[]>().notNull().default([]),
  phrasesJson: text("phrases_json", { mode: "json" }).$type<PhraseItem[]>().notNull().default([]),
  formsJson: text("forms_json", { mode: "json" }).$type<WordFormItem[]>().notNull().default([]),
  synonymsJson: text("synonyms_json", { mode: "json" }).$type<RelatedWordItem[]>().notNull().default([]),
  antonymsJson: text("antonyms_json", { mode: "json" }).$type<RelatedWordItem[]>().notNull().default([]),
  wordFamilyJson: text("word_family_json", { mode: "json" }).$type<RelatedWordItem[]>().notNull().default([]),
  confusedWordsJson: text("confused_words_json", { mode: "json" }).$type<RelatedWordItem[]>().notNull().default([]),
  rootsJson: text("roots_json", { mode: "json" }).$type<RootItem[]>().notNull().default([]),
  affixesJson: text("affixes_json", { mode: "json" }).$type<AffixItem[]>().notNull().default([]),
  summaryJson: text("summary_json", { mode: "json" }).$type<LexicalSummary>().notNull().default({ shortDefinition: null, translation: null, cefrLevel: null, frequency: null }),
  learningJson: text("learning_json", { mode: "json" }).$type<LearningContent>().notNull().default({ pronunciationTip: null, mnemonic: null, commonMistakes: [] }),
  sentenceAnalysisJson: text("sentence_analysis_json", { mode: "json" }).$type<SentenceAnalysis>().notNull().default({ grammarNotes: [], keyExpressions: [], variations: [] }),
  tagsJson: text("tags_json", { mode: "json" }).$type<string[]>().notNull().default([]),
  providerMetadataJson: text("provider_metadata_json", { mode: "json" }).$type<ProviderAttempt[]>().notNull().default([]),
  contentVersion: integer("content_version").notNull().default(1),
  initializedAt: integer("initialized_at", { mode: "timestamp_ms" }),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
});

export const studySessions = sqliteTable("study_sessions", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  sessionType: text("session_type", { enum: ["DAILY", "NEW_WORDS", "DUE_REVIEW", "WRONG_WORDS", "LISTENING", "SPELLING"] }).notNull(),
  startedAt: integer("started_at", { mode: "timestamp_ms" }).notNull(),
  completedAt: integer("completed_at", { mode: "timestamp_ms" }),
  plannedCount: integer("planned_count").notNull().default(0),
  completedCount: integer("completed_count").notNull().default(0),
  correctCount: integer("correct_count").notNull().default(0),
  wrongCount: integer("wrong_count").notNull().default(0),
  skippedCount: integer("skipped_count").notNull().default(0),
  durationMs: integer("duration_ms"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const studySessionItems = sqliteTable("study_session_items", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  studySessionId: integer("study_session_id").notNull().references(() => studySessions.id, { onDelete: "cascade" }),
  position: integer("position").notNull(),
  wordId: integer("word_id").notNull().references(() => words.id, { onDelete: "cascade" }),
  taskType: text("task_type", { enum: ["NEW", "REVIEW", "WRONG", "LISTENING", "SPELLING"] }).notNull(),
  questionType: text("question_type", { enum: ["EN_TO_ZH", "ZH_TO_EN_SPELLING", "LISTENING_SPELLING"] }).notNull(),
  status: text("status", { enum: ["PENDING", "ANSWERED", "SKIPPED"] }).notNull().default("PENDING"),
  answeredAt: integer("answered_at", { mode: "timestamp_ms" }),
  skipReason: text("skip_reason"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
}, (table) => [
  uniqueIndex("study_session_items_position_unique").on(table.studySessionId, table.position),
  index("study_session_items_session_idx").on(table.studySessionId, table.status),
]);

export const reviewCards = sqliteTable("review_cards", {
  wordId: integer("word_id").primaryKey().references(() => words.id, { onDelete: "cascade" }),
  dueAt: integer("due_at", { mode: "timestamp_ms" }).notNull(),
  stability: real("stability").notNull(),
  difficulty: real("difficulty").notNull(),
  elapsedDays: integer("elapsed_days").notNull(),
  scheduledDays: integer("scheduled_days").notNull(),
  reps: integer("reps").notNull(),
  lapses: integer("lapses").notNull(),
  fsrsState: integer("fsrs_state").notNull(),
  learningSteps: integer("learning_steps").notNull().default(0),
  lastReviewAt: integer("last_review_at", { mode: "timestamp_ms" }),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
});

export const reviewLogs = sqliteTable("review_logs", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  clientAnswerId: text("client_answer_id").notNull(),
  wordId: integer("word_id").notNull().references(() => words.id, { onDelete: "cascade" }),
  studySessionId: integer("study_session_id").references(() => studySessions.id, { onDelete: "set null" }),
  studySessionItemId: integer("study_session_item_id").references(() => studySessionItems.id, { onDelete: "set null" }),
  reviewedAt: integer("reviewed_at", { mode: "timestamp_ms" }).notNull(),
  rating: text("rating", { enum: ["AGAIN", "HARD", "GOOD", "EASY"] }).notNull(),
  questionType: text("question_type").notNull(),
  presentedPrompt: text("presented_prompt"),
  userAnswer: text("user_answer"),
  expectedAnswer: text("expected_answer"),
  isCorrect: integer("is_correct", { mode: "boolean" }).notNull(),
  durationMs: integer("duration_ms"),
  cardBeforeJson: text("card_before_json", { mode: "json" }).$type<Record<string, unknown>>(),
  cardAfterJson: text("card_after_json", { mode: "json" }).$type<Record<string, unknown>>(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
}, (table) => [
  uniqueIndex("review_logs_client_answer_unique").on(table.clientAnswerId),
  index("review_logs_word_idx").on(table.wordId, table.reviewedAt),
  index("review_logs_session_idx").on(table.studySessionId),
]);

export const wrongWordStates = sqliteTable("wrong_word_states", {
  wordId: integer("word_id").primaryKey().references(() => words.id, { onDelete: "cascade" }),
  active: integer("active", { mode: "boolean" }).notNull().default(false),
  wrongCount: integer("wrong_count").notNull().default(0),
  hardCount: integer("hard_count").notNull().default(0),
  consecutiveCorrect: integer("consecutive_correct").notNull().default(0),
  lastWrongAt: integer("last_wrong_at", { mode: "timestamp_ms" }),
  lastCorrectAt: integer("last_correct_at", { mode: "timestamp_ms" }),
  resolvedAt: integer("resolved_at", { mode: "timestamp_ms" }),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
});

export const manualPreviews = sqliteTable("manual_previews", {
  token: text("token").primaryKey(),
  inputText: text("input_text").notNull(),
  normalizedTerm: text("normalized_term").notNull(),
  sourceLanguage: text("source_language").notNull(),
  targetLanguage: text("target_language").notNull(),
  sourceLanguageName: text("source_language_name"),
  targetLanguageName: text("target_language_name"),
  contentType: text("content_type", { enum: ["WORD", "PHRASE", "SENTENCE"] }).$type<EntryType>().notNull(),
  contentJson: text("content_json", { mode: "json" }).$type<DictionaryContent>().notNull(),
  providerAttemptsJson: text("provider_attempts_json", { mode: "json" }).$type<ProviderAttempt[]>().notNull().default([]),
  existingWordId: integer("existing_word_id").references(() => words.id, { onDelete: "set null" }),
  status: text("status", { enum: ["PREVIEW", "COMMITTED", "EXPIRED"] }).notNull().default("PREVIEW"),
  expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  committedAt: integer("committed_at", { mode: "timestamp_ms" }),
}, (table) => [
  index("manual_previews_expiry_idx").on(table.status, table.expiresAt),
  index("manual_previews_identity_idx").on(table.normalizedTerm, table.sourceLanguage, table.targetLanguage),
]);

export const importPreviews = sqliteTable("import_previews", {
  token: text("token").primaryKey(),
  filename: text("filename").notNull(),
  fileHash: text("file_hash").notNull(),
  rowsJson: text("rows_json", { mode: "json" }).$type<unknown[]>().notNull(),
  expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const importBatches = sqliteTable("import_batches", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  filename: text("filename").notNull(),
  fileHash: text("file_hash"),
  importMode: text("import_mode", { enum: ["SKIP_EXISTING", "FILL_MISSING", "FORCE_DICTIONARY_REFRESH"] }).notNull(),
  resetLearningProgress: integer("reset_learning_progress", { mode: "boolean" }).notNull().default(false),
  totalRows: integer("total_rows").notNull().default(0),
  validRows: integer("valid_rows").notNull().default(0),
  invalidRows: integer("invalid_rows").notNull().default(0),
  duplicateRows: integer("duplicate_rows").notNull().default(0),
  createdWords: integer("created_words").notNull().default(0),
  existingWords: integer("existing_words").notNull().default(0),
  queuedInitializations: integer("queued_initializations").notNull().default(0),
  status: text("status", { enum: ["PENDING", "COMMITTED", "FAILED", "ROLLED_BACK"] }).notNull().default("PENDING"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  completedAt: integer("completed_at", { mode: "timestamp_ms" }),
  rolledBackAt: integer("rolled_back_at", { mode: "timestamp_ms" }),
});

export const importRows = sqliteTable("import_rows", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  importBatchId: integer("import_batch_id").notNull().references(() => importBatches.id, { onDelete: "cascade" }),
  rowNumber: integer("row_number").notNull(),
  rawJson: text("raw_json", { mode: "json" }).$type<Record<string, unknown>>(),
  normalizedTerm: text("normalized_term"),
  wordId: integer("word_id").references(() => words.id, { onDelete: "set null" }),
  status: text("status", { enum: ["INVALID", "DUPLICATE", "NEW", "EXISTING", "IMPORTED", "ERROR"] }).notNull(),
  errorCode: text("error_code"),
  errorMessage: text("error_message"),
  metadataJson: text("metadata_json", { mode: "json" }).$type<ProviderAttempt["metadata"]>(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const initializationJobs = sqliteTable("initialization_jobs", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  wordId: integer("word_id").notNull().references(() => words.id, { onDelete: "cascade" }),
  mode: text("mode", { enum: ["SKIP_INITIALIZED", "FILL_MISSING_FIELDS", "FORCE_OVERWRITE"] }).notNull(),
  requestedFieldsJson: text("requested_fields_json", { mode: "json" }).$type<string[]>(),
  status: text("status", { enum: ["PENDING", "QUEUED", "RUNNING", "READY", "PARTIAL", "FAILED", "DISABLED"] }).notNull().default("QUEUED"),
  priority: integer("priority").notNull().default(0),
  attemptCount: integer("attempt_count").notNull().default(0),
  maxAttempts: integer("max_attempts").notNull().default(5),
  availableAt: integer("available_at", { mode: "timestamp_ms" }),
  lockedAt: integer("locked_at", { mode: "timestamp_ms" }),
  lockedBy: text("locked_by"),
  lastError: text("last_error"),
  lastErrorCode: text("last_error_code"),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
  completedAt: integer("completed_at", { mode: "timestamp_ms" }),
}, (table) => [
  index("initialization_jobs_status_idx").on(table.status, table.availableAt, table.priority),
  index("initialization_jobs_word_idx").on(table.wordId),
]);

export const providerAttempts = sqliteTable("provider_attempts", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  initializationJobId: integer("initialization_job_id").references(() => initializationJobs.id, { onDelete: "cascade" }),
  wordId: integer("word_id").notNull().references(() => words.id, { onDelete: "cascade" }),
  providerId: text("provider_id").notNull(),
  status: text("status", { enum: ["SUCCESS", "EMPTY", "FAILED"] }).notNull(),
  durationMs: integer("duration_ms"),
  fieldsReturnedJson: text("fields_returned_json", { mode: "json" }).$type<string[]>(),
  errorCode: text("error_code"),
  errorMessage: text("error_message"),
  metadataJson: text("metadata_json", { mode: "json" }).$type<ProviderAttempt["metadata"]>(),
  createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});

export const workerHeartbeats = sqliteTable("worker_heartbeats", {
  workerId: text("worker_id").primaryKey(),
  status: text("status", { enum: ["STARTING", "IDLE", "WORKING", "STOPPING", "ERROR"] }).notNull(),
  currentJobId: integer("current_job_id"),
  metadataJson: text("metadata_json", { mode: "json" }).$type<Record<string, unknown>>(),
  lastSeenAt: integer("last_seen_at", { mode: "timestamp_ms" }).notNull(),
  startedAt: integer("started_at", { mode: "timestamp_ms" }).notNull(),
});

export const settings = sqliteTable("settings", {
  key: text("key").primaryKey(),
  valueJson: text("value_json", { mode: "json" }).$type<unknown>().notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
});
