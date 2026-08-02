import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { scheduleAdaptiveFollowUp } from "@/modules/study/adaptive";

async function createSession(overrides: { completedAt?: number | null; sourceType?: string | null } = {}): Promise<number> {
  const now = Date.now();
  const { lastInsertRowid } = await sqlite.prepare(`INSERT INTO study_sessions
    (session_type, source_type, started_at, completed_at, planned_count, created_at)
    VALUES ('DAILY', ?, ?, ?, 10, ?)`).run(
    overrides.sourceType ?? null,
    now,
    overrides.completedAt ?? null,
    now,
  );
  return Number(lastInsertRowid);
}

async function createWord(term = "river"): Promise<number> {
  const now = Date.now();
  const { lastInsertRowid } = await sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, content_type,
     initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'WORD', 'READY', ?, ?)`).run(term, term.toLowerCase(), now, now);
  return Number(lastInsertRowid);
}

async function insertItem(sessionId: number, position: number, wordId: number, status = "PENDING"): Promise<number> {
  const now = Date.now();
  const { lastInsertRowid } = await sqlite.prepare(`INSERT INTO study_session_items
    (study_session_id, position, word_id, task_type, question_type, status, created_at)
    VALUES (?, ?, ?, 'REVIEW', 'EN_TO_ZH_CHOICE', ?, ?)`).run(sessionId, position, wordId, status, now);
  return Number(lastInsertRowid);
}

describe("adaptive follow-up scheduling", () => {
  it("re-inserts a forgotten (AGAIN) word after a delay of several items", async () => {
    const sessionId = await createSession();
    const wordId = await createWord();
    const currentItemId = await insertItem(sessionId, 0, wordId, "ANSWERED");
    for (let position = 1; position <= 9; position += 1) await insertItem(sessionId, position, await createWord(`river${position}`));

    const result = await scheduleAdaptiveFollowUp({
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
    const between = await sqlite.prepare(`SELECT count(*) AS count FROM study_session_items
      WHERE study_session_id = ? AND position > 0 AND position < ?`)
      .get(sessionId, result!.position) as { count: number };
    expect(Number(between.count)).toBe(7);
    const inserted = await sqlite.prepare(`SELECT position, question_type, task_type, status
      FROM study_session_items WHERE study_session_id = ? AND position = ?`)
      .get(sessionId, result!.position) as Record<string, unknown>;
    expect(inserted).toEqual({
      position: 7.5,
      question_type: "ZH_TO_EN_SPELLING",
      task_type: "WRONG",
      status: "PENDING",
    });
  });

  it("does not re-insert a fuzzy (HARD) word into the current session", async () => {
    const sessionId = await createSession();
    const wordId = await createWord();
    const currentItemId = await insertItem(sessionId, 0, wordId, "ANSWERED");
    for (let position = 1; position <= 9; position += 1) await insertItem(sessionId, position, await createWord(`fuzzy${position}`));

    const result = await scheduleAdaptiveFollowUp({
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
    const count = await sqlite.prepare("SELECT count(*) AS count FROM study_session_items WHERE study_session_id = ?")
      .get(sessionId) as { count: number };
    expect(Number(count.count)).toBe(10);
  });

  it("skips re-insertion when the word already has a pending item", async () => {
    const sessionId = await createSession();
    const wordId = await createWord();
    const currentItemId = await insertItem(sessionId, 0, wordId, "ANSWERED");
    await insertItem(sessionId, 1, wordId);
    for (let position = 2; position <= 9; position += 1) await insertItem(sessionId, position, await createWord(`dup${position}`));

    const result = await scheduleAdaptiveFollowUp({
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
    const planned = await sqlite.prepare("SELECT planned_count FROM study_sessions WHERE id = ?")
      .get(sessionId) as { planned_count: number };
    expect(planned.planned_count).toBe(10);
  });

  it("skips re-insertion for completed or game sessions", async () => {
    const wordId = await createWord();
    const completedSessionId = await createSession({ completedAt: Date.now() });
    const completedItemId = await insertItem(completedSessionId, 0, wordId, "ANSWERED");
    const gameSessionId = await createSession({ sourceType: "MATCH_GAME" });
    const gameItemId = await insertItem(gameSessionId, 0, wordId, "ANSWERED");

    await expect(scheduleAdaptiveFollowUp({
      sessionId: completedSessionId, itemId: completedItemId, wordId,
      currentQuestionType: "EN_TO_ZH_CHOICE", entryType: "WORD",
      isCorrect: false, rating: "AGAIN", now: Date.now(),
    })).resolves.toBeNull();
    await expect(scheduleAdaptiveFollowUp({
      sessionId: gameSessionId, itemId: gameItemId, wordId,
      currentQuestionType: "EN_TO_ZH_CHOICE", entryType: "WORD",
      isCorrect: false, rating: "AGAIN", now: Date.now(),
    })).resolves.toBeNull();
  });
});
