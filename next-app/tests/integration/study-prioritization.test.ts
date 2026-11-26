import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { updateSettings } from "@/modules/settings/service";
import { processReviewAnswer } from "@/modules/reviews/service";
import { continuousCandidates, dailyProgress, selectCandidates } from "@/modules/study/candidates";
import { skipStudyItem, startStudySession } from "@/modules/study/service";

async function insertReadyWord(term: string): Promise<number> {
  const now = Date.now();
  const result = await sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'READY', ?, ?)`).run(term, term, now, now);
  const wordId = Number(result.lastInsertRowid);
  await sqlite.prepare(`INSERT INTO word_contents
    (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
     synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
    VALUES (?, ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', ?)`).run(
    wordId,
    JSON.stringify([{ language: "zh-CN", partOfSpeech: null, text: `${term} 释义`, source: "test", isUserEdited: false }]),
    now,
  );
  return wordId;
}

async function insertDueCard(wordId: number, now: number): Promise<void> {
  await sqlite.prepare(`INSERT INTO review_cards
    (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses,
     fsrs_state, learning_steps, last_review_at, created_at, updated_at)
    VALUES (?, ?, 1, 5, 1, 1, 1, 0, 2, 0, ?, ?, ?)`).run(wordId, now - 86_400_000, now - 172_800_000, now, now);
}

function candidate(id: number, term: string) {
  return { id, term, normalized_term: term, source_language: "en", target_language: "zh-CN", content_type: "WORD" as const };
}

function seededRandom(seed: number) {
  let value = seed >>> 0;
  return () => {
    value = (value * 1_664_525 + 1_013_904_223) >>> 0;
    return value / 4_294_967_296;
  };
}

describe("study prioritization", () => {
  it("moves recently failed due words ahead of equally overdue words", async () => {
    const fragileId = await insertReadyWord("fragile");
    const steadyId = await insertReadyWord("steady");
    const now = Date.now();
    await insertDueCard(fragileId, now);
    await insertDueCard(steadyId, now);
    await sqlite.prepare(`INSERT INTO review_logs
      (client_answer_id, word_id, reviewed_at, rating, question_type, is_correct, created_at)
      VALUES (?, ?, ?, 'AGAIN', 'EN_TO_ZH_CHOICE', 0, ?)`).run(crypto.randomUUID(), fragileId, now - 3_600_000, now - 3_600_000);
    await sqlite.prepare(`INSERT INTO word_review_stats
      (word_id, total_reviews, correct_reviews, recent_again_30d, recent_again_14d,
       recent_wrong_14d, recent_hard_14d, total_duration_ms, duration_count,
       last_reviewed_at, updated_at)
      VALUES (?, 1, 0, 0, 0, 1, 0, 0, 0, ?, ?)`).run(fragileId, now - 3_600_000, now - 3_600_000);
    await updateSettings({ dailyNewWords: 0, dailyWrongWordLimit: 0, dailyDueReviewLimit: 1 });

    const session = await startStudySession("DAILY", false);

    expect(session.items[0]?.word.id).toBe(fragileId);
    expect(session.items[0]?.word.id).not.toBe(steadyId);
  });

  it("allows a small daily overflow after the configured target is reached", async () => {
    await insertReadyWord("first");
    await insertReadyWord("second");
    await updateSettings({ dailyNewWords: 1, dailyWrongWordLimit: 0, dailyDueReviewLimit: 1 });

    const first = await startStudySession("DAILY", false);
    expect(first.items).toHaveLength(1);
    await skipStudyItem(first.session.id, first.items[0]!.itemId, "LATER");

    const overflow = await startStudySession("DAILY", false);

    expect(overflow.items).toHaveLength(1);
    expect(overflow.items[0]?.word.id).not.toBe(first.items[0]?.word.id);
  });

  it("continues with unlearned words after the daily new-word limit is exhausted", async () => {
    const firstId = await insertReadyWord("first");
    const secondId = await insertReadyWord("second");
    await updateSettings({ dailyNewWords: 0, dailyWrongWordLimit: 0, dailyDueReviewLimit: 1 });

    const session = await startStudySession("DAILY", false, true);

    expect(new Set(session.items.map((item) => item.word.id))).toEqual(new Set([firstId, secondId]));
    expect(session.items.every((item) => item.taskType === "NEW")).toBe(true);
  });

  it("prioritizes due, wrong, and new words before cycling older reviews", async () => {
    const dueId = await insertReadyWord("due");
    const wrongId = await insertReadyWord("wrong");
    const newId = await insertReadyWord("new");
    const oldId = await insertReadyWord("old");
    const now = Date.now();
    await insertDueCard(dueId, now);
    await sqlite.prepare(`INSERT INTO wrong_word_states
      (word_id, active, wrong_count, hard_count, consecutive_correct, updated_at)
      VALUES (?, 1, 2, 1, 0, ?)`).run(wrongId, now);
    await sqlite.prepare(`INSERT INTO review_cards
      (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses,
       fsrs_state, learning_steps, last_review_at, created_at, updated_at)
      VALUES (?, ?, 10, 5, 1, 10, 2, 0, 2, 0, ?, ?, ?)`).run(oldId, now + 86_400_000, now - 30 * 86_400_000, now, now);

    const candidates = await continuousCandidates(4, now, "LEXICAL", () => 0);

    expect(candidates.map((item) => item.id)).toEqual([dueId, wrongId, newId, oldId]);
    expect(candidates.map((item) => item.continuousTaskType)).toEqual(["REVIEW", "WRONG", "NEW", "REVIEW"]);
  });

  it("mixes daily categories with weighted randomness without starving fresh words", () => {
    const pools = {
      due: Array.from({ length: 10 }, (_, index) => candidate(index + 1, `due-${index}`)),
      wrong: Array.from({ length: 5 }, (_, index) => candidate(index + 11, `wrong-${index}`)),
      fresh: Array.from({ length: 5 }, (_, index) => candidate(index + 16, `fresh-${index}`)),
      limits: { due: 10, wrong: 5, fresh: 5 },
    };
    const runs = Array.from({ length: 40 }, (_, index) => selectCandidates("DAILY", pools, { random: seededRandom(index + 1) }));
    const orders = new Set(runs.map((items) => items.map((item) => item.id).join(",")));
    const freshIds = new Set(pools.fresh.map((item) => item.id));
    const freshInFirstNine = runs.reduce((total, items) => total + items.slice(0, 9).filter((item) => freshIds.has(item.id)).length, 0);

    expect(orders.size).toBeGreaterThan(1);
    expect(freshInFirstNine).toBeGreaterThan(40);
    expect(runs.every((items) => items.length === 20)).toBe(true);
    expect(runs[0]).toHaveLength(20);
  });

  it("excludes words without a usable definition from study sessions", async () => {
    await insertReadyWord("with-meaning");
    const now = Date.now();
    const missing = await sqlite.prepare(`INSERT INTO words
      (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
      VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'READY', ?, ?)`).run("no-definition", "no-definition", now, now);
    const missingId = Number(missing.lastInsertRowid);
    await sqlite.prepare(`INSERT INTO word_contents (word_id, definitions_json, updated_at)
      VALUES (?, '[]', ?)`).run(missingId, now);
    const emptyText = await sqlite.prepare(`INSERT INTO words
      (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
      VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'READY', ?, ?)`).run("empty-text", "empty-text", now, now);
    const emptyTextId = Number(emptyText.lastInsertRowid);
    await sqlite.prepare(`INSERT INTO word_contents (word_id, definitions_json, updated_at)
      VALUES (?, ?, ?)`).run(emptyTextId, JSON.stringify([{ language: "zh-CN", text: "", source: "test" }]), now);
    await updateSettings({ dailyNewWords: 10, dailyWrongWordLimit: 0, dailyDueReviewLimit: 1 });

    const session = await startStudySession("NEW_WORDS", false);

    expect(session.items.map((item) => item.word.term)).toEqual(["with-meaning"]);
  });

  it("counts game tasks in the daily category quotas", async () => {
    const now = Date.now();
    const wordId = await insertReadyWord("game-review");
    const sessionId = Number((await sqlite.prepare(`INSERT INTO study_sessions
      (session_type, source_type, started_at, completed_at, planned_count, completed_count, created_at)
      VALUES ('DAILY', 'GAME_MEANING_BLITZ', ?, ?, 1, 1, ?)`).run(now, now, now)).lastInsertRowid);
    await sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, status, answered_at, created_at)
      VALUES (?, 0, ?, 'REVIEW', 'EN_TO_ZH_CHOICE', 'ANSWERED', ?, ?)`).run(sessionId, wordId, now, now);

    expect(await dailyProgress(now)).toMatchObject({ due: 1, wrong: 0, fresh: 0 });
  });

  it("cycles reviewed words in a later batch after all fresh words are processed", async () => {
    const wordId = await insertReadyWord("repeat");
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
