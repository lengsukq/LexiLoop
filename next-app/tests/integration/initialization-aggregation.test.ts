import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { listInitializationJobs } from "@/modules/initialization/queries";
import { retryFailedJobsForWords } from "@/modules/initialization/bulk";

async function insertWord(term: string): Promise<number> {
  const now = Date.now();
  const result = await sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'PENDING', ?, ?)`).run(term, term.toLowerCase(), now, now);
  return Number(result.lastInsertRowid);
}

async function insertJob(wordId: number, status: string, taskType = "INITIALIZE", error?: string): Promise<number> {
  const now = Date.now();
  const result = await sqlite.prepare(`INSERT INTO initialization_jobs
    (word_id, task_type, mode, status, priority, attempt_count, max_attempts, available_at, last_error, created_at, updated_at)
    VALUES (?, ?, 'FILL_MISSING_FIELDS', ?, 0, 2, 5, ?, ?, ?, ?)`).run(wordId, taskType, status, now, error ?? null, now, now);
  return Number(result.lastInsertRowid);
}

describe("initialization word aggregation", () => {
  it("returns one row per word and applies aggregate status precedence", async () => {
    const runningWord = await insertWord("word-running");
    await insertJob(runningWord, "RUNNING", "INITIALIZE");
    await insertJob(runningWord, "FAILED", "MNEMONIC", "助记失败");
    await insertJob(runningWord, "PARTIAL", "EXAMPLE_TRANSLATIONS");

    const queuedWord = await insertWord("word-queued");
    await insertJob(queuedWord, "QUEUED", "INITIALIZE");
    await insertJob(queuedWord, "FAILED", "MNEMONIC");

    const failedWord = await insertWord("word-failed");
    await insertJob(failedWord, "FAILED", "INITIALIZE", "网络错误");
    await insertJob(failedWord, "PARTIAL", "MNEMONIC");

    const partialWord = await insertWord("word-partial");
    await insertJob(partialWord, "PARTIAL", "INITIALIZE");
    await insertJob(partialWord, "READY", "MNEMONIC");

    const readyWord = await insertWord("word-ready");
    await insertJob(readyWord, "READY");

    const result = await listInitializationJobs({ page: 1, pageSize: 10 });
    expect(result.total).toBe(5);
    expect(result.items).toHaveLength(5);
    expect(result.items.find((item) => item.wordId === runningWord)).toMatchObject({
      status: "RUNNING",
      taskCount: 3,
      failedTaskCount: 1,
      activeTaskCount: 1,
      errorSummary: "助记失败",
    });
    expect(result.items.find((item) => item.wordId === queuedWord)?.status).toBe("QUEUED");
    expect(result.items.find((item) => item.wordId === failedWord)?.status).toBe("FAILED");
    expect(result.items.find((item) => item.wordId === partialWord)?.status).toBe("PARTIAL");
    expect(result.items.find((item) => item.wordId === readyWord)?.status).toBe("READY");
  });

  it("filters, searches and paginates by word rather than by task", async () => {
    for (let index = 1; index <= 5; index += 1) {
      const wordId = await insertWord(`filter-word-${index}`);
      await insertJob(wordId, index === 3 ? "FAILED" : "READY", "INITIALIZE", index === 3 ? "failed" : undefined);
      if (index === 1) await insertJob(wordId, "PARTIAL", "MNEMONIC");
    }

    const page = await listInitializationJobs({ page: 1, pageSize: 2 });
    expect(page.total).toBe(5);
    expect(page.items).toHaveLength(2);

    const filtered = await listInitializationJobs({ status: "FAILED" });
    expect(filtered.total).toBe(1);
    expect(filtered.items[0]?.term).toBe("filter-word-3");

    const searched = await listInitializationJobs({ search: "WORD-4" });
    expect(searched.total).toBe(1);
    expect(searched.items[0]?.term).toBe("filter-word-4");
  });
});

describe("retry initialization by word", () => {
  it("requeues only failed tasks for the requested words", async () => {
    const wordId = await insertWord("retry-word");
    const failedJobId = await insertJob(wordId, "FAILED", "INITIALIZE", "provider failed");
    const readyJobId = await insertJob(wordId, "READY", "MNEMONIC");

    expect(await retryFailedJobsForWords([wordId])).toBe(1);
    expect((await sqlite.prepare("SELECT status, attempt_count, last_error FROM initialization_jobs WHERE id = ?").get(failedJobId) as { status: string; attempt_count: number; last_error: string | null })).toEqual({
      status: "QUEUED",
      attempt_count: 0,
      last_error: null,
    });
    expect((await sqlite.prepare("SELECT status FROM initialization_jobs WHERE id = ?").get(readyJobId) as { status: string }).status).toBe("READY");
  });
});
