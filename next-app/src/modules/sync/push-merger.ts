import { sqlite } from "@/db/client";
import { DAY_MS } from "@/lib/time";
import type { ReviewRating } from "@/lib/types";
import { getSettings, invalidateSettingsCache } from "@/modules/settings/service";
import { replayWordHistory, type ReplayLogEntry } from "./learning-replay";
import { ensureServerSyncState, recordServerPeerSync } from "./server-state";
import {
  SQL_BATCH_SIZE,
  SYNC_EXCLUDED_SETTING_KEYS,
  type PushRequest,
  type SyncMergeSummary,
  type SyncRow,
} from "./types";

const MASTERY_WINDOW_MS = 30 * DAY_MS;
const PERFORMANCE_WINDOW_MS = 14 * DAY_MS;

const MERGEABLE_WORD_COLS = [
  "term",
  "source_language_name",
  "target_language_name",
  "entry_type",
  "content_type",
  "source_created_at",
  "is_suspended",
  "user_note",
  "updated_at",
] as const;

const SESSION_ADVANCE_COLS = [
  "completed_at",
  "planned_count",
  "completed_count",
  "correct_count",
  "wrong_count",
  "skipped_count",
  "duration_ms",
] as const;

const BOOLEAN_INT_COLS: Readonly<Record<string, ReadonlySet<string>>> = {
  words: new Set(["is_suspended", "is_personal"]),
  review_logs: new Set(["is_correct"]),
  wrong_word_states: new Set(["active"]),
  word_packs: new Set(["include_in_daily_study"]),
};

const VALID_RATINGS: ReadonlySet<string> = new Set(["AGAIN", "HARD", "GOOD", "EASY"]);

function asInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asFloat(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function isTruthyBool(value: unknown, defaultTrue = false): boolean {
  if (value === null || value === undefined) return defaultTrue;
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  return defaultTrue;
}

function normalizeInitStatus(value: unknown): unknown {
  return value === "QUEUED" || value === "RUNNING" ? "PENDING" : value;
}

function isNewer(incoming: SyncRow, existing: SyncRow): boolean {
  return (asInt(incoming.updated_at) ?? 0) > (asInt(existing.updated_at) ?? 0);
}

function wordIdentityOf(row: SyncRow): string {
  return `${asString(row.normalized_term)}\u0000${asString(row.source_language)}\u0000${asString(row.target_language)}`;
}

function sessionIdentityOf(row: SyncRow): string {
  return `${asInt(row.started_at) ?? 0}\u0000${asString(row.session_type)}\u0000${asString(row.source_type)}`;
}

function sessionProgressOf(row: SyncRow): number {
  return (asInt(row.completed_count) ?? 0) + (asInt(row.skipped_count) ?? 0);
}

function escapeId(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}

function normalizeCell(table: string, col: string, value: unknown): unknown {
  if (value === undefined) return null;
  if (typeof value === "boolean" && BOOLEAN_INT_COLS[table]?.has(col)) {
    return value ? 1 : 0;
  }
  return value;
}

function* chunksOf<T>(items: readonly T[]): Generator<T[]> {
  for (let start = 0; start < items.length; start += SQL_BATCH_SIZE) {
    yield items.slice(start, start + SQL_BATCH_SIZE);
  }
}

function compareLogRows(a: SyncRow, b: SyncRow): number {
  const byTime = (asInt(a.reviewed_at) ?? 0) - (asInt(b.reviewed_at) ?? 0);
  if (byTime !== 0) return byTime;
  return asString(a.client_answer_id).localeCompare(asString(b.client_answer_id));
}

function toReplayLog(row: SyncRow): ReplayLogEntry {
  const rawRating = asString(row.rating);
  const rating: ReviewRating = VALID_RATINGS.has(rawRating) ? (rawRating as ReviewRating) : "GOOD";
  return {
    reviewedAt: asInt(row.reviewed_at) ?? 0,
    rating,
    isCorrect: isTruthyBool(row.is_correct, false),
    durationMs: asInt(row.duration_ms),
  };
}

class PushMergeRun {
  private readonly columnCache = new Map<string, string[]>();
  private readonly wordIdMap = new Map<number, number>();
  private readonly sessionIdMap = new Map<number, number>();
  private readonly itemIdMap = new Map<number, number>();
  private readonly touchedWordIds = new Set<number>();

  private addedWords = 0;
  private updatedWords = 0;
  private addedLogs = 0;

  constructor(
    private readonly payload: PushRequest,
    private readonly requestRetention: number,
    private readonly now: number,
  ) {}

  async execute(): Promise<SyncMergeSummary> {
    await this.resolveAndMergeWords();
    await this.mergeContents();
    await this.resolveSessionAndItemRefs();
    await this.mergeSessions();
    await this.mergeLogs();
    await this.rebuildTouchedDerived();
    await this.mergeSettings();
    await this.mergeWordPacks();
    await this.mergeWordPackItems();

    const countRow = await sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count?: number } | undefined;
    return {
      addedWords: this.addedWords,
      updatedWords: this.updatedWords,
      addedLogs: this.addedLogs,
      rebuiltWords: this.touchedWordIds.size,
      wordCount: countRow?.count ?? 0,
    };
  }

  private async columnsOf(table: string): Promise<string[]> {
    const cached = this.columnCache.get(table);
    if (cached) return cached;
    const rows = await sqlite
      .prepare(
        `SELECT column_name FROM information_schema.columns
         WHERE table_schema = current_schema() AND table_name = ?`,
      )
      .all(table) as { column_name: string }[];
    const cols = rows.map((row) => row.column_name);
    this.columnCache.set(table, cols);
    return cols;
  }

  private async insertReturningId(table: string, row: SyncRow, tableCols: readonly string[]): Promise<number> {
    const usable = tableCols.filter((col) => col !== "id" && col in row);
    const colList = usable.map(escapeId).join(", ");
    const marks = usable.map(() => "?").join(", ");
    const params = usable.map((col) => normalizeCell(table, col, row[col]));
    const result = await sqlite
      .prepare(`INSERT INTO ${escapeId(table)} (${colList}) VALUES (${marks}) RETURNING id`)
      .get(...params) as { id: number };
    return result.id;
  }

  private async updateWhereId(table: string, id: number, updates: SyncRow, tableCols: readonly string[]): Promise<void> {
    const usable = tableCols.filter((col) => col !== "id" && col in updates);
    if (usable.length === 0) return;
    const setSql = usable.map((col) => `${escapeId(col)} = ?`).join(", ");
    const params = [...usable.map((col) => normalizeCell(table, col, updates[col])), id];
    await sqlite.prepare(`UPDATE ${escapeId(table)} SET ${setSql} WHERE id = ?`).run(...params);
  }

  private async upsertByConflict(
    table: string,
    conflictCol: string,
    row: SyncRow,
    tableCols: readonly string[],
  ): Promise<void> {
    const usable = tableCols.filter((col) => col in row);
    if (usable.length === 0) return;
    const colList = usable.map(escapeId).join(", ");
    const marks = usable.map(() => "?").join(", ");
    const updates = usable
      .filter((col) => col !== conflictCol)
      .map((col) => `${escapeId(col)} = EXCLUDED.${escapeId(col)}`)
      .join(", ");
    const sql = updates
      ? `INSERT INTO ${escapeId(table)} (${colList}) VALUES (${marks}) ON CONFLICT(${escapeId(conflictCol)}) DO UPDATE SET ${updates}`
      : `INSERT INTO ${escapeId(table)} (${colList}) VALUES (${marks}) ON CONFLICT(${escapeId(conflictCol)}) DO NOTHING`;
    const params = usable.map((col) => normalizeCell(table, col, row[col]));
    await sqlite.prepare(sql).run(...params);
  }

  private async resolveAndMergeWords(): Promise<void> {
    const terms = new Set<string>();
    for (const ref of this.payload.word_refs) {
      const term = asString(ref.normalized_term);
      if (term) terms.add(term);
    }
    for (const row of this.payload.words) {
      const term = asString(row.normalized_term);
      if (term) terms.add(term);
    }

    const existingByIdentity = new Map<string, SyncRow>();
    for (const chunk of chunksOf([...terms])) {
      const marks = chunk.map(() => "?").join(", ");
      const rows = await sqlite
        .prepare(`SELECT * FROM words WHERE normalized_term IN (${marks})`)
        .all(...chunk) as SyncRow[];
      for (const row of rows) existingByIdentity.set(wordIdentityOf(row), row);
    }

    for (const ref of this.payload.word_refs) {
      const remoteId = asInt(ref.id);
      const existing = existingByIdentity.get(wordIdentityOf(ref));
      const localId = existing ? asInt(existing.id) : null;
      if (remoteId !== null && localId !== null) this.wordIdMap.set(remoteId, localId);
    }

    if (this.payload.words.length === 0) return;
    const wordCols = await this.columnsOf("words");

    for (const incoming of this.payload.words) {
      const identity = wordIdentityOf(incoming);
      const remoteId = asInt(incoming.id);
      const existing = existingByIdentity.get(identity);

      if (!existing) {
        const prepared: SyncRow = {
          ...incoming,
          is_personal: isTruthyBool(incoming.is_personal, true) ? 1 : 0,
          is_suspended: isTruthyBool(incoming.is_suspended, false) ? 1 : 0,
          ...("initialization_status" in incoming
            ? { initialization_status: normalizeInitStatus(incoming.initialization_status) }
            : {}),
        };
        delete prepared.id;
        const insertedId = await this.insertReturningId("words", prepared, wordCols);
        prepared.id = insertedId;
        existingByIdentity.set(identity, prepared);
        if (remoteId !== null) this.wordIdMap.set(remoteId, insertedId);
        this.addedWords += 1;
        continue;
      }

      const localId = asInt(existing.id)!;
      if (remoteId !== null) this.wordIdMap.set(remoteId, localId);

      const updates: SyncRow = {};
      if (!isTruthyBool(existing.is_personal, true) && isTruthyBool(incoming.is_personal, true)) {
        updates.is_personal = 1;
      }
      const metadataChanged = isNewer(incoming, existing);
      if (metadataChanged) {
        for (const col of MERGEABLE_WORD_COLS) {
          if (col in incoming) updates[col] = incoming[col];
        }
      }
      if (Object.keys(updates).length > 0) {
        await this.updateWhereId("words", localId, updates, wordCols);
        Object.assign(existing, updates);
        if (metadataChanged) this.updatedWords += 1;
      }
    }
  }

  private async mergeContents(): Promise<void> {
    if (this.payload.word_contents.length === 0) return;
    const mappedWordIds = new Set<number>();
    for (const row of this.payload.word_contents) {
      const wid = this.wordIdMap.get(asInt(row.word_id) ?? -1);
      if (wid !== undefined) mappedWordIds.add(wid);
    }
    const existingByWord = new Map<number, SyncRow>();
    for (const chunk of chunksOf([...mappedWordIds])) {
      const marks = chunk.map(() => "?").join(", ");
      const rows = await sqlite
        .prepare(`SELECT * FROM word_contents WHERE word_id IN (${marks})`)
        .all(...chunk) as SyncRow[];
      for (const row of rows) {
        const wid = asInt(row.word_id);
        if (wid !== null) existingByWord.set(wid, row);
      }
    }

    const cols = await this.columnsOf("word_contents");
    for (const row of this.payload.word_contents) {
      const wid = this.wordIdMap.get(asInt(row.word_id) ?? -1);
      if (wid === undefined) continue;
      const existing = existingByWord.get(wid);
      if (existing && !isNewer(row, existing)) continue;
      const prepared: SyncRow = { ...row, word_id: wid };
      await this.upsertByConflict("word_contents", "word_id", prepared, cols);
      existingByWord.set(wid, prepared);
    }
  }

  private async resolveSessionAndItemRefs(): Promise<void> {
    if (this.payload.session_refs.length === 0 && this.payload.item_refs.length === 0) return;

    const startedAts = new Set<number>();
    for (const ref of this.payload.session_refs) {
      const ts = asInt(ref.started_at);
      if (ts !== null) startedAts.add(ts);
    }

    if (startedAts.size > 0) {
      const byIdentity = new Map<string, SyncRow>();
      for (const chunk of chunksOf([...startedAts])) {
        const marks = chunk.map(() => "?").join(", ");
        const rows = await sqlite
          .prepare(`SELECT id, started_at, session_type, source_type FROM study_sessions WHERE started_at IN (${marks})`)
          .all(...chunk) as SyncRow[];
        for (const row of rows) byIdentity.set(sessionIdentityOf(row), row);
      }
      for (const ref of this.payload.session_refs) {
        const remoteId = asInt(ref.id);
        const existing = byIdentity.get(sessionIdentityOf(ref));
        const localId = existing ? asInt(existing.id) : null;
        if (remoteId !== null && localId !== null) this.sessionIdMap.set(remoteId, localId);
      }
    }

    if (this.payload.item_refs.length === 0) return;
    const localSessionIds = new Set<number>();
    for (const ref of this.payload.item_refs) {
      const localSid = this.sessionIdMap.get(asInt(ref.study_session_id) ?? -1);
      if (localSid !== undefined) localSessionIds.add(localSid);
    }
    if (localSessionIds.size === 0) return;

    const itemBySessionPos = new Map<string, number>();
    for (const chunk of chunksOf([...localSessionIds])) {
      const marks = chunk.map(() => "?").join(", ");
      const rows = await sqlite
        .prepare(`SELECT id, study_session_id, position FROM study_session_items WHERE study_session_id IN (${marks})`)
        .all(...chunk) as SyncRow[];
      for (const row of rows) {
        const sid = asInt(row.study_session_id);
        const pos = asFloat(row.position);
        const id = asInt(row.id);
        if (sid !== null && pos !== null && id !== null) {
          itemBySessionPos.set(`${sid}\u0000${pos}`, id);
        }
      }
    }
    for (const ref of this.payload.item_refs) {
      const remoteItemId = asInt(ref.id);
      const localSid = this.sessionIdMap.get(asInt(ref.study_session_id) ?? -1);
      const pos = asFloat(ref.position);
      if (remoteItemId === null || localSid === undefined || pos === null) continue;
      const localItemId = itemBySessionPos.get(`${localSid}\u0000${pos}`);
      if (localItemId !== undefined) this.itemIdMap.set(remoteItemId, localItemId);
    }
  }

  private async mergeSessions(): Promise<void> {
    if (this.payload.study_sessions.length === 0) return;

    const itemsByRemoteSession = new Map<number, SyncRow[]>();
    for (const item of this.payload.study_session_items) {
      const sid = asInt(item.study_session_id);
      if (sid === null) continue;
      const list = itemsByRemoteSession.get(sid) ?? [];
      list.push(item);
      itemsByRemoteSession.set(sid, list);
    }

    const startedAts = new Set<number>();
    for (const s of this.payload.study_sessions) {
      const ts = asInt(s.started_at);
      if (ts !== null) startedAts.add(ts);
    }
    const existingSessions = new Map<string, SyncRow>();
    for (const chunk of chunksOf([...startedAts])) {
      const marks = chunk.map(() => "?").join(", ");
      const rows = await sqlite
        .prepare(`SELECT * FROM study_sessions WHERE started_at IN (${marks})`)
        .all(...chunk) as SyncRow[];
      for (const row of rows) existingSessions.set(sessionIdentityOf(row), row);
    }

    const sessionCols = await this.columnsOf("study_sessions");
    const itemCols = await this.columnsOf("study_session_items");

    for (const incoming of this.payload.study_sessions) {
      const remoteId = asInt(incoming.id);
      const identity = sessionIdentityOf(incoming);
      const existing = existingSessions.get(identity);
      const remoteItems = remoteId !== null ? (itemsByRemoteSession.get(remoteId) ?? []) : [];

      if (existing) {
        const localId = asInt(existing.id)!;
        if (remoteId !== null) this.sessionIdMap.set(remoteId, localId);
        await this.advanceSession(existing, incoming, sessionCols);
        await this.mergeExistingSessionItems(localId, remoteItems, itemCols);
        continue;
      }

      const prepared: SyncRow = { ...incoming };
      delete prepared.id;
      const localId = await this.insertReturningId("study_sessions", prepared, sessionCols);
      prepared.id = localId;
      existingSessions.set(identity, prepared);
      if (remoteId !== null) this.sessionIdMap.set(remoteId, localId);
      await this.insertSessionItems(localId, remoteItems, itemCols);
    }
  }

  private async advanceSession(existing: SyncRow, incoming: SyncRow, cols: readonly string[]): Promise<void> {
    const incomingDone = asInt(incoming.completed_at);
    const existingDone = asInt(existing.completed_at);
    const shouldAdvance =
      (incomingDone !== null && existingDone === null) ||
      sessionProgressOf(incoming) > sessionProgressOf(existing);
    if (!shouldAdvance) return;

    const updates: SyncRow = {};
    for (const col of SESSION_ADVANCE_COLS) {
      if (col in incoming) updates[col] = incoming[col];
    }
    if (Object.keys(updates).length === 0) return;
    await this.updateWhereId("study_sessions", asInt(existing.id)!, updates, cols);
    Object.assign(existing, updates);
  }

  private async mergeExistingSessionItems(
    localSessionId: number,
    incomingItems: readonly SyncRow[],
    itemCols: readonly string[],
  ): Promise<void> {
    if (incomingItems.length === 0) return;
    const localRows = await sqlite
      .prepare("SELECT * FROM study_session_items WHERE study_session_id = ?")
      .all(localSessionId) as SyncRow[];
    const byPos = new Map<number, SyncRow>();
    for (const row of localRows) {
      const pos = asFloat(row.position);
      if (pos !== null) byPos.set(pos, row);
    }

    for (const item of incomingItems) {
      const remoteId = asInt(item.id);
      const pos = asFloat(item.position);
      const existing = pos !== null ? byPos.get(pos) : undefined;
      if (existing) {
        const localItemId = asInt(existing.id)!;
        if (remoteId !== null) this.itemIdMap.set(remoteId, localItemId);
        if (asString(existing.status) === "PENDING" && asString(item.status) !== "PENDING") {
          const updates: SyncRow = {
            status: item.status,
            answered_at: item.answered_at ?? null,
            skip_reason: item.skip_reason ?? null,
          };
          await this.updateWhereId("study_session_items", localItemId, updates, itemCols);
          Object.assign(existing, updates);
        }
        continue;
      }

      const wordId = this.wordIdMap.get(asInt(item.word_id) ?? -1);
      if (wordId === undefined) continue;
      const prepared: SyncRow = {
        ...item,
        study_session_id: localSessionId,
        word_id: wordId,
      };
      delete prepared.id;
      const insertedId = await this.insertReturningId("study_session_items", prepared, itemCols);
      if (pos !== null) byPos.set(pos, { ...prepared, id: insertedId });
      if (remoteId !== null) this.itemIdMap.set(remoteId, insertedId);
    }
  }

  private async insertSessionItems(
    localSessionId: number,
    items: readonly SyncRow[],
    itemCols: readonly string[],
  ): Promise<void> {
    for (const item of items) {
      const wordId = this.wordIdMap.get(asInt(item.word_id) ?? -1);
      if (wordId === undefined) continue;
      const remoteId = asInt(item.id);
      const prepared: SyncRow = {
        ...item,
        study_session_id: localSessionId,
        word_id: wordId,
      };
      delete prepared.id;
      const insertedId = await this.insertReturningId("study_session_items", prepared, itemCols);
      if (remoteId !== null) this.itemIdMap.set(remoteId, insertedId);
    }
  }

  private async mergeLogs(): Promise<void> {
    if (this.payload.review_logs.length === 0) return;

    const answerIds = new Set<string>();
    for (const row of this.payload.review_logs) {
      const answerId = asString(row.client_answer_id);
      if (answerId) answerIds.add(answerId);
    }
    const seen = new Set<string>();
    for (const chunk of chunksOf([...answerIds])) {
      const marks = chunk.map(() => "?").join(", ");
      const rows = await sqlite
        .prepare(`SELECT client_answer_id FROM review_logs WHERE client_answer_id IN (${marks})`)
        .all(...chunk) as { client_answer_id: string }[];
      for (const row of rows) seen.add(row.client_answer_id);
    }

    const cols = await this.columnsOf("review_logs");
    for (const row of this.payload.review_logs) {
      const answerId = asString(row.client_answer_id);
      if (!answerId || seen.has(answerId)) continue;
      const wordId = this.wordIdMap.get(asInt(row.word_id) ?? -1);
      if (wordId === undefined) continue;
      seen.add(answerId);

      const prepared: SyncRow = {
        ...row,
        word_id: wordId,
        study_session_id: this.sessionIdMap.get(asInt(row.study_session_id) ?? -1) ?? null,
        study_session_item_id: this.itemIdMap.get(asInt(row.study_session_item_id) ?? -1) ?? null,
      };
      delete prepared.id;
      await this.insertReturningId("review_logs", prepared, cols);
      this.touchedWordIds.add(wordId);
      this.addedLogs += 1;
    }
  }

  private async rebuildTouchedDerived(): Promise<void> {
    if (this.touchedWordIds.size === 0) return;
    const wordIds = [...this.touchedWordIds];

    const grouped = new Map<number, SyncRow[]>();
    const existingCards = new Map<number, SyncRow>();
    for (const chunk of chunksOf(wordIds)) {
      const marks = chunk.map(() => "?").join(", ");
      const logRows = await sqlite
        .prepare(`SELECT * FROM review_logs WHERE word_id IN (${marks})`)
        .all(...chunk) as SyncRow[];
      for (const row of logRows) {
        const wid = asInt(row.word_id);
        if (wid === null) continue;
        const list = grouped.get(wid) ?? [];
        list.push(row);
        grouped.set(wid, list);
      }

      const cardRows = await sqlite
        .prepare(`SELECT * FROM review_cards WHERE word_id IN (${marks})`)
        .all(...chunk) as SyncRow[];
      for (const row of cardRows) {
        const wid = asInt(row.word_id);
        if (wid !== null) existingCards.set(wid, row);
      }
    }

    const cardCols = await this.columnsOf("review_cards");
    const wrongCols = await this.columnsOf("wrong_word_states");

    for (const [wordId, rawLogs] of grouped.entries()) {
      rawLogs.sort(compareLogRows);
      const replayed = replayWordHistory(rawLogs.map(toReplayLog), this.requestRetention, this.now);
      const existingCard = existingCards.get(wordId);
      const dueAt = replayed.card.due.getTime();
      const lastReviewAt = replayed.card.last_review ? replayed.card.last_review.getTime() : null;

      await this.upsertByConflict(
        "review_cards",
        "word_id",
        {
          word_id: wordId,
          due_at: dueAt,
          stability: replayed.card.stability,
          difficulty: replayed.card.difficulty,
          elapsed_days: replayed.card.elapsed_days,
          scheduled_days: replayed.card.scheduled_days,
          reps: replayed.card.reps,
          lapses: replayed.card.lapses,
          fsrs_state: replayed.card.state,
          learning_steps: replayed.card.learning_steps,
          last_review_at: lastReviewAt,
          created_at: existingCard?.created_at ?? dueAt,
          updated_at: this.now,
        },
        cardCols,
      );

      if (!replayed.wrong) {
        await sqlite.prepare("DELETE FROM wrong_word_states WHERE word_id = ?").run(wordId);
      } else {
        await this.upsertByConflict(
          "wrong_word_states",
          "word_id",
          {
            word_id: wordId,
            active: replayed.wrong.active ? 1 : 0,
            wrong_count: replayed.wrong.wrongCount,
            hard_count: replayed.wrong.hardCount,
            consecutive_correct: replayed.wrong.consecutiveCorrect,
            last_wrong_at: replayed.wrong.lastWrongAt,
            last_correct_at: replayed.wrong.lastCorrectAt,
            resolved_at: replayed.wrong.resolvedAt,
            updated_at: replayed.wrong.lastCorrectAt ?? replayed.wrong.lastWrongAt ?? lastReviewAt ?? this.now,
          },
          wrongCols,
        );
      }

      await sqlite
        .prepare("UPDATE words SET mastery_score = ?, mastery_level = ? WHERE id = ?")
        .run(replayed.masteryScore, replayed.masteryLevel, wordId);
    }

    await this.recomputeStatsForWords(wordIds);
  }

  private async recomputeStatsForWords(wordIds: readonly number[]): Promise<void> {
    const since30 = this.now - MASTERY_WINDOW_MS;
    const since14 = this.now - PERFORMANCE_WINDOW_MS;
    for (const chunk of chunksOf(wordIds)) {
      const marks = chunk.map(() => "?").join(", ");
      await sqlite.prepare(`DELETE FROM word_review_stats WHERE word_id IN (${marks})`).run(...chunk);
      await sqlite
        .prepare(
          `INSERT INTO word_review_stats (
             word_id, total_reviews, correct_reviews,
             recent_again_30d, recent_again_14d, recent_wrong_14d, recent_hard_14d,
             total_duration_ms, duration_count, last_reviewed_at, updated_at
           )
           SELECT
             word_id,
             count(*),
             coalesce(sum(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0),
             coalesce(sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
             coalesce(sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
             coalesce(sum(CASE WHEN is_correct = 0 AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
             coalesce(sum(CASE WHEN rating = 'HARD' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
             coalesce(sum(CASE WHEN duration_ms > 0 THEN duration_ms ELSE 0 END), 0),
             coalesce(sum(CASE WHEN duration_ms > 0 THEN duration_ms ELSE 0 END), 0),
             max(reviewed_at),
             ?
           FROM review_logs
           WHERE word_id IN (${marks})
           GROUP BY word_id`,
        )
        .run(since30, since14, since14, since14, this.now, ...chunk);
    }
  }

  private async mergeSettings(): Promise<void> {
    if (this.payload.settings.length === 0) return;
    const keys = new Set<string>();
    for (const row of this.payload.settings) {
      const key = asString(row.key);
      if (key && !SYNC_EXCLUDED_SETTING_KEYS.has(key)) keys.add(key);
    }
    if (keys.size === 0) return;

    const existing = new Map<string, SyncRow>();
    for (const chunk of chunksOf([...keys])) {
      const marks = chunk.map(() => "?").join(", ");
      const rows = await sqlite
        .prepare(`SELECT * FROM settings WHERE key IN (${marks})`)
        .all(...chunk) as SyncRow[];
      for (const row of rows) existing.set(asString(row.key), row);
    }

    const cols = await this.columnsOf("settings");
    for (const row of this.payload.settings) {
      const key = asString(row.key);
      if (!key || SYNC_EXCLUDED_SETTING_KEYS.has(key)) continue;
      const current = existing.get(key);
      if (current && !isNewer(row, current)) continue;
      await this.upsertByConflict("settings", "key", row, cols);
      existing.set(key, row);
    }
  }

  private async mergeWordPacks(): Promise<void> {
    if (this.payload.word_packs.length === 0) return;
    const ids = new Set<string>();
    for (const row of this.payload.word_packs) {
      const id = asString(row.id);
      if (id) ids.add(id);
    }
    if (ids.size === 0) return;

    const existing = new Map<string, SyncRow>();
    for (const chunk of chunksOf([...ids])) {
      const marks = chunk.map(() => "?").join(", ");
      const rows = await sqlite
        .prepare(`SELECT * FROM word_packs WHERE id IN (${marks})`)
        .all(...chunk) as SyncRow[];
      for (const row of rows) existing.set(asString(row.id), row);
    }

    const cols = await this.columnsOf("word_packs");
    for (const row of this.payload.word_packs) {
      const id = asString(row.id);
      if (!id) continue;
      const current = existing.get(id);
      if (current && !isNewer(row, current)) continue;
      await this.upsertByConflict("word_packs", "id", row, cols);
      existing.set(id, row);
    }
  }

  private async mergeWordPackItems(): Promise<void> {
    if (this.payload.word_pack_items.length === 0) return;
    const packIds = new Set<string>();
    for (const row of this.payload.word_pack_items) {
      const pid = asString(row.pack_id);
      if (pid) packIds.add(pid);
    }
    if (packIds.size === 0) return;

    const validPacks = new Set<string>();
    for (const chunk of chunksOf([...packIds])) {
      const marks = chunk.map(() => "?").join(", ");
      const rows = await sqlite
        .prepare(`SELECT id FROM word_packs WHERE id IN (${marks})`)
        .all(...chunk) as { id: string }[];
      for (const row of rows) validPacks.add(row.id);
    }

    for (const row of this.payload.word_pack_items) {
      const packId = asString(row.pack_id);
      const wordId = this.wordIdMap.get(asInt(row.word_id) ?? -1);
      if (!packId || wordId === undefined || !validPacks.has(packId)) continue;
      await sqlite
        .prepare(
          `INSERT INTO word_pack_items (pack_id, word_id, rank)
           VALUES (?, ?, ?)
           ON CONFLICT(pack_id, word_id) DO NOTHING`,
        )
        .run(packId, wordId, asInt(row.rank) ?? 0);
    }
  }
}

export interface ApplyPushResult {
  summary: SyncMergeSummary;
  datasetEpoch: string;
  serverNow: number;
}

/**
 * Applies one push delta batch inside a single atomic PostgreSQL transaction.
 * Commits client watermark only when `payload.commitWatermark === true`.
 */
export async function applySyncPushBatch(payload: PushRequest, now = Date.now()): Promise<ApplyPushResult> {
  const settings = await getSettings();
  const summary = await sqlite.transaction(() =>
    new PushMergeRun(payload, settings.targetRetentionRate, now).execute(),
  )();

  invalidateSettingsCache();

  const hasChanges = summary.addedWords > 0 || summary.updatedWords > 0 || summary.addedLogs > 0;
  const serverState = payload.commitWatermark
    ? await recordServerPeerSync({
        peerDeviceId: payload.clientDeviceId,
        peerDeviceName: payload.clientDeviceName,
        peerDatasetEpoch: payload.clientDatasetEpoch,
        peerCursorMs: payload.clientServerNow,
        localCursorMs: payload.pulledServerNow,
        hasChanges,
        now,
      })
    : await ensureServerSyncState(now);

  return {
    summary,
    datasetEpoch: serverState.datasetEpoch,
    serverNow: now,
  };
}
