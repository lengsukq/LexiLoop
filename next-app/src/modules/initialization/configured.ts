import { sqlite } from "@/db/client";
import type { InitializationMode, InitializationTaskOptions } from "@/lib/types";
import { dictionaryContentFromRow } from "@/modules/dictionary/content";
import { normalizeRequestedFields, requestedFieldStatusForLanguages } from "@/modules/dictionary/selection";
import { queueSelectedInitialization } from "./queue";
import { uniqueOrdered } from "./shared";

export interface ConfiguredInitializationInput extends InitializationTaskOptions {
  wordIds?: number[];
  mode?: Extract<InitializationMode, "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE">;
  onlyMissing?: boolean;
}

async function candidates(input: ConfiguredInitializationInput) {
  const requestedFields = normalizeRequestedFields(input.requestedFields);
  const requestedIds = input.wordIds?.length ? [...new Set(input.wordIds.filter((id) => Number.isInteger(id) && id > 0))] : null;
  const where = requestedIds ? `WHERE w.id IN (${requestedIds.map(() => "?").join(",")})` : "";
  const rows = await sqlite.prepare(`SELECT w.id AS selected_word_id, w.term, w.source_language, w.target_language, wc.*
    FROM words w LEFT JOIN word_contents wc ON wc.word_id = w.id ${where} ORDER BY w.id ASC`).all(...(requestedIds ?? [])) as Array<Record<string, unknown>>;
  const onlyMissing = input.onlyMissing ?? input.mode !== "FORCE_OVERWRITE";
  const selected = rows.filter((row) => !onlyMissing || !requestedFields.length || requestedFieldStatusForLanguages(
    dictionaryContentFromRow(row), requestedFields, String(row.source_language), String(row.target_language)) !== "READY");
  return { requestedFields, requestedIds, rows, selected };
}

export async function previewConfiguredInitialization(input: ConfiguredInitializationInput) {
  const { requestedFields, requestedIds, rows, selected } = await candidates(input);
  return {
    scope: requestedIds ? "SELECTED" as const : "ALL" as const,
    requestedWords: requestedIds?.length ?? rows.length, existingWords: rows.length,
    selectedWords: selected.length, skippedExisting: rows.length - selected.length, requestedFields,
    requestedProviders: uniqueOrdered(input.requestedProviders), providerStrategy: input.providerStrategy ?? "PRIORITY_FALLBACK",
    mode: input.mode ?? "FILL_MISSING_FIELDS", sample: selected.slice(0, 8).map((row) => ({ id: Number(row.selected_word_id), term: String(row.term) })),
  };
}

export async function queueConfiguredInitialization(input: ConfiguredInitializationInput) {
  const preview = await previewConfiguredInitialization(input);
  const { selected } = await candidates(input);
  const queued = await queueSelectedInitialization(selected.map((row) => Number(row.selected_word_id)), input.mode ?? "FILL_MISSING_FIELDS", input);
  return { ...preview, createdJobs: queued.createdJobs, updatedJobs: queued.updatedJobs };
}
