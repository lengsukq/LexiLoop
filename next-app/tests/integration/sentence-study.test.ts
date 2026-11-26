import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { getDailyStudyPlan, startStudySession } from "@/modules/study/service";

async function insertReadyEntry(options: {
  term: string;
  normalized: string;
  contentType: "WORD" | "SENTENCE";
  translation: string;
}): Promise<number> {
  const now = Date.now();
  const legacyType = options.contentType === "SENTENCE" ? "PHRASE" : options.contentType;
  const result = await sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, content_type,
     initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', ?, ?, 'READY', ?, ?)`)
    .run(options.term, options.normalized, legacyType, options.contentType, now, now);
  const wordId = Number(result.lastInsertRowid);
  const analysis = options.contentType === "SENTENCE"
    ? {
        grammarNotes: ["测试语法说明"],
        keyExpressions: [{ expression: "have finished", meaning: "已经完成", note: null }],
        variations: [{ sentence: "I have completed the work.", translation: "我已经完成工作了。" }],
      }
    : { grammarNotes: [], keyExpressions: [], variations: [] };
  await sqlite.prepare(`INSERT INTO word_contents
    (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
     synonyms_json, antonyms_json, word_family_json, confused_words_json, roots_json, affixes_json,
     summary_json, learning_json, sentence_analysis_json, tags_json, provider_metadata_json, updated_at)
    VALUES (?, ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]',
      ?, ?, ?, '[]', '[]', ?)`)
    .run(
      wordId,
      JSON.stringify([{ language: "zh-CN", partOfSpeech: null, text: options.translation, source: "test", isUserEdited: false }]),
      JSON.stringify({ shortDefinition: options.term, translation: options.translation, cefrLevel: null, frequency: null }),
      JSON.stringify({ pronunciationTip: null, mnemonic: null, commonMistakes: [] }),
      JSON.stringify(analysis),
      now,
    );
  return wordId;
}

async function makeDue(wordId: number): Promise<void> {
  const now = Date.now();
  await sqlite.prepare(`INSERT INTO review_cards
    (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses,
     fsrs_state, learning_steps, last_review_at, created_at, updated_at)
    VALUES (?, ?, 1, 5, 1, 1, 1, 0, 2, 0, ?, ?, ?)`)
    .run(wordId, now - 1_000, now - 86_400_000, now, now);
}

describe("sentence study mode", () => {
  it("creates a sentence-only fresh session with sentence analysis in the payload", async () => {
    await insertReadyEntry({
      term: "I have finished the work.",
      normalized: "i have finished the work.",
      contentType: "SENTENCE",
      translation: "我已经完成工作了。",
    });

    const session = await startStudySession("SENTENCE_REVIEW", false);

    expect(session.session.sessionType).toBe("SENTENCE_REVIEW");
    expect(session.items).toHaveLength(1);
    expect(session.items[0]?.word.entryType).toBe("SENTENCE");
    expect(session.items[0]?.questionType).toBe("EN_TO_ZH");
    expect(session.items[0]?.word.content.sentenceAnalysis.grammarNotes).toEqual(["测试语法说明"]);
  });

  it("uses reverse sentence reconstruction for due sentences", async () => {
    const wordId = await insertReadyEntry({
      term: "I have finished the work.",
      normalized: "i have finished the work.",
      contentType: "SENTENCE",
      translation: "我已经完成工作了。",
    });
    await makeDue(wordId);

    const session = await startStudySession("SENTENCE_REVIEW", false);

    expect(session.items[0]?.taskType).toBe("REVIEW");
    expect(session.items[0]?.questionType).toBe("ZH_TO_EN_SPELLING");
  });

  it("keeps ordinary new-word sessions free of sentence entries", async () => {
    await insertReadyEntry({ term: "hello", normalized: "hello", contentType: "WORD", translation: "你好" });
    await insertReadyEntry({
      term: "How are you?",
      normalized: "how are you?",
      contentType: "SENTENCE",
      translation: "你好吗？",
    });

    const session = await startStudySession("NEW_WORDS", false);

    expect(session.items).toHaveLength(1);
    expect(session.items[0]?.word.term).toBe("hello");
    expect(session.items[0]?.word.entryType).toBe("WORD");
  });

  it("reports sentence work separately from the ordinary daily queue", async () => {
    await insertReadyEntry({
      term: "How are you?",
      normalized: "how are you?",
      contentType: "SENTENCE",
      translation: "你好吗？",
    });

    const plan = await getDailyStudyPlan();

    expect(plan.newWordCount).toBe(0);
    expect(plan.sentenceReviewCount).toBe(1);
    expect(plan.plannedSentenceReviewCount).toBe(1);
    expect(plan.plannedTotal).toBe(0);
  });
});
