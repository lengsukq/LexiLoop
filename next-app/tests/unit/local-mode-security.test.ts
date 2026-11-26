import { afterEach, describe, expect, test } from "vitest";
import { NextRequest } from "next/server";
import { POST as loginRoute } from "@/app/api/auth/login/route";
import { DELETE as disableLocalRoute, POST as enableLocalRoute } from "@/app/api/auth/local-mode/route";
import { POST as logoutRoute } from "@/app/api/auth/logout/route";
import {
  AUTH_COOKIE_NAME,
  createAuthCookieValue,
  LOCAL_MODE_COOKIE_NAME,
} from "@/lib/security";
import { assertPublicSafeUrl } from "@/lib/ssrf-guard";
import { hmacSha256Hex, randomHexToken, randomUuid, sha256Hex, utf8ByteLength } from "@/lib/iso-crypto";
import { proxy } from "@/proxy";

const originalPassword = process.env.LEXILOOP_PASSWORD;

function req(path: string, init?: ConstructorParameters<typeof NextRequest>[1]): NextRequest {
  return new NextRequest(`https://lexiloop.example${path}`, init);
}

describe.sequential("local browser mode security and isomorphic helpers", () => {
  afterEach(() => {
    if (originalPassword === undefined) delete process.env.LEXILOOP_PASSWORD;
    else process.env.LEXILOOP_PASSWORD = originalPassword;
  });

  test("proxy isolates local mode to page shells and stateless relays while keeping cloud DB gated", async () => {
    process.env.LEXILOOP_PASSWORD = "super-secret-password";

    const localCookieHeaders = {
      cookie: `${LOCAL_MODE_COOKIE_NAME}=local`,
      "sec-fetch-site": "same-origin",
    };

    // Page routes and stateless relays pass with lexiloop_mode=local.
    expect(proxy(req("/", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/words", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/settings", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/api/tts?word=hello", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/api/tts/youdao?word=hello", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/api/local-proxy/dictionary", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/api/local-proxy/tencent-translate", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/api/local-proxy/llm", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/api/settings/models", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/api/settings/test-provider", { headers: localCookieHeaders })).status).toBe(200);
    expect(proxy(req("/api/settings/test-tencent-translate", { headers: localCookieHeaders })).status).toBe(200);

    // Cross-site requests to stateless relays must be rejected even with local cookie.
    const crossSiteRes = proxy(req("/api/local-proxy/llm", {
      headers: { cookie: `${LOCAL_MODE_COOKIE_NAME}=local`, "sec-fetch-site": "cross-site" },
    }));
    expect(crossSiteRes.status).toBe(401);

    // Cloud DB endpoints MUST still require real password auth.
    for (const cloudEndpoint of [
      "/api/words",
      "/api/dashboard",
      "/api/settings",
      "/api/backups/json",
      "/api/backups/restore",
      "/api/study/sessions",
      "/api/sync/status",
      "/api/sync/handshake",
      "/api/sync/pull",
      "/api/sync/push",
    ]) {
      const res = proxy(req(cloudEndpoint, { headers: localCookieHeaders }));
      expect(res.status, `expected 401 for ${cloudEndpoint}`).toBe(401);
    }
  });

  test("local-mode cookie endpoints set/clear mode and password login clears local cookie", async () => {
    process.env.LEXILOOP_PASSWORD = "super-secret-password";

    const enabled = await enableLocalRoute(req("/api/auth/local-mode", {
      method: "POST",
      body: JSON.stringify({ enabled: true }),
      headers: { "content-type": "application/json" },
    }));
    expect(enabled.status).toBe(200);
    expect(enabled.cookies.get(LOCAL_MODE_COOKIE_NAME)?.value).toBe("local");
    expect(enabled.cookies.get(AUTH_COOKIE_NAME)).toBeUndefined();

    const loginRes = await loginRoute(req("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ password: "super-secret-password" }),
      headers: { "content-type": "application/json" },
    }));
    expect(loginRes.status).toBe(200);
    expect(loginRes.cookies.get(AUTH_COOKIE_NAME)?.value).toBeTruthy();
    expect(loginRes.cookies.get(LOCAL_MODE_COOKIE_NAME)?.value).toBe("");

    const disabled = await disableLocalRoute(req("/api/auth/local-mode", { method: "DELETE" }));
    expect(disabled.cookies.get(LOCAL_MODE_COOKIE_NAME)?.value).toBe("");

    const loggedOut = await logoutRoute(req("/api/auth/logout", { method: "POST" }));
    expect(loggedOut.cookies.get(AUTH_COOKIE_NAME)?.value).toBe("");
    expect(loggedOut.cookies.get(LOCAL_MODE_COOKIE_NAME)?.value).toBe("");

    // Authenticated requests still access cloud endpoints normally.
    const authCookie = createAuthCookieValue(Date.now());
    expect(proxy(req("/api/words", { headers: { cookie: `${AUTH_COOKIE_NAME}=${authCookie}` } })).status).toBe(200);
  });

  test("ssrf-guard rejects localhost, metadata IPs, private IPv4/IPv6, and invalid schemes", async () => {
    const blockedUrls = [
      "http://127.0.0.1:11434/v1",
      "http://localhost:3000/api/words",
      "http://169.254.169.254/latest/meta-data",
      "http://10.0.0.1/v1",
      "http://172.16.5.4/v1",
      "http://192.168.1.10/v1",
      "http://[::1]:8080/v1",
      "http://[::ffff:127.0.0.1]/v1",
      "http://service.internal/v1",
      "http://printer.local/v1",
      "file:///etc/passwd",
      "https://user:pass@api.openai.com/v1",
    ];

    for (const url of blockedUrls) {
      await expect(assertPublicSafeUrl(url), `should reject ${url}`).rejects.toThrow();
    }

    const safe = await assertPublicSafeUrl("https://1.1.1.1/v1");
    expect(safe.hostname).toBe("1.1.1.1");
  });

  test("iso-crypto matches standard Node sha256/hmac/uuid behavior", async () => {
    const crypto = await import("node:crypto");
    expect(randomUuid()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(randomHexToken(16)).toMatch(/^[0-9a-f]{16}$/);
    expect(utf8ByteLength("你好LexiLoop")).toBe(Buffer.byteLength("你好LexiLoop", "utf8"));

    const expectedSha = crypto.createHash("sha256").update("hello world").digest("hex");
    expect(await sha256Hex("hello world")).toBe(expectedSha);

    const expectedHmac = crypto.createHmac("sha256", "TC3secret").update("payload").digest("hex");
    expect(await hmacSha256Hex("TC3secret", "payload")).toBe(expectedHmac);
  });
});
