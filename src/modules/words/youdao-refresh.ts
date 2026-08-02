import { sqlite } from "@/db/client";
import type { DictionaryContent, EntryType, ProviderAttempt } from "@/lib/types";
import { contentStatus, dictionaryContentFromRow, emptyDictionaryContent, mergeDictionaryContent } from "@/modules/dictionary/content";
import { lookupDictionary } from "@/modules/dictionary/pipeline";
import { hasAnyContent } from "@/modules/dictionary/providers/youdao-parser";
import { normalizeTerm } from "@/modules/imports/normalizer";
import { getSettings } from "@/modules/settings/service";
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
  if (!row) throw new Error("WORD_NOT_FOUND");
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
    term = newTerm.trim();
    if (!term) throw new Error("TERM_REQUIRED");
    if (term.length > 300) throw new Error("TERM_TOO_LONG");
    normalizedTerm = normalizeTerm(term, row.source_language);
    const duplicate = await sqlite.prepare(`SELECT id FROM words
      WHERE normalized_term = ? AND source_language = ? AND target_language = ? AND id != ? LIMIT 1`)
      .get(normalizedTerm, row.source_language, row.target_language, wordId);
    if (duplicate) throw new Error("TERM_ALREADY_EXISTS");
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
    await sqlite.prepare(`INSERT INTO word_contents
      (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
       synonyms_json, antonyms_json, word_family_json, confused_words_json, roots_json, affixes_json,
       summary_json, learning_json, sentence_analysis_json, tags_json, provider_metadata_json, content_source, content_version, initialized_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'DICTIONARY_ONLY', 1, ?, ?)
      ON CONFLICT(word_id) DO UPDATE SET
        definitions_json = excluded.definitions_json,
        pronunciations_json = excluded.pronunciations_json,
        examples_json = excluded.examples_json,
        phrases_json = excluded.phrases_json,
        forms_json = excluded.forms_json,
        synonyms_json = excluded.synonyms_json,
        antonyms_json = excluded.antonyms_json,
        word_family_json = excluded.word_family_json,
        confused_words_json = excluded.confused_words_json,
        roots_json = excluded.roots_json,
        affixes_json = excluded.affixes_json,
        summary_json = excluded.summary_json,
        learning_json = excluded.learning_json,
        sentence_analysis_json = excluded.sentence_analysis_json,
        tags_json = excluded.tags_json,
        provider_metadata_json = excluded.provider_metadata_json,
        content_source = excluded.content_source,
        content_version = word_contents.content_version + 1,
        initialized_at = excluded.initialized_at,
        updated_at = excluded.updated_at`)
      .run(
        wordId,
        JSON.stringify(merged.definitions), JSON.stringify(merged.pronunciations), JSON.stringify(merged.examples),
        JSON.stringify(merged.phrases), JSON.stringify(merged.forms), JSON.stringify(merged.synonyms),
        JSON.stringify(merged.antonyms), JSON.stringify(merged.wordFamily), JSON.stringify(merged.confusedWords),
        JSON.stringify(merged.roots), JSON.stringify(merged.affixes), JSON.stringify(merged.summary),
        JSON.stringify(merged.learning), JSON.stringify(merged.sentenceAnalysis), JSON.stringify(merged.tags),
        JSON.stringify(attempts), now, now,
      );
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
