import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { getSettings, updateSettings } from "@/modules/settings/service";
import { z } from "zod";
export const dynamic = "force-dynamic";
export async function GET() { try { return ok(await getSettings()); } catch (error) { return internalError(error, "获取设置失败。"); } }
export async function PUT(request: NextRequest) { try { return ok(await updateSettings(await request.json())); } catch (error) { if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "设置参数无效。", 400, error.issues); return internalError(error, "保存设置失败。"); } }
