import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { evaluateReviewAnswer } from "@/modules/reviews/answer-evaluation";
import { extractPreferredDefinition } from "@/modules/practice/candidates";
import { getStudySession } from "@/modules/study/view";

describe("multi-meaning review content", () => {
  it("keeps all target-language meanings in practice content", () => {
    expect(extractPreferredDefinition(JSON.stringify([
      { language: "zh-CN", text: "运行" },
      { language: "zh-CN", text: "奔跑" },
      { language: "en", text: "move fast" },
    ]), "zh-CN")).toBe("运行；奔跑");
  });

  it("uses all meanings as the correct choice and review prompt", () => {
    const word = {
      id: 1,
      term: "run",
      normalized_term: "run",
      source_language: "en",
      target_language: "zh-CN",
      content_type: "WORD",
      initialization_status: "READY",
      is_suspended: 0,
      definitions_json: JSON.stringify([
        { language: "zh-CN", text: "运行" },
        { language: "zh-CN", text: "奔跑" },
      ]),
    };

    const result = evaluateReviewAnswer({
      clientAnswerId: "test-answer",
      wordId: 1,
      rating: "GOOD",
      questionType: "EN_TO_ZH_CHOICE",
      userAnswer: "运行；奔跑",
    }, word);

    expect(result.isCorrect).toBe(true);
    expect(result.expectedAnswer).toBe("运行；奔跑");
    expect(result.presentedPrompt).toBe("run");
  });

  it("scores a definition-to-word choice against the normalized term", () => {
    const word = {
      id: 1,
      term: "Run",
      normalized_term: "run",
      source_language: "en",
      target_language: "zh-CN",
      content_type: "WORD",
      initialization_status: "READY",
      is_suspended: 0,
      definitions_json: JSON.stringify([{ language: "zh-CN", text: "运行" }]),
    };

    expect(evaluateReviewAnswer({
      clientAnswerId: "reverse-choice-correct",
      wordId: 1,
      rating: "GOOD",
      questionType: "ZH_TO_EN_CHOICE",
      userAnswer: " run ",
    }, word)).toMatchObject({ isCorrect: true, expectedAnswer: "Run", presentedPrompt: "运行" });

    expect(evaluateReviewAnswer({
      clientAnswerId: "reverse-choice-wrong",
      wordId: 1,
      rating: "GOOD",
      questionType: "ZH_TO_EN_CHOICE",
      userAnswer: "walk",
    }, word)).toMatchObject({ isCorrect: false, effectiveRating: "AGAIN" });

    expect(evaluateReviewAnswer({
      clientAnswerId: "reverse-choice-fuzzy",
      wordId: 1,
      rating: "HARD",
      questionType: "ZH_TO_EN_CHOICE",
      userAnswer: "walk",
    }, word)).toMatchObject({ isCorrect: false, effectiveRating: "HARD" });

    expect(evaluateReviewAnswer({
      clientAnswerId: "reverse-choice-familiar",
      wordId: 1,
      rating: "EASY",
      questionType: "ZH_TO_EN_CHOICE",
      userAnswer: "walk",
    }, word)).toMatchObject({ isCorrect: false, effectiveRating: "EASY" });
  });

  it("puts all meanings into the generated meaning choice", () => {
    const now = Date.now();
    const wordId = Number(sqlite.prepare(`INSERT INTO words
      (term, normalized_term, source_language, target_language, entry_type, content_type,
       initialization_status, created_at, updated_at)
      VALUES ('run', 'run', 'en', 'zh-CN', 'WORD', 'WORD', 'READY', ?, ?)`)
      .run(now, now).lastInsertRowid);
    sqlite.prepare(`INSERT INTO word_contents (word_id, definitions_json, updated_at)
      VALUES (?, ?, ?)`)
      .run(wordId, JSON.stringify([
        { language: "zh-CN", text: "运行" },
        { language: "zh-CN", text: "奔跑" },
      ]), now);
    const sessionId = Number(sqlite.prepare(`INSERT INTO study_sessions
      (session_type, started_at, planned_count, created_at)
      VALUES ('DAILY', ?, 1, ?)`)
      .run(now, now).lastInsertRowid);
    sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, created_at)
      VALUES (?, 0, ?, 'NEW', 'EN_TO_ZH_CHOICE', ?)`)
      .run(sessionId, wordId, now);

    const session = getStudySession(sessionId);

    expect(session.items[0]?.choices).toContain("运行；奔跑");
  });

  it("returns word choices with definitions for reverse choice questions", () => {
    const now = Date.now();
    const insertWord = (term: string, definition: string) => {
      const wordId = Number(sqlite.prepare(`INSERT INTO words
        (term, normalized_term, source_language, target_language, entry_type, content_type,
         initialization_status, created_at, updated_at)
        VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'WORD', 'READY', ?, ?)`).run(term, term.toLowerCase(), now, now).lastInsertRowid);
      sqlite.prepare(`INSERT INTO word_contents (word_id, definitions_json, updated_at) VALUES (?, ?, ?)`).run(
        wordId,
        JSON.stringify([{ language: "zh-CN", text: definition }]),
        now,
      );
      return wordId;
    };
    const targetId = insertWord("run", "运行");
    insertWord("walk", "走路");
    insertWord("jump", "跳跃");
    const sessionId = Number(sqlite.prepare(`INSERT INTO study_sessions
      (session_type, started_at, planned_count, created_at) VALUES ('DAILY', ?, 1, ?)`).run(now, now).lastInsertRowid);
    sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, created_at)
      VALUES (?, 0, ?, 'REVIEW', 'ZH_TO_EN_CHOICE', ?)`).run(sessionId, targetId, now);

    const item = getStudySession(sessionId).items[0];

    expect(item?.choices).toEqual(expect.arrayContaining(["run", "walk", "jump"]));
    expect(item?.choiceDefinitions).toMatchObject({ run: "运行", walk: "走路", jump: "跳跃" });
  });
});
