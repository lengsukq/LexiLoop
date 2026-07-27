import type { NextRequest } from "next/server";

export function isAdminAuthorized(request: NextRequest): boolean {
  const expected = process.env.LEXILOOP_ADMIN_TOKEN;
  if (!expected) return true;
  const supplied = request.headers.get("x-lexiloop-admin-token") ?? request.nextUrl.searchParams.get("token");
  return supplied === expected;
}
