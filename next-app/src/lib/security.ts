import { createHmac, timingSafeEqual } from "node:crypto";
import type { NextRequest, NextResponse } from "next/server";
import { SYNC_PASSWORD_HEADER } from "@/lib/sync-constants";

export const AUTH_COOKIE_NAME = "lexiloop_auth";
export const AUTH_COOKIE_MAX_AGE_SECONDS = 7 * 24 * 60 * 60;
export const LOCAL_MODE_COOKIE_NAME = "lexiloop_mode";
export const LOCAL_MODE_COOKIE_MAX_AGE_SECONDS = 365 * 24 * 60 * 60;
export { SYNC_PASSWORD_HEADER };

function configuredPassword(): string | null {
  const password = process.env.LEXILOOP_PASSWORD;
  return password && password.length > 0 ? password : null;
}

export function isPasswordEnabled(): boolean {
  return configuredPassword() !== null;
}

function signature(payload: string, password: string): string {
  return createHmac("sha256", password).update(`lexiloop-auth-v1:${payload}`).digest("base64url");
}

function secureCompare(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  const size = Math.max(leftBuffer.length, rightBuffer.length);
  const paddedLeft = Buffer.alloc(size);
  const paddedRight = Buffer.alloc(size);
  leftBuffer.copy(paddedLeft);
  rightBuffer.copy(paddedRight);
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(paddedLeft, paddedRight);
}

export function isPasswordCorrect(supplied: string): boolean {
  const expected = configuredPassword();
  return expected !== null && secureCompare(supplied, expected);
}

export function createAuthCookieValue(now = Date.now()): string {
  const password = configuredPassword();
  if (!password) throw new Error("LEXILOOP_PASSWORD is not configured");
  const expiresAt = Math.floor(now / 1000) + AUTH_COOKIE_MAX_AGE_SECONDS;
  const payload = String(expiresAt);
  return `${payload}.${signature(payload, password)}`;
}

export function isAuthCookieValid(request: NextRequest, now = Date.now()): boolean {
  const password = configuredPassword();
  if (!password) return true;

  const cookie = request.cookies.get(AUTH_COOKIE_NAME)?.value;
  if (!cookie) return false;
  const [expiresAt, suppliedSignature] = cookie.split(".");
  if (!expiresAt || !suppliedSignature) return false;
  const expiresAtSeconds = Number(expiresAt);
  if (!Number.isSafeInteger(expiresAtSeconds) || expiresAtSeconds <= Math.floor(now / 1000)) return false;
  return secureCompare(suppliedSignature, signature(expiresAt, password));
}

function extractSyncPassword(request: NextRequest): string | null {
  const direct = request.headers.get(SYNC_PASSWORD_HEADER);
  if (direct && direct.length > 0) return direct;
  const auth = request.headers.get("authorization");
  if (!auth) return null;
  const match = /^Bearer\s+(.+)$/i.exec(auth.trim());
  return match?.[1] ?? null;
}

/**
 * Authorizes cross-device cloud sync API calls (`/api/sync/*`).
 * Accepts either the standard browser auth cookie or a stateless password header
 * (`X-LexiLoop-Sync-Password` / `Authorization: Bearer <password>`).
 */
export function isSyncRequestAuthorized(request: NextRequest, now = Date.now()): boolean {
  if (!isPasswordEnabled()) return true;
  if (isAuthCookieValid(request, now)) return true;
  const supplied = extractSyncPassword(request);
  return supplied !== null && isPasswordCorrect(supplied);
}

function requestIsSecure(request: NextRequest): boolean {
  const forwardedProtocol = request.headers.get("x-forwarded-proto")?.split(",", 1)[0]?.trim();
  return (forwardedProtocol ?? new URL(request.url).protocol.replace(":", "")) === "https";
}

export function hasLocalModeCookie(request: NextRequest): boolean {
  return request.cookies.get(LOCAL_MODE_COOKIE_NAME)?.value === "local";
}

export function setAuthCookie(response: NextResponse, request: NextRequest): void {
  const secure = requestIsSecure(request);
  response.cookies.set({
    name: AUTH_COOKIE_NAME,
    value: createAuthCookieValue(),
    httpOnly: true,
    maxAge: AUTH_COOKIE_MAX_AGE_SECONDS,
    path: "/",
    sameSite: "lax",
    secure,
  });
  // Signing into cloud mode clears any previous browser-local cookie so visits return to cloud DB.
  response.cookies.set({
    name: LOCAL_MODE_COOKIE_NAME,
    value: "",
    maxAge: 0,
    path: "/",
    sameSite: "lax",
    secure,
  });
}

export function setLocalModeCookie(response: NextResponse, request: NextRequest, enabled: boolean): void {
  const secure = requestIsSecure(request);
  response.cookies.set({
    name: LOCAL_MODE_COOKIE_NAME,
    value: enabled ? "local" : "",
    httpOnly: false,
    maxAge: enabled ? LOCAL_MODE_COOKIE_MAX_AGE_SECONDS : 0,
    path: "/",
    sameSite: "lax",
    secure,
  });
}

export function clearAuthCookies(response: NextResponse, request: NextRequest): void {
  const secure = requestIsSecure(request);
  response.cookies.set({
    name: AUTH_COOKIE_NAME,
    value: "",
    httpOnly: true,
    maxAge: 0,
    path: "/",
    sameSite: "lax",
    secure,
  });
  response.cookies.set({
    name: LOCAL_MODE_COOKIE_NAME,
    value: "",
    maxAge: 0,
    path: "/",
    sameSite: "lax",
    secure,
  });
}

/** Requires SSRF validation for AI/provider relays whenever the caller is not explicitly password-authenticated. */
export function requiresSsrfGuard(request: NextRequest): boolean {
  return !(isPasswordEnabled() && isAuthCookieValid(request));
}

export function isSameSiteStatelessRelayAllowed(request: NextRequest): boolean {
  const secFetchSite = request.headers.get("sec-fetch-site");
  if (secFetchSite && secFetchSite !== "same-origin" && secFetchSite !== "same-site" && secFetchSite !== "none") {
    return false;
  }
  return isAuthCookieValid(request) || hasLocalModeCookie(request);
}
