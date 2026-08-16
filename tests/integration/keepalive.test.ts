import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { GET } from "@/app/api/background/keepalive/route";

interface KeepalivePayload {
  success: boolean;
  data?: { running: boolean; queued: number; claimed: number; elapsedMs: number };
}

async function callKeepalive(): Promise<{ status: number; payload: KeepalivePayload }> {
  const response = await GET();
  return { status: response.status, payload: await response.json() as KeepalivePayload };
}

/** 插入带 READY 词条的待初始化单词，使 SKIP_INITIALIZED 任务无需调用 provider 即可完成。 */
async function insertReadyWord(term: string): Promise<number> {
  const now = Date.now();
  const wordResult = await sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'PENDING', ?, ?)`)
    .run(term, term, now, now);
  const wordId = Number(wordResult.lastInsertRowid);
  await sqlite.prepare(`INSERT INTO word_contents
    (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
     synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
    VALUES (?, ?, '[]', ?, '[]', '[]', '[]', '[]', '[]', '[]', ?)`)
    .run(wordId,
      JSON.stringify([{ language: "zh-CN", partOfSpeech: null, text: "测试释义", source: "test", isUserEdited: false }]),
      JSON.stringify([{ sentence: "This is a test sentence.", translation: "这是一个测试句子。" }]),
      now);
  return wordId;
}

describe("background keepalive", () => {
  it("returns idle structure when nothing is queued", async () => {
    const { status, payload } = await callKeepalive();
    expect(status).toBe(200);
    expect(payload.success).toBe(true);
    expect(payload.data).toMatchObject({ running: false, queued: 0, claimed: 0 });
    expect(payload.data!.elapsedMs).toBeGreaterThanOrEqual(0);
  });

  it("runs a tick and completes a queued SKIP_INITIALIZED job", async () => {
    const wordId = await insertReadyWord("keepalive-word");
    const now = Date.now();
    const jobResult = await sqlite.prepare(`INSERT INTO initialization_jobs
      (word_id, mode, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
      VALUES (?, 'SKIP_INITIALIZED', 'QUEUED', 0, 0, 5, ?, ?, ?)`)
      .run(wordId, now, now, now);
    const jobId = Number(jobResult.lastInsertRowid);

    const { status, payload } = await callKeepalive();
    expect(status).toBe(200);
    expect(payload.success).toBe(true);
    expect(payload.data).toMatchObject({ claimed: 1, running: false, queued: 0 });

    const job = await sqlite.prepare("SELECT status FROM initialization_jobs WHERE id = ?").get(jobId) as { status: string };
    expect(job.status).toBe("READY");
    const word = await sqlite.prepare("SELECT initialization_status FROM words WHERE id = ?").get(wordId) as { initialization_status: string };
    expect(word.initialization_status).toBe("READY");
  });
});
