import { describe, expect, it } from "vitest";
import { sqlite } from "@/db/client";
import { getDashboard } from "@/modules/statistics/service";

describe("dashboard", () => {
  it("returns the latest resumable session with its pending count", async () => {
    const now = Date.now();
    const wordId = Number(sqlite.prepare(`INSERT INTO words
      (term, normalized_term, source_language, target_language, entry_type, initialization_status, created_at, updated_at)
      VALUES ('resume', 'resume', 'en', 'zh-CN', 'WORD', 'READY', ?, ?)`).run(now, now).lastInsertRowid);
    const sessionId = Number(sqlite.prepare(`INSERT INTO study_sessions
      (session_type, started_at, planned_count, created_at) VALUES ('SPELLING', ?, 3, ?)`).run(now, now).lastInsertRowid);
    const insertItem = sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, status, created_at)
      VALUES (?, ?, ?, 'SPELLING', 'ZH_TO_EN_SPELLING', ?, ?)`);
    insertItem.run(sessionId, 0, wordId, "ANSWERED", now);
    insertItem.run(sessionId, 1, wordId, "PENDING", now);
    insertItem.run(sessionId, 2, wordId, "PENDING", now);

    const dashboard = await getDashboard();

    expect(dashboard.resumeSession).toMatchObject({
      id: sessionId,
      sessionType: "SPELLING",
      remainingCount: 2,
      plannedCount: 3,
    });
  });
});
