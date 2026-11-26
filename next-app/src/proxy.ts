import { NextRequest, NextResponse } from "next/server";
import { authRequired } from "@/lib/api";
import {
  hasLocalModeCookie,
  isAuthCookieValid,
  isPasswordEnabled,
  isSameSiteStatelessRelayAllowed,
  isSyncRequestAuthorized,
} from "@/lib/security";

const PUBLIC_PATHS = new Set([
  "/login",
  "/api/auth/login",
  "/api/auth/local-mode",
  "/api/auth/logout",
  "/api/health",
]);

const LOCAL_STATELESS_API_PATHS = new Set([
  "/api/tts",
  "/api/tts/youdao",
  "/api/local-proxy/dictionary",
  "/api/local-proxy/tencent-translate",
  "/api/local-proxy/llm",
  "/api/settings/models",
  "/api/settings/test-provider",
  "/api/settings/test-tencent-translate",
]);

function isSafeNextPath(value: string | null): value is string {
  return Boolean(value && value.startsWith("/") && !value.startsWith("//") && !value.startsWith("/login"));
}

function redirectToLogin(request: NextRequest): NextResponse {
  const loginUrl = new URL("/login", request.url);
  const nextPath = `${request.nextUrl.pathname}${request.nextUrl.search}`;
  if (nextPath !== "/") loginUrl.searchParams.set("next", nextPath);
  return NextResponse.redirect(loginUrl);
}

export function proxy(request: NextRequest): NextResponse {
  if (!isPasswordEnabled()) return NextResponse.next();

  const pathname = request.nextUrl.pathname;
  if (PUBLIC_PATHS.has(pathname)) {
    if (pathname === "/login" && isAuthCookieValid(request)) {
      const nextPath = request.nextUrl.searchParams.get("next");
      const destination = isSafeNextPath(nextPath) ? nextPath : "/";
      return NextResponse.redirect(new URL(destination, request.url));
    }
    return NextResponse.next();
  }

  if (pathname.startsWith("/api/sync/")) {
    if (isSyncRequestAuthorized(request)) return NextResponse.next();
    return authRequired();
  }

  if (isAuthCookieValid(request)) return NextResponse.next();

  // Browser Local Mode: permit page shells and strictly stateless external proxies,
  // while keeping all cloud database `/api/*` endpoints behind password auth.
  if (hasLocalModeCookie(request)) {
    if (LOCAL_STATELESS_API_PATHS.has(pathname) && isSameSiteStatelessRelayAllowed(request)) {
      return NextResponse.next();
    }
    if (pathname.startsWith("/api/")) return authRequired();
    return NextResponse.next();
  }

  if (pathname.startsWith("/api/")) return authRequired();
  return redirectToLogin(request);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
