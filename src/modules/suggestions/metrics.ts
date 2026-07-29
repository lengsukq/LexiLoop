import { sqlite } from "@/db/client";
import { boundedActiveDurationMs } from "@/modules/reviews/duration";
import { DAY_MS, suggestionDateKey } from "./date";
import type { DailySuggestionMetrics, ReviewRow } from "./types";

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

function questionAccuracy(reviews: ReviewRow[]): Record<string, number | null> {
  const groups = new Map<string, { total: number; correct: number }>();
  for (const review of reviews) {
    const group = groups.get(review.question_type) ?? { total: 0, correct: 0 };
    group.total += 1;
    if (review.is_correct) group.correct += 1;
    groups.set(review.question_type, group);
  }
  return Object.fromEntries([...groups.entries()].map(([questionType, group]) => [
    questionType,
    group.total ? Math.round(group.correct / group.total * 100) : null,
  ]));
}

export function collectSuggestionMetrics(now: number, sourceDateKey: string): {
  metrics: DailySuggestionMetrics;
  reviews: ReviewRow[];
} {
  const since = now - 3 * DAY_MS;
  const reviews = (sqlite.prepare(`SELECT word_id, reviewed_at, rating, question_type, is_correct,
      duration_ms, study_session_id FROM review_logs WHERE reviewed_at >= ? ORDER BY reviewed_at ASC`)
    .all(since) as ReviewRow[])
    .filter((review) => suggestionDateKey(review.reviewed_at) === sourceDateKey);
  const skips = (sqlite.prepare(`SELECT answered_at FROM study_session_items
      WHERE status = 'SKIPPED' AND COALESCE(skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET')
        AND answered_at >= ?`).all(since) as Array<{ answered_at: number }>)
    .filter((row) => suggestionDateKey(row.answered_at) === sourceDateKey);
  const sessions = (sqlite.prepare(`SELECT started_at, duration_ms, completed_count FROM study_sessions
      WHERE started_at >= ?`).all(since) as Array<{
        started_at: number;
        duration_ms: number | null;
        completed_count: number;
      }>)
    .filter((session) => suggestionDateKey(session.started_at) === sourceDateKey && session.completed_count > 0);

  const correctCount = reviews.filter((review) => Boolean(review.is_correct)).length;
  const timedReviews = reviews
    .map((review) => boundedActiveDurationMs(review.duration_ms))
    .filter((duration): duration is number => duration !== null);
  const activeDuration = timedReviews.reduce((sum, duration) => sum + duration, 0);

  return {
    reviews,
    metrics: {
      reviewCount: reviews.length,
      correctCount,
      accuracy: reviews.length ? Math.round(correctCount / reviews.length * 100) : null,
      againCount: reviews.filter((review) => review.rating === "AGAIN").length,
      hardCount: reviews.filter((review) => review.rating === "HARD").length,
      skippedCount: skips.length,
      sessionCount: sessions.length,
      averageDurationMs: timedReviews.length
        ? Math.round(activeDuration / timedReviews.length)
        : null,
      studyMinutes: Math.round(activeDuration / 60_000),
      completionRate: reviews.length + skips.length
        ? Math.round(reviews.length / (reviews.length + skips.length) * 100)
        : null,
      questionAccuracy: questionAccuracy(reviews),
    },
  };
}

export function calculateQualityScore(metrics: DailySuggestionMetrics): number | null {
  if (!metrics.reviewCount || metrics.accuracy === null) return null;
  const challengePenalty = (metrics.againCount * 1.5 + metrics.hardCount * 0.7) / metrics.reviewCount;
  const stability = clamp(100 - challengePenalty * 55, 0, 100);
  const speed = metrics.averageDurationMs === null
    ? 70
    : clamp(100 - Math.max(0, metrics.averageDurationMs - 5_000) / 180, 35, 100);
  const completion = metrics.completionRate ?? 70;
  return Math.round(metrics.accuracy * 0.58 + stability * 0.2 + speed * 0.08 + completion * 0.14);
}
