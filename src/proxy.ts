import { NextRequest, NextResponse } from "next/server";
import { authRequired } from "@/lib/api";
import { isAuthCookieValid, isPasswordEnabled } from "@/lib/security";

const PUBLIC_PATHS = new Set(["/login", "/api/auth/login", "/api/health"]);

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

  if (isAuthCookieValid(request)) return NextResponse.next();
  if (pathname.startsWith("/api/")) return authRequired();
  return redirectToLogin(request);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico).*)"],
};
