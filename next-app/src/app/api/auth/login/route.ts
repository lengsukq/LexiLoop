import { NextRequest } from "next/server";
import { z } from "zod";
import { fail, internalError, ok } from "@/lib/api";
import { isPasswordCorrect, isPasswordEnabled, setAuthCookie } from "@/lib/security";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const loginSchema = z.object({ password: z.string() });

export async function POST(request: NextRequest) {
  if (!isPasswordEnabled()) return ok({ authenticated: true });

  try {
    const input = loginSchema.parse(await request.json());
    if (!isPasswordCorrect(input.password)) return fail("INVALID_PASSWORD", "密码不正确，请重试。", 401);

    const response = ok({ authenticated: true });
    setAuthCookie(response, request);
    return response;
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "请输入登录密码。", 400, error.issues);
    return internalError(error, "登录失败，请稍后重试。");
  }
}
