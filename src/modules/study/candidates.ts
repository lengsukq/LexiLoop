import { sqlite } from "@/db/client";
import type { EntryType, QuestionType, StudyMode } from "@/lib/types";
import { getSettings } from "@/modules/settings/service";
import { getTodayRecommendedItems } from "@/modules/suggestions/service";
import { DAY_MS, HOUR_MS } from "@/lib/time";
import { startOfLocalDay } from "@/lib/date-key";
import { definitionMeaningSql, summaryTranslationSql } from "@/modules/dictionary/availability";

export interface StudyCandidate {
  id: number;
  term: string;
  normalized_term: string;
  source_language: string;
  target_language: string;
  content_type: EntryType;
  mastery_score?: number | null;
  continuousTaskType?: "REVIEW" | "WRONG" | "NEW";
}
export type CandidateScope = "LEXICAL" | "SENTENCE" | "ALL";
type RecommendedCandidate = StudyCandidate & { recommendedQuestionType: QuestionType };
type Pools = { due: StudyCandidate[]; wrong: StudyCandidate[]; fresh: StudyCandidate[]; limits: { due: number; wrong: number; fresh: number } };
export type CandidateRandom = () => number;
const SKIP_COOLDOWN_MS = 12 * HOUR_MS;
export const SESSION_RESUME_TTL_MS = DAY_MS;
const DAILY_QUOTA_GRACE_RATIO = 0.2;
const DAILY_NEW_WORD_RATIO = 1 / 3;
const CATEGORY_LOOKAHEAD = 6;

function scopeSql(scope: CandidateScope): string { return scope === "SENTENCE" ? "AND COALESCE(w.content_type, w.entry_type) = 'SENTENCE'" : scope === "LEXICAL" ? "AND COALESCE(w.content_type, w.entry_type) <> 'SENTENCE'" : ""; }

/**
 * Only words with a usable meaning may enter study sessions: a word whose
 * definitions are missing or contain only empty text produces a question
 * without choices. Sentences may also carry their meaning in
 * `summary.translation` (e.g. AI/translation providers).
 */
function hasMeaningSql(scope: CandidateScope): string {
  // json_typeof guards against rows where the payload is valid JSON but not
  // an array (e.g. an object from a legacy import), which would otherwise make
  // the whole candidate query fail on PostgreSQL.
  const definitionMeaning = definitionMeaningSql();
  if (scope !== "SENTENCE") return `AND ${definitionMeaning}`;
  return `AND (${definitionMeaning} OR ${summaryTranslationSql()})`;
}
function availabilitySql(): string { return `NOT EXISTS (SELECT 1 FROM study_session_items skipped WHERE skipped.word_id = w.id AND skipped.status = 'SKIPPED' AND COALESCE(skipped.skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET') AND skipped.answered_at IS NOT NULL AND skipped.answered_at >= ?) AND NOT EXISTS (SELECT 1 FROM study_session_items active_item JOIN study_sessions active_session ON active_session.id = active_item.study_session_id WHERE active_item.word_id = w.id AND active_item.status = 'PENDING' AND active_session.completed_at IS NULL AND COALESCE(active_session.source_type, '') <> 'MATCH_GAME' AND COALESCE(active_session.source_type, '') NOT LIKE 'GAME_%' AND active_session.started_at >= ?)`; }
const selectColumns = "w.id, w.term, w.normalized_term, w.source_language, w.target_language, w.content_type, performance.mastery_score";
async function dueCandidates(limit: number, now: number, scope: CandidateScope): Promise<StudyCandidate[]> {
  return await sqlite.prepare(`SELECT ${selectColumns} FROM review_cards c JOIN words w ON w.id = c.word_id
    LEFT JOIN word_review_stats performance ON performance.word_id = w.id
    WHERE c.due_at <= ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${scopeSql(scope)} ${hasMeaningSql(scope)} AND ${availabilitySql()}
    ORDER BY
      LEAST((CAST(? - c.due_at AS REAL) / 86400000.0), 10) * (1.0 + c.difficulty * 0.15)
      + COALESCE(performance.recent_wrong_14d, 0) * 1.2
      + COALESCE(performance.recent_again_14d, 0) * 0.8
      + COALESCE(performance.recent_hard_14d, 0) * 0.35 DESC,
      c.due_at ASC LIMIT ?`).all(
    now,
    now - SKIP_COOLDOWN_MS,
    now - SESSION_RESUME_TTL_MS,
    now,
    limit,
  ) as StudyCandidate[];
}
async function wrongCandidates(limit: number, now: number, scope: CandidateScope): Promise<StudyCandidate[]> {
  return await sqlite.prepare(`SELECT ${selectColumns} FROM wrong_word_states x JOIN words w ON w.id = x.word_id
    WHERE x.active = 1 AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${scopeSql(scope)} ${hasMeaningSql(scope)} AND ${availabilitySql()}
    ORDER BY x.wrong_count DESC, x.hard_count DESC, COALESCE(x.last_wrong_at, x.updated_at) DESC LIMIT ?`).all(
    now - SKIP_COOLDOWN_MS,
    now - SESSION_RESUME_TTL_MS,
    limit,
  ) as StudyCandidate[];
}
async function newCandidates(limit: number, now: number, scope: CandidateScope): Promise<StudyCandidate[]> { return await sqlite.prepare(`SELECT ${selectColumns} FROM words w LEFT JOIN review_cards c ON c.word_id = w.id WHERE c.word_id IS NULL AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${scopeSql(scope)} ${hasMeaningSql(scope)} AND ${availabilitySql()} ORDER BY COALESCE(w.source_created_at, w.created_at) ASC LIMIT ?`).all(now - SKIP_COOLDOWN_MS, now - SESSION_RESUME_TTL_MS, limit) as StudyCandidate[]; }

async function leastRecentlyReviewedCandidates(limit: number, now: number, scope: CandidateScope, excludedIds: number[]): Promise<StudyCandidate[]> {
  const exclusion = excludedIds.length ? `AND w.id NOT IN (${excludedIds.map(() => "?").join(",")})` : "";
  return await sqlite.prepare(`SELECT ${selectColumns},
      COALESCE(stats.last_reviewed_at, w.source_created_at, w.created_at) AS last_reviewed_at
    FROM words w
    LEFT JOIN word_review_stats stats ON stats.word_id = w.id
    WHERE w.is_suspended = 0
      AND w.initialization_status IN ('READY','PARTIAL')
      ${scopeSql(scope)}
      ${hasMeaningSql(scope)}
      AND ${availabilitySql()}
      ${exclusion}
    ORDER BY last_reviewed_at ASC, w.id ASC
    LIMIT ?`).all(
    now - SKIP_COOLDOWN_MS,
    now - SESSION_RESUME_TTL_MS,
    ...excludedIds,
    limit,
  ) as StudyCandidate[];
}

function boundedRandom(random: CandidateRandom): number {
  return Math.min(0.999999, Math.max(0, random()));
}

function weightedIndex(length: number, random: CandidateRandom, weightAt: (index: number) => number): number {
  if (length <= 1) return 0;
  const weights = Array.from({ length }, (_, index) => Math.max(0.001, weightAt(index)));
  const total = weights.reduce((sum, weight) => sum + weight, 0);
  let cursor = boundedRandom(random) * total;
  for (let index = 0; index < weights.length; index += 1) {
    cursor -= weights[index]!;
    if (cursor < 0) return index;
  }
  return weights.length - 1;
}

function takeWeightedCandidate(items: StudyCandidate[], random: CandidateRandom, taskType: StudyCandidate["continuousTaskType"]): StudyCandidate | null {
  if (!items.length) return null;
  const lookahead = Math.min(CATEGORY_LOOKAHEAD, items.length);
  const index = weightedIndex(lookahead, random, (rank) => 1 + (lookahead - rank) / lookahead);
  const [candidate] = items.splice(index, 1);
  return candidate ? { ...candidate, continuousTaskType: taskType } : null;
}

type MixedGroups = { due: StudyCandidate[]; wrong: StudyCandidate[]; fresh: StudyCandidate[] };
type MixedCategory = keyof MixedGroups;

function categoryWeight(category: MixedCategory, groups: MixedGroups, targetFresh: number, selectedFresh: number): number {
  const remainingFresh = Math.max(0, targetFresh - selectedFresh);
  const remainingTotal = groups.due.length + groups.wrong.length + groups.fresh.length;
  if (!remainingTotal) return 0;
  if (category === "fresh") return groups.fresh.length ? remainingFresh / remainingTotal : 0;

  const remainingReviews = groups.due.length + groups.wrong.length;
  if (!remainingReviews) return 0;
  const reviewShare = 1 - remainingFresh / remainingTotal;
  const dueWeight = groups.due.length;
  const wrongWeight = groups.wrong.length * 1.25;
  const reviewWeight = dueWeight + wrongWeight;
  if (!reviewWeight) return 0;
  return reviewShare * (category === "wrong" ? wrongWeight : dueWeight) / reviewWeight;
}

function selectWeightedMixed(groups: MixedGroups, limit: number, random: CandidateRandom): StudyCandidate[] {
  const working: MixedGroups = {
    due: [...groups.due],
    wrong: [...groups.wrong],
    fresh: [...groups.fresh],
  };
  const selected: StudyCandidate[] = [];
  const targetFresh = Math.min(working.fresh.length, Math.ceil(Math.min(limit, working.due.length + working.wrong.length + working.fresh.length) * DAILY_NEW_WORD_RATIO));
  let selectedFresh = 0;

  while (selected.length < limit && (working.due.length || working.wrong.length || working.fresh.length)) {
    const available = (Object.keys(working) as MixedCategory[]).filter((category) => working[category].length > 0);
    const category = available[weightedIndex(available.length, random, (index) => categoryWeight(available[index]!, working, targetFresh, selectedFresh))]!;
    const taskType = category === "fresh" ? "NEW" : category === "wrong" ? "WRONG" : "REVIEW";
    const candidate = takeWeightedCandidate(working[category], random, taskType);
    if (!candidate) continue;
    selected.push(candidate);
    if (category === "fresh") selectedFresh += 1;
  }
  return selected;
}

/** Selects a continuation batch with a soft new-word target and urgency-weighted randomness. */
export async function continuousCandidates(limit: number, now: number, scope: CandidateScope = "LEXICAL", random: CandidateRandom = Math.random): Promise<StudyCandidate[]> {
  const due = await dueCandidates(limit, now, scope);
  const dueIds = new Set(due.map((item) => item.id));
  const wrong = (await wrongCandidates(limit, now, scope)).filter((item) => !dueIds.has(item.id));
  const reviewIds = new Set([...dueIds, ...wrong.map((item) => item.id)]);
  const selected = selectWeightedMixed({
    due,
    wrong,
    fresh: (await newCandidates(limit, now, scope)).filter((item) => !reviewIds.has(item.id)),
  }, limit, random);
  if (selected.length >= limit) return selected;

  const seen = selected.map((item) => item.id);
  const fallback = await leastRecentlyReviewedCandidates(limit - selected.length, now, scope, seen);
  const fallbackSelected: StudyCandidate[] = [];
  while (fallbackSelected.length < limit - selected.length && fallback.length) {
    const candidate = takeWeightedCandidate(fallback, random, "REVIEW");
    if (candidate) fallbackSelected.push(candidate);
  }
  return [...selected, ...fallbackSelected];
}

export async function aiRecommendedCandidates(now: number): Promise<RecommendedCandidate[]> {
  const recommendations = await getTodayRecommendedItems(); if (!recommendations.length) return [];
  const ids = recommendations.map((item) => item.wordId); const rows = await sqlite.prepare(`SELECT ${selectColumns} FROM words w WHERE w.id IN (${ids.map(() => "?").join(",")}) AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${hasMeaningSql("ALL")} AND NOT EXISTS (SELECT 1 FROM study_session_items skipped WHERE skipped.word_id = w.id AND skipped.status = 'SKIPPED' AND COALESCE(skipped.skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET') AND skipped.answered_at IS NOT NULL AND skipped.answered_at >= ?) AND NOT EXISTS (SELECT 1 FROM study_session_items done JOIN study_sessions ds ON ds.id = done.study_session_id WHERE done.word_id = w.id AND ds.source_type = 'AI_RECOMMENDED' AND ds.started_at >= ? AND done.status IN ('ANSWERED', 'SKIPPED') AND COALESCE(done.skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET'))`).all(...ids, now - SKIP_COOLDOWN_MS, startOfLocalDay(now)) as StudyCandidate[];
  const byId = new Map(rows.map((row) => [row.id, row])); return recommendations.flatMap((item) => { const candidate = byId.get(item.wordId); return candidate ? [{ ...candidate, recommendedQuestionType: item.questionType }] : []; });
}
function interleave(groups: Array<{ items: StudyCandidate[]; take: number }>): StudyCandidate[] { const indexes = groups.map(() => 0); const result: StudyCandidate[] = []; const seen = new Set<number>(); while (groups.some((group, index) => indexes[index]! < group.items.length)) groups.forEach((group, index) => { for (let count = 0; count < group.take && indexes[index]! < group.items.length; count++) { const item = group.items[indexes[index]!]!; indexes[index]! += 1; if (!seen.has(item.id)) { seen.add(item.id); result.push(item); } } }); return result; }
function prioritizedGroups(pools: Pools) { const selected = new Set<number>(); const take = (items: StudyCandidate[], limit: number) => items.filter((item) => !selected.has(item.id)).slice(0, limit).filter((item) => { selected.add(item.id); return true; }); return { due: take(pools.due, pools.limits.due), wrong: take(pools.wrong, pools.limits.wrong), fresh: take(pools.fresh, pools.limits.fresh) }; }
export function selectCandidates(mode: StudyMode, pools: Pools, options: { random?: CandidateRandom } = {}): StudyCandidate[] {
  const groups = prioritizedGroups(pools); if (mode === "DUE_REVIEW") return pools.due.slice(0, pools.limits.due); if (mode === "WRONG_WORDS") return pools.wrong.slice(0, pools.limits.wrong); if (mode === "NEW_WORDS") return pools.fresh.slice(0, pools.limits.fresh); if (mode === "AI_RECOMMENDED") return [];
  if (mode === "DAILY") return selectWeightedMixed(groups, groups.due.length + groups.wrong.length + groups.fresh.length, options.random ?? Math.random);
  const ratios: Array<{ items: StudyCandidate[]; take: number }> = mode === "LISTENING" ? [{ items: groups.due, take: 5 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 2 }] : mode === "SPELLING" ? [{ items: groups.due, take: 5 }, { items: groups.wrong, take: 3 }, { items: groups.fresh, take: 1 }] : [{ items: groups.due, take: 4 }, { items: groups.wrong, take: 2 }, { items: groups.fresh, take: 1 }];
  return interleave(ratios);
}
export function questionFor(mode: StudyMode, taskType: string, position = 0, masteryScore?: number): QuestionType {
  if (mode === "SENTENCE_REVIEW") return taskType === "NEW" ? "EN_TO_ZH" : "ZH_TO_EN_SPELLING";
  if (mode === "LISTENING") return "LISTENING_SPELLING";
  if (mode === "SPELLING" || mode === "WRONG_WORDS" || taskType === "WRONG") return "ZH_TO_EN_SPELLING";
  if (mode === "DAILY") {
    if (taskType === "NEW") return "EN_TO_ZH";
    if (masteryScore != null) {
      if (masteryScore < 35) return "EN_TO_ZH_CHOICE";
      if (masteryScore < 70) return "ZH_TO_EN_CHOICE";
      return "ZH_TO_EN_SPELLING";
    }
    return position % 2 === 1 ? "ZH_TO_EN_CHOICE" : "EN_TO_ZH_CHOICE";
  }
  return mode === "DUE_REVIEW" || mode === "NEW_WORDS" ? "EN_TO_ZH_CHOICE" : "EN_TO_ZH";
}
export function taskFor(mode: StudyMode, candidate: StudyCandidate, sets: { due: Set<number>; wrong: Set<number> }): "NEW" | "REVIEW" | "WRONG" | "LISTENING" | "SPELLING" { if (mode === "LISTENING") return "LISTENING"; if (mode === "SPELLING") return "SPELLING"; if (mode === "DUE_REVIEW") return "REVIEW"; if (mode === "NEW_WORDS") return "NEW"; if (candidate.continuousTaskType) return candidate.continuousTaskType; if (sets.due.has(candidate.id)) return "REVIEW"; if (sets.wrong.has(candidate.id)) return "WRONG"; return "NEW"; }
type PoolLimits = { due: number; wrong: number; fresh: number };

function dailySoftLimit(target: number, used: number): number {
  const remaining = Math.max(0, target - used);
  if (used < target || target === 0) return remaining;
  const grace = Math.max(1, Math.ceil(target * DAILY_QUOTA_GRACE_RATIO));
  return Math.max(0, target + grace - used);
}

export async function dailyProgress(now: number): Promise<PoolLimits> {
  const today = startOfLocalDay(now);
  const rows = await sqlite.prepare(`SELECT i.task_type, count(*) AS count
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
  const progress = options.applyDailySoftQuota && scope === "LEXICAL" ? await dailyProgress(now) : { due: 0, wrong: 0, fresh: 0 };
  const limits = options.applyDailySoftQuota && scope === "LEXICAL"
    ? {
        due: dailySoftLimit(configured.due, progress.due),
        wrong: dailySoftLimit(configured.wrong, progress.wrong),
        fresh: dailySoftLimit(configured.fresh, progress.fresh),
      }
    : configured;
  const buffer = configured.due + configured.wrong + configured.fresh;
  return { due: await dueCandidates(limits.due + buffer, now, scope), wrong: await wrongCandidates(limits.wrong + buffer, now, scope), fresh: await newCandidates(limits.fresh + buffer, now, scope), limits };
}
export async function countAvailableCandidates(now: number, scope: CandidateScope = "LEXICAL") { const skipped = now - SKIP_COOLDOWN_MS; const available = async (sql: string, params: number[]) => Number((await sqlite.prepare(sql).get(...params) as { count: number }).count); const suffix = `${scopeSql(scope)} ${hasMeaningSql(scope)} AND ${availabilitySql()}`; return { due: await available(`SELECT count(*) AS count FROM review_cards c JOIN words w ON w.id = c.word_id WHERE c.due_at <= ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${suffix}`, [now, skipped, now - SESSION_RESUME_TTL_MS]), wrong: await available(`SELECT count(*) AS count FROM wrong_word_states x JOIN words w ON w.id = x.word_id WHERE x.active = 1 AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${suffix}`, [skipped, now - SESSION_RESUME_TTL_MS]), fresh: await available(`SELECT count(*) AS count FROM words w LEFT JOIN review_cards c ON c.word_id = w.id WHERE c.word_id IS NULL AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') ${suffix}`, [skipped, now - SESSION_RESUME_TTL_MS]) }; }
