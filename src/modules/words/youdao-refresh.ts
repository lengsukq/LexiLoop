import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import type { DictionaryContent, EntryType, ProviderAttempt } from "@/lib/types";
import { contentStatus, dictionaryContentFromRow, emptyDictionaryContent, mergeDictionaryContent } from "@/modules/dictionary/content";
import { lookupDictionary } from "@/modules/dictionary/pipeline";
import { hasAnyContent } from "@/modules/dictionary/providers/youdao-parser";
import { displayTerm, normalizeTerm } from "@/modules/imports/normalizer";
import { getSettings } from "@/modules/settings/service";
import { saveWordContent } from "./save-content";
import { getWordDetail } from "./queries";

export interface YoudaoPreviewResult {
  content: DictionaryContent;
  attempts: ProviderAttempt[];
  hasContent: boolean;
}

async function wordRowOrThrow(wordId: number) {
  const row = await sqlite.prepare("SELECT id, term, normalized_term, source_language, target_language, content_type FROM words WHERE id = ?").get(wordId) as {
    id: number; term: string; normalized_term: string; source_language: string; target_language: string; content_type: EntryType;
  } | undefined;
  if (!row) throw new ApiError("WORD_NOT_FOUND");
  return row;
}

/** 仅使用有道词典抓取单词内容，不写入数据库。 */
export async function previewYoudaoContent(wordId: number, termOverride?: string): Promise<YoudaoPreviewResult> {
  const row = await wordRowOrThrow(wordId);
  const term = termOverride?.trim() || row.term;
  const normalizedTerm = termOverride ? normalizeTerm(term, row.source_language) : row.normalized_term;
  const settings = await getSettings();
  const result = await lookupDictionary({
    term,
    normalizedTerm,
    entryType: row.content_type,
    sourceLanguage: row.source_language,
    targetLanguage: row.target_language,
    requestedProviders: ["youdao"],
    providerStrategy: "PRIORITY_FALLBACK",
  }, settings);
  const hasContent = hasAnyContent(result.content);
  return { content: result.content, attempts: result.attempts, hasContent };
}

function preserveUserContent(existing: DictionaryContent, refreshed: DictionaryContent): DictionaryContent {
  return mergeDictionaryContent({
    definitions: existing.definitions.filter((item) => item.isUserEdited),
    examples: existing.examples.filter((item) => item.isUserAdded),
  }, refreshed);
}

/** 将有道词典预览内容应用到单词，确认后写入数据库。 */
export async function applyYoudaoContent(
  wordId: number,
  fetched: DictionaryContent,
  mode: "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE",
  attempts: ProviderAttempt[],
  newTerm?: string,
) {
  const row = await wordRowOrThrow(wordId);
  const contentRow = await sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(wordId) as Record<string, unknown> | undefined;
  const existing: DictionaryContent = contentRow ? dictionaryContentFromRow(contentRow) : emptyDictionaryContent();

  let term = row.term;
  let normalizedTerm = row.normalized_term;
  if (newTerm !== undefined) {
    term = displayTerm(newTerm.trim(), row.source_language, row.content_type);
    if (!term) throw new ApiError("TERM_REQUIRED");
    if (term.length > 300) throw new ApiError("TERM_TOO_LONG");
    normalizedTerm = normalizeTerm(term, row.source_language);
    const duplicate = await sqlite.prepare(`SELECT id FROM words
      WHERE normalized_term = ? AND source_language = ? AND target_language = ? AND id != ? LIMIT 1`)
      .get(normalizedTerm, row.source_language, row.target_language, wordId);
    if (duplicate) throw new ApiError("TERM_ALREADY_EXISTS");
  }

  const merged = mode === "FORCE_OVERWRITE"
    ? preserveUserContent(existing, fetched)
    : mergeDictionaryContent(existing, fetched);

  const status = contentStatus(merged, row.content_type);
  const now = Date.now();

  await sqlite.transaction(async () => {
    if (term !== row.term || normalizedTerm !== row.normalized_term) {
      await sqlite.prepare("UPDATE words SET term = ?, normalized_term = ?, updated_at = ? WHERE id = ?")
        .run(term, normalizedTerm, now, wordId);
    }
    await saveWordContent(wordId, merged, { providerMetadata: attempts, contentSource: "DICTIONARY_ONLY" });
    await sqlite.prepare("UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?").run(status, now, wordId);
    const insert = sqlite.prepare(`INSERT INTO provider_attempts
      (initialization_job_id, word_id, provider_id, status, duration_ms, fields_returned_json, error_code, error_message, metadata_json, created_at)
      VALUES (NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
    for (const attempt of attempts) {
      await insert.run(wordId, attempt.providerId, attempt.status, attempt.durationMs, JSON.stringify(attempt.fieldsReturned), attempt.errorCode ?? null, attempt.errorMessage ?? null, attempt.metadata ? JSON.stringify(attempt.metadata) : null, now);
    }
  }).immediate();

  return getWordDetail(wordId);
}
