import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { updateSettings } from "@/modules/settings/service";
import { processReviewAnswer } from "@/modules/reviews/service";
import { continuousCandidates } from "@/modules/study/candidates";
import { skipStudyItem, startStudySession } from "@/modules/study/service";

function insertReadyWord(term: string): number {
  const now = Date.now();
  const result = sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'READY', ?, ?)`).run(term, term, now, now);
  const wordId = Number(result.lastInsertRowid);
  sqlite.prepare(`INSERT INTO word_contents
    (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
     synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
    VALUES (?, ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', ?)`).run(
    wordId,
    JSON.stringify([{ language: "zh-CN", partOfSpeech: null, text: `${term} 释义`, source: "test", isUserEdited: false }]),
    now,
  );
  return wordId;
}

function insertDueCard(wordId: number, now: number): void {
  sqlite.prepare(`INSERT INTO review_cards
    (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses,
     fsrs_state, learning_steps, last_review_at, created_at, updated_at)
    VALUES (?, ?, 1, 5, 1, 1, 1, 0, 2, 0, ?, ?, ?)`).run(wordId, now - 86_400_000, now - 172_800_000, now, now);
}

describe("study prioritization", () => {
  it("moves recently failed due words ahead of equally overdue words", async () => {
    const fragileId = insertReadyWord("fragile");
    const steadyId = insertReadyWord("steady");
    const now = Date.now();
    insertDueCard(fragileId, now);
    insertDueCard(steadyId, now);
    sqlite.prepare(`INSERT INTO review_logs
      (client_answer_id, word_id, reviewed_at, rating, question_type, is_correct, created_at)
      VALUES (?, ?, ?, 'AGAIN', 'EN_TO_ZH_CHOICE', 0, ?)`).run(crypto.randomUUID(), fragileId, now - 3_600_000, now - 3_600_000);
    await updateSettings({ dailyNewWords: 0, dailyWrongWordLimit: 0, dailyDueReviewLimit: 1 });

    const session = await startStudySession("DAILY", false);

    expect(session.items[0]?.word.id).toBe(fragileId);
    expect(session.items[0]?.word.id).not.toBe(steadyId);
  });

  it("allows a small daily overflow after the configured target is reached", async () => {
    insertReadyWord("first");
    insertReadyWord("second");
    await updateSettings({ dailyNewWords: 1, dailyWrongWordLimit: 0, dailyDueReviewLimit: 1 });

    const first = await startStudySession("DAILY", false);
    expect(first.items).toHaveLength(1);
    skipStudyItem(first.session.id, first.items[0]!.itemId, "LATER");

    const overflow = await startStudySession("DAILY", false);

    expect(overflow.items).toHaveLength(1);
    expect(overflow.items[0]?.word.id).not.toBe(first.items[0]?.word.id);
  });

  it("continues with unlearned words after the daily new-word limit is exhausted", async () => {
    const firstId = insertReadyWord("first");
    const secondId = insertReadyWord("second");
    await updateSettings({ dailyNewWords: 0, dailyWrongWordLimit: 0, dailyDueReviewLimit: 1 });

    const session = await startStudySession("DAILY", false, true);

    expect(session.items.map((item) => item.word.id)).toEqual([firstId, secondId]);
    expect(session.items.every((item) => item.taskType === "NEW")).toBe(true);
  });

  it("prioritizes due, wrong, and new words before cycling older reviews", async () => {
    const dueId = insertReadyWord("due");
    const wrongId = insertReadyWord("wrong");
    const newId = insertReadyWord("new");
    const oldId = insertReadyWord("old");
    const now = Date.now();
    insertDueCard(dueId, now);
    sqlite.prepare(`INSERT INTO wrong_word_states
      (word_id, active, wrong_count, hard_count, consecutive_correct, updated_at)
      VALUES (?, 1, 2, 1, 0, ?)`).run(wrongId, now);
    sqlite.prepare(`INSERT INTO review_cards
      (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses,
       fsrs_state, learning_steps, last_review_at, created_at, updated_at)
      VALUES (?, ?, 10, 5, 1, 10, 2, 0, 2, 0, ?, ?, ?)`).run(oldId, now + 86_400_000, now - 30 * 86_400_000, now, now);

    const candidates = continuousCandidates(4, now);

    expect(candidates.map((item) => item.id)).toEqual([dueId, wrongId, newId, oldId]);
    expect(candidates.map((item) => item.continuousTaskType)).toEqual(["REVIEW", "WRONG", "NEW", "REVIEW"]);
  });

  it("cycles reviewed words in a later batch after all fresh words are processed", async () => {
    const wordId = insertReadyWord("repeat");
    await updateSettings({ dailyNewWords: 0, dailyWrongWordLimit: 0, dailyDueReviewLimit: 1 });

    const first = await startStudySession("DAILY", false, true);
    expect(first.items[0]?.word.id).toBe(wordId);
    await processReviewAnswer({
      clientAnswerId: crypto.randomUUID(),
      wordId,
      studySessionId: first.session.id,
      studySessionItemId: first.items[0]!.itemId,
      rating: "GOOD",
      questionType: first.items[0]!.questionType,
      userAnswer: "repeat 释义",
    });

    const next = await startStudySession("DAILY", false, true);

    expect(next.items).toHaveLength(1);
    expect(next.items[0]?.word.id).toBe(wordId);
    expect(next.items[0]?.taskType).toBe("REVIEW");
  });
});
