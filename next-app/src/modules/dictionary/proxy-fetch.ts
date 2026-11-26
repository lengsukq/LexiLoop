export type DictionaryProxyTarget =
  | "youdao-dict"
  | "youdao-result"
  | "iciba"
  | "dictionaryapi"
  | "mymemory"
  | "merriam-webster";

export interface DictionaryProxyPayload {
  target: DictionaryProxyTarget;
  term: string;
  sourceLanguage?: string;
  targetLanguage?: string;
  reference?: "collegiate" | "thesaurus";
  apiKey?: string;
  timeoutMs?: number;
}

/**
 * Fetches upstream dictionary resources directly on the server, or routes
 * through `/api/local-proxy/dictionary` when executing inside Local Browser Mode.
 */
export async function fetchDictionaryUpstream(
  payload: DictionaryProxyPayload,
  directFetch: () => Promise<Response>,
): Promise<Response> {
  if (typeof window === "undefined" || typeof document === "undefined") {
    return directFetch();
  }

  const response = await fetch("/api/local-proxy/dictionary", {
    method: "POST",
    signal: AbortSignal.timeout((payload.timeoutMs ?? 10_000) + 2_000),
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify(payload),
  });

  const wrapped = await response.json().catch(() => null) as {
    success?: boolean;
    data?: { status?: number; contentType?: string; body?: string };
    error?: { message?: string };
  } | null;

  if (!response.ok || !wrapped?.success || !wrapped.data) {
    throw new Error(wrapped?.error?.message ?? `词典代理返回 HTTP ${response.status}`);
  }

  return new Response(wrapped.data.body ?? "", {
    status: wrapped.data.status ?? 502,
    headers: { "content-type": wrapped.data.contentType ?? "text/plain; charset=utf-8" },
  });
}
