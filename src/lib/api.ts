import { NextResponse } from "next/server";

export function ok<T>(data: T, init?: ResponseInit) {
  return NextResponse.json({ success: true, data }, init);
}

export function fail(code: string, message: string, status = 400, details?: unknown) {
  return NextResponse.json(
    { success: false, error: { code, message, ...(details === undefined ? {} : { details }) } },
    { status },
  );
}

export function internalError(error: unknown, message = "服务器处理请求时发生错误。") {
  console.error(error);
  return fail("INTERNAL_ERROR", message, 500);
}

export function authRequired() {
  return fail("AUTH_REQUIRED", "请先输入登录密码。", 401);
}

export function parsePositiveInt(value: string | null, fallback: number, max = 500): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback;
  return Math.min(parsed, max);
}
