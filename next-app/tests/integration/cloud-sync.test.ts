import { describe, expect, test } from "vitest";
import { NextRequest } from "next/server";
import { sqlite } from "@/db/client";
import { POST as handshakeRoute } from "@/app/api/sync/handshake/route";
import { POST as pullRoute } from "@/app/api/sync/pull/route";
import { POST as pushRoute } from "@/app/api/sync/push/route";
import { GET as statusRoute } from "@/app/api/sync/status/route";
import { createJsonBackup, restoreJsonBackup } from "@/modules/backups/service";
import { exportSyncPullPage } from "@/modules/sync/pull-exporter";
import { applySyncPushBatch } from "@/modules/sync/push-merger";
import { CLOUD_SYNC_DELTA_FORMAT, pushRequestSchema } from "@/modules/sync/types";

describe("Next.js ↔ Flutter cloud sync integration", () => {
  test("merges split push batches with refs, replays FSRS, preserves word packs, and paginates pulls", async () => {
    const t0 = 1_730_000_000_000;
    const t1 = t0 + 10_000;

    // Batch 1: words only
    const batch1 = pushRequestSchema.parse({
      format: CLOUD_SYNC_DELTA_FORMAT,
      version: 1,
      clientDeviceId: "flutter-mac-01",
      clientDeviceName: "MacBook Pro",
      clientDatasetEpoch: "epoch-a",
      clientServerNow: t1,
      commitWatermark: false,
      words: [
        {
          id: 101,
          term: "Resilient",
          normalized_term: "resilient",
          source_language: "en",
          target_language: "zh-CN",
          entry_type: "WORD",
          content_type: "WORD",
          initialization_status: "QUEUED",
          mastery_level: "NEW",
          mastery_score: 0,
          is_suspended: false,
          is_personal: true,
          user_note: "来自 Flutter",
          created_at: t0,
          updated_at: t1,
        },
        {
          id: 102,
          term: "Ephemeral",
          normalized_term: "ephemeral",
          source_language: "en",
          target_language: "zh-CN",
          entry_type: "WORD",
          content_type: "WORD",
          initialization_status: "READY",
          mastery_level: "NEW",
          mastery_score: 0,
          is_suspended: 0,
          is_personal: 0,
          created_at: t0,
          updated_at: t1,
        },
      ],
    });
    const res1 = await applySyncPushBatch(batch1, t1);
    expect(res1.summary.addedWords).toBe(2);
    expect(res1.summary.wordCount).toBe(2);

    // Transient QUEUED status normalized to PENDING on server
    const resilientRow = await sqlite
      .prepare("SELECT initialization_status, is_personal FROM words WHERE normalized_term = ?")
      .get("resilient") as { initialization_status: string; is_personal: number };
    expect(resilientRow.initialization_status).toBe("PENDING");
    expect(resilientRow.is_personal).toBe(1);

    // Batch 2: contents + sessions + items (using word_refs)
    const batch2 = pushRequestSchema.parse({
      format: CLOUD_SYNC_DELTA_FORMAT,
      version: 1,
      clientDeviceId: "flutter-mac-01",
      clientDeviceName: "MacBook Pro",
      clientDatasetEpoch: "epoch-a",
      clientServerNow: t1,
      commitWatermark: false,
      word_refs: [
        { id: 101, normalized_term: "resilient", source_language: "en", target_language: "zh-CN" },
        { id: 102, normalized_term: "ephemeral", source_language: "en", target_language: "zh-CN" },
      ],
      word_contents: [
        {
          word_id: 101,
          definitions_json: JSON.stringify([{ pos: "adj.", text: "有弹性的；能迅速恢复的" }]),
          updated_at: t1,
        },
      ],
      study_sessions: [
        {
          id: 501,
          session_type: "DAILY",
          source_type: null,
          started_at: t0,
          completed_at: t1,
          planned_count: 1,
          completed_count: 1,
          correct_count: 1,
          wrong_count: 0,
          skipped_count: 0,
          duration_ms: 2500,
          created_at: t0,
        },
      ],
      study_session_items: [
        {
          id: 601,
          study_session_id: 501,
          position: 1,
          word_id: 101,
          task_type: "NEW",
          question_type: "EN_TO_ZH",
          status: "ANSWERED",
          answered_at: t1,
          created_at: t0,
        },
      ],
    });
    await applySyncPushBatch(batch2, t1);

    // Batch 3: review_logs + word_packs + word_pack_items + settings (with session_refs/item_refs & commitWatermark)
    const batch3 = pushRequestSchema.parse({
      format: CLOUD_SYNC_DELTA_FORMAT,
      version: 1,
      clientDeviceId: "flutter-mac-01",
      clientDeviceName: "MacBook Pro",
      clientDatasetEpoch: "epoch-a",
      clientServerNow: t1,
      pulledServerNow: t0,
      commitWatermark: true,
      word_refs: [
        { id: 101, normalized_term: "resilient", source_language: "en", target_language: "zh-CN" },
        { id: 102, normalized_term: "ephemeral", source_language: "en", target_language: "zh-CN" },
      ],
      session_refs: [{ id: 501, started_at: t0, session_type: "DAILY", source_type: null }],
      item_refs: [{ id: 601, study_session_id: 501, position: 1 }],
      review_logs: [
        {
          id: 701,
          client_answer_id: "ans-resilient-1",
          word_id: 101,
          study_session_id: 501,
          study_session_item_id: 601,
          reviewed_at: t1,
          rating: "GOOD",
          question_type: "EN_TO_ZH",
          is_correct: true,
          duration_ms: 2500,
          created_at: t1,
        },
      ],
      settings: [
        { key: "dailyNewWords", value_json: "25", updated_at: t1 + 5000 },
        { key: "cloudSync", value_json: JSON.stringify({ password: "secret" }), updated_at: t1 + 5000 },
      ],
      word_packs: [
        {
          id: "ielts",
          slug: "ielts",
          name: "雅思核心词书",
          category: "EXAM_INTL",
          description: "test pack",
          version: "2026.1",
          content_mode: "ECDICT_BASE",
          word_count: 1,
          include_in_daily_study: false,
          sha256: "abc123",
          installed_at: t0,
          updated_at: t1,
        },
      ],
      word_pack_items: [{ pack_id: "ielts", word_id: 102, rank: 1 }],
    });
    const res3 = await applySyncPushBatch(batch3, t1 + 1000);
    expect(res3.summary.addedLogs).toBe(1);
    expect(res3.summary.rebuiltWords).toBe(1);

    // Verify FSRS card, stats, pack, and secret exclusion
    const card = await sqlite
      .prepare("SELECT reps, fsrs_state FROM review_cards c JOIN words w ON w.id = c.word_id WHERE w.normalized_term = ?")
      .get("resilient") as { reps: number; fsrs_state: number } | undefined;
    expect(card?.reps).toBe(1);

    const stats = await sqlite
      .prepare("SELECT total_reviews, correct_reviews FROM word_review_stats s JOIN words w ON w.id = s.word_id WHERE w.normalized_term = ?")
      .get("resilient") as { total_reviews: number; correct_reviews: number } | undefined;
    expect(stats).toEqual({ total_reviews: 1, correct_reviews: 1 });

    const cloudSyncSetting = await sqlite.prepare("SELECT * FROM settings WHERE key = 'cloudSync'").get();
    expect(cloudSyncSetting).toBeUndefined();

    // Idempotent re-push adds 0 logs and 0 words
    const repeat = await applySyncPushBatch(batch3, t1 + 2000);
    expect(repeat.summary.addedLogs).toBe(0);
    expect(repeat.summary.addedWords).toBe(0);

    // Handshake returns remembered pushSince for this Flutter client
    const handshakeRes = await handshakeRoute(
      new NextRequest("http://localhost/api/sync/handshake", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          protocolVersion: 1,
          deviceId: "flutter-mac-01",
          deviceName: "MacBook Pro",
          datasetEpoch: "epoch-a",
          knownServerEpoch: res3.datasetEpoch,
        }),
      }),
    );
    expect(handshakeRes.status).toBe(200);
    const handshakeJson = (await handshakeRes.json()) as { data: { pushSince: number | null; wordCount: number; pullFullRequired: boolean } };
    expect(handshakeJson.data.pushSince).toBe(t1);
    expect(handshakeJson.data.wordCount).toBe(2);
    expect(handshakeJson.data.pullFullRequired).toBe(false);

    // Paginated pull with tiny byte budget forces multiple pages and preserves all rows + word_refs
    const collectedWords: unknown[] = [];
    const collectedPacks: unknown[] = [];
    const collectedPackItems: unknown[] = [];
    let cursor = null;
    let pages = 0;
    let snapshotAt: number | undefined;
    do {
      const page = await exportSyncPullPage({
        request: { mode: "delta", since: null, snapshotAt, cursor, maxPageBytes: 4096 },
        datasetEpoch: res3.datasetEpoch,
      });
      snapshotAt = page.snapshotAt;
      collectedWords.push(...(page.tables.words ?? []));
      collectedPacks.push(...(page.tables.word_packs ?? []));
      collectedPackItems.push(...(page.tables.word_pack_items ?? []));
      cursor = page.nextCursor;
      pages += 1;
      if (!page.hasMore) break;
    } while (pages < 20);

    expect(collectedWords).toHaveLength(2);
    expect(collectedPacks).toHaveLength(1);
    expect(collectedPackItems).toHaveLength(1);

    // HTTP pull/push/status routes succeed cleanly
    const httpPull = await pullRoute(
      new NextRequest("http://localhost/api/sync/pull", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ mode: "replace" }),
      }),
    );
    expect(httpPull.status).toBe(200);
    const httpPush = await pushRoute(
      new NextRequest("http://localhost/api/sync/push", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(batch3),
      }),
    );
    expect(httpPush.status).toBe(200);
    const httpStatus = await statusRoute(new NextRequest("http://localhost/api/sync/status"));
    expect(httpStatus.status).toBe(200);
    const statusBody = (await httpStatus.json()) as { data: { peers: { peerDeviceId: string }[] } };
    expect(statusBody.data.peers[0]?.peerDeviceId).toBe("flutter-mac-01");
  });

  test("restoreJsonBackup ignores unknown future columns and recomputes word_review_stats", async () => {
    const now = Date.now();
    const backup = await createJsonBackup();
    const raw = JSON.stringify({
      ...backup,
      words: [
        {
          id: 1,
          term: "tenacious",
          normalized_term: "tenacious",
          source_language: "en",
          target_language: "zh-CN",
          entry_type: "WORD",
          content_type: "WORD",
          initialization_status: "READY",
          mastery_level: "LEARNING",
          mastery_score: 50,
          is_suspended: false,
          is_personal: true,
          future_unknown_col: "ignored-safely",
          created_at: now,
          updated_at: now,
        },
      ],
      review_logs: [
        {
          id: 1,
          client_answer_id: "ans-tenacious-1",
          word_id: 1,
          reviewed_at: now,
          rating: "GOOD",
          question_type: "EN_TO_ZH",
          is_correct: true,
          duration_ms: 1200,
          created_at: now,
        },
      ],
    });

    const restored = await restoreJsonBackup(raw);
    expect(restored.rowCounts.words).toBe(1);
    const stats = await sqlite
      .prepare("SELECT total_reviews, correct_reviews FROM word_review_stats WHERE word_id = 1")
      .get() as { total_reviews: number; correct_reviews: number } | undefined;
    expect(stats).toEqual({ total_reviews: 1, correct_reviews: 1 });
  });
});
