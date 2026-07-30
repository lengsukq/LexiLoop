import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { claimJobs, recoverStaleJobs } from "@/modules/initialization/service";
import { processReviewAnswer } from "@/modules/reviews/service";

describe("initialization locking", () => {
  it("claims jobs once and recovers stale locks", () => {
    const now = Date.now();
    sqlite.prepare(`INSERT INTO words(term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
      VALUES ('hello','hello','en','zh-CN','WORD','QUEUED',?,?)`).run(now, now);
    const wordId = Number((sqlite.prepare("SELECT id FROM words").get() as { id: number }).id);
    sqlite.prepare(`INSERT INTO initialization_jobs(word_id, mode, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
      VALUES (?, 'SKIP_INITIALIZED', 'QUEUED', 0, 0, 5, ?, ?, ?)`).run(wordId, now, now, now);
    expect(claimJobs("worker-a", 2)).toHaveLength(1);
    expect(claimJobs("worker-b", 2)).toHaveLength(0);
    sqlite.prepare("UPDATE initialization_jobs SET locked_at = ? WHERE word_id = ?").run(now - 11 * 60_000, wordId);
    expect(recoverStaleJobs()).toBe(1);
    expect((sqlite.prepare("SELECT status FROM initialization_jobs WHERE word_id = ?").get(wordId) as { status: string }).status).toBe("QUEUED");
  });
});

describe("review service", () => {
  it("creates an FSRS card, log and wrong-word state idempotently", async () => {
    const now = Date.now();
    sqlite.prepare(`INSERT INTO words(term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
      VALUES ('cotton','cotton','en','zh-CN','WORD','READY',?,?)`).run(now, now);
    const wordId = Number((sqlite.prepare("SELECT id FROM words").get() as { id: number }).id);
    sqlite.prepare(`INSERT INTO word_contents(word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json, synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
      VALUES (?, ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', ?)`)
      .run(wordId, JSON.stringify([{ language: "zh-CN", partOfSpeech: "n", text: "棉花", source: "test", isUserEdited: false }]), now);
    const sessionId = Number(sqlite.prepare(`INSERT INTO study_sessions
      (session_type, started_at, planned_count, created_at) VALUES ('NEW_WORDS', ?, 1, ?)`).run(now, now).lastInsertRowid);
    const itemId = Number(sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, status, created_at)
      VALUES (?, 0, ?, 'NEW', 'EN_TO_ZH', 'PENDING', ?)`).run(sessionId, wordId, now).lastInsertRowid);
    const clientAnswerId = crypto.randomUUID();
    const first = await processReviewAnswer({ clientAnswerId, wordId, studySessionId: sessionId, studySessionItemId: itemId, rating: "AGAIN", questionType: "EN_TO_ZH" });
    expect(first.idempotent).toBe(false);
    expect(first.wrongWordActive).toBe(true);
    const second = await processReviewAnswer({ clientAnswerId, wordId, studySessionId: sessionId, studySessionItemId: itemId, rating: "GOOD", questionType: "EN_TO_ZH" });
    expect(second.idempotent).toBe(true);
    expect((sqlite.prepare("SELECT count(*) AS count FROM review_logs").get() as { count: number }).count).toBe(1);
  });

  it("schedules a delayed spelling follow-up after a wrong choice", async () => {
    const now = Date.now();
    sqlite.prepare(`INSERT INTO words(term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
      VALUES ('river','river','en','zh-CN','WORD','READY',?,?)`).run(now, now);
    const wordId = Number((sqlite.prepare("SELECT id FROM words").get() as { id: number }).id);
    sqlite.prepare(`INSERT INTO word_contents(word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json, synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
      VALUES (?, ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', ?)`).run(
      wordId,
      JSON.stringify([{ language: "zh-CN", partOfSpeech: "n", text: "河流", source: "test", isUserEdited: false }]),
      now,
    );
    const sessionId = Number(sqlite.prepare(`INSERT INTO study_sessions
      (session_type, started_at, planned_count, created_at) VALUES ('DAILY', ?, 1, ?)`).run(now, now).lastInsertRowid);
    const itemId = Number(sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, status, created_at)
      VALUES (?, 0, ?, 'NEW', 'EN_TO_ZH_CHOICE', 'PENDING', ?)`).run(sessionId, wordId, now).lastInsertRowid);

    const result = await processReviewAnswer({
      clientAnswerId: crypto.randomUUID(),
      wordId,
      studySessionId: sessionId,
      studySessionItemId: itemId,
      rating: "AGAIN",
      questionType: "EN_TO_ZH_CHOICE",
    });

    expect(result.adaptiveFollowUp).toMatchObject({ questionType: "ZH_TO_EN_SPELLING", repetition: 1 });
    expect((sqlite.prepare("SELECT planned_count FROM study_sessions WHERE id = ?").get(sessionId) as { planned_count: number }).planned_count).toBe(2);
    expect((sqlite.prepare(`SELECT question_type, task_type, status FROM study_session_items
      WHERE study_session_id = ? AND id != ?`).get(sessionId, itemId) as { question_type: string; task_type: string; status: string })).toEqual({
      question_type: "ZH_TO_EN_SPELLING",
      task_type: "WRONG",
      status: "PENDING",
    });
  });
});
