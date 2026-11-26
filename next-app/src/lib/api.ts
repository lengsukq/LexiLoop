import { NextResponse } from "next/server";
import {
  ApiError,
  ERROR_MESSAGES,
  parsePositiveInt,
  requireRouteId,
  resolveFailPayload,
  resolveRouteError,
} from "@/lib/api-errors";

export { ApiError, ERROR_MESSAGES, parsePositiveInt, requireRouteId };

export function ok<T>(data: T, init?: ResponseInit) {
  return NextResponse.json({ success: true, data }, init);
}

export function fail(code: string, message?: string, status?: number, details?: unknown) {
  const { status: resolvedStatus, body } = resolveFailPayload(code, message, status, details);
  return NextResponse.json(body, { status: resolvedStatus });
}

export interface RouteErrorOptions {
  /** 未匹配到业务错误时的兜底文案（服务端 500）。 */
  fallbackMessage?: string;
  /** zod 参数校验错误文案（默认「参数无效。」）。 */
  validationMessage?: string;
}

/** 路由统一错误出口：ApiError → 对应失败响应；zod 校验 → VALIDATION_ERROR；其余 → 500。 */
export function handleRouteError(error: unknown, options: RouteErrorOptions = {}): NextResponse {
  const { status, body } = resolveRouteError(error, options);
  return NextResponse.json(body, { status });
}

export function internalError(error: unknown, message = "服务器处理请求时发生错误。") {
  console.error(error);
  return fail("INTERNAL_ERROR", message, 500);
}

export function authRequired() {
  return fail("AUTH_REQUIRED", "请先输入登录密码。", 401);
}
