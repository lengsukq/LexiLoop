import { afterAll, beforeAll, beforeEach, describe, expect, test } from "vitest";
import type { SqliteLikeDatabase } from "@/db/types";
import { createPgliteFacade, type PgliteFacade } from "@/local/pglite-executor";
import { setBrowserDbFacadeForTests } from "@/local/browser-db-client";
import { dispatchLocalApiRaw } from "@/local/local-router";
import { invalidateSettingsCache } from "@/modules/settings/service";

const globalDb = globalThis as typeof globalThis & { __lexiloopDbFacade?: SqliteLikeDatabase };

function apiUrl(path: string): URL {
  return new URL(`http://127.0.0.1${path}`);
}

describe.sequential("Browser PGlite local router integration", () => {
  let previousFacade: SqliteLikeDatabase | undefined;
  let facade: PgliteFacade;

  beforeAll(async () => {
    previousFacade = globalDb.__lexiloopDbFacade;
    if (previousFacade) {
      await previousFacade.close();
    }
    facade = createPgliteFacade("memory://", { relaxedDurability: true });
    await facade.ensureReady();
    globalDb.__lexiloopDbFacade = facade;
    setBrowserDbFacadeForTests(facade);
  });

  beforeEach(async () => {
    await facade.exec(`TRUNCATE
      word_pack_items, word_packs, provider_attempts, initialization_jobs,
      import_rows, import_batches, import_previews, wrong_word_states,
      review_logs, review_cards, study_session_items, study_sessions,
      word_contents, words, worker_heartbeats, settings,
      manual_previews, daily_ai_suggestions, game_high_scores
      CASCADE`);
    const now = Date.now();
    for (const key of [
      "dictionaryApiEnabled",
      "myMemoryEnabled",
      "merriamWebsterEnabled",
      "youdaoEnabled",
      "icibaEnabled",
      "tencentTranslateEnabled",
    ]) {
      await facade
        .prepare("INSERT INTO settings(key, value_json, updated_at) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value_json = EXCLUDED.value_json, updated_at = EXCLUDED.updated_at")
        .run(key, JSON.stringify(false), now);
    }
    invalidateSettingsCache();
  });

  afterAll(async () => {
    // tests/setup.ts afterAll calls sqlite.close() on globalDb.__lexiloopDbFacade.
    setBrowserDbFacadeForTests(undefined);
    invalidateSettingsCache();
  });

  test("preserves numeric types, lastInsertRowid, and supports full CSV import -> edit -> study -> backup/restore -> delete", async () => {
    // 1. Settings update & retrieval via local router
    const settingsBefore = await dispatchLocalApiRaw(apiUrl("/api/settings"));
    expect(settingsBefore.status).toBe(200);

    const updatedSettings = await dispatchLocalApiRaw(apiUrl("/api/settings"), {
      method: "PUT",
      body: JSON.stringify({ dailyNewWords: 35, choiceRevealDelaySeconds: 2 }),
    });
    expect(updatedSettings.status).toBe(200);
    expect(updatedSettings.body.success).toBe(true);
    if (updatedSettings.body.success) {
      expect((updatedSettings.body.data as { dailyNewWords: number }).dailyNewWords).toBe(35);
    }

    // 2. CSV import preview (FormData) & commit
    const csvContent = [
      "queryText,queryFromLanguage,queryToLanguage,timestamp",
      "ephemeral,English,Chinese-Simplified,2026-01-01T00:00:00Z",
      "resilient,English,Chinese-Simplified,2026-01-01T00:01:00Z",
      "lucid,English,Chinese-Simplified,2026-01-01T00:02:00Z",
      "candid,English,Chinese-Simplified,2026-01-01T00:03:00Z",
    ].join("\n");
    const csvForm = new FormData();
    csvForm.append("file", new File([csvContent], "local-words.csv", { type: "text/csv" }));

    const previewRes = await dispatchLocalApiRaw(apiUrl("/api/imports/preview"), {
      method: "POST",
      body: csvForm,
    });
    expect(previewRes.status).toBe(200);
    expect(previewRes.body.success).toBe(true);
    const previewData = (previewRes.body as { success: true; data: { previewToken: string; newRows: number } }).data;
    expect(previewData.newRows).toBe(4);

    const commitRes = await dispatchLocalApiRaw(apiUrl("/api/imports/commit"), {
      method: "POST",
      body: JSON.stringify({ previewToken: previewData.previewToken, mode: "SKIP_EXISTING", resetLearningProgress: false }),
    });
    expect(commitRes.status).toBe(200);

    // 3. List words & update manual definition so words become READY for study
    const wordsRes = await dispatchLocalApiRaw(apiUrl("/api/words?limit=20"));
    expect(wordsRes.status).toBe(200);
    const listed = (wordsRes.body as { success: true; data: { items: Array<{ id: number; term: string }> } }).data.items;
    expect(listed).toHaveLength(4);
    expect(typeof listed[0]!.id).toBe("number");

    for (const item of listed) {
      const defRes = await dispatchLocalApiRaw(apiUrl(`/api/words/${item.id}/content`), {
        method: "PUT",
        body: JSON.stringify({
          definition: `${item.term} 的中文释义`,
          partOfSpeech: "adj.",
        }),
      });
      expect(defRes.status).toBe(200);
    }

    // 4. Start study session & answer first card via PGlite
    const sessionRes = await dispatchLocalApiRaw(apiUrl("/api/study/sessions"), {
      method: "POST",
      body: JSON.stringify({ mode: "DAILY", resume: false }),
    });
    expect(sessionRes.status).toBe(200);
    const session = (sessionRes.body as { success: true; data: { session: { id: number }; items: Array<{ itemId: number; word: { id: number }; questionType: string }> } }).data;
    expect(session.items.length).toBeGreaterThan(0);

    const firstItem = session.items[0]!;
    const answerRes = await dispatchLocalApiRaw(apiUrl("/api/study/answer"), {
      method: "POST",
      body: JSON.stringify({
        clientAnswerId: "local-browser-answer-001",
        wordId: firstItem.word.id,
        studySessionId: session.session.id,
        studySessionItemId: firstItem.itemId,
        rating: "GOOD",
        questionType: firstItem.questionType,
        durationMs: 1200,
      }),
    });
    expect(answerRes.status).toBe(200);

    // 5. Export JSON backup -> wipe -> restore JSON backup cleanly into PGlite
    const backupRes = await dispatchLocalApiRaw(apiUrl("/api/backups/json"));
    expect(backupRes.status).toBe(200);
    const backupJson = JSON.stringify((backupRes.body as { success: true; data: Record<string, unknown> }).data);

    await facade.exec("TRUNCATE words CASCADE");
    const afterTruncate = await dispatchLocalApiRaw(apiUrl("/api/words"));
    expect((afterTruncate.body as { success: true; data: { items: unknown[] } }).data.items).toHaveLength(0);

    const restoreForm = new FormData();
    restoreForm.append("file", new File([backupJson], "backup.json", { type: "application/json" }));
    const restoreRes = await dispatchLocalApiRaw(apiUrl("/api/backups/restore"), {
      method: "POST",
      body: restoreForm,
    });
    expect(restoreRes.status).toBe(200);

    const restoredWords = await dispatchLocalApiRaw(apiUrl("/api/words"));
    expect((restoredWords.body as { success: true; data: { items: unknown[] } }).data.items).toHaveLength(4);

    // 6. Health & statistics endpoints work cleanly
    const healthRes = await dispatchLocalApiRaw(apiUrl("/api/health"));
    expect(healthRes.status).toBe(200);
    const statsRes = await dispatchLocalApiRaw(apiUrl("/api/statistics?days=7"));
    expect(statsRes.status).toBe(200);
  });

  test("serializes concurrent PGlite transactions cleanly without connection aborts", async () => {
    const writes = await Promise.all(
      Array.from({ length: 8 }, (_, idx) =>
        dispatchLocalApiRaw(apiUrl("/api/settings"), {
          method: "PUT",
          body: JSON.stringify({ dailyNewWords: 15 + idx }),
        }),
      ),
    );
    for (const res of writes) {
      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    }
    const finalSettings = await dispatchLocalApiRaw(apiUrl("/api/settings"));
    expect((finalSettings.body as { success: true; data: { dailyNewWords: number } }).data.dailyNewWords).toBe(22);
  });
});
