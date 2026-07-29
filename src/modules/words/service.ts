import { sqlite } from "@/db/client";
import type { DictionaryContent, InitializationStatus, MasteryLevel } from "@/lib/types";
import { contentStatus, dictionaryContentFromRow, emptyDictionaryContent } from "@/modules/dictionary/content";
import { INITIALIZATION_STATUSES, MASTERY_LEVELS } from "@/lib/types";
import { z } from "zod";
import { detectEntryType, legacyEntryType, normalizeTerm } from "@/modules/imports/normalizer";

export interface WordListFilters {
  query?: string;
  status?: InitializationStatus;
  mastery?: MasteryLevel;
  wrong?: boolean;
  due?: boolean;
  suspended?: boolean;
  page: number;
  limit: number;
  sort: "createdAt" | "term" | "masteryScore" | "sourceCreatedAt" | "dueAt";
  order: "asc" | "desc";
}

function parseJson<T>(value: unknown, fallback: T): T {
  if (typeof value !== "string") return (value ?? fallback) as T;
  try { return JSON.parse(value) as T; } catch { return fallback; }
}

export function listWords(filters: WordListFilters) {
  const conditions: string[] = ["1 = 1"];
  const params: Array<string | number> = [];
  if (filters.query) {
    conditions.push("(w.term LIKE ? ESCAPE '\\' OR w.normalized_term LIKE ? ESCAPE '\\' OR COALESCE(w.user_note, '') LIKE ? ESCAPE '\\')");
    const escaped = filters.query.replace(/[\\%_]/g, "\\$&");
    params.push(`%${escaped}%`, `%${escaped}%`, `%${escaped}%`);
  }
  if (filters.status && INITIALIZATION_STATUSES.includes(filters.status)) { conditions.push("w.initialization_status = ?"); params.push(filters.status); }
  if (filters.mastery && MASTERY_LEVELS.includes(filters.mastery)) { conditions.push("w.mastery_level = ?"); params.push(filters.mastery); }
  if (filters.wrong) conditions.push("COALESCE(x.active, 0) = 1");
  if (filters.due) { conditions.push("c.due_at <= ?"); params.push(Date.now()); }
  if (filters.suspended !== undefined) { conditions.push("w.is_suspended = ?"); params.push(filters.suspended ? 1 : 0); }
  const sortMap = {
    createdAt: "w.created_at",
    term: "w.normalized_term",
    masteryScore: "w.mastery_score",
    sourceCreatedAt: "COALESCE(w.source_created_at, w.created_at)",
    dueAt: "COALESCE(c.due_at, 9223372036854775807)",
  } as const;
  const where = conditions.join(" AND ");
  const total = sqlite.prepare(`SELECT count(*) AS count FROM words w
    LEFT JOIN review_cards c ON c.word_id = w.id
    LEFT JOIN wrong_word_states x ON x.word_id = w.id WHERE ${where}`).get(...params) as { count: number };
  const offset = (filters.page - 1) * filters.limit;
  const rows = sqlite.prepare(`SELECT w.*, c.due_at, c.reps, x.active AS wrong_active,
    wc.definitions_json, wc.pronunciations_json
    FROM words w LEFT JOIN review_cards c ON c.word_id = w.id
    LEFT JOIN wrong_word_states x ON x.word_id = w.id
    LEFT JOIN word_contents wc ON wc.word_id = w.id
    WHERE ${where} ORDER BY ${sortMap[filters.sort]} ${filters.order.toUpperCase()} LIMIT ? OFFSET ?`)
    .all(...params, filters.limit, offset) as Array<Record<string, unknown>>;
  return {
    items: rows.map((row) => {
      const definitions = parseJson<Array<{ language: string; text: string }>>(row.definitions_json, []);
      const preferred = definitions.find((item) => item.language === row.target_language) ?? definitions[0];
      return {
        id: Number(row.id), term: String(row.term), normalizedTerm: String(row.normalized_term),
        sourceLanguage: String(row.source_language), targetLanguage: String(row.target_language),
        entryType: String(row.content_type ?? row.entry_type), initializationStatus: String(row.initialization_status),
        masteryLevel: String(row.mastery_level), masteryScore: Number(row.mastery_score),
        isSuspended: Boolean(row.is_suspended), sourceCreatedAt: row.source_created_at ? new Date(Number(row.source_created_at)).toISOString() : null,
        createdAt: new Date(Number(row.created_at)).toISOString(), dueAt: row.due_at ? new Date(Number(row.due_at)).toISOString() : null,
        reps: Number(row.reps ?? 0), wrongWordActive: Boolean(row.wrong_active), definition: preferred?.text ?? null,
        hasPronunciation: parseJson<unknown[]>(row.pronunciations_json, []).length > 0,
      };
    }),
    pagination: { page: filters.page, limit: filters.limit, total: total.count, pages: Math.ceil(total.count / filters.limit) },
  };
}

export function getWordDetail(wordId: number) {
  const row = sqlite.prepare(`SELECT w.*, wc.*, c.due_at, c.stability, c.difficulty, c.elapsed_days,
    c.scheduled_days, c.reps, c.lapses, c.fsrs_state, c.last_review_at,
    x.active AS wrong_active, x.wrong_count, x.hard_count, x.consecutive_correct,
    x.last_wrong_at, x.last_correct_at, x.resolved_at
    FROM words w LEFT JOIN word_contents wc ON wc.word_id = w.id
    LEFT JOIN review_cards c ON c.word_id = w.id
    LEFT JOIN wrong_word_states x ON x.word_id = w.id WHERE w.id = ?`).get(wordId) as Record<string, unknown> | undefined;
  if (!row) return null;
  const content: DictionaryContent = row.word_id === null || row.word_id === undefined ? emptyDictionaryContent() : dictionaryContentFromRow(row);
  const recentLogs = sqlite.prepare(`SELECT id, reviewed_at, rating, question_type, is_correct, duration_ms
    FROM review_logs WHERE word_id = ? ORDER BY reviewed_at DESC LIMIT 20`).all(wordId) as Array<Record<string, unknown>>;
  const attempts = sqlite.prepare(`SELECT provider_id, status, duration_ms, fields_returned_json, error_code, error_message, metadata_json, created_at
    FROM provider_attempts WHERE word_id = ? ORDER BY created_at DESC LIMIT 20`).all(wordId) as Array<Record<string, unknown>>;
  return {
    id: Number(row.id), term: String(row.term), normalizedTerm: String(row.normalized_term),
    sourceLanguage: String(row.source_language), targetLanguage: String(row.target_language),
    sourceLanguageName: row.source_language_name, targetLanguageName: row.target_language_name,
    entryType: String(row.content_type ?? row.entry_type), initializationStatus: String(row.initialization_status),
    contentSource: String(row.content_source ?? "MIXED"),
    masteryLevel: String(row.mastery_level), masteryScore: Number(row.mastery_score), isSuspended: Boolean(row.is_suspended),
    userNote: row.user_note, sourceCreatedAt: row.source_created_at ? new Date(Number(row.source_created_at)).toISOString() : null,
    createdAt: new Date(Number(row.created_at)).toISOString(), updatedAt: new Date(Number(row.updated_at)).toISOString(),
    content,
    reviewCard: row.due_at === null || row.due_at === undefined ? null : {
      dueAt: new Date(Number(row.due_at)).toISOString(), stability: Number(row.stability), difficulty: Number(row.difficulty),
      elapsedDays: Number(row.elapsed_days), scheduledDays: Number(row.scheduled_days), reps: Number(row.reps),
      lapses: Number(row.lapses), state: Number(row.fsrs_state), lastReviewAt: row.last_review_at ? new Date(Number(row.last_review_at)).toISOString() : null,
    },
    wrongWordState: row.wrong_active === null || row.wrong_active === undefined ? null : {
      active: Boolean(row.wrong_active), wrongCount: Number(row.wrong_count), hardCount: Number(row.hard_count),
      consecutiveCorrect: Number(row.consecutive_correct), lastWrongAt: row.last_wrong_at ? new Date(Number(row.last_wrong_at)).toISOString() : null,
      lastCorrectAt: row.last_correct_at ? new Date(Number(row.last_correct_at)).toISOString() : null,
      resolvedAt: row.resolved_at ? new Date(Number(row.resolved_at)).toISOString() : null,
    },
    recentReviews: recentLogs.map((item) => ({
      id: Number(item.id), reviewedAt: new Date(Number(item.reviewed_at)).toISOString(), rating: String(item.rating),
      questionType: String(item.question_type), isCorrect: Boolean(item.is_correct), durationMs: item.duration_ms === null ? null : Number(item.duration_ms),
    })),
    providerAttempts: attempts.map((item) => ({
      providerId: String(item.provider_id), status: String(item.status), durationMs: Number(item.duration_ms ?? 0),
      fieldsReturned: parseJson(item.fields_returned_json, []), errorCode: item.error_code, errorMessage: item.error_message,
      metadata: parseJson(item.metadata_json, null), createdAt: new Date(Number(item.created_at)).toISOString(),
    })),
  };
}

function cancelPendingStudyItemsForSuspend(wordId: number, now: number): void {
  const sessions = sqlite.prepare(`SELECT study_session_id AS session_id, count(*) AS count
    FROM study_session_items
    WHERE word_id = ? AND status = 'PENDING'
    GROUP BY study_session_id`).all(wordId) as Array<{ session_id: number; count: number }>;
  if (sessions.length === 0) return;
  sqlite.prepare(`UPDATE study_session_items SET status = 'SKIPPED', answered_at = ?, skip_reason = 'WORD_SUSPENDED'
    WHERE word_id = ? AND status = 'PENDING'`).run(now, wordId);
  for (const session of sessions) {
    sqlite.prepare(`UPDATE study_sessions SET completed_count = completed_count + ?, skipped_count = skipped_count + ? WHERE id = ?`)
      .run(session.count, session.count, session.session_id);
    const pending = sqlite.prepare(`SELECT count(*) AS count FROM study_session_items
      WHERE study_session_id = ? AND status = 'PENDING'`).get(session.session_id) as { count: number };
    if (pending.count === 0) {
      const started = sqlite.prepare("SELECT started_at FROM study_sessions WHERE id = ?").get(session.session_id) as { started_at: number };
      sqlite.prepare("UPDATE study_sessions SET completed_at = ?, duration_ms = ? WHERE id = ?")
        .run(now, now - started.started_at, session.session_id);
    }
  }
}

const updateSchema = z.object({ userNote: z.string().max(5000).nullable().optional(), isSuspended: z.boolean().optional() }).strict();
export function updateWord(wordId: number, input: unknown) {
  const values = updateSchema.parse(input);
  const current = sqlite.prepare("SELECT id FROM words WHERE id = ?").get(wordId);
  if (!current) throw new Error("WORD_NOT_FOUND");
  const updates: string[] = [];
  const params: Array<string | number | null> = [];
  if (values.userNote !== undefined) { updates.push("user_note = ?"); params.push(values.userNote); }
  if (values.isSuspended !== undefined) { updates.push("is_suspended = ?"); params.push(values.isSuspended ? 1 : 0); }
  if (updates.length) {
    updates.push("updated_at = ?"); params.push(Date.now(), wordId);
    sqlite.prepare(`UPDATE words SET ${updates.join(", ")} WHERE id = ?`).run(...params);
  }
  if (values.isSuspended === true) {
    cancelPendingStudyItemsForSuspend(wordId, Date.now());
  }
  return getWordDetail(wordId);
}



const manualDefinitionSchema = z.object({
  definition: z.string().trim().max(2000),
  partOfSpeech: z.string().trim().max(50).nullable().optional(),
}).strict();

export function updateManualDefinition(wordId: number, input: unknown) {
  const values = manualDefinitionSchema.parse(input);
  const word = sqlite.prepare("SELECT id, target_language, content_type FROM words WHERE id = ?").get(wordId) as {
    id: number; target_language: string; content_type: import("@/lib/types").EntryType;
  } | undefined;
  if (!word) throw new Error("WORD_NOT_FOUND");
  const row = sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(wordId) as Record<string, unknown> | undefined;
  const content: DictionaryContent = row ? dictionaryContentFromRow(row) : emptyDictionaryContent();
  content.definitions = content.definitions.filter((definition) => !(definition.source === "user" && definition.isUserEdited));
  if (values.definition) {
    content.definitions.unshift({
      language: word.target_language,
      partOfSpeech: values.partOfSpeech || null,
      text: values.definition,
      source: "user",
      isUserEdited: true,
    });
  }
  const status = contentStatus(content, word.content_type);
  const now = Date.now();
  sqlite.transaction(() => {
    sqlite.prepare(`INSERT INTO word_contents
      (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
       synonyms_json, antonyms_json, word_family_json, confused_words_json, roots_json, affixes_json,
       summary_json, learning_json, sentence_analysis_json, tags_json, provider_metadata_json, content_version, initialized_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', 1, ?, ?)
      ON CONFLICT(word_id) DO UPDATE SET definitions_json = excluded.definitions_json,
        content_version = word_contents.content_version + 1, initialized_at = excluded.initialized_at,
        updated_at = excluded.updated_at`)
      .run(
        wordId,
        JSON.stringify(content.definitions), JSON.stringify(content.pronunciations), JSON.stringify(content.examples),
        JSON.stringify(content.phrases), JSON.stringify(content.forms), JSON.stringify(content.synonyms),
        JSON.stringify(content.antonyms), JSON.stringify(content.wordFamily), JSON.stringify(content.confusedWords),
        JSON.stringify(content.roots), JSON.stringify(content.affixes), JSON.stringify(content.summary),
        JSON.stringify(content.learning), JSON.stringify(content.sentenceAnalysis), JSON.stringify(content.tags), now, now,
      );
    sqlite.prepare("UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?")
      .run(status, now, wordId);
  }).immediate();
  return getWordDetail(wordId);
}


const relatedWordSchema = z.object({
  term: z.string().trim().min(1).max(300),
  relation: z.enum(["SYNONYM", "ANTONYM", "WORD_FAMILY", "CONFUSED_WITH"]).default("SYNONYM"),
}).strict();

function findRelatedContent(content: DictionaryContent, term: string) {
  const key = term.normalize("NFKC").trim().toLocaleLowerCase();
  return [...content.synonyms, ...content.antonyms, ...content.wordFamily, ...content.confusedWords]
    .find((item) => item.word.normalize("NFKC").trim().toLocaleLowerCase() === key) ?? null;
}

export function previewRelatedWord(parentWordId: number, rawTerm: string) {
  const parent = sqlite.prepare(`SELECT w.*, wc.* FROM words w
    LEFT JOIN word_contents wc ON wc.word_id = w.id WHERE w.id = ?`).get(parentWordId) as Record<string, unknown> | undefined;
  if (!parent) throw new Error("WORD_NOT_FOUND");
  const term = relatedWordSchema.shape.term.parse(rawTerm);
  const normalizedTerm = normalizeTerm(term, String(parent.source_language));
  if (normalizedTerm === String(parent.normalized_term)) throw new Error("RELATED_WORD_SAME_AS_PARENT");
  const existing = sqlite.prepare(`SELECT id, term, initialization_status, mastery_level, mastery_score
    FROM words WHERE normalized_term = ? AND source_language = ? AND target_language = ? LIMIT 1`)
    .get(normalizedTerm, parent.source_language, parent.target_language) as {
      id: number; term: string; initialization_status: string; mastery_level: string; mastery_score: number;
    } | undefined;
  const content = parent.word_id === null || parent.word_id === undefined ? emptyDictionaryContent() : dictionaryContentFromRow(parent);
  const related = findRelatedContent(content, term);
  return {
    term,
    normalizedTerm,
    sourceLanguage: String(parent.source_language),
    targetLanguage: String(parent.target_language),
    relation: related?.relation ?? "SYNONYM",
    translation: related?.translation ?? null,
    partOfSpeech: related?.partOfSpeech ?? null,
    difference: related?.difference ?? null,
    source: related?.source ?? null,
    existing: existing ? {
      id: existing.id,
      term: existing.term,
      initializationStatus: existing.initialization_status,
      masteryLevel: existing.mastery_level,
      masteryScore: existing.mastery_score,
    } : null,
  };
}

export function addRelatedWord(parentWordId: number, input: unknown) {
  const values = relatedWordSchema.parse(input);
  const parent = sqlite.prepare(`SELECT id, normalized_term, source_language, target_language,
    source_language_name, target_language_name, content_type FROM words WHERE id = ?`).get(parentWordId) as {
      id: number; normalized_term: string; source_language: string; target_language: string;
      source_language_name: string | null; target_language_name: string | null; content_type: import("@/lib/types").EntryType;
    } | undefined;
  if (!parent) throw new Error("WORD_NOT_FOUND");
  const normalizedTerm = normalizeTerm(values.term, parent.source_language);
  if (normalizedTerm === parent.normalized_term) throw new Error("RELATED_WORD_SAME_AS_PARENT");
  const now = Date.now();
  return sqlite.transaction(() => {
    let word = sqlite.prepare(`SELECT id, term, initialization_status FROM words
      WHERE normalized_term = ? AND source_language = ? AND target_language = ? LIMIT 1`)
      .get(normalizedTerm, parent.source_language, parent.target_language) as {
        id: number; term: string; initialization_status: string;
      } | undefined;
    let created = false;
    if (!word) {
      const inserted = sqlite.prepare(`INSERT INTO words
        (term, normalized_term, source_language, target_language, source_language_name, target_language_name,
         entry_type, content_type, initialization_status, mastery_level, mastery_score, is_suspended, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'QUEUED', 'NEW', 0, 0, ?, ?)`)
        .run(values.term, normalizedTerm, parent.source_language, parent.target_language,
          parent.source_language_name, parent.target_language_name,
          legacyEntryType(detectEntryType(values.term)), detectEntryType(values.term), now, now);
      word = { id: Number(inserted.lastInsertRowid), term: values.term, initialization_status: "QUEUED" };
      created = true;
    }

    let jobId: number | null = null;
    const needsInitialization = !["READY", "PARTIAL"].includes(word.initialization_status);
    if (needsInitialization) {
      const active = sqlite.prepare(`SELECT id FROM initialization_jobs
        WHERE word_id = ? AND status IN ('QUEUED','RUNNING') LIMIT 1`).get(word.id) as { id: number } | undefined;
      if (active) {
        jobId = active.id;
        sqlite.prepare(`UPDATE initialization_jobs SET mode = 'FILL_MISSING_FIELDS',
          priority = MAX(priority, 80), available_at = ?, updated_at = ? WHERE id = ?`)
          .run(now, now, active.id);
      } else {
        const job = sqlite.prepare(`INSERT INTO initialization_jobs
          (word_id, mode, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
          VALUES (?, ?, 'QUEUED', 80, 0, 5, ?, ?, ?)`)
          .run(word.id, created ? "SKIP_INITIALIZED" : "FILL_MISSING_FIELDS", now, now, now);
        jobId = Number(job.lastInsertRowid);
      }
      sqlite.prepare("UPDATE words SET initialization_status = 'QUEUED', updated_at = ? WHERE id = ?")
        .run(now, word.id);
    }
    return {
      wordId: word.id,
      term: word.term,
      created,
      queued: needsInitialization,
      jobId,
      relation: values.relation,
      initializationStatus: needsInitialization ? "QUEUED" : word.initialization_status,
    };
  }).immediate();
}

export function deleteWord(wordId: number, force = false): boolean {
  const word = sqlite.prepare("SELECT id FROM words WHERE id = ?").get(wordId);
  if (!word) return false;
  if (!force) {
    const history = sqlite.prepare(`SELECT
      EXISTS(SELECT 1 FROM review_logs WHERE word_id = ?) AS has_reviews,
      EXISTS(SELECT 1 FROM study_session_items WHERE word_id = ?) AS has_session_items`)
      .get(wordId, wordId) as { has_reviews: number; has_session_items: number };
    if (history.has_reviews || history.has_session_items) throw new Error("WORD_HAS_LEARNING_HISTORY");
  }
  return sqlite.transaction(() => {
    if (force) {
      sqlite.prepare("DELETE FROM review_logs WHERE word_id = ?").run(wordId);
      sqlite.prepare("DELETE FROM review_cards WHERE word_id = ?").run(wordId);
      sqlite.prepare("DELETE FROM wrong_word_states WHERE word_id = ?").run(wordId);
      sqlite.prepare("DELETE FROM study_session_items WHERE word_id = ?").run(wordId);
      sqlite.prepare("DELETE FROM initialization_jobs WHERE word_id = ?").run(wordId);
      sqlite.prepare("DELETE FROM provider_attempts WHERE word_id = ?").run(wordId);
    }
    return sqlite.prepare("DELETE FROM words WHERE id = ?").run(wordId).changes === 1;
  }).immediate();
}
