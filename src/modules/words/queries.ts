import { sqlite } from "@/db/client";
import { parseJson } from "@/lib/json";
import type { DictionaryContent, InitializationStatus, MasteryLevel } from "@/lib/types";
import { INITIALIZATION_STATUSES, MASTERY_LEVELS } from "@/lib/types";
import { dictionaryContentFromRow, emptyDictionaryContent } from "@/modules/dictionary/content";

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

const SORT_COLUMNS = {
  createdAt: "w.created_at",
  term: "w.normalized_term",
  masteryScore: "w.mastery_score",
  sourceCreatedAt: "COALESCE(w.source_created_at, w.created_at)",
  dueAt: "COALESCE(c.due_at, 9223372036854775807)",
} as const;

function buildFilters(filters: WordListFilters) {
  const conditions = ["1 = 1"];
  const params: Array<string | number> = [];
  if (filters.query) {
    conditions.push("(w.term LIKE ? ESCAPE '\\' OR w.normalized_term LIKE ? ESCAPE '\\' OR COALESCE(w.user_note, '') LIKE ? ESCAPE '\\')");
    const escaped = filters.query.replace(/[\\%_]/g, "\\$&");
    params.push(`%${escaped}%`, `%${escaped}%`, `%${escaped}%`);
  }
  if (filters.status && INITIALIZATION_STATUSES.includes(filters.status)) {
    conditions.push("w.initialization_status = ?");
    params.push(filters.status);
  }
  if (filters.mastery && MASTERY_LEVELS.includes(filters.mastery)) {
    conditions.push("w.mastery_level = ?");
    params.push(filters.mastery);
  }
  if (filters.wrong) conditions.push("COALESCE(x.active, 0) = 1");
  if (filters.due) {
    conditions.push("c.due_at <= ?");
    params.push(Date.now());
  }
  if (filters.suspended !== undefined) {
    conditions.push("w.is_suspended = ?");
    params.push(filters.suspended ? 1 : 0);
  }
  return { where: conditions.join(" AND "), params };
}

function mapWordRow(row: Record<string, unknown>) {
  const definitions = parseJson<Array<{ language: string; text: string }>>(row.definitions_json, []);
  const preferred = definitions.find((item) => item.language === row.target_language) ?? definitions[0];
  return {
    id: Number(row.id),
    term: String(row.term),
    normalizedTerm: String(row.normalized_term),
    sourceLanguage: String(row.source_language),
    targetLanguage: String(row.target_language),
    entryType: String(row.content_type ?? row.entry_type),
    initializationStatus: String(row.initialization_status),
    masteryLevel: String(row.mastery_level),
    masteryScore: Number(row.mastery_score),
    isSuspended: Boolean(row.is_suspended),
    sourceCreatedAt: row.source_created_at ? new Date(Number(row.source_created_at)).toISOString() : null,
    createdAt: new Date(Number(row.created_at)).toISOString(),
    dueAt: row.due_at ? new Date(Number(row.due_at)).toISOString() : null,
    reps: Number(row.reps ?? 0),
    wrongWordActive: Boolean(row.wrong_active),
    definition: preferred?.text ?? null,
    hasPronunciation: parseJson<unknown[]>(row.pronunciations_json, []).length > 0,
  };
}

export function listWords(filters: WordListFilters) {
  const { where, params } = buildFilters(filters);
  const total = sqlite.prepare(`SELECT count(*) AS count FROM words w
    LEFT JOIN review_cards c ON c.word_id = w.id
    LEFT JOIN wrong_word_states x ON x.word_id = w.id WHERE ${where}`).get(...params) as { count: number };
  const rows = sqlite.prepare(`SELECT w.*, c.due_at, c.reps, x.active AS wrong_active,
    wc.definitions_json, wc.pronunciations_json
    FROM words w LEFT JOIN review_cards c ON c.word_id = w.id
    LEFT JOIN wrong_word_states x ON x.word_id = w.id
    LEFT JOIN word_contents wc ON wc.word_id = w.id
    WHERE ${where} ORDER BY ${SORT_COLUMNS[filters.sort]} ${filters.order.toUpperCase()} LIMIT ? OFFSET ?`)
    .all(...params, filters.limit, (filters.page - 1) * filters.limit) as Array<Record<string, unknown>>;
  return {
    items: rows.map(mapWordRow),
    pagination: { page: filters.page, limit: filters.limit, total: total.count, pages: Math.ceil(total.count / filters.limit) },
  };
}

function mapReview(row: Record<string, unknown>) {
  return {
    id: Number(row.id), reviewedAt: new Date(Number(row.reviewed_at)).toISOString(), rating: String(row.rating),
    questionType: String(row.question_type), isCorrect: Boolean(row.is_correct),
    durationMs: row.duration_ms === null ? null : Number(row.duration_ms),
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
  const content: DictionaryContent = row.word_id == null ? emptyDictionaryContent() : dictionaryContentFromRow(row);
  const recentReviews = sqlite.prepare(`SELECT id, reviewed_at, rating, question_type, is_correct, duration_ms
    FROM review_logs WHERE word_id = ? ORDER BY reviewed_at DESC LIMIT 20`).all(wordId) as Array<Record<string, unknown>>;
  const attempts = sqlite.prepare(`SELECT provider_id, status, duration_ms, fields_returned_json, error_code, error_message, metadata_json, created_at
    FROM provider_attempts WHERE word_id = ? ORDER BY created_at DESC LIMIT 20`).all(wordId) as Array<Record<string, unknown>>;
  return {
    id: Number(row.id), term: String(row.term), normalizedTerm: String(row.normalized_term),
    sourceLanguage: String(row.source_language), targetLanguage: String(row.target_language),
    sourceLanguageName: row.source_language_name, targetLanguageName: row.target_language_name,
    entryType: String(row.content_type ?? row.entry_type), contentSource: String(row.content_source ?? "MIXED"),
    initializationStatus: String(row.initialization_status), masteryLevel: String(row.mastery_level),
    masteryScore: Number(row.mastery_score), isSuspended: Boolean(row.is_suspended), userNote: row.user_note,
    sourceCreatedAt: row.source_created_at ? new Date(Number(row.source_created_at)).toISOString() : null,
    createdAt: new Date(Number(row.created_at)).toISOString(), updatedAt: new Date(Number(row.updated_at)).toISOString(),
    content,
    reviewCard: row.due_at == null ? null : {
      dueAt: new Date(Number(row.due_at)).toISOString(), stability: Number(row.stability), difficulty: Number(row.difficulty),
      elapsedDays: Number(row.elapsed_days), scheduledDays: Number(row.scheduled_days), reps: Number(row.reps),
      lapses: Number(row.lapses), state: Number(row.fsrs_state),
      lastReviewAt: row.last_review_at ? new Date(Number(row.last_review_at)).toISOString() : null,
    },
    wrongWordState: row.wrong_active == null ? null : {
      active: Boolean(row.wrong_active), wrongCount: Number(row.wrong_count), hardCount: Number(row.hard_count),
      consecutiveCorrect: Number(row.consecutive_correct),
      lastWrongAt: row.last_wrong_at ? new Date(Number(row.last_wrong_at)).toISOString() : null,
      lastCorrectAt: row.last_correct_at ? new Date(Number(row.last_correct_at)).toISOString() : null,
      resolvedAt: row.resolved_at ? new Date(Number(row.resolved_at)).toISOString() : null,
    },
    recentReviews: recentReviews.map(mapReview),
    providerAttempts: attempts.map((item) => ({
      providerId: String(item.provider_id), status: String(item.status), durationMs: Number(item.duration_ms ?? 0),
      fieldsReturned: parseJson(item.fields_returned_json, []), errorCode: item.error_code, errorMessage: item.error_message,
      metadata: parseJson(item.metadata_json, null), createdAt: new Date(Number(item.created_at)).toISOString(),
    })),
  };
}
