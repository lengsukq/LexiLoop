import fs from "node:fs";
import path from "node:path";
import { describe, expect, it, vi } from "vitest";
import { sqlite } from "@/db/client";
import { createImportPreview, commitImport, ImportRollbackError, rollbackImportBatch } from "@/modules/imports/service";
import { processJob, queueAiTask, queueBulkInitialization, queueSelectedInitialization, queueWordInitialization } from "@/modules/initialization/service";
import { processReviewAnswer } from "@/modules/reviews/service";
import { getDailyStudyPlan, skipStudyItem, startStudySession } from "@/modules/study/service";
import { updateSettings } from "@/modules/settings/service";
import { DEFAULT_SETTINGS } from "@/lib/config";

async function insertReadyWord(term: string, definition = "测试释义"): Promise<number> {
  const now = Date.now();
  const normalized = term.toLocaleLowerCase();
  const result = await sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'READY', ?, ?)`).run(term, normalized, now, now);
  const wordId = Number(result.lastInsertRowid);
  await sqlite.prepare(`INSERT INTO word_contents
    (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
     synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
    VALUES (?, ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', ?)`)
    .run(wordId, JSON.stringify([{ language: "zh-CN", partOfSpeech: null, text: definition, source: "test", isUserEdited: false }]), now);
  return wordId;
}

describe("import rollback business rules", () => {
  it("rolls back an untouched import batch", async () => {
    const content = fs.readFileSync(path.join(process.cwd(), "tests/fixtures/easydict-sample.csv"), "utf8");
    const preview = await createImportPreview(content, "rollback.csv");
    const committed = await commitImport(preview.previewToken, "FILL_MISSING", false);
    const result = await rollbackImportBatch(committed.batchId);
    expect(result.deletedWords).toBe(3);
    expect((await sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count: number }).count).toBe(0);
    expect((await sqlite.prepare("SELECT status FROM import_batches WHERE id = ?").get(committed.batchId) as { status: string }).status).toBe("ROLLED_BACK");
  });

  it("blocks rollback after a created word enters a study session", async () => {
    const content = fs.readFileSync(path.join(process.cwd(), "tests/fixtures/easydict-sample.csv"), "utf8");
    const preview = await createImportPreview(content, "used.csv");
    const committed = await commitImport(preview.previewToken, "FILL_MISSING", false);
    const wordId = (await sqlite.prepare("SELECT word_id FROM import_rows WHERE import_batch_id = ? AND status = 'IMPORTED' LIMIT 1").get(committed.batchId) as { word_id: number }).word_id;
    const now = Date.now();
    const sessionId = Number((await sqlite.prepare(`INSERT INTO study_sessions
      (session_type, started_at, planned_count, created_at) VALUES ('NEW_WORDS', ?, 1, ?)`).run(now, now)).lastInsertRowid);
    await sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, status, created_at)
      VALUES (?, 0, ?, 'NEW', 'EN_TO_ZH', 'PENDING', ?)`).run(sessionId, wordId, now);
    await expect(rollbackImportBatch(committed.batchId)).rejects.toThrowError(ImportRollbackError);
  });
});

describe("study session closure", () => {
  it("prevents the same session item from being reviewed twice with different UUIDs", async () => {
    await insertReadyWord("alpha");
    const session = await startStudySession("NEW_WORDS", false);
    const item = session.items[0]!;
    await processReviewAnswer({
      clientAnswerId: crypto.randomUUID(),
      wordId: item.word.id,
      studySessionId: session.session.id,
      studySessionItemId: item.itemId,
      rating: "GOOD",
      questionType: item.questionType,
    });
    await expect(processReviewAnswer({
      clientAnswerId: crypto.randomUUID(),
      wordId: item.word.id,
      studySessionId: session.session.id,
      studySessionItemId: item.itemId,
      rating: "GOOD",
      questionType: item.questionType,
    })).rejects.toThrow("STUDY_ITEM_ALREADY_PROCESSED");
    expect((await sqlite.prepare("SELECT count(*) AS count FROM review_logs").get() as { count: number }).count).toBe(1);
  });

  it("skips without changing FSRS and resumes the remaining item", async () => {
    await insertReadyWord("alpha");
    await insertReadyWord("beta");
    const session = await startStudySession("NEW_WORDS", false);
    expect(session.items.length).toBe(2);
    const skipped = await skipStudyItem(session.session.id, session.items[0]!.itemId, "LATER");
    expect(skipped.session.skippedCount).toBe(1);
    expect((await sqlite.prepare("SELECT count(*) AS count FROM review_cards").get() as { count: number }).count).toBe(0);
    const resumed = await startStudySession("NEW_WORDS", true);
    expect(resumed.resumed).toBe(true);
    expect(resumed.session.id).toBe(session.session.id);
    expect(resumed.resumeIndex).toBe(1);
  });

  it("deduplicates a word that is both due and active in the wrong-word queue", async () => {
    const wordId = await insertReadyWord("alpha");
    const now = Date.now();
    await sqlite.prepare(`INSERT INTO review_cards
      (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses, fsrs_state, learning_steps, created_at, updated_at)
      VALUES (?, ?, 1, 5, 1, 1, 1, 1, 2, 0, ?, ?)`).run(wordId, now - 1000, now, now);
    await sqlite.prepare(`INSERT INTO wrong_word_states
      (word_id, active, wrong_count, hard_count, consecutive_correct, updated_at)
      VALUES (?, 1, 1, 0, 0, ?)`).run(wordId, now);
    const plan = await getDailyStudyPlan();
    expect(plan.plannedTotal).toBe(1);
    expect(plan.plannedDueReviewCount).toBe(1);
    expect(plan.plannedWrongWordCount).toBe(0);
  });
});

describe("initialization continuity", () => {
  it("keeps an existing usable word learnable when a forced refresh fails", async () => {
    // 禁用有道以避免测试依赖外部网络：强制刷新失败需所有 provider 均不可用。
    const now0 = Date.now();
    await sqlite.prepare("INSERT INTO settings(key, value_json, updated_at) VALUES (?, ?, ?)")
      .run("youdaoEnabled", JSON.stringify(false), now0);
    const { invalidateSettingsCache } = await import("@/modules/settings/service");
    invalidateSettingsCache();

    const wordId = await insertReadyWord("alpha");
    const now = Date.now();
    const jobId = Number((await sqlite.prepare(`INSERT INTO initialization_jobs
      (word_id, mode, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
      VALUES (?, 'FORCE_OVERWRITE', 'RUNNING', 100, 5, 5, ?, ?, ?)`).run(wordId, now, now, now)).lastInsertRowid);
    await processJob({ id: jobId, wordId, taskType: "INITIALIZE", mode: "FORCE_OVERWRITE", attemptCount: 5, maxAttempts: 5 });
    expect((await sqlite.prepare("SELECT status FROM initialization_jobs WHERE id = ?").get(jobId) as { status: string }).status).toBe("FAILED");
    expect((await sqlite.prepare("SELECT initialization_status FROM words WHERE id = ?").get(wordId) as { initialization_status: string }).initialization_status).toBe("PARTIAL");
  });
});

describe("related word initialization", () => {
  it("previews a generated synonym and adds it to the same language direction", async () => {
    const parentId = await insertReadyWord("happy", "快乐的");
    const row = await sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(parentId) as Record<string, unknown>;
    await sqlite.prepare("UPDATE word_contents SET synonyms_json = ? WHERE word_id = ?").run(JSON.stringify([
      {
        word: "joyful",
        translation: "喜悦的",
        partOfSpeech: "adj.",
        relation: "SYNONYM",
        source: "ai:test",
        difference: "joyful 更强调明显表达出来的喜悦。",
      },
    ]), parentId);
    expect(row).toBeTruthy();

    const { previewRelatedWord, addRelatedWord } = await import("@/modules/words/service");
    const preview = await previewRelatedWord(parentId, "joyful");
    expect(preview.existing).toBeNull();
    expect(preview.translation).toBe("喜悦的");
    expect(preview.difference).toContain("喜悦");

    const added = await addRelatedWord(parentId, { term: "joyful", relation: "SYNONYM" });
    expect(added.created).toBe(true);
    expect(added.queued).toBe(true);
    const created = await sqlite.prepare("SELECT source_language, target_language, initialization_status FROM words WHERE id = ?").get(added.wordId) as {
      source_language: string; target_language: string; initialization_status: string;
    };
    expect(created).toEqual({ source_language: "en", target_language: "zh-CN", initialization_status: "QUEUED" });
    expect((await sqlite.prepare("SELECT count(*) AS count FROM initialization_jobs WHERE word_id = ?").get(added.wordId) as { count: number }).count).toBe(1);

    const repeated = await addRelatedWord(parentId, { term: "JOYFUL", relation: "SYNONYM" });
    expect(repeated.wordId).toBe(added.wordId);
    expect(repeated.created).toBe(false);
    expect((await sqlite.prepare("SELECT count(*) AS count FROM initialization_jobs WHERE word_id = ?").get(added.wordId) as { count: number }).count).toBe(1);
  });
});


describe("bulk AI initialization", () => {
  it("skips words already initialized by AI and upgrades active jobs in force mode", async () => {
    const aiDoneId = await insertReadyWord("alpha");
    const pendingId = await insertReadyWord("beta");
    const now = Date.now();
    await sqlite.prepare(`INSERT INTO provider_attempts
      (word_id, provider_id, status, duration_ms, fields_returned_json, metadata_json, created_at)
      VALUES (?, 'ai:openai:test-model', 'SUCCESS', 100, '["definitions"]', '{"qualityScore":90}', ?)`)
      .run(aiDoneId, now);

    const fill = await queueBulkInitialization("FILL_MISSING_FIELDS", true);
    expect(fill.totalWords).toBe(2);
    expect(fill.selectedWords).toBe(1);
    expect(fill.skippedAiInitialized).toBe(1);
    expect((await sqlite.prepare("SELECT count(*) AS count FROM initialization_jobs WHERE word_id = ?").get(pendingId) as { count: number }).count).toBe(1);
    expect((await sqlite.prepare("SELECT count(*) AS count FROM initialization_jobs WHERE word_id = ?").get(aiDoneId) as { count: number }).count).toBe(0);

    const forced = await queueBulkInitialization("FORCE_OVERWRITE", false);
    expect(forced.selectedWords).toBe(2);
    expect(forced.createdJobs).toBe(1);
    expect(forced.updatedJobs).toBe(1);
    const active = await sqlite.prepare(`SELECT word_id, mode FROM initialization_jobs
      WHERE status IN ('QUEUED','RUNNING') ORDER BY word_id`).all() as Array<{ word_id: number; mode: string }>;
    expect(active).toEqual([
      { word_id: aiDoneId, mode: "FORCE_OVERWRITE" },
      { word_id: pendingId, mode: "FORCE_OVERWRITE" },
    ]);
  });

  it("queues selected words for missing-field completion even after an earlier AI success", async () => {
    const aiDoneId = await insertReadyWord("alpha");
    const otherId = await insertReadyWord("beta");
    const now = Date.now();
    await sqlite.prepare(`INSERT INTO provider_attempts
      (word_id, provider_id, status, duration_ms, fields_returned_json, metadata_json, created_at)
      VALUES (?, 'ai:openai:test-model', 'SUCCESS', 100, '["definitions"]', '{}', ?)`)
      .run(aiDoneId, now);

    const selected = await queueSelectedInitialization([aiDoneId, otherId, otherId, 999999]);
    expect(selected).toMatchObject({ requestedWords: 3, selectedWords: 2, skippedWords: 1, createdJobs: 2, updatedJobs: 0, mode: "FILL_MISSING_FIELDS" });
    expect((await sqlite.prepare("SELECT mode FROM initialization_jobs WHERE word_id = ?").get(aiDoneId) as { mode: string }).mode).toBe("FILL_MISSING_FIELDS");

    const singleJobId = await queueWordInitialization(aiDoneId);
    expect((await sqlite.prepare("SELECT mode FROM initialization_jobs WHERE id = ?").get(singleJobId) as { mode: string }).mode).toBe("FILL_MISSING_FIELDS");
  });
});

describe("example translation completion", () => {
  it("fills only missing example translations and preserves existing text", async () => {
    const wordId = await insertReadyWord("dry", "干燥的");
    await sqlite.prepare("UPDATE word_contents SET examples_json = ? WHERE word_id = ?").run(JSON.stringify([
      { sentence: "This well is as dry as that cow.", translation: null, source: "dictionaryapi.dev", isUserAdded: false },
      { sentence: "Dry alcohol is 200 proof.", translation: "无水酒精的浓度为 200 proof。", source: "dictionaryapi.dev", isUserAdded: false },
    ]), wordId);
    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      choices: [{ message: { content: JSON.stringify({ translations: [{ index: 0, translation: "这口井和那头牛一样干。" }] }) } }],
    }), { status: 200, headers: { "content-type": "application/json" } })) as typeof fetch;
    try {
      await updateSettings({
        llmConfig: {
          ...DEFAULT_SETTINGS.llmConfig,
          providers: [{ id: "test", name: "Test", apiType: "openai", baseUrl: "https://example.test/v1", apiKey: "test", models: ["test-model"], defaultModel: "test-model" }],
          purposes: { ...DEFAULT_SETTINGS.llmConfig.purposes, IMPORT_ENRICHMENT: { enabled: true, providerId: "test", model: "test-model" } },
        },
      });
      const { translateMissingExamples } = await import("@/modules/translations/service");
      await expect(translateMissingExamples(wordId)).resolves.toEqual({ translated: 1, remaining: 0 });
      const examples = JSON.parse((await sqlite.prepare("SELECT examples_json FROM word_contents WHERE word_id = ?").get(wordId) as { examples_json: string }).examples_json) as Array<{ translation: string }>;
      expect(examples.map((example) => example.translation)).toEqual(["这口井和那头牛一样干。", "无水酒精的浓度为 200 proof。"]);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});

describe("unified AI task queue", () => {
  it("keeps independent AI operations for one word in the same retryable task table", async () => {
    const wordId = await insertReadyWord("stunning", "惊艳的");
    const initializeId = await queueAiTask(wordId, "INITIALIZE");
    const mnemonicId = await queueAiTask(wordId, "MNEMONIC");
    const translationId = await queueAiTask(wordId, "EXAMPLE_TRANSLATIONS");
    expect(new Set([initializeId, mnemonicId, translationId]).size).toBe(3);
    const tasks = await sqlite.prepare("SELECT task_type, max_attempts FROM initialization_jobs WHERE word_id = ? ORDER BY task_type").all(wordId) as Array<{ task_type: string; max_attempts: number }>;
    expect(tasks).toEqual([
      { task_type: "EXAMPLE_TRANSLATIONS", max_attempts: 2 },
      { task_type: "INITIALIZE", max_attempts: 2 },
      { task_type: "MNEMONIC", max_attempts: 2 },
    ]);
  });
});
