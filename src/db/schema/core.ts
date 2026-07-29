import { index, integer, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";
import type { EntryType } from "@/lib/types";

export const words = sqliteTable("words", {
  id: integer("id").primaryKey({ autoIncrement: true }), term: text("term").notNull(), normalizedTerm: text("normalized_term").notNull(),
  sourceLanguage: text("source_language").notNull(), targetLanguage: text("target_language").notNull(), sourceLanguageName: text("source_language_name"), targetLanguageName: text("target_language_name"),
  entryType: text("entry_type", { enum: ["WORD", "PHRASE"] }).notNull(), contentType: text("content_type", { enum: ["WORD", "PHRASE", "SENTENCE"] }).$type<EntryType>().notNull().default("WORD"),
  sourceCreatedAt: integer("source_created_at", { mode: "timestamp_ms" }), initializationStatus: text("initialization_status", { enum: ["PENDING", "QUEUED", "RUNNING", "READY", "PARTIAL", "FAILED", "DISABLED"] }).notNull().default("PENDING"),
  masteryLevel: text("mastery_level", { enum: ["NEW", "LEARNING", "FAMILIAR", "PROFICIENT", "MASTERED"] }).notNull().default("NEW"), masteryScore: integer("mastery_score").notNull().default(0),
  isSuspended: integer("is_suspended", { mode: "boolean" }).notNull().default(false), userNote: text("user_note"), createdAt: integer("created_at", { mode: "timestamp_ms" }).notNull(), updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
}, (table) => [
  uniqueIndex("words_identity_unique").on(table.normalizedTerm, table.sourceLanguage, table.targetLanguage),
  index("words_status_idx").on(table.initializationStatus), index("words_mastery_idx").on(table.masteryLevel),
]);

export const settings = sqliteTable("settings", {
  key: text("key").primaryKey(), valueJson: text("value_json", { mode: "json" }).$type<unknown>().notNull(), updatedAt: integer("updated_at", { mode: "timestamp_ms" }).notNull(),
});
