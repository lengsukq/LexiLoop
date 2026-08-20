import { type NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { handleRouteError, ok, requireRouteId } from "@/lib/api";

export interface CompleteHandlerOptions<T extends z.ZodObject<z.ZodRawShape>> {
  schema: T;
  /** 用 `{ sessionId, ...解析后的入参 }` 调用业务层完成逻辑。 */
  complete: (args: { sessionId: number } & z.infer<T>) => Promise<unknown>;
  idErrorMessage: string;
  validationMessage: string;
  fallbackMessage: string;
}

/**
 * 统一 `sessions/[id]/complete` 类路由：解析路径 ID、校验 zod 入参、调业务层、用 `ok`/`handleRouteError` 收敛响应。
 * 消除 games / match / phonetics 三处逐字重复的样板。
 */
export function createCompleteHandler<T extends z.ZodObject<z.ZodRawShape>>(options: CompleteHandlerOptions<T>) {
  return async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }): Promise<NextResponse> {
    try {
      const sessionId = requireRouteId((await context.params).id, "VALIDATION_ERROR", options.idErrorMessage);
      const input = options.schema.parse(await request.json());
      return ok(await options.complete({ sessionId, ...input }));
    } catch (error) {
      return handleRouteError(error, { validationMessage: options.validationMessage, fallbackMessage: options.fallbackMessage });
    }
  };
}
