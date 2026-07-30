import { sqlite } from "@/db/client";
import type { EntryType, QuestionType, StudyMode } from "@/lib/types";
import { getSettings } from "@/modules/settings/service";
import { getTodayRecommendedItems } from "@/modules/suggestions/service";

export interface StudyCandidate { id: number; term: string; normalized_term: string; source_language: string; target_language: string; content_type: EntryType; }
export type CandidateScope = "LEXICAL" | "SENTENCE" | "ALL";
type RecommendedCandidate = StudyCandidate & { recommendedQuestionType: QuestionType };
type Pools = { due: StudyCandidate[]; wrong: StudyCandidate[]; fresh: StudyCandidate[]; limits: { due: number; wrong: number; fresh: number } };
const SKIP_COOLDOWN_MS = 12 * 60 * 60 * 1000;
const SESSION_RESUME_TTL_MS = 24 * 60 * 60 * 1000;
const PERFORMANCE_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;
const DAILY_QUOTA_GRACE_RATIO = 0.2;
const timezone = process.env.APP_TIMEZONE ?? "Asia/Shanghai";

function scopeSql(scope: CandidateScope): string { return scope === "SENTENCE" ? "AND COALESCE(w.content_type, w.entry_type) = 'SENTENCE'" : scope === "LEXICAL" ? "AND COALESCE(w.content_type, w.entry_type) <> 'SENTENCE'" : ""; }
function availabilitySql(): string { return `NOT EXISTS (SELECT 1 FROM study_session_items skipped WHERE skipped.word_id = w.id AND skipped.status = 'SKIPPED' AND COALESCE(skipped.skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET') AND skipped.answered_at IS NOT NULL AND skipped.answered_at >= ?) AND NOT EXISTS (SELECT 1 FROM study_session_items active_item JOIN study_sessions active_session ON active_session.id = active_item.study_session_id WHERE active_item.word_id = w.id AND active_item.status = 'PENDING' AND active_session.completed_at IS NULL AND COALESCE(active_session.source_type, '') <> 'MATCH_GAME' AND COALESCE(active_session.source_type, '') NOT LIKE 'GAME_%' AND active_session.started_at >= ?)`; }
const selectColumns = "w.id, w.term, w.normalized_term, w.source_language, w.target_language, w.content_type";
function dueCandidates(limit: number, now: number, scope: CandidateScope): StudyCandidate[] {
  const performanceSince = now - PERFORMANCE_WINDOW_MS;
  return sqlite.prepare(`SELECT ${selectColumns} FROM review_cards c JOIN words w ON w.id = c.word_id
    LEFT JOIN (
      SELECT word_id,
        SUM(CASE WHEN reviewed_at >= ? AND is_correct = 0 THEN 1 ELSE 0 END) AS recent_wrong,
        SUM(CASE WHEN reviewed_at >= ? AND rating = 'AGAIN' THEN 1 ELSE 0 END) AS recent_again,
        SUM(CASE WHEN reviewed_at >= ? AND rating = 'HARD' THEN 1 ELSE 0 END) AS recent_hard
      FROM review_logs GROUP BY word_id
    ) performance ON performance.word_id = w.id
    WHERE c.due_at <= ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${scopeSql(scope)} AND ${availabilitySql()}
    ORDER BY
      (CAST(? - c.due_at AS REAL) / 86400000.0) * (1.0 + c.difficulty * 0.15)
      + COALESCE(performance.recent_wrong, 0) * 1.2
      + COALESCE(performance.recent_again, 0) * 0.8
      + COALESCE(performance.recent_hard, 0) * 0.35 DESC,
      c.due_at ASC LIMIT ?`).all(
    performanceSince,
    performanceSince,
    performanceSince,
    now,
    now - SKIP_COOLDOWN_MS,
    now - SESSION_RESUME_TTL_MS,
    now,
    limit,
  ) as StudyCandidate[];
}
function wrongCandidates(limit: number, now: number, scope: CandidateScope): StudyCandidate[] {
  return sqlite.prepare(`SELECT ${selectColumns} FROM wrong_word_states x JOIN words w ON w.id = x.word_id
    WHERE x.active = 1 AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${scopeSql(scope)} AND ${availabilitySql()}
    ORDER BY x.wrong_count DESC, x.hard_count DESC, COALESCE(x.last_wrong_at, x.updated_at) ASC LIMIT ?`).all(
    now - SKIP_COOLDOWN_MS,
    now - SESSION_RESUME_TTL_MS,
    limit,
  ) as StudyCandidate[];
}
function newCandidates(limit: number, now: number, scope: CandidateScope): StudyCandidate[] { return sqlite.prepare(`SELECT ${selectColumns} FROM words w LEFT JOIN review_cards c ON c.word_id = w.id WHERE c.word_id IS NULL AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${scopeSql(scope)} AND ${availabilitySql()} ORDER BY COALESCE(w.source_created_at, w.created_at) ASC LIMIT ?`).all(now - SKIP_COOLDOWN_MS, now - SESSION_RESUME_TTL_MS, limit) as StudyCandidate[]; }

function startOfToday(now: number): number { const parts = new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date(now)); const value = (type: string) => parts.find((part) => part.type === type)?.value ?? "01"; return new Date(`${value("year")}-${value("month")}-${value("day")}T00:00:00.000`).getTime(); }
export async function aiRecommendedCandidates(now: number): Promise<RecommendedCandidate[]> {
  const recommendations = await getTodayRecommendedItems(); if (!recommendations.length) return [];
  const ids = recommendations.map((item) => item.wordId); const rows = sqlite.prepare(`SELECT ${selectColumns} FROM words w WHERE w.id IN (${ids.map(() => "?").join(",")}) AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') AND NOT EXISTS (SELECT 1 FROM study_session_items skipped WHERE skipped.word_id = w.id AND skipped.status = 'SKIPPED' AND COALESCE(skipped.skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET') AND skipped.answered_at IS NOT NULL AND skipped.answered_at >= ?) AND NOT EXISTS (SELECT 1 FROM study_session_items done JOIN study_sessions ds ON ds.id = done.study_session_id WHERE done.word_id = w.id AND ds.source_type = 'AI_RECOMMENDED' AND ds.started_at >= ? AND done.status IN ('ANSWERED', 'SKIPPED') AND COALESCE(done.skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET'))`).all(...ids, now - SKIP_COOLDOWN_MS, startOfToday(now)) as StudyCandidate[];
  const byId = new Map(rows.map((row) => [row.id, row])); return recommendations.flatMap((item) => { const candidate = byId.get(item.wordId); return candidate ? [{ ...candidate, recommendedQuestionType: item.questionType }] : []; });
}
function interleave(groups: Array<{ items: StudyCandidate[]; take: number }>): StudyCandidate[] { const indexes = groups.map(() => 0); const result: StudyCandidate[] = []; const seen = new Set<number>(); while (groups.some((group, index) => indexes[index]! < group.items.length)) groups.forEach((group, index) => { for (let count = 0; count < group.take && indexes[index]! < group.items.length; count++) { const item = group.items[indexes[index]!]!; indexes[index]! += 1; if (!seen.has(item.id)) { seen.add(item.id); result.push(item); } } }); return result; }
function prioritizedGroups(pools: Pools) { const selected = new Set<number>(); const take = (items: StudyCandidate[], limit: number) => items.filter((item) => !selected.has(item.id)).slice(0, limit).filter((item) => { selected.add(item.id); return true; }); return { due: take(pools.due, pools.limits.due), wrong: take(pools.wrong, pools.limits.wrong), fresh: take(pools.fresh, pools.limits.fresh) }; }
function adaptiveDailyRatios(groups: { due: StudyCandidate[]; wrong: StudyCandidate[]; fresh: StudyCandidate[] }) { const total = groups.due.length + groups.wrong.length + groups.fresh.length; if (!total) return [{ items: groups.due, take: 5 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 2 }]; const wrongRatio = groups.wrong.length / total; const dueRatio = groups.due.length / total; return wrongRatio > 0.4 ? [{ items: groups.due, take: 3 }, { items: groups.wrong, take: 4 }, { items: groups.fresh, take: 1 }] : dueRatio > 0.7 ? [{ items: groups.due, take: 6 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 1 }] : [{ items: groups.due, take: 5 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 2 }]; }
export function selectCandidates(mode: StudyMode, pools: Pools): StudyCandidate[] {
  const groups = prioritizedGroups(pools); if (mode === "DUE_REVIEW") return pools.due.slice(0, pools.limits.due); if (mode === "WRONG_WORDS") return pools.wrong.slice(0, pools.limits.wrong); if (mode === "NEW_WORDS") return pools.fresh.slice(0, pools.limits.fresh); if (mode === "AI_RECOMMENDED") return [];
  const ratios: Array<{ items: StudyCandidate[]; take: number }> = mode === "LISTENING" ? [{ items: groups.due, take: 5 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 2 }] : mode === "SPELLING" ? [{ items: groups.due, take: 5 }, { items: groups.wrong, take: 3 }, { items: groups.fresh, take: 1 }] : mode === "SENTENCE_REVIEW" ? [{ items: groups.due, take: 4 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 1 }] : adaptiveDailyRatios(groups);
  return interleave(ratios);
}
export function questionFor(mode: StudyMode, taskType: string): QuestionType { if (mode === "SENTENCE_REVIEW") return taskType === "NEW" ? "EN_TO_ZH" : "ZH_TO_EN_SPELLING"; if (mode === "LISTENING") return "LISTENING_SPELLING"; if (mode === "SPELLING" || mode === "WRONG_WORDS" || taskType === "WRONG") return "ZH_TO_EN_SPELLING"; return mode === "DAILY" || mode === "DUE_REVIEW" || mode === "NEW_WORDS" ? "EN_TO_ZH_CHOICE" : "EN_TO_ZH"; }
export function taskFor(mode: StudyMode, candidate: StudyCandidate, sets: { due: Set<number>; wrong: Set<number> }): "NEW" | "REVIEW" | "WRONG" | "LISTENING" | "SPELLING" { if (mode === "LISTENING") return "LISTENING"; if (mode === "SPELLING") return "SPELLING"; if (mode === "DUE_REVIEW") return "REVIEW"; if (mode === "NEW_WORDS") return "NEW"; if (sets.due.has(candidate.id)) return "REVIEW"; if (sets.wrong.has(candidate.id)) return "WRONG"; return "NEW"; }
type PoolLimits = { due: number; wrong: number; fresh: number };

function dailySoftLimit(target: number, used: number): number {
  const remaining = Math.max(0, target - used);
  if (used < target || target === 0) return remaining;
  const grace = Math.max(1, Math.ceil(target * DAILY_QUOTA_GRACE_RATIO));
  return Math.max(0, target + grace - used);
}

export function dailyProgress(now: number): PoolLimits {
  const today = startOfToday(now);
  const rows = sqlite.prepare(`SELECT i.task_type, count(*) AS count
    FROM study_session_items i JOIN study_sessions s ON s.id = i.study_session_id
    WHERE s.session_type = 'DAILY'
      AND ((i.status IN ('ANSWERED', 'SKIPPED') AND i.answered_at >= ?) OR (i.status = 'PENDING' AND s.started_at >= ?))
    GROUP BY i.task_type`).all(today, today) as Array<{ task_type: string; count: number }>;
  const progress = { due: 0, wrong: 0, fresh: 0 };
  for (const row of rows) {
    if (row.task_type === "REVIEW") progress.due += Number(row.count);
    if (row.task_type === "WRONG") progress.wrong += Number(row.count);
    if (row.task_type === "NEW") progress.fresh += Number(row.count);
  }
  return progress;
}

export async function loadPools(now: number, scope: CandidateScope = "LEXICAL", options: { applyDailySoftQuota?: boolean } = {}): Promise<Pools> {
  const settings = await getSettings();
  const configured = { due: settings.dailyDueReviewLimit, wrong: settings.dailyWrongWordLimit, fresh: settings.dailyNewWords };
  const progress = options.applyDailySoftQuota && scope === "LEXICAL" ? dailyProgress(now) : { due: 0, wrong: 0, fresh: 0 };
  const limits = options.applyDailySoftQuota && scope === "LEXICAL"
    ? {
        due: dailySoftLimit(configured.due, progress.due),
        wrong: dailySoftLimit(configured.wrong, progress.wrong),
        fresh: dailySoftLimit(configured.fresh, progress.fresh),
      }
    : configured;
  const buffer = configured.due + configured.wrong + configured.fresh;
  return { due: dueCandidates(limits.due + buffer, now, scope), wrong: wrongCandidates(limits.wrong + buffer, now, scope), fresh: newCandidates(limits.fresh + buffer, now, scope), limits };
}
export function countAvailableCandidates(now: number, scope: CandidateScope = "LEXICAL") { const skipped = now - SKIP_COOLDOWN_MS; const available = (sql: string, params: number[]) => Number((sqlite.prepare(sql).get(...params) as { count: number }).count); const suffix = `${scopeSql(scope)} AND ${availabilitySql()}`; return { due: available(`SELECT count(*) AS count FROM review_cards c JOIN words w ON w.id = c.word_id WHERE c.due_at <= ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${suffix}`, [now, skipped, now - SESSION_RESUME_TTL_MS]), wrong: available(`SELECT count(*) AS count FROM wrong_word_states x JOIN words w ON w.id = x.word_id WHERE x.active = 1 AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${suffix}`, [skipped, now - SESSION_RESUME_TTL_MS]), fresh: available(`SELECT count(*) AS count FROM words w LEFT JOIN review_cards c ON c.word_id = w.id WHERE c.word_id IS NULL AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${suffix}`, [skipped, now - SESSION_RESUME_TTL_MS]) }; }
