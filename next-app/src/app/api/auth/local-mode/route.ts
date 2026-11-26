import { NextRequest } from "next/server";
import { z } from "zod";
import { handleRouteError, ok } from "@/lib/api";
import { setLocalModeCookie } from "@/lib/security";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const schema = z.object({
  enabled: z.boolean().default(true),
});

export async function POST(request: NextRequest) {
  try {
    const body = await request.json().catch(() => ({}));
    const input = schema.parse(body);
    const response = ok({ mode: input.enabled ? "local" : "cloud" });
    setLocalModeCookie(response, request, input.enabled);
    return response;
  } catch (error) {
    return handleRouteError(error, {
      validationMessage: "模式参数无效。",
      fallbackMessage: "切换本地模式失败。",
    });
  }
}

export async function DELETE(request: NextRequest) {
  const response = ok({ mode: "cloud" });
  setLocalModeCookie(response, request, false);
  return response;
}
