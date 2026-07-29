import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { closeStudySessionWithActiveDuration, MAX_ACTIVE_ANSWER_DURATION_MS } from "@/modules/reviews/duration";
import { getStatistics } from "@/modules/statistics/service";

function insertWord(term: string): number {
  const now = Date.now();
  return Number(sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, content_type,
     initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'WORD', 'READY', ?, ?)`)
    .run(term, term.toLocaleLowerCase(), now, now).lastInsertRowid);
}

function insertReview(wordId: number, reviewedAt: number, durationMs: number, sessionId: number | null): void {
  sqlite.prepare(`INSERT INTO review_logs
    (client_answer_id, word_id, study_session_id, reviewed_at, rating, question_type,
     is_correct, duration_ms, created_at)
    VALUES (?, ?, ?, ?, 'GOOD', 'EN_TO_ZH', 1, ?, ?)`)
    .run(crypto.randomUUID(), wordId, sessionId, reviewedAt, durationMs, reviewedAt);
}

describe("active study duration statistics", () => {
  it("sums answer time instead of wall-clock session duration", () => {
    const now = Date.now();
    const wordId = insertWord("active-time");
    const sessionId = Number(sqlite.prepare(`INSERT INTO study_sessions
      (session_type, started_at, completed_at, planned_count, completed_count,
       correct_count, wrong_count, skipped_count, duration_ms, created_at)
      VALUES ('DAILY', ?, ?, 2, 2, 2, 0, 0, ?, ?)`)
      .run(now, now, 8 * 60 * 60 * 1000, now).lastInsertRowid);

    insertReview(wordId, now - 40_000, 30_000, sessionId);
    insertReview(wordId, now - 20_000, 20 * 60 * 1000, sessionId);
    insertReview(wordId, now - 10_000, 15_000, null);

    const statistics = getStatistics(1);
    const today = statistics.daily[0]!;

    expect(today.reviews).toBe(3);
    expect(today.sessions).toBe(1);
    expect(today.minutes).toBe(11);
  });

  it("stores completed session duration as the capped sum of its answers", () => {
    const now = Date.now();
    const wordId = insertWord("session-active-time");
    const sessionId = Number(sqlite.prepare(`INSERT INTO study_sessions
      (session_type, started_at, planned_count, completed_count, created_at)
      VALUES ('DAILY', ?, 2, 2, ?)`)
      .run(now - 60 * 60 * 1000, now).lastInsertRowid);

    insertReview(wordId, now - 30_000, 20_000, sessionId);
    insertReview(wordId, now - 10_000, 30 * 60 * 1000, sessionId);
    closeStudySessionWithActiveDuration(sessionId, now);

    const session = sqlite.prepare("SELECT duration_ms, completed_at FROM study_sessions WHERE id = ?")
      .get(sessionId) as { duration_ms: number; completed_at: number };
    expect(session.duration_ms).toBe(20_000 + MAX_ACTIVE_ANSWER_DURATION_MS);
    expect(session.completed_at).toBe(now);
  });
});
