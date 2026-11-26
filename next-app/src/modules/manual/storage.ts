import { sqlite } from "@/db/client";
import type { DictionaryContent, EntryType, ManualContentPreview, ProviderAttempt } from "@/lib/types";
import { normalizeDictionaryContent } from "@/modules/dictionary/content";
import { saveWordContent } from "@/modules/words/save-content";

export function fieldsReturned(content: DictionaryContent): string[] {
  return Object.entries(content).filter(([, value]) => Array.isArray(value)
    ? value.length > 0
    : Boolean(value && typeof value === "object" && Object.values(value).some((item) => Array.isArray(item) ? item.length > 0 : Boolean(item)))).map(([key]) => key);
}

export async function saveContent(wordId: number, content: DictionaryContent, attempts: ProviderAttempt[], now: number): Promise<void> {
  await saveWordContent(wordId, content, { providerMetadata: attempts, now });
}

export async function saveAttempts(wordId: number, attempts: ProviderAttempt[], now: number): Promise<void> {
  const insert = sqlite.prepare(`INSERT INTO provider_attempts
    (initialization_job_id, word_id, provider_id, status, duration_ms, fields_returned_json, error_code, error_message, metadata_json, created_at)
    VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  for (const attempt of attempts) {
    await insert.run(wordId, attempt.providerId, attempt.status, attempt.durationMs, JSON.stringify(attempt.fieldsReturned), attempt.errorCode ?? null, attempt.errorMessage ?? null, attempt.metadata ? JSON.stringify(attempt.metadata) : null, now);
  }
}

export function rowToPreview(row: {
  token: string; input_text: string; normalized_term: string; source_language: string; target_language: string;
  source_language_name: string | null; target_language_name: string | null; content_type: EntryType;
  content_json: string; provider_attempts_json: string; existing_word_id: number | null; expires_at: number;
}): ManualContentPreview {
  return {
    previewToken: row.token, term: row.input_text, normalizedTerm: row.normalized_term,
    sourceLanguage: row.source_language, targetLanguage: row.target_language,
    sourceLanguageName: row.source_language_name ?? row.source_language, targetLanguageName: row.target_language_name ?? row.target_language,
    contentType: row.content_type, content: normalizeDictionaryContent(JSON.parse(row.content_json) as Record<string, unknown>),
    providerAttempts: JSON.parse(row.provider_attempts_json) as ProviderAttempt[], existingWordId: row.existing_word_id,
    expiresAt: new Date(row.expires_at).toISOString(),
  };
}
