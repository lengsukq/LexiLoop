import { sqlite } from "@/db/client";
import type { AiTaskType, InitializationField, InitializationProviderId, ProviderStrategy } from "@/lib/types";
import { parseJson } from "@/lib/json";
import { parseStringArray } from "./shared";

const CONTENT_FIELDS = ["definitions", "pronunciations", "examples", "phrases", "forms", "synonyms", "antonyms", "wordFamily", "confusedWords", "roots", "affixes", "tags"] as const;

function contentFieldStatus(row: Record<string, unknown> | undefined) {
  const fields = Object.fromEntries(CONTENT_FIELDS.map((key) => {
    const column = `${key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)}_json`;
    return [key, parseJson<unknown[]>(row?.[column], []).length > 0];
  })) as Record<string, boolean>;
  const summary = parseJson<Record<string, unknown> | null>(row?.summary_json, null);
  const learning = parseJson<Record<string, unknown> | null>(row?.learning_json, null);
  const sentence = parseJson<Record<string, unknown> | null>(row?.sentence_analysis_json, null);
  fields.summary = Boolean(summary?.shortDefinition || summary?.translation);
  fields.learning = Boolean(learning?.pronunciationTip || learning?.mnemonic || (learning?.commonMistakes as unknown[] | undefined)?.length);
  fields.sentenceAnalysis = Boolean(sentence?.grammarPattern || sentence?.grammarExplanation
    || (sentence?.grammarNotes as unknown[] | undefined)?.length || (sentence?.keyExpressions as unknown[] | undefined)?.length
    || (sentence?.similarExamples as unknown[] | undefined)?.length || (sentence?.variations as unknown[] | undefined)?.length);
  return fields;
}

export async function getJobDetails(jobId: number) {
  const row = await sqlite.prepare(`SELECT j.*, w.term, w.normalized_term, w.source_language, w.target_language
    FROM initialization_jobs j JOIN words w ON w.id = j.word_id WHERE j.id = ?`).get(jobId) as Record<string, unknown> | undefined;
  if (!row) return null;
  const attempts = await sqlite.prepare("SELECT * FROM provider_attempts WHERE initialization_job_id = ? ORDER BY created_at ASC").all(jobId) as Array<Record<string, unknown>>;
  const wordContent = await sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(row.word_id as number) as Record<string, unknown> | undefined;
  return {
    job: {
      id: row.id as number, wordId: row.word_id as number, taskType: row.task_type as AiTaskType,
      term: row.term as string, normalizedTerm: row.normalized_term as string, sourceLanguage: row.source_language as string,
      targetLanguage: row.target_language as string, status: row.status as string, mode: row.mode as string,
      requestedFields: parseStringArray<InitializationField>(row.requested_fields_json),
      requestedProviders: parseStringArray<InitializationProviderId>(row.requested_providers_json),
      providerStrategy: (row.provider_strategy as ProviderStrategy | null) ?? "PRIORITY_FALLBACK",
      priority: row.priority as number, attemptCount: row.attempt_count as number, maxAttempts: row.max_attempts as number,
      lastError: row.last_error as string | null, lastErrorCode: row.last_error_code as string | null,
      availableAt: row.available_at as number | null, lockedAt: row.locked_at as number | null, lockedBy: row.locked_by as string | null,
      createdAt: row.created_at as number, updatedAt: row.updated_at as number, completedAt: row.completed_at as number | null,
    },
    attempts: attempts.map((attempt) => ({
      id: attempt.id as number, providerId: attempt.provider_id as string, status: attempt.status as string,
      durationMs: attempt.duration_ms as number, fieldsReturned: parseJson<string[]>(attempt.fields_returned_json, []),
      errorCode: attempt.error_code as string | null, errorMessage: attempt.error_message as string | null,
      metadata: parseJson(attempt.metadata_json, null), createdAt: attempt.created_at as number,
    })),
    contentFields: contentFieldStatus(wordContent),
  };
}
