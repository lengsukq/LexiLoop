import { sqlite } from "@/db/client";
import { getDailyStudyPlan } from "@/modules/study/service";

const timezone = process.env.APP_TIMEZONE ?? "Asia/Shanghai";
function dateKey(timestamp: number): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(timestamp));
}
function lastDateKeys(days: number): string[] {
  const result: string[] = [];
  const now = Date.now();
  for (let offset = days - 1; offset >= 0; offset -= 1) result.push(dateKey(now - offset * 24 * 60 * 60 * 1000));
  return result;
}

export async function getDashboard() {
  const plan = await getDailyStudyPlan();
  const totals = sqlite.prepare(`SELECT count(*) AS total,
    sum(CASE WHEN mastery_level = 'MASTERED' THEN 1 ELSE 0 END) AS mastered,
    sum(CASE WHEN initialization_status IN ('READY','PARTIAL') THEN 1 ELSE 0 END) AS initialized,
    sum(CASE WHEN initialization_status = 'FAILED' THEN 1 ELSE 0 END) AS failed
    FROM words`).get() as { total: number; mastered: number; initialized: number; failed: number };
  const today = dateKey(Date.now());
  const since = Date.now() - 48 * 60 * 60 * 1000;
  const logs = sqlite.prepare("SELECT reviewed_at, is_correct FROM review_logs WHERE reviewed_at >= ?").all(since) as Array<{ reviewed_at: number; is_correct: number }>;
  const skips = sqlite.prepare(`SELECT answered_at FROM study_session_items
    WHERE status = 'SKIPPED' AND COALESCE(skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET') AND answered_at >= ?`).all(since) as Array<{ answered_at: number }>;
  const todayLogs = logs.filter((item) => dateKey(item.reviewed_at) === today);
  const todaySkipped = skips.filter((item) => dateKey(item.answered_at) === today).length;
  const todayProcessed = todayLogs.length + todaySkipped;
  return {
    totalWords: totals.total,
    masteredWords: totals.mastered ?? 0,
    initializedWords: totals.initialized ?? 0,
    failedWords: totals.failed ?? 0,
    todayReviews: todayLogs.length,
    todaySkipped,
    todayProcessed,
    todayGoalTotal: todayProcessed + plan.plannedTotal,
    todayAccuracy: todayLogs.length ? Math.round(todayLogs.filter((item) => item.is_correct).length / todayLogs.length * 100) : null,
    plan,
  };
}

export function getStatistics(days = 30) {
  const since = Date.now() - (days + 1) * 24 * 60 * 60 * 1000;
  const logs = sqlite.prepare(`SELECT reviewed_at, is_correct, rating, duration_ms, study_session_id
    FROM review_logs WHERE reviewed_at >= ? ORDER BY reviewed_at ASC`).all(since) as Array<{
      reviewed_at: number; is_correct: number; rating: string; duration_ms: number | null; study_session_id: number | null;
    }>;
  const sessions = sqlite.prepare(`SELECT started_at, completed_count, correct_count, skipped_count, duration_ms
    FROM study_sessions WHERE started_at >= ?`).all(since) as Array<{
      started_at: number; completed_count: number; correct_count: number; skipped_count: number; duration_ms: number | null;
    }>;
  const keys = lastDateKeys(days);
  const daily = new Map(keys.map((key) => [key, { date: key, reviews: 0, correct: 0, again: 0, skipped: 0, minutes: 0, sessions: 0 }]));
  for (const log of logs) {
    const item = daily.get(dateKey(log.reviewed_at));
    if (!item) continue;
    item.reviews += 1;
    item.correct += log.is_correct ? 1 : 0;
    item.again += log.rating === "AGAIN" ? 1 : 0;
    if (log.study_session_id === null) item.minutes += (log.duration_ms ?? 0) / 60_000;
  }
  for (const session of sessions) {
    const item = daily.get(dateKey(session.started_at));
    if (!item || session.completed_count === 0) continue;
    item.sessions += 1;
    item.skipped += session.skipped_count ?? 0;
    item.minutes += (session.duration_ms ?? 0) / 60_000;
  }
  const activeDates = new Set([
    ...logs.map((item) => dateKey(item.reviewed_at)),
    ...sessions.filter((item) => item.completed_count > 0).map((item) => dateKey(item.started_at)),
  ]);
  let streak = 0;
  for (let offset = 0; offset < 3650; offset += 1) {
    const key = dateKey(Date.now() - offset * 24 * 60 * 60 * 1000);
    if (activeDates.has(key)) streak += 1;
    else if (offset === 0) continue;
    else break;
  }
  const total = sqlite.prepare("SELECT count(*) AS count FROM review_logs").get() as { count: number };
  const correct = sqlite.prepare("SELECT count(*) AS count FROM review_logs WHERE is_correct = 1").get() as { count: number };
  const mastery = sqlite.prepare("SELECT mastery_level AS level, count(*) AS count FROM words GROUP BY mastery_level").all() as Array<{ level: string; count: number }>;
  const wrong = sqlite.prepare("SELECT count(*) AS count FROM wrong_word_states WHERE active = 1").get() as { count: number };
  return {
    summary: {
      totalReviews: total.count,
      totalAccuracy: total.count ? Math.round(correct.count / total.count * 100) : null,
      streakDays: streak,
      activeWrongWords: wrong.count,
    },
    daily: [...daily.values()].map((item) => ({
      ...item,
      accuracy: item.reviews ? Math.round(item.correct / item.reviews * 100) : null,
      minutes: Math.round(item.minutes),
    })),
    mastery: ["NEW", "LEARNING", "FAMILIAR", "PROFICIENT", "MASTERED"].map((level) => ({
      level,
      count: mastery.find((item) => item.level === level)?.count ?? 0,
    })),
  };
}
