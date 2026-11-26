import { afterAll, beforeEach, describe, expect, test } from "vitest";
import { NextRequest } from "next/server";
import { proxy } from "@/proxy";
import {
  AUTH_COOKIE_NAME,
  SYNC_PASSWORD_HEADER,
  createAuthCookieValue,
  isSyncRequestAuthorized,
} from "@/lib/security";

const originalPassword = process.env.LEXILOOP_PASSWORD;
const NOW = 1_800_000_000_000;

function makeRequest(path: string, headers?: Record<string, string>): NextRequest {
  return new NextRequest(`http://localhost${path}`, { method: "POST", headers });
}

describe.sequential("cloud sync authentication", () => {
  beforeEach(() => {
    delete process.env.LEXILOOP_PASSWORD;
  });

  afterAll(() => {
    if (originalPassword === undefined) delete process.env.LEXILOOP_PASSWORD;
    else process.env.LEXILOOP_PASSWORD = originalPassword;
  });

  test("allows sync requests when LEXILOOP_PASSWORD is not configured", () => {
    const req = makeRequest("/api/sync/handshake");
    expect(isSyncRequestAuthorized(req, NOW)).toBe(true);
    expect(proxy(req).status).toBe(200);
  });

  test("rejects unauthenticated or wrong-password sync requests when password is enabled", async () => {
    process.env.LEXILOOP_PASSWORD = "sync-secret";

    const noAuth = makeRequest("/api/sync/handshake");
    expect(isSyncRequestAuthorized(noAuth, NOW)).toBe(false);
    const res = proxy(noAuth);
    expect(res.status).toBe(401);
    expect(await res.json()).toMatchObject({ success: false, error: { code: "AUTH_REQUIRED" } });

    const wrongHeader = makeRequest("/api/sync/pull", { [SYNC_PASSWORD_HEADER]: "wrong" });
    expect(isSyncRequestAuthorized(wrongHeader, NOW)).toBe(false);
    expect(proxy(wrongHeader).status).toBe(401);
  });

  test("accepts X-LexiLoop-Sync-Password, Bearer token, and valid auth cookie", () => {
    process.env.LEXILOOP_PASSWORD = "sync-secret";

    const directHeader = makeRequest("/api/sync/handshake", { [SYNC_PASSWORD_HEADER]: "sync-secret" });
    expect(isSyncRequestAuthorized(directHeader, NOW)).toBe(true);
    expect(proxy(directHeader).status).toBe(200);

    const bearer = makeRequest("/api/sync/push", { authorization: "Bearer sync-secret" });
    expect(isSyncRequestAuthorized(bearer, NOW)).toBe(true);
    expect(proxy(bearer).status).toBe(200);

    const cookie = createAuthCookieValue(NOW);
    const withCookie = makeRequest("/api/sync/status", { cookie: `${AUTH_COOKIE_NAME}=${cookie}` });
    expect(isSyncRequestAuthorized(withCookie, NOW)).toBe(true);
  });
});
