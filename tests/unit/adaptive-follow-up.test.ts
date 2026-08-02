import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { scheduleAdaptiveFollowUp } from "@/modules/study/adaptive";

function createSession(overrides: { completedAt?: number | null; sourceType?: string | null } = {}): number {
  const now = Date.now();
  const { lastInsertRowid } = sqlite.prepare(`INSERT INTO study_sessions
    (session_type, source_type, started_at, completed_at, planned_count, created_at)
    VALUES ('DAILY', ?, ?, ?, 10, ?)`).run(
    overrides.sourceType ?? null,
    now,
    overrides.completedAt ?? null,
    now,
  );
  return Number(lastInsertRowid);
}

function createWord(term = "river"): number {
  const now = Date.now();
  const { lastInsertRowid } = sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, content_type,
     initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'WORD', 'READY', ?, ?)`).run(term, term.toLowerCase(), now, now);
  return Number(lastInsertRowid);
}

function insertItem(sessionId: number, position: number, wordId: number, status = "PENDING"): number {
  const now = Date.now();
  const { lastInsertRowid } = sqlite.prepare(`INSERT INTO study_session_items
    (study_session_id, position, word_id, task_type, question_type, status, created_at)
    VALUES (?, ?, ?, 'REVIEW', 'EN_TO_ZH_CHOICE', ?, ?)`).run(sessionId, position, wordId, status, now);
  return Number(lastInsertRowid);
}

describe("adaptive follow-up scheduling", () => {
  it("re-inserts a forgotten (AGAIN) word after a delay of several items", () => {
    const sessionId = createSession();
    const wordId = createWord();
    const currentItemId = insertItem(sessionId, 0, wordId, "ANSWERED");
    for (let position = 1; position <= 9; position += 1) insertItem(sessionId, position, createWord(`river${position}`));

    const result = scheduleAdaptiveFollowUp({
      sessionId,
      itemId: currentItemId,
      wordId,
      currentQuestionType: "EN_TO_ZH_CHOICE",
      entryType: "WORD",
      isCorrect: false,
      rating: "AGAIN",
      now: Date.now(),
    });

    expect(result).toMatchObject({ questionType: "ZH_TO_EN_SPELLING", repetition: 1 });
    const between = sqlite.prepare(`SELECT count(*) AS count FROM study_session_items
      WHERE study_session_id = ? AND position > 0 AND position < ?`)
      .get(sessionId, result!.position) as { count: number };
    expect(Number(between.count)).toBe(7);
    const inserted = sqlite.prepare(`SELECT position, question_type, task_type, status
      FROM study_session_items WHERE study_session_id = ? AND position = ?`)
      .get(sessionId, result!.position) as Record<string, unknown>;
    expect(inserted).toEqual({
      position: 7.5,
      question_type: "ZH_TO_EN_SPELLING",
      task_type: "WRONG",
      status: "PENDING",
    });
  });

  it("does not re-insert a fuzzy (HARD) word into the current session", () => {
    const sessionId = createSession();
    const wordId = createWord();
    const currentItemId = insertItem(sessionId, 0, wordId, "ANSWERED");
    for (let position = 1; position <= 9; position += 1) insertItem(sessionId, position, createWord(`fuzzy${position}`));

    const result = scheduleAdaptiveFollowUp({
      sessionId,
      itemId: currentItemId,
      wordId,
      currentQuestionType: "EN_TO_ZH_CHOICE",
      entryType: "WORD",
      isCorrect: false,
      rating: "HARD",
      now: Date.now(),
    });

    expect(result).toBeNull();
    const count = sqlite.prepare("SELECT count(*) AS count FROM study_session_items WHERE study_session_id = ?")
      .get(sessionId) as { count: number };
    expect(Number(count.count)).toBe(10);
  });

  it("skips re-insertion when the word already has a pending item", () => {
    const sessionId = createSession();
    const wordId = createWord();
    const currentItemId = insertItem(sessionId, 0, wordId, "ANSWERED");
    insertItem(sessionId, 1, wordId);
    for (let position = 2; position <= 9; position += 1) insertItem(sessionId, position, createWord(`dup${position}`));

    const result = scheduleAdaptiveFollowUp({
      sessionId,
      itemId: currentItemId,
      wordId,
      currentQuestionType: "EN_TO_ZH_CHOICE",
      entryType: "WORD",
      isCorrect: false,
      rating: "AGAIN",
      now: Date.now(),
    });

    expect(result).toBeNull();
    const planned = sqlite.prepare("SELECT planned_count FROM study_sessions WHERE id = ?")
      .get(sessionId) as { planned_count: number };
    expect(planned.planned_count).toBe(10);
  });

  it("skips re-insertion for completed or game sessions", () => {
    const wordId = createWord();
    const completedSessionId = createSession({ completedAt: Date.now() });
    const completedItemId = insertItem(completedSessionId, 0, wordId, "ANSWERED");
    const gameSessionId = createSession({ sourceType: "MATCH_GAME" });
    const gameItemId = insertItem(gameSessionId, 0, wordId, "ANSWERED");

    expect(scheduleAdaptiveFollowUp({
      sessionId: completedSessionId, itemId: completedItemId, wordId,
      currentQuestionType: "EN_TO_ZH_CHOICE", entryType: "WORD",
      isCorrect: false, rating: "AGAIN", now: Date.now(),
    })).toBeNull();
    expect(scheduleAdaptiveFollowUp({
      sessionId: gameSessionId, itemId: gameItemId, wordId,
      currentQuestionType: "EN_TO_ZH_CHOICE", entryType: "WORD",
      isCorrect: false, rating: "AGAIN", now: Date.now(),
    })).toBeNull();
  });
});
