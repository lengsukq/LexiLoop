import { sqlite } from "@/db/client";
import type { DictionaryContent, EntryType, ManualContentPreview, ProviderAttempt } from "@/lib/types";
import { normalizeDictionaryContent } from "@/modules/dictionary/content";

export function fieldsReturned(content: DictionaryContent): string[] {
  return Object.entries(content).filter(([, value]) => Array.isArray(value)
    ? value.length > 0
    : Boolean(value && typeof value === "object" && Object.values(value).some((item) => Array.isArray(item) ? item.length > 0 : Boolean(item)))).map(([key]) => key);
}

export function saveContent(wordId: number, content: DictionaryContent, attempts: ProviderAttempt[], now: number): void {
  sqlite.prepare(`INSERT INTO word_contents
    (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json, synonyms_json, antonyms_json,
     word_family_json, confused_words_json, roots_json, affixes_json, summary_json, learning_json, sentence_analysis_json,
     tags_json, provider_metadata_json, content_version, initialized_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
    ON CONFLICT(word_id) DO UPDATE SET definitions_json = excluded.definitions_json, pronunciations_json = excluded.pronunciations_json,
      examples_json = excluded.examples_json, phrases_json = excluded.phrases_json, forms_json = excluded.forms_json,
      synonyms_json = excluded.synonyms_json, antonyms_json = excluded.antonyms_json, word_family_json = excluded.word_family_json,
      confused_words_json = excluded.confused_words_json, roots_json = excluded.roots_json, affixes_json = excluded.affixes_json,
      summary_json = excluded.summary_json, learning_json = excluded.learning_json, sentence_analysis_json = excluded.sentence_analysis_json,
      tags_json = excluded.tags_json, provider_metadata_json = excluded.provider_metadata_json,
      content_version = word_contents.content_version + 1, initialized_at = excluded.initialized_at, updated_at = excluded.updated_at`)
    .run(wordId, JSON.stringify(content.definitions), JSON.stringify(content.pronunciations), JSON.stringify(content.examples), JSON.stringify(content.phrases), JSON.stringify(content.forms), JSON.stringify(content.synonyms), JSON.stringify(content.antonyms), JSON.stringify(content.wordFamily), JSON.stringify(content.confusedWords), JSON.stringify(content.roots), JSON.stringify(content.affixes), JSON.stringify(content.summary), JSON.stringify(content.learning), JSON.stringify(content.sentenceAnalysis), JSON.stringify(content.tags), JSON.stringify(attempts), now, now);
}

export function saveAttempts(wordId: number, attempts: ProviderAttempt[], now: number): void {
  const insert = sqlite.prepare(`INSERT INTO provider_attempts
    (initialization_job_id, word_id, provider_id, status, duration_ms, fields_returned_json, error_code, error_message, metadata_json, created_at)
    VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  for (const attempt of attempts) insert.run(wordId, attempt.providerId, attempt.status, attempt.durationMs, JSON.stringify(attempt.fieldsReturned), attempt.errorCode ?? null, attempt.errorMessage ?? null, attempt.metadata ? JSON.stringify(attempt.metadata) : null, now);
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
