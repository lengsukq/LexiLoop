import { isLocalModeActive } from "@/lib/app-mode";

const SERVER_ONLY_PREFIXES = [
  "/api/auth/",
  "/api/tts",
  "/api/local-proxy/",
];

const SERVER_ONLY_EXACT = new Set([
  "/api/settings/models",
  "/api/settings/test-provider",
  "/api/settings/test-tencent-translate",
]);

function shouldHandleLocally(url: URL): boolean {
  if (typeof window === "undefined") return false;
  if (!isLocalModeActive()) return false;
  if (url.origin !== window.location.origin) return false;
  if (!url.pathname.startsWith("/api/")) return false;
  if (SERVER_ONLY_EXACT.has(url.pathname)) return false;
  if (SERVER_ONLY_PREFIXES.some((prefix) => url.pathname.startsWith(prefix))) return false;
  // Remote cloud sync explicitly uses raw fetch / remote-sync options, never apiFetch.
  if (url.pathname.startsWith("/api/sync/")) return false;
  return true;
}

export async function apiFetch<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  if (typeof window !== "undefined") {
    const rawUrl = typeof input === "string"
      ? input
      : input instanceof URL
        ? input.toString()
        : input.url;
    const parsed = new URL(rawUrl, window.location.origin);
    if (shouldHandleLocally(parsed)) {
      const { dispatchLocalApi } = await import("@/local/local-router");
      return dispatchLocalApi<T>(parsed, init);
    }
  }

  const response = await fetch(input, { ...init, headers: { ...(init?.headers ?? {}), accept: "application/json" }, cache: "no-store" });
  const payload = await response.json().catch(() => null) as { success?: boolean; data?: T; error?: { code?: string; message?: string } } | null;
  if (response.status === 401 && payload?.error?.code === "AUTH_REQUIRED" && typeof window !== "undefined" && window.location.pathname !== "/login") {
    const next = `${window.location.pathname}${window.location.search}${window.location.hash}`;
    window.location.assign(`/login?next=${encodeURIComponent(next)}`);
  }
  if (!response.ok || !payload?.success) throw new Error(payload?.error?.message ?? `请求失败：HTTP ${response.status}`);
  return payload.data as T;
}

export function formatDate(value: string | null | undefined, options?: Intl.DateTimeFormatOptions): string {
  if (!value) return "—";
  return new Intl.DateTimeFormat("zh-CN", options ?? { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
