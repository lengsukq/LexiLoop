import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { updateSettings } from "@/modules/settings/service";
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
});
