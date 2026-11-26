import { hmacSha256Hex, hmacSha256Raw, sha256Hex } from "@/lib/iso-crypto";

export interface TencentTranslateConfig {
  secretId: string;
  secretKey: string;
  projectId: number;
}

const ENDPOINT = "tmt.tencentcloudapi.com";
const SERVICE = "tmt";
const VERSION = "2018-03-21";
const TIMEOUT_MS = 8_000;

/** Map internal language codes to Tencent TMT language codes. */
function mapLanguage(lang: string): string {
  const lower = lang.toLowerCase();
  if (lower === "zh-cn" || lower === "zh" || lower === "zh-hans") return "zh";
  if (lower === "zh-tw" || lower === "zh-hant") return "zh-TW";
  if (lower === "en" || lower === "english") return "en";
  if (lower === "ja" || lower === "japanese") return "ja";
  if (lower === "ko" || lower === "korean") return "ko";
  if (lower === "fr" || lower === "french") return "fr";
  if (lower === "de" || lower === "german") return "de";
  if (lower === "es" || lower === "spanish") return "es";
  if (lower === "ru" || lower === "russian") return "ru";
  if (lower === "pt" || lower === "portuguese") return "pt";
  if (lower === "it" || lower === "italian") return "it";
  if (lower === "ar" || lower === "arabic") return "ar";
  if (lower === "th" || lower === "thai") return "th";
  if (lower === "vi" || lower === "vietnamese") return "vi";
  return lower;
}

export class TencentTranslateError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number,
  ) {
    super(message);
  }
}

async function callViaBrowserProxy(
  text: string,
  source: string,
  target: string,
  config: TencentTranslateConfig,
): Promise<string> {
  const response = await fetch("/api/local-proxy/tencent-translate", {
    method: "POST",
    signal: AbortSignal.timeout(TIMEOUT_MS + 2_000),
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      text,
      source,
      target,
      secretId: config.secretId,
      secretKey: config.secretKey,
      projectId: config.projectId,
    }),
  });
  const body = await response.json().catch(() => null) as {
    success?: boolean;
    data?: { translation?: string };
    error?: { code?: string; message?: string };
  } | null;

  if (!response.ok || !body?.success) {
    throw new TencentTranslateError(
      body?.error?.code ?? `HTTP_${response.status}`,
      body?.error?.message ?? `HTTP ${response.status}`,
      response.status,
    );
  }
  const translation = body.data?.translation;
  if (typeof translation !== "string" || !translation.trim()) {
    throw new TencentTranslateError("EMPTY_RESULT", "腾讯翻译未返回翻译结果。", 422);
  }
  return translation;
}

/**
 * Call Tencent Cloud TMT TextTranslate API with TC3-HMAC-SHA256 signing.
 * In browser Local Mode, delegates to the stateless `/api/local-proxy/tencent-translate` relay.
 */
export async function tencentTranslateText(
  text: string,
  source: string,
  target: string,
  config: TencentTranslateConfig,
): Promise<string> {
  if (typeof window !== "undefined" && typeof document !== "undefined") {
    return callViaBrowserProxy(text, source, target, config);
  }

  const payload = JSON.stringify({
    SourceText: text,
    Source: mapLanguage(source),
    Target: mapLanguage(target),
    ProjectId: config.projectId,
  });

  const timestamp = Math.floor(Date.now() / 1000);
  const date = new Date(timestamp * 1000).toISOString().slice(0, 10);

  // Step 1: Canonical request
  const httpRequestMethod = "POST";
  const canonicalUri = "/";
  const canonicalQueryString = "";
  const canonicalHeaders = `content-type:application/json\nhost:${ENDPOINT}\n`;
  const signedHeaders = "content-type;host";
  const hashedPayload = await sha256Hex(payload);
  const canonicalRequest = [
    httpRequestMethod,
    canonicalUri,
    canonicalQueryString,
    canonicalHeaders,
    signedHeaders,
    hashedPayload,
  ].join("\n");

  // Step 2: String to sign
  const algorithm = "TC3-HMAC-SHA256";
  const credentialScope = `${date}/${SERVICE}/tc3_request`;
  const stringToSign = [
    algorithm,
    String(timestamp),
    credentialScope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  // Step 3: Signing key chain
  const secretDate = await hmacSha256Raw(`TC3${config.secretKey}`, date);
  const secretService = await hmacSha256Raw(secretDate, SERVICE);
  const secretSigning = await hmacSha256Raw(secretService, "tc3_request");
  const signature = await hmacSha256Hex(secretSigning, stringToSign);

  // Step 4: Authorization header
  const authorization = `${algorithm} Credential=${config.secretId}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

  const response = await fetch(`https://${ENDPOINT}`, {
    method: "POST",
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: {
      "Content-Type": "application/json",
      Authorization: authorization,
      "X-TC-Action": "TextTranslate",
      "X-TC-Version": VERSION,
      "X-TC-Timestamp": String(timestamp),
      "X-TC-Region": "ap-guangzhou",
    },
    body: payload,
  });

  const rawBody = await response.text().catch(() => "");
  let body: Record<string, unknown> | null = null;
  try {
    body = JSON.parse(rawBody) as Record<string, unknown>;
  } catch { /* handled below */ }

  if (!response.ok) {
    const errorObj = body?.Response as Record<string, unknown> | undefined;
    const errorInfo = errorObj?.Error as Record<string, unknown> | undefined;
    const message = errorInfo?.Message ? String(errorInfo.Message) : `HTTP ${response.status}`;
    const code = errorInfo?.Code ? String(errorInfo.Code) : `HTTP_${response.status}`;
    throw new TencentTranslateError(code, message, response.status);
  }

  const resp = body?.Response as Record<string, unknown> | undefined;
  if (!resp) throw new TencentTranslateError("INVALID_RESPONSE", "腾讯翻译返回格式无效。", 422);

  const error = resp.Error as Record<string, unknown> | undefined;
  if (error) {
    const code = String(error.Code ?? "UNKNOWN");
    const message = String(error.Message ?? "腾讯翻译接口错误");
    const status = code.includes("LimitExceeded") || code.includes("RequestLimitExceeded") ? 429 : 400;
    throw new TencentTranslateError(code, message, status);
  }

  const targetText = resp.TargetText;
  if (typeof targetText !== "string" || !targetText.trim()) {
    throw new TencentTranslateError("EMPTY_RESULT", "腾讯翻译未返回翻译结果。", 422);
  }

  return targetText;
}

/**
 * Translate multiple items using Tencent TMT.
 * Calls the API sequentially for each item (TMT does not support batch in a single request).
 */
export async function tencentTranslateBatch(
  items: Array<{ index: number; sentence: string }>,
  source: string,
  target: string,
  config: TencentTranslateConfig,
): Promise<Map<number, string>> {
  const results = new Map<number, string>();
  for (const item of items) {
    try {
      const translated = await tencentTranslateText(item.sentence, source, target, config);
      results.set(item.index, translated);
    } catch (error) {
      if (error instanceof TencentTranslateError && error.status === 429) {
        throw error; // propagate rate limit
      }
    }
  }
  return results;
}
