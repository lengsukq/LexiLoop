import { sqlite } from "@/db/client";
import type { DictionaryContent, EntryType, QuestionType, StudyItemView, StudyMode } from "@/lib/types";
import { dictionaryContentFromRow, emptyDictionaryContent } from "@/modules/dictionary/content";
import { getSettings } from "@/modules/settings/service";
import { getTodayRecommendedItems } from "@/modules/suggestions/service";

const SKIP_COOLDOWN_MS = 12 * 60 * 60 * 1000;
const SESSION_RESUME_TTL_MS = 24 * 60 * 60 * 1000;

interface Candidate {
  id: number;
  term: string;
  normalized_term: string;
  source_language: string;
  target_language: string;
  content_type: EntryType;
}

interface StudyLimits {
  due: number;
  wrong: number;
  fresh: number;
}

interface CandidatePools {
  due: Candidate[];
  wrong: Candidate[];
  fresh: Candidate[];
  limits: StudyLimits;
}

function candidateAvailabilitySql(): string {
  return `NOT EXISTS (
    SELECT 1 FROM study_session_items skipped
    WHERE skipped.word_id = w.id
      AND skipped.status = 'SKIPPED'
      AND COALESCE(skipped.skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET')
      AND skipped.answered_at IS NOT NULL
      AND skipped.answered_at >= ?
  ) AND NOT EXISTS (
    SELECT 1 FROM study_session_items active_item
    JOIN study_sessions active_session ON active_session.id = active_item.study_session_id
    WHERE active_item.word_id = w.id
      AND active_item.status = 'PENDING'
      AND active_session.completed_at IS NULL
      AND active_session.started_at >= ?
  )`;
}

function dueCandidates(limit: number, now: number): Candidate[] {
  return sqlite.prepare(`SELECT w.id, w.term, w.normalized_term, w.source_language, w.target_language, w.content_type
    FROM review_cards c JOIN words w ON w.id = c.word_id
    WHERE c.due_at <= ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      AND ${candidateAvailabilitySql()}
    ORDER BY (CAST(? - c.due_at AS REAL) / 86400000.0) * (1.0 + c.difficulty * 0.15) DESC LIMIT ?`).all(now, now - SKIP_COOLDOWN_MS, now - SESSION_RESUME_TTL_MS, now, limit) as Candidate[];
}

function wrongCandidates(limit: number, now: number): Candidate[] {
  return sqlite.prepare(`SELECT w.id, w.term, w.normalized_term, w.source_language, w.target_language, w.content_type
    FROM wrong_word_states x JOIN words w ON w.id = x.word_id
    WHERE x.active = 1 AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      AND ${candidateAvailabilitySql()}
    ORDER BY x.updated_at ASC LIMIT ?`).all(now - SKIP_COOLDOWN_MS, now - SESSION_RESUME_TTL_MS, limit) as Candidate[];
}

function newCandidates(limit: number, now: number): Candidate[] {
  return sqlite.prepare(`SELECT w.id, w.term, w.normalized_term, w.source_language, w.target_language, w.content_type
    FROM words w LEFT JOIN review_cards c ON c.word_id = w.id
    WHERE c.word_id IS NULL AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      AND ${candidateAvailabilitySql()}
    ORDER BY COALESCE(w.source_created_at, w.created_at) ASC LIMIT ?`).all(now - SKIP_COOLDOWN_MS, now - SESSION_RESUME_TTL_MS, limit) as Candidate[];
}

type RecommendedCandidate = Candidate & { recommendedQuestionType: QuestionType };

async function aiRecommendedCandidates(now: number): Promise<RecommendedCandidate[]> {
  const recommendations = await getTodayRecommendedItems();
  if (!recommendations.length) return [];
  const ids = recommendations.map((item) => item.wordId);
  const placeholders = ids.map(() => "?").join(",");
  const rows = sqlite.prepare(`SELECT w.id, w.term, w.normalized_term, w.source_language, w.target_language, w.content_type
    FROM words w
    WHERE w.id IN (${placeholders})
      AND w.is_suspended = 0
      AND w.initialization_status IN ('READY','PARTIAL')
      AND ${candidateAvailabilitySql()}`)
    .all(...ids, now - SKIP_COOLDOWN_MS, now - SESSION_RESUME_TTL_MS) as Candidate[];
  const byId = new Map(rows.map((row) => [row.id, row]));
  return recommendations.flatMap((recommendation) => {
    const candidate = byId.get(recommendation.wordId);
    return candidate ? [{ ...candidate, recommendedQuestionType: recommendation.questionType }] : [];
  });
}

function interleave(groups: Array<{ items: Candidate[]; take: number }>): Candidate[] {
  const indexes = groups.map(() => 0);
  const output: Candidate[] = [];
  const seen = new Set<number>();
  while (groups.some((group, index) => indexes[index]! < group.items.length)) {
    groups.forEach((group, groupIndex) => {
      for (let count = 0; count < group.take && indexes[groupIndex]! < group.items.length; count += 1) {
        const item = group.items[indexes[groupIndex]!]!;
        indexes[groupIndex] = indexes[groupIndex]! + 1;
        if (!seen.has(item.id)) { seen.add(item.id); output.push(item); }
      }
    });
  }
  return output;
}

function questionFor(mode: StudyMode, taskType: string): QuestionType {
  if (mode === "LISTENING") return "LISTENING_SPELLING";
  if (mode === "SPELLING" || mode === "WRONG_WORDS" || taskType === "WRONG") return "ZH_TO_EN_SPELLING";
  if (taskType === "NEW") return "EN_TO_ZH_CHOICE";
  return "EN_TO_ZH";
}

function taskFor(mode: StudyMode, candidate: Candidate, sets: { due: Set<number>; wrong: Set<number> }): "NEW" | "REVIEW" | "WRONG" | "LISTENING" | "SPELLING" {
  if (mode === "LISTENING") return "LISTENING";
  if (mode === "SPELLING") return "SPELLING";
  if (mode === "WRONG_WORDS") return "WRONG";
  if (mode === "DUE_REVIEW") return "REVIEW";
  if (mode === "NEW_WORDS") return "NEW";
  if (sets.due.has(candidate.id)) return "REVIEW";
  if (sets.wrong.has(candidate.id)) return "WRONG";
  return "NEW";
}

function prioritizedGroups(pools: CandidatePools) {
  const selected = new Set<number>();
  const due = pools.due.filter((item) => {
    if (selected.has(item.id) || selected.size >= pools.limits.due) return false;
    selected.add(item.id);
    return true;
  });
  const wrong: Candidate[] = [];
  for (const item of pools.wrong) {
    if (wrong.length >= pools.limits.wrong) break;
    if (selected.has(item.id)) continue;
    selected.add(item.id);
    wrong.push(item);
  }
  const fresh: Candidate[] = [];
  for (const item of pools.fresh) {
    if (fresh.length >= pools.limits.fresh) break;
    if (selected.has(item.id)) continue;
    selected.add(item.id);
    fresh.push(item);
  }
  return { due, wrong, fresh };
}

function selectCandidates(mode: StudyMode, pools: CandidatePools): Candidate[] {
  const groups = prioritizedGroups(pools);
  switch (mode) {
    case "DUE_REVIEW": return pools.due.slice(0, pools.limits.due);
    case "WRONG_WORDS": return pools.wrong.slice(0, pools.limits.wrong);
    case "NEW_WORDS": return pools.fresh.slice(0, pools.limits.fresh);
    case "LISTENING": return interleave([{ items: groups.due, take: 5 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 2 }]);
    case "SPELLING": return interleave([{ items: groups.due, take: 5 }, { items: groups.wrong, take: 3 }, { items: groups.fresh, take: 1 }]);
    case "AI_RECOMMENDED": return [];
    case "DAILY": return interleave(adaptiveDailyRatios(groups));
  }
}

function adaptiveDailyRatios(groups: { due: Candidate[]; wrong: Candidate[]; fresh: Candidate[] }) {
  const total = groups.due.length + groups.wrong.length + groups.fresh.length;
  if (total === 0) return [{ items: groups.due, take: 5 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 2 }];
  const wrongRatio = groups.wrong.length / total;
  const dueRatio = groups.due.length / total;
  if (wrongRatio > 0.4) return [{ items: groups.due, take: 3 }, { items: groups.wrong, take: 4 }, { items: groups.fresh, take: 1 }];
  if (dueRatio > 0.7) return [{ items: groups.due, take: 6 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 1 }];
  return [{ items: groups.due, take: 5 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 2 }];
}

async function loadPools(now: number): Promise<CandidatePools> {
  const settings = await getSettings();
  const limits = {
    due: settings.dailyDueReviewLimit,
    wrong: settings.dailyWrongWordLimit,
    fresh: settings.dailyNewWords,
  };
  const overlapBuffer = limits.due + limits.wrong + limits.fresh;
  return {
    due: dueCandidates(limits.due + overlapBuffer, now),
    wrong: wrongCandidates(limits.wrong + overlapBuffer, now),
    fresh: newCandidates(limits.fresh + overlapBuffer, now),
    limits,
  };
}

function countAvailableCandidates(now: number) {
  const skippedAfter = now - SKIP_COOLDOWN_MS;
  const due = sqlite.prepare(`SELECT count(*) AS count FROM review_cards c JOIN words w ON w.id = c.word_id
    WHERE c.due_at <= ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      AND ${candidateAvailabilitySql()}`).get(now, skippedAfter, now - SESSION_RESUME_TTL_MS) as { count: number };
  const wrong = sqlite.prepare(`SELECT count(*) AS count FROM wrong_word_states x JOIN words w ON w.id = x.word_id
    WHERE x.active = 1 AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      AND ${candidateAvailabilitySql()}`).get(skippedAfter, now - SESSION_RESUME_TTL_MS) as { count: number };
  const fresh = sqlite.prepare(`SELECT count(*) AS count FROM words w LEFT JOIN review_cards c ON c.word_id = w.id
    WHERE c.word_id IS NULL AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      AND ${candidateAvailabilitySql()}`).get(skippedAfter, now - SESSION_RESUME_TTL_MS) as { count: number };
  return { due: due.count, wrong: wrong.count, fresh: fresh.count };
}

export async function getDailyStudyPlan() {
  const now = Date.now();
  const active = activePendingPlan(now);
  const pools = await loadPools(now);
  const selected = selectCandidates("DAILY", pools);
  const dueSet = new Set(pools.due.map((item) => item.id));
  const wrongSet = new Set(pools.wrong.map((item) => item.id));
  const planned = { REVIEW: active.REVIEW, WRONG: active.WRONG, NEW: active.NEW };
  for (const candidate of selected) {
    const task = taskFor("DAILY", candidate, { due: dueSet, wrong: wrongSet });
    if (task === "REVIEW" || task === "WRONG" || task === "NEW") planned[task] += 1;
  }
  const available = countAvailableCandidates(now);
  const activeTotal = active.REVIEW + active.WRONG + active.NEW;
  const plannedTotal = activeTotal + selected.length;
  const estimatedSeconds = planned.REVIEW * 35 + planned.WRONG * 55 + planned.NEW * 70;
  return {
    dueReviewCount: available.due + active.REVIEW,
    plannedDueReviewCount: planned.REVIEW,
    wrongWordCount: available.wrong + active.WRONG,
    plannedWrongWordCount: planned.WRONG,
    newWordCount: available.fresh + active.NEW,
    plannedNewWordCount: planned.NEW,
    plannedTotal,
    activeSessionTasks: activeTotal,
    estimatedMinutes: plannedTotal === 0 ? 0 : Math.max(1, Math.ceil(estimatedSeconds / 60)),
  };
}

function expireStaleSessions(now: number): number {
  const staleBefore = now - SESSION_RESUME_TTL_MS;
  return sqlite.transaction(() => {
    const stale = sqlite.prepare(`SELECT id, started_at FROM study_sessions
      WHERE completed_at IS NULL AND started_at < ?`).all(staleBefore) as Array<{ id: number; started_at: number }>;
    let expiredItems = 0;
    for (const session of stale) {
      const result = sqlite.prepare(`UPDATE study_session_items
        SET status = 'SKIPPED', answered_at = ?, skip_reason = 'SESSION_EXPIRED'
        WHERE study_session_id = ? AND status = 'PENDING'`).run(now, session.id);
      expiredItems += result.changes;
      sqlite.prepare(`UPDATE study_sessions SET completed_at = ?, duration_ms = ?,
        completed_count = completed_count + ?
        WHERE id = ?`).run(now, now - session.started_at, result.changes, session.id);
    }
    return expiredItems;
  }).immediate();
}

function findResumableSession(mode: StudyMode, now: number): number | null {
  const ttl = now - SESSION_RESUME_TTL_MS;
  if (mode === "AI_RECOMMENDED") {
    const row = sqlite.prepare(`SELECT s.id FROM study_sessions s
      WHERE s.source_type = 'AI_RECOMMENDED' AND s.completed_at IS NULL AND s.started_at >= ?
        AND EXISTS (SELECT 1 FROM study_session_items i WHERE i.study_session_id = s.id AND i.status = 'PENDING')
      ORDER BY s.started_at DESC LIMIT 1`).get(ttl) as { id: number } | undefined;
    return row?.id ?? null;
  }
  if (mode === "DAILY") {
    const row = sqlite.prepare(`SELECT s.id FROM study_sessions s
      WHERE s.completed_at IS NULL AND s.started_at >= ?
        AND EXISTS (SELECT 1 FROM study_session_items i WHERE i.study_session_id = s.id AND i.status = 'PENDING')
      ORDER BY s.started_at DESC LIMIT 1`).get(ttl) as { id: number } | undefined;
    return row?.id ?? null;
  }
  const taskTypeMap: Record<string, string> = { DUE_REVIEW: "REVIEW", WRONG_WORDS: "WRONG", NEW_WORDS: "NEW", LISTENING: "LISTENING", SPELLING: "SPELLING" };
  const taskType = taskTypeMap[mode];
  // First: exact mode match
  const exact = sqlite.prepare(`SELECT s.id FROM study_sessions s
    WHERE s.session_type = ? AND s.completed_at IS NULL AND s.started_at >= ?
      AND EXISTS (SELECT 1 FROM study_session_items i WHERE i.study_session_id = s.id AND i.status = 'PENDING')
    ORDER BY s.started_at DESC LIMIT 1`).get(mode, ttl) as { id: number } | undefined;
  if (exact) return exact.id;
  // Fallback: DAILY session with matching task type
  if (taskType) {
    const daily = sqlite.prepare(`SELECT s.id FROM study_sessions s
      WHERE s.completed_at IS NULL AND s.started_at >= ?
        AND EXISTS (SELECT 1 FROM study_session_items i WHERE i.study_session_id = s.id AND i.status = 'PENDING' AND i.task_type = ?)
      ORDER BY s.started_at DESC LIMIT 1`).get(ttl, taskType) as { id: number } | undefined;
    if (daily) return daily.id;
  }
  return null;
}

function activePendingPlan(now: number) {
  const rows = sqlite.prepare(`SELECT
      CASE
        WHEN c.due_at IS NOT NULL AND c.due_at <= ? THEN 'REVIEW'
        WHEN COALESCE(x.active, 0) = 1 THEN 'WRONG'
        ELSE 'NEW'
      END AS category,
      count(*) AS count
    FROM study_session_items i
    JOIN study_sessions s ON s.id = i.study_session_id
    JOIN words w ON w.id = i.word_id
    LEFT JOIN review_cards c ON c.word_id = w.id
    LEFT JOIN wrong_word_states x ON x.word_id = w.id
    WHERE i.status = 'PENDING' AND s.completed_at IS NULL AND s.started_at >= ?
    GROUP BY category`).all(now, now - SESSION_RESUME_TTL_MS) as Array<{ category: "REVIEW" | "WRONG" | "NEW"; count: number }>;
  const result = { REVIEW: 0, WRONG: 0, NEW: 0 };
  for (const row of rows) result[row.category] = Number(row.count);
  return result;
}

export async function startStudySession(mode: StudyMode, resume = true) {
  const now = Date.now();
  expireStaleSessions(now);
  if (resume) {
    const resumableId = findResumableSession(mode, now);
    if (resumableId) return getStudySession(resumableId, true);
  }

  const pools = await loadPools(now);
  const recommended = mode === "AI_RECOMMENDED" ? await aiRecommendedCandidates(now) : null;
  const selected: Candidate[] = recommended ?? selectCandidates(mode, pools);
  const dueSet = new Set(pools.due.map((item) => item.id));
  const wrongSet = new Set(pools.wrong.map((item) => item.id));
  const persistedMode = mode === "AI_RECOMMENDED" ? "WRONG_WORDS" : mode;
  const sourceType = mode === "AI_RECOMMENDED" ? "AI_RECOMMENDED" : null;
  const sessionId = sqlite.transaction(() => {
    const session = sqlite.prepare(`INSERT INTO study_sessions
      (session_type, source_type, started_at, completed_at, planned_count, completed_count, correct_count, wrong_count, skipped_count, created_at)
      VALUES (?, ?, ?, ?, ?, 0, 0, 0, 0, ?)`).run(persistedMode, sourceType, now, selected.length === 0 ? now : null, selected.length, now);
    const id = Number(session.lastInsertRowid);
    const insert = sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, status, created_at)
      VALUES (?, ?, ?, ?, ?, 'PENDING', ?)`);
    selected.forEach((candidate, index) => {
      const taskMode = mode === "AI_RECOMMENDED" ? "DAILY" : mode;
      const taskType = taskFor(taskMode, candidate, { due: dueSet, wrong: wrongSet });
      const recommendedQuestion = mode === "AI_RECOMMENDED"
        ? (candidate as RecommendedCandidate).recommendedQuestionType
        : null;
      insert.run(id, index, candidate.id, taskType, recommendedQuestion ?? questionFor(mode, taskType), now);
    });
    return id;
  }).immediate();
  return getStudySession(sessionId, false);
}

export function getStudySession(sessionId: number, resumed = false) {
  const session = sqlite.prepare("SELECT * FROM study_sessions WHERE id = ?").get(sessionId) as Record<string, unknown> | undefined;
  if (!session) throw new Error("STUDY_SESSION_NOT_FOUND");
  const rows = sqlite.prepare(`SELECT i.id AS item_id, i.position, i.task_type, i.question_type, i.status, i.skip_reason,
    w.id AS word_id, w.term, w.source_language, w.target_language, w.content_type,
    c.definitions_json, c.pronunciations_json, c.examples_json, c.phrases_json, c.forms_json,
    c.synonyms_json, c.antonyms_json, c.word_family_json, c.confused_words_json,
    c.roots_json, c.affixes_json, c.summary_json, c.learning_json, c.tags_json
    FROM study_session_items i JOIN words w ON w.id = i.word_id
    LEFT JOIN word_contents c ON c.word_id = w.id
    WHERE i.study_session_id = ? ORDER BY i.position ASC`).all(sessionId) as Array<Record<string, unknown>>;
  const items: Array<StudyItemView & { status: string; skipReason: string | null }> = rows.map((row) => {
    const questionType = row.question_type as QuestionType;
    const content = row.definitions_json === null ? emptyDictionaryContent() : dictionaryContentFromRow(row);
    const item: StudyItemView & { status: string; skipReason: string | null } = {
      itemId: Number(row.item_id),
      position: Number(row.position),
      taskType: row.task_type as StudyItemView["taskType"],
      questionType,
      status: String(row.status),
      skipReason: row.skip_reason === null ? null : String(row.skip_reason),
      word: {
        id: Number(row.word_id),
        term: String(row.term),
        sourceLanguage: String(row.source_language),
        targetLanguage: String(row.target_language),
        entryType: row.content_type as EntryType,
        content,
      },
    };
    if (questionType === "EN_TO_ZH_CHOICE") {
      item.choices = generateChoices(Number(row.word_id), String(row.target_language), content);
    }
    return item;
  });
  const resumeIndex = items.findIndex((item) => item.status === "PENDING");
  return {
    resumed,
    resumeIndex: resumeIndex === -1 ? items.length : resumeIndex,
    session: {
      id: Number(session.id),
      sessionType: session.source_type === "AI_RECOMMENDED" ? "AI_RECOMMENDED" : String(session.session_type),
      startedAt: new Date(Number(session.started_at)).toISOString(),
      completedAt: session.completed_at ? new Date(Number(session.completed_at)).toISOString() : null,
      plannedCount: Number(session.planned_count),
      completedCount: Number(session.completed_count),
      correctCount: Number(session.correct_count),
      wrongCount: Number(session.wrong_count),
      skippedCount: Number(session.skipped_count ?? 0),
      durationMs: session.duration_ms === null ? null : Number(session.duration_ms),
    },
    items,
  };
}

function generateChoices(wordId: number, targetLanguage: string, content: DictionaryContent): string[] {
  const correctDefs = content.definitions
    .filter((d) => d.language === targetLanguage)
    .map((d) => d.text);
  const correct = correctDefs[0] ?? content.definitions[0]?.text ?? "";
  if (!correct) return [];
  const distractorRows = sqlite.prepare(`SELECT c.definitions_json FROM word_contents c
    JOIN words w ON w.id = c.word_id
    WHERE c.word_id != ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      AND c.definitions_json IS NOT NULL AND c.definitions_json != '[]'
    ORDER BY RANDOM() LIMIT 12`).all(wordId) as Array<{ definitions_json: string }>;
  const distractors: string[] = [];
  const seen = new Set([correct.toLocaleLowerCase()]);
  for (const row of distractorRows) {
    if (distractors.length >= 3) break;
    try {
      const defs = JSON.parse(row.definitions_json) as Array<{ language: string; text: string }>;
      const target = defs.filter((d) => d.language === targetLanguage);
      const pool = target.length ? target : defs;
      const text = pool[0]?.text;
      if (text && !seen.has(text.toLocaleLowerCase())) {
        seen.add(text.toLocaleLowerCase());
        distractors.push(text);
      }
    } catch { /* skip malformed json */ }
  }
  const choices = [correct, ...distractors];
  // Fisher-Yates shuffle
  for (let i = choices.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [choices[i], choices[j]] = [choices[j]!, choices[i]!];
  }
  return choices;
}

export function skipStudyItem(sessionId: number, itemId: number, reason = "LATER") {
  const now = Date.now();
  sqlite.transaction(() => {
    const item = sqlite.prepare(`SELECT i.status, s.started_at, s.completed_at
      FROM study_session_items i JOIN study_sessions s ON s.id = i.study_session_id
      WHERE i.id = ? AND i.study_session_id = ?`).get(itemId, sessionId) as {
        status: string; started_at: number; completed_at: number | null;
      } | undefined;
    if (!item) throw new Error("STUDY_ITEM_NOT_FOUND");
    if (item.completed_at !== null || item.status !== "PENDING") throw new Error("STUDY_ITEM_ALREADY_PROCESSED");
    const updated = sqlite.prepare(`UPDATE study_session_items
      SET status = 'SKIPPED', answered_at = ?, skip_reason = ?
      WHERE id = ? AND study_session_id = ? AND status = 'PENDING'`).run(now, reason, itemId, sessionId);
    if (updated.changes !== 1) throw new Error("STUDY_ITEM_ALREADY_PROCESSED");
    sqlite.prepare(`UPDATE study_sessions
      SET completed_count = completed_count + 1, skipped_count = skipped_count + 1
      WHERE id = ?`).run(sessionId);
    const pending = sqlite.prepare(`SELECT count(*) AS count FROM study_session_items
      WHERE study_session_id = ? AND status = 'PENDING'`).get(sessionId) as { count: number };
    if (pending.count === 0) {
      sqlite.prepare("UPDATE study_sessions SET completed_at = ?, duration_ms = ? WHERE id = ?")
        .run(now, now - item.started_at, sessionId);
    }
  }).immediate();
  return getStudySession(sessionId, false);
}
