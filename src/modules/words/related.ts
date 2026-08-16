import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import type { DictionaryContent, EntryType } from "@/lib/types";
import { dictionaryContentFromRow, emptyDictionaryContent } from "@/modules/dictionary/content";
import { detectEntryType, displayTerm, legacyEntryType, normalizeTerm } from "@/modules/imports/normalizer";
import { z } from "zod";

const relatedWordSchema = z.object({
  term: z.string().trim().min(1).max(300),
  relation: z.enum(["SYNONYM", "ANTONYM", "WORD_FAMILY", "CONFUSED_WITH"]).default("SYNONYM"),
}).strict();

function findRelatedContent(content: DictionaryContent, term: string) {
  const key = term.normalize("NFKC").trim().toLocaleLowerCase();
  return [...content.synonyms, ...content.antonyms, ...content.wordFamily, ...content.confusedWords]
    .find((item) => item.word.normalize("NFKC").trim().toLocaleLowerCase() === key) ?? null;
}

export async function previewRelatedWord(parentWordId: number, rawTerm: string) {
  const parent = await sqlite.prepare(`SELECT w.*, wc.* FROM words w LEFT JOIN word_contents wc ON wc.word_id = w.id WHERE w.id = ?`)
    .get(parentWordId) as Record<string, unknown> | undefined;
  if (!parent) throw new ApiError("WORD_NOT_FOUND");
  const term = relatedWordSchema.shape.term.parse(rawTerm);
  const normalizedTerm = normalizeTerm(term, String(parent.source_language));
  if (normalizedTerm === String(parent.normalized_term)) throw new ApiError("RELATED_WORD_SAME_AS_PARENT");
  const existing = await sqlite.prepare(`SELECT id, term, initialization_status, mastery_level, mastery_score
    FROM words WHERE normalized_term = ? AND source_language = ? AND target_language = ? LIMIT 1`)
    .get(normalizedTerm, parent.source_language, parent.target_language) as {
      id: number; term: string; initialization_status: string; mastery_level: string; mastery_score: number;
    } | undefined;
  const content = parent.word_id == null ? emptyDictionaryContent() : dictionaryContentFromRow(parent);
  const related = findRelatedContent(content, term);
  return {
    term, normalizedTerm, sourceLanguage: String(parent.source_language), targetLanguage: String(parent.target_language),
    relation: related?.relation ?? "SYNONYM", translation: related?.translation ?? null,
    partOfSpeech: related?.partOfSpeech ?? null, difference: related?.difference ?? null, source: related?.source ?? null,
    existing: existing ? {
      id: existing.id, term: existing.term, initializationStatus: existing.initialization_status,
      masteryLevel: existing.mastery_level, masteryScore: existing.mastery_score,
    } : null,
  };
}

export async function addRelatedWord(parentWordId: number, input: unknown) {
  const values = relatedWordSchema.parse(input);
  const parent = await sqlite.prepare(`SELECT id, normalized_term, source_language, target_language,
    source_language_name, target_language_name, content_type FROM words WHERE id = ?`).get(parentWordId) as {
      id: number; normalized_term: string; source_language: string; target_language: string;
      source_language_name: string | null; target_language_name: string | null; content_type: EntryType;
    } | undefined;
  if (!parent) throw new ApiError("WORD_NOT_FOUND");
  const normalizedTerm = normalizeTerm(values.term, parent.source_language);
  if (normalizedTerm === parent.normalized_term) throw new ApiError("RELATED_WORD_SAME_AS_PARENT");
  const now = Date.now();
  return await sqlite.transaction(async () => {
    let word = await sqlite.prepare(`SELECT id, term, initialization_status FROM words
      WHERE normalized_term = ? AND source_language = ? AND target_language = ? LIMIT 1`)
      .get(normalizedTerm, parent.source_language, parent.target_language) as {
        id: number; term: string; initialization_status: string;
      } | undefined;
    let created = false;
    if (!word) {
      const type = detectEntryType(values.term);
      const display = displayTerm(values.term, parent.source_language, type);
      const inserted = await sqlite.prepare(`INSERT INTO words
        (term, normalized_term, source_language, target_language, source_language_name, target_language_name,
         entry_type, content_type, initialization_status, mastery_level, mastery_score, is_suspended, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'QUEUED', 'NEW', 0, 0, ?, ?)`)
        .run(display, normalizedTerm, parent.source_language, parent.target_language,
          parent.source_language_name, parent.target_language_name, legacyEntryType(type), type, now, now);
      word = { id: Number(inserted.lastInsertRowid), term: display, initialization_status: "QUEUED" };
      created = true;
    }
    const needsInitialization = !["READY", "PARTIAL"].includes(word.initialization_status);
    let jobId: number | null = null;
    if (needsInitialization) {
      const active = await sqlite.prepare(`SELECT id FROM initialization_jobs WHERE word_id = ? AND status IN ('QUEUED','RUNNING') LIMIT 1`)
        .get(word.id) as { id: number } | undefined;
      if (active) {
        jobId = active.id;
        await sqlite.prepare(`UPDATE initialization_jobs SET mode = 'FILL_MISSING_FIELDS', priority = GREATEST(priority, 80), available_at = ?, updated_at = ? WHERE id = ?`)
          .run(now, now, active.id);
      } else {
        const job = await sqlite.prepare(`INSERT INTO initialization_jobs
          (word_id, mode, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
          VALUES (?, ?, 'QUEUED', 80, 0, 5, ?, ?, ?)`)
          .run(word.id, created ? "SKIP_INITIALIZED" : "FILL_MISSING_FIELDS", now, now, now);
        jobId = Number(job.lastInsertRowid);
      }
      await sqlite.prepare("UPDATE words SET initialization_status = 'QUEUED', updated_at = ? WHERE id = ?").run(now, word.id);
    }
    return {
      wordId: word.id, term: word.term, created, queued: needsInitialization, jobId, relation: values.relation,
      initializationStatus: needsInitialization ? "QUEUED" : word.initialization_status,
    };
  }).immediate();
}

export async function deleteWord(wordId: number, force = false): Promise<boolean> {
  if (!await sqlite.prepare("SELECT id FROM words WHERE id = ?").get(wordId)) return false;
  if (!force) {
    const history = await sqlite.prepare(`SELECT EXISTS(SELECT 1 FROM review_logs WHERE word_id = ?) AS has_reviews,
      EXISTS(SELECT 1 FROM study_session_items WHERE word_id = ?) AS has_session_items`).get(wordId, wordId) as {
        has_reviews: number; has_session_items: number;
      };
    if (history.has_reviews || history.has_session_items) throw new ApiError("WORD_HAS_LEARNING_HISTORY");
  }
  return await sqlite.transaction(async () => {
    if (force) for (const table of ["review_logs", "review_cards", "wrong_word_states", "study_session_items", "initialization_jobs", "provider_attempts"]) {
      await sqlite.prepare(`DELETE FROM ${table} WHERE word_id = ?`).run(wordId);
    }
    return (await sqlite.prepare("DELETE FROM words WHERE id = ?").run(wordId)).changes === 1;
  }).immediate();
}
