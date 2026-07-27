export async function apiFetch<T>(input: RequestInfo | URL, init?: RequestInit): Promise<T> {
  const response = await fetch(input, { ...init, headers: { ...(init?.headers ?? {}), accept: "application/json" }, cache: "no-store" });
  const payload = await response.json().catch(() => null) as { success?: boolean; data?: T; error?: { message?: string } } | null;
  if (!response.ok || !payload?.success) throw new Error(payload?.error?.message ?? `请求失败：HTTP ${response.status}`);
  return payload.data as T;
}

export function formatDate(value: string | null | undefined, options?: Intl.DateTimeFormatOptions): string {
  if (!value) return "—";
  return new Intl.DateTimeFormat("zh-CN", options ?? { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
