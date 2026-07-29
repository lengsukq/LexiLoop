import { integer, sqliteTable, text } from "drizzle-orm/sqlite-core";
import type { ProviderAttempt } from "@/lib/types";
import { words } from "./core";

export const importPreviews = sqliteTable("import_previews", {
  token: text("token").primaryKey(), filename: text("filename").notNull(), fileHash: text("file_hash").notNull(), rowsJson: text("rows_json", { mode: "json" }).notNull(), expiresAt: integer("expires_at", { mode: "timestamp_ms" }).notNull(), createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});
export const importBatches = sqliteTable("import_batches", {
  id: integer("id").primaryKey({ autoIncrement: true }), filename: text("filename").notNull(), fileHash: text("file_hash"), importMode: text("import_mode", { enum: ["SKIP_EXISTING", "FILL_MISSING", "FORCE_DICTIONARY_REFRESH"] }).notNull(), resetLearningProgress: integer("reset_learning_progress", { mode: "boolean" }).notNull().default(false), totalRows: integer("total_rows").notNull().default(0), validRows: integer("valid_rows").notNull().default(0), invalidRows: integer("invalid_rows").notNull().default(0), duplicateRows: integer("duplicate_rows").notNull().default(0), createdWords: integer("created_words").notNull().default(0), existingWords: integer("existing_words").notNull().default(0), queuedInitializations: integer("queued_initializations").notNull().default(0), status: text("status", { enum: ["PENDING", "COMMITTED", "FAILED", "ROLLED_BACK"] }).notNull().default("PENDING"), createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(), completedAt: integer("completed_at", { mode: "timestamp_ms" }), rolledBackAt: integer("rolled_back_at", { mode: "timestamp_ms" }),
});
export const importRows = sqliteTable("import_rows", {
  id: integer("id").primaryKey({ autoIncrement: true }), importBatchId: integer("import_batch_id").notNull().references(() => importBatches.id, { onDelete: "cascade" }), rowNumber: integer("row_number").notNull(), rawJson: text("raw_json", { mode: "json" }).$type<Record<string, unknown>>(), normalizedTerm: text("normalized_term"), wordId: integer("word_id").references(() => words.id, { onDelete: "set null" }), status: text("status", { enum: ["INVALID", "DUPLICATE", "NEW", "EXISTING", "IMPORTED", "ERROR"] }).notNull(), errorCode: text("error_code"), errorMessage: text("error_message"), metadataJson: text("metadata_json", { mode: "json" }).$type<ProviderAttempt["metadata"]>(), createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(),
});
