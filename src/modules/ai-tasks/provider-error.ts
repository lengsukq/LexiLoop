/**
 * Keep upstream gateway pages out of task records and user-facing toasts.
 * Reverse proxies frequently return an HTML error document for 5xx responses;
 * that document is diagnostic noise rather than a useful AI error message.
 */
export function formatAiProviderError(status: number, rawBody: string): string {
  const body = rawBody.trim();
  const isHtml = /<!doctype\s+html|<html\b|<body\b/i.test(body);

  if (isHtml || [502, 503, 504].includes(status)) {
    return `AI 服务暂时不可用（上游网关返回 ${status}）。任务会按设置自动重试；若仍失败，请稍后重试或在设置中检查 AI Provider。`;
  }

  const detail = body.replace(/\s+/g, " ").slice(0, 200);
  return detail
    ? `AI 服务请求失败（${status}）：${detail}`
    : `AI 服务请求失败（${status}）。`;
}
