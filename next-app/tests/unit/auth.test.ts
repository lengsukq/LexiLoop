import { afterAll, beforeEach, describe, expect, test } from "vitest";
import { NextRequest } from "next/server";
import { POST as login } from "@/app/api/auth/login/route";
import { proxy } from "@/proxy";
import {
  AUTH_COOKIE_MAX_AGE_SECONDS,
  AUTH_COOKIE_NAME,
  createAuthCookieValue,
  isAuthCookieValid,
  isPasswordCorrect,
} from "@/lib/security";

const originalPassword = process.env.LEXILOOP_PASSWORD;
const NOW = 1_800_000_000_000;

function request(path: string, init?: ConstructorParameters<typeof NextRequest>[1]): NextRequest {
  return new NextRequest(`http://localhost${path}`, init);
}

describe.sequential("optional password authentication", () => {
  beforeEach(() => {
    delete process.env.LEXILOOP_PASSWORD;
  });

  afterAll(() => {
    if (originalPassword === undefined) delete process.env.LEXILOOP_PASSWORD;
    else process.env.LEXILOOP_PASSWORD = originalPassword;
  });

  test("does not gate pages or APIs when the password is not configured", async () => {
    expect(proxy(request("/"))).toHaveProperty("status", 200);
    expect(proxy(request("/api/dashboard"))).toHaveProperty("status", 200);
    expect((await login(request("/api/auth/login", { method: "POST", body: JSON.stringify({ password: "anything" }) }))).status).toBe(200);
  });

  test("redirects pages and returns a JSON 401 for protected APIs", async () => {
    process.env.LEXILOOP_PASSWORD = "correct horse";

    const pageResponse = proxy(request("/words?view=all"));
    expect(pageResponse.status).toBe(307);
    expect(pageResponse.headers.get("location")).toBe("http://localhost/login?next=%2Fwords%3Fview%3Dall");

    const apiResponse = proxy(request("/api/dashboard"));
    expect(apiResponse.status).toBe(401);
    expect(await apiResponse.json()).toMatchObject({ success: false, error: { code: "AUTH_REQUIRED" } });
  });

  test("keeps the health check public and allows authenticated requests", () => {
    process.env.LEXILOOP_PASSWORD = "correct horse";
    const cookie = createAuthCookieValue(NOW);

    expect(proxy(request("/api/health")).status).toBe(200);
    expect(proxy(request("/", { headers: { cookie: `${AUTH_COOKIE_NAME}=${cookie}` } })).status).toBe(200);
    expect(isAuthCookieValid(request("/", { headers: { cookie: `${AUTH_COOKIE_NAME}=${cookie}` } }), NOW)).toBe(true);
  });

  test("accepts the exact password and issues a seven-day HttpOnly cookie", async () => {
    process.env.LEXILOOP_PASSWORD = "correct horse";
    expect(isPasswordCorrect("correct horse")).toBe(true);
    expect(isPasswordCorrect("Correct horse")).toBe(false);

    const response = await login(request("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ password: "correct horse" }),
      headers: { "content-type": "application/json" },
    }));

    expect(response.status).toBe(200);
    const cookie = response.cookies.get(AUTH_COOKIE_NAME);
    expect(cookie?.value).toBeTruthy();
    expect(response.headers.get("set-cookie")).toContain(`Max-Age=${AUTH_COOKIE_MAX_AGE_SECONDS}`);
    expect(response.headers.get("set-cookie")).toContain("HttpOnly");
    expect(isAuthCookieValid(request("/", { headers: { cookie: `${AUTH_COOKIE_NAME}=${cookie?.value}` } }), Date.now())).toBe(true);
  });

  test("rejects wrong passwords and invalidates old cookies after a password change", async () => {
    process.env.LEXILOOP_PASSWORD = "old-password";
    const oldCookie = createAuthCookieValue(NOW);
    const invalidResponse = await login(request("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ password: "wrong-password" }),
      headers: { "content-type": "application/json" },
    }));
    expect(invalidResponse.status).toBe(401);

    process.env.LEXILOOP_PASSWORD = "new-password";
    expect(isAuthCookieValid(request("/", { headers: { cookie: `${AUTH_COOKIE_NAME}=${oldCookie}` } }), NOW)).toBe(false);
  });
});
