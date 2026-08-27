import { afterEach, describe, expect, it, vi } from "vitest";
import { DEFAULT_SETTINGS } from "@/lib/config";
import { sqlite } from "@/db/client";
import { getTodaySuggestion, suggestionDateKey } from "@/modules/suggestions/service";
import { updateSettings } from "@/modules/settings/service";
import { startStudySession } from "@/modules/study/service";

afterEach(() => {
  vi.unstubAllGlobals();
});

async function insertReadyWord(term: string, definition: string): Promise<number> {
  const now = Date.now();
  const result = await sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, initialization_status, mastery_score, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'READY', 10, ?, ?)`).run(term, term.toLowerCase(), now, now);
  const wordId = Number(result.lastInsertRowid);
  await sqlite.prepare(`INSERT INTO word_contents
    (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
     synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
    VALUES (?, ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', ?)`)
    .run(wordId, JSON.stringify([{ language: "zh-CN", partOfSpeech: null, text: definition, source: "test", isUserEdited: false }]), now);
  return wordId;
}

async function insertYesterdayReview(wordId: number, options: { correct: boolean; rating: "AGAIN" | "HARD" | "GOOD" | "EASY"; questionType: string; offsetMs?: number }) {
  const reviewedAt = Date.now() - 24 * 60 * 60 * 1000 + (options.offsetMs ?? 0);
  await sqlite.prepare(`INSERT INTO review_logs
    (client_answer_id, word_id, reviewed_at, rating, question_type, is_correct, duration_ms, created_at)
    VALUES (?, ?, ?, ?, ?, ?, 12000, ?)`)
    .run(crypto.randomUUID(), wordId, reviewedAt, options.rating, options.questionType, options.correct ? 1 : 0, reviewedAt);
}

describe("daily AI suggestion", () => {
  it("retries with the configured fallback model after an invalid AI response", async () => {
    await updateSettings({
      llmConfig: {
        providers: [
          { id: "primary", name: "Primary", apiType: "openai", apiKey: "test-key", baseUrl: "https://primary.test/v1" },
          { id: "fallback", name: "Fallback", apiType: "openai", apiKey: "test-key", baseUrl: "https://fallback.test/v1" },
        ],
        ai: {
          ...DEFAULT_SETTINGS.llmConfig.ai,
          enabled: true,
          providerId: "primary",
          model: "primary-model",
          retryProviderId: "fallback",
          retryModel: "fallback-model",
        },
      },
    });
    const invalidPayload = JSON.stringify({ choices: [{ message: { content: '{"headline":"不完整' } }] });
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(invalidPayload, { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ choices: [{ message: { content: JSON.stringify({
        headline: "备用建议",
        summary: "先复习高风险词。",
        strengths: [],
        risks: [],
        actions: ["先完成重点复习"],
        recommended: [],
      }) } }] }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await getTodaySuggestion({ force: true });
    const calls = fetchMock.mock.calls as Array<[string, RequestInit]>;
    const firstBody = JSON.parse(String(calls[0]?.[1]?.body));
    const retryBody = JSON.parse(String(calls[1]?.[1]?.body));

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(firstBody.model).toBe("primary-model");
    expect(retryBody.model).toBe("fallback-model");
    expect(result.generator).toBe("AI");
    expect(result.headline).toBe("备用建议");
    expect(result.generationWarning).toBeNull();
  });

  it("reviews yesterday and prioritizes the weakest word without requiring AI configuration", async () => {
    const weakId = await insertReadyWord("fragile", "脆弱的");
    const strongId = await insertReadyWord("stable", "稳定的");
    await insertYesterdayReview(weakId, { correct: false, rating: "AGAIN", questionType: "ZH_TO_EN_SPELLING" });
    await insertYesterdayReview(strongId, { correct: true, rating: "GOOD", questionType: "EN_TO_ZH" });
    const now = Date.now();
    await sqlite.prepare(`INSERT INTO wrong_word_states
      (word_id, active, wrong_count, hard_count, consecutive_correct, last_wrong_at, updated_at)
      VALUES (?, 1, 2, 0, 0, ?, ?)`).run(weakId, now - 24 * 60 * 60 * 1000, now);

    const result = await getTodaySuggestion({ force: true });
    expect(result.sourceDateKey).toBe(suggestionDateKey(Date.now() - 24 * 60 * 60 * 1000));
    expect(result.metrics.reviewCount).toBe(2);
    expect(result.metrics.accuracy).toBe(50);
    expect(result.generator).toBe("RULE_BASED");
    expect(result.recommendedItems[0]).toMatchObject({
      wordId: weakId,
      term: "fragile",
      questionType: "ZH_TO_EN_SPELLING",
    });
    expect((await sqlite.prepare("SELECT count(*) AS count FROM daily_ai_suggestions").get() as { count: number }).count).toBe(1);
  });

  it("creates a resumable AI recommended study session from the cached must-do list", async () => {
    const weakId = await insertReadyWord("hesitate", "犹豫");
    await insertYesterdayReview(weakId, { correct: false, rating: "HARD", questionType: "ZH_TO_EN_SPELLING" });
    const now = Date.now();
    await sqlite.prepare(`INSERT INTO wrong_word_states
      (word_id, active, wrong_count, hard_count, consecutive_correct, last_wrong_at, updated_at)
      VALUES (?, 1, 1, 1, 0, ?, ?)`).run(weakId, now - 24 * 60 * 60 * 1000, now);
    await getTodaySuggestion({ force: true });

    const session = await startStudySession("AI_RECOMMENDED", false);
    expect(session.session.sessionType).toBe("AI_RECOMMENDED");
    expect(session.items.map((item) => item.word.id)).toContain(weakId);
    expect(session.items[0]?.questionType).toBe("ZH_TO_EN_SPELLING");
    const stored = await sqlite.prepare("SELECT session_type, source_type FROM study_sessions WHERE id = ?").get(session.session.id) as {
      session_type: string; source_type: string | null;
    };
    expect(stored).toEqual({ session_type: "WRONG_WORDS", source_type: "AI_RECOMMENDED" });
  });
});
