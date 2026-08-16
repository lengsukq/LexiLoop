import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import type { QuestionType, StudyMode } from "@/lib/types";
import { closeStudySessionWithActiveDuration } from "@/modules/reviews/duration";
import { aiRecommendedCandidates, continuousCandidates, loadPools, questionFor, selectCandidates, SESSION_RESUME_TTL_MS, taskFor, type CandidateScope, type StudyCandidate } from "./candidates";
import { getStudySession } from "./view";

export { getDailyStudyPlan } from "./plan";
export { getStudySession } from "./view";

async function expireStaleSessions(now: number): Promise<number> {
  const staleBefore = now - SESSION_RESUME_TTL_MS;
  return await sqlite.transaction(async () => {
    const sessions = await sqlite.prepare("SELECT id FROM study_sessions WHERE completed_at IS NULL AND started_at < ?").all(staleBefore) as Array<{ id: number }>;
    let expired = 0;
    for (const session of sessions) {
      const result = await sqlite.prepare("UPDATE study_session_items SET status = 'SKIPPED', answered_at = ?, skip_reason = 'SESSION_EXPIRED' WHERE study_session_id = ? AND status = 'PENDING'").run(now, session.id);
      expired += result.changes; await sqlite.prepare("UPDATE study_sessions SET completed_count = completed_count + ? WHERE id = ?").run(result.changes, session.id); await closeStudySessionWithActiveDuration(session.id, now);
    }
    return expired;
  }).immediate();
}

async function findResumableSession(mode: StudyMode, now: number): Promise<number | null> {
  const ttl = now - SESSION_RESUME_TTL_MS;
  const special = mode === "AI_RECOMMENDED" ? "AI_RECOMMENDED" : mode === "SENTENCE_REVIEW" ? "SENTENCE_REVIEW" : null;
  if (special) {
    const row = await sqlite.prepare("SELECT s.id FROM study_sessions s WHERE s.source_type = ? AND s.completed_at IS NULL AND s.started_at >= ? AND EXISTS (SELECT 1 FROM study_session_items i WHERE i.study_session_id = s.id AND i.status = 'PENDING') ORDER BY s.started_at DESC LIMIT 1").get(special, ttl) as { id: number } | undefined;
    return row?.id ?? null;
  }
  const exclusions = "COALESCE(s.source_type, '') <> 'MATCH_GAME' AND COALESCE(s.source_type, '') <> 'SENTENCE_REVIEW' AND COALESCE(s.source_type, '') NOT LIKE 'GAME_%'";
  const taskType: Record<string, string> = { DUE_REVIEW: "REVIEW", WRONG_WORDS: "WRONG", NEW_WORDS: "NEW", LISTENING: "LISTENING", SPELLING: "SPELLING" };
  const exact = await sqlite.prepare(`SELECT s.id FROM study_sessions s WHERE s.session_type = ? AND s.completed_at IS NULL AND s.started_at >= ? AND ${exclusions} AND EXISTS (SELECT 1 FROM study_session_items i WHERE i.study_session_id = s.id AND i.status = 'PENDING') ORDER BY s.started_at DESC LIMIT 1`).get(mode, ttl) as { id: number } | undefined;
  if (exact) return exact.id;
  const task = taskType[mode]; if (!task) return null;
  const daily = await sqlite.prepare(`SELECT s.id FROM study_sessions s WHERE s.completed_at IS NULL AND s.started_at >= ? AND ${exclusions} AND EXISTS (SELECT 1 FROM study_session_items i WHERE i.study_session_id = s.id AND i.status = 'PENDING' AND i.task_type = ?) ORDER BY s.started_at DESC LIMIT 1`).get(ttl, task) as { id: number } | undefined;
  return daily?.id ?? null;
}

export async function startStudySession(mode: StudyMode, resume = true, continuous = false) {
  const now = Date.now(); await expireStaleSessions(now);
  if (resume) { const resumableId = await findResumableSession(mode, now); if (resumableId) return getStudySession(resumableId, true); }
  const scope: CandidateScope = mode === "SENTENCE_REVIEW" ? "SENTENCE" : mode === "AI_RECOMMENDED" ? "ALL" : "LEXICAL";
  const pools = await loadPools(now, scope, { applyDailySoftQuota: mode === "DAILY" }); const recommended = mode === "AI_RECOMMENDED" ? await aiRecommendedCandidates(now) : null;
  if (mode === "AI_RECOMMENDED" && !recommended?.length) throw new ApiError("AI_RECOMMENDED_ALL_DONE");
  let selected: StudyCandidate[] = recommended ?? selectCandidates(mode, pools);
  if (mode === "DAILY" && continuous && selected.length === 0) selected = await continuousCandidates(10, now);
  const due = new Set(pools.due.map((item) => item.id)); const wrong = new Set(pools.wrong.map((item) => item.id));
  const persistedMode = mode === "AI_RECOMMENDED" ? "WRONG_WORDS" : mode === "SENTENCE_REVIEW" ? "DUE_REVIEW" : mode; const sourceType = mode === "AI_RECOMMENDED" || mode === "SENTENCE_REVIEW" ? mode : null;
  const sessionId = await sqlite.transaction(async () => {
    const session = await sqlite.prepare("INSERT INTO study_sessions (session_type, source_type, started_at, completed_at, planned_count, completed_count, correct_count, wrong_count, skipped_count, created_at) VALUES (?, ?, ?, ?, ?, 0, 0, 0, 0, ?)").run(persistedMode, sourceType, now, selected.length === 0 ? now : null, selected.length, now);
    const id = Number(session.lastInsertRowid); const insert = sqlite.prepare("INSERT INTO study_session_items (study_session_id, position, word_id, task_type, question_type, status, created_at) VALUES (?, ?, ?, ?, ?, 'PENDING', ?)");
    for (const [index, candidate] of selected.entries()) { const taskType = taskFor(mode === "AI_RECOMMENDED" ? "DAILY" : mode, candidate, { due, wrong }); const recommendedQuestion = (candidate as StudyCandidate & { recommendedQuestionType?: QuestionType }).recommendedQuestionType; await insert.run(id, index, candidate.id, taskType, recommendedQuestion ?? questionFor(mode, taskType, index), now); }
    return id;
  }).immediate();
  return getStudySession(sessionId, false);
}

export async function skipStudyItem(sessionId: number, itemId: number, reason = "LATER") {
  const now = Date.now();
  await sqlite.transaction(async () => {
    const item = await sqlite.prepare("SELECT i.status, s.completed_at FROM study_session_items i JOIN study_sessions s ON s.id = i.study_session_id WHERE i.id = ? AND i.study_session_id = ?").get(itemId, sessionId) as { status: string; completed_at: number | null } | undefined;
    if (!item) throw new ApiError("STUDY_ITEM_NOT_FOUND"); if (item.completed_at !== null || item.status !== "PENDING") throw new ApiError("STUDY_ITEM_ALREADY_PROCESSED");
    const updated = await sqlite.prepare("UPDATE study_session_items SET status = 'SKIPPED', answered_at = ?, skip_reason = ? WHERE id = ? AND study_session_id = ? AND status = 'PENDING'").run(now, reason, itemId, sessionId);
    if (updated.changes !== 1) throw new ApiError("STUDY_ITEM_ALREADY_PROCESSED");
    await sqlite.prepare("UPDATE study_sessions SET completed_count = completed_count + 1, skipped_count = skipped_count + 1 WHERE id = ?").run(sessionId);
    const pending = await sqlite.prepare("SELECT count(*) AS count FROM study_session_items WHERE study_session_id = ? AND status = 'PENDING'").get(sessionId) as { count: number }; if (pending.count === 0) await closeStudySessionWithActiveDuration(sessionId, now);
  }).immediate();
  return getStudySession(sessionId, false);
}
