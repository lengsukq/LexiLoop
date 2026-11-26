import { NextResponse } from "next/server";
import { z } from "zod";

/** 业务错误码 → 默认文案与 HTTP 状态码。服务层抛 `new ApiError(code)` 即获得默认行为，路由可传自定义文案覆盖。 */
const ERROR_MESSAGES: Record<string, { message: string; status: number }> = {
  // 通用
  VALIDATION_ERROR: { message: "参数无效。", status: 400 },
  WORD_ID_INVALID: { message: "词条 ID 无效。", status: 400 },
  JOB_ID_INVALID: { message: "任务 ID 无效。", status: 400 },
  JOB_NOT_FOUND: { message: "任务不存在。", status: 404 },
  IMPORT_BATCH_ID_INVALID: { message: "导入批次 ID 无效。", status: 400 },
  // 词条
  WORD_NOT_FOUND: { message: "词条不存在。", status: 404 },
  WORD_NOT_READY: { message: "词条尚未初始化完成。", status: 409 },
  WORD_SUSPENDED: { message: "词条已暂停学习。", status: 409 },
  WORD_HAS_LEARNING_HISTORY: { message: "该词条已有学习记录，不能硬删除。请改为暂停学习，或使用 ?force=true 强制删除。", status: 409 },
  TERM_REQUIRED: { message: "词条文本不能为空。", status: 400 },
  TERM_TOO_LONG: { message: "词条文本过长。", status: 400 },
  TERM_ALREADY_EXISTS: { message: "已存在相同词条，无法修改为该文本。", status: 409 },
  RELATED_WORD_SAME_AS_PARENT: { message: "不能把当前词条再次加入词库。", status: 409 },
  EXAMPLE_NOT_FOUND: { message: "例句不存在。", status: 404 },
  // 学习 / 复习
  SESSION_NOT_FOUND: { message: "学习会话不存在。", status: 404 },
  STUDY_ITEM_NOT_FOUND: { message: "学习题目不存在。", status: 404 },
  STUDY_ITEM_ALREADY_PROCESSED: { message: "该题目已经处理，不能重复操作。", status: 409 },
  STUDY_ITEM_WORD_MISMATCH: { message: "提交的词条与学习题目不匹配。", status: 409 },
  STUDY_ITEM_QUESTION_MISMATCH: { message: "提交的题型与学习题目不匹配。", status: 409 },
  INVALID_STUDY_CONTEXT: { message: "学习会话和题目参数必须同时提供。", status: 409 },
  IDEMPOTENCY_KEY_CONFLICT: { message: "该答案请求标识已被其他提交使用。", status: 409 },
  AI_RECOMMENDED_ALL_DONE: { message: "今日 AI 必做题已全部完成，明天再来吧。", status: 409 },
  // 游戏 / 配对 / 发音
  NOT_ENOUGH_GAME_WORDS: { message: "至少需要 4 个带有效释义的可学习词条。", status: 409 },
  NOT_ENOUGH_MATCHING_WORDS: { message: "至少需要 4 个带释义且不重复的可学习词条。", status: 409 },
  NOT_ENOUGH_PHONETIC_WORDS: { message: "至少需要 4 个带有对应音标的可学习单词。请先在初始化页补齐音标。", status: 409 },
  GAME_SESSION_NOT_FOUND: { message: "小游戏会话不存在或已经失效。", status: 404 },
  MATCH_SESSION_NOT_FOUND: { message: "配对会话不存在或已经失效。", status: 404 },
  PHONETIC_SESSION_NOT_FOUND: { message: "音标训练会话不存在或已经失效。", status: 404 },
  PRACTICE_SESSION_NOT_FOUND: { message: "练习会话不存在或已经失效。", status: 404 },
  // 导入
  IMPORT_PREVIEW_EXPIRED: { message: "导入预览已过期，请重新上传。", status: 409 },
  // AI 辅助
  AI_DISABLED: { message: "该 AI 功能未启用。", status: 409 },
  AI_CONFIG_INCOMPLETE: { message: "AI 服务配置不完整，请到设置页补全。", status: 409 },
  AI_EMPTY_RESPONSE: { message: "AI 没有返回有效内容，请重试或更换模型。", status: 422 },
  AI_RESPONSE_INVALID: { message: "AI 返回的内容格式无效，请重试或更换模型。", status: 422 },
  AI_MNEMONIC_LANGUAGE_INVALID: { message: "AI 生成的助记词不是中文。", status: 400 },
  AI_REQUEST_FAILED: { message: "AI 服务请求失败。", status: 502 },
};

/**
 * 业务错误：带机器可读 `code`、HTTP `status` 与面向用户的 `message`。
 * 服务层抛此错误，路由统一用 `handleRouteError` 转为失败响应，避免靠 `error.message` 字符串判错。
 */
export class ApiError extends Error {
  readonly code: string;
  readonly status: number;
  readonly details?: unknown;

  constructor(code: string, message?: string, status?: number, details?: unknown) {
    const preset = ERROR_MESSAGES[code] ?? { message: code, status: 400 };
    super(message ?? preset.message);
    this.name = "ApiError";
    this.code = code;
    this.status = status ?? preset.status;
    this.details = details;
  }
}

export function ok<T>(data: T, init?: ResponseInit) {
  return NextResponse.json({ success: true, data }, init);
}

export function fail(code: string, message?: string, status?: number, details?: unknown) {
  const preset = ERROR_MESSAGES[code];
  return NextResponse.json(
    { success: false, error: { code, message: message ?? preset?.message ?? code, ...(details === undefined ? {} : { details }) } },
    { status: status ?? preset?.status ?? 400 },
  );
}

export interface RouteErrorOptions {
  /** 未匹配到业务错误时的兜底文案（服务端 500）。 */
  fallbackMessage?: string;
  /** zod 参数校验错误文案（默认「参数无效。」）。 */
  validationMessage?: string;
}

/** 路由统一错误出口：ApiError → 对应失败响应；zod 校验 → VALIDATION_ERROR；其余 → 500。 */
export function handleRouteError(error: unknown, options: RouteErrorOptions = {}): NextResponse {
  if (error instanceof ApiError) return fail(error.code, error.message, error.status, error.details);
  if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", options.validationMessage, 400, error.issues);
  return internalError(error, options.fallbackMessage ?? "服务器处理请求时发生错误。");
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

/**
 * 解析并校验路径中的数字 ID；无效（非正整数，含 `1.5` 这类非整数）时抛 ApiError，
 * 由外层 `handleRouteError` 统一返回失败信封。
 */
export function requireRouteId(id: string, code = "INVALID_ID", message?: string): number {
  const value = Number(id);
  if (!Number.isInteger(value) || value <= 0) throw new ApiError(code, message, 400);
  return value;
}
