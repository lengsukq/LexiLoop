import { gzipSync } from "node:zlib";
import { describe, expect, test } from "vitest";
import { DAY_MS } from "@/lib/time";
import { okMaybeGzip, readJsonRequestMaybeGzip } from "@/modules/sync/http-codec";
import { replayWordHistory, transitionWrongStatePure } from "@/modules/sync/learning-replay";

describe("sync deterministic FSRS replay and wrong state", () => {
  const baseTime = Date.UTC(2026, 9, 1, 8, 0, 0);

  test("replays identical state deterministically across repeated runs", () => {
    const logs = [
      { reviewedAt: baseTime, rating: "AGAIN" as const, isCorrect: false, durationMs: 3200 },
      { reviewedAt: baseTime + DAY_MS, rating: "GOOD" as const, isCorrect: true, durationMs: 2100 },
      { reviewedAt: baseTime + 2 * DAY_MS, rating: "GOOD" as const, isCorrect: true, durationMs: 1800 },
      { reviewedAt: baseTime + 3 * DAY_MS, rating: "GOOD" as const, isCorrect: true, durationMs: 1500 },
    ];

    const first = replayWordHistory(logs, 0.9, baseTime + 4 * DAY_MS);
    const second = replayWordHistory(logs, 0.9, baseTime + 4 * DAY_MS);

    expect(first.card.due.getTime()).toBe(second.card.due.getTime());
    expect(first.card.stability).toBe(second.card.stability);
    expect(first.card.difficulty).toBe(second.card.difficulty);
    expect(first.card.reps).toBe(4);
    expect(first.wrong?.active).toBe(false);
    expect(first.wrong?.wrongCount).toBe(1);
    expect(first.wrong?.consecutiveCorrect).toBe(3);
    expect(first.masteryScore).toBeGreaterThan(0);
  });

  test("resolves wrong state immediately on EASY rating", () => {
    const wrong = transitionWrongStatePure(null, "AGAIN", false, baseTime);
    expect(wrong?.active).toBe(true);
    const cleared = transitionWrongStatePure(wrong, "EASY", true, baseTime + 10_000);
    expect(cleared?.active).toBe(false);
    expect(cleared?.resolvedAt).toBe(baseTime + 10_000);
  });

  test("round-trips GZip requests and responses cleanly", async () => {
    const payload = { hello: "lexiloop", items: Array.from({ length: 50 }, (_, i) => `word-${i}`) };
    const gzBody = gzipSync(Buffer.from(JSON.stringify(payload), "utf8"));
    const req = new Request("http://localhost/api/sync/push", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "content-encoding": "gzip",
        "accept-encoding": "gzip",
      },
      body: gzBody,
    });

    const decoded = await readJsonRequestMaybeGzip(req);
    expect(decoded).toEqual(payload);

    const response = okMaybeGzip(req, { ok: true });
    expect(response.headers.get("content-encoding")).toBe("gzip");
    const responseBuf = Buffer.from(await response.arrayBuffer());
    const responseReq = new Request("http://localhost/check", {
      method: "POST",
      headers: { "content-encoding": "gzip" },
      body: responseBuf,
    });
    expect(await readJsonRequestMaybeGzip(responseReq)).toEqual({ success: true, data: { ok: true } });
  });
});
