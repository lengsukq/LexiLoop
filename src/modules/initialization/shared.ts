import { sqlite } from "@/db/client";
import type { InitializationStatus } from "@/lib/types";
import { contentStatus, dictionaryContentFromRow } from "@/modules/dictionary/content";

export function parseStringArray<T extends string>(value: unknown): T[] {
  if (!value) return [];
  try {
    const parsed = typeof value === "string" ? JSON.parse(value) : value;
    return Array.isArray(parsed) ? parsed.filter((item): item is T => typeof item === "string") : [];
  } catch {
    return [];
  }
}

export function uniqueOrdered<T extends string>(...groups: Array<readonly T[] | undefined>): T[] {
  return [...new Set(groups.flatMap((group) => group ?? []))];
}

export function maxAttemptsFromSettings(): number {
  try {
    const row = sqlite.prepare("SELECT value_json FROM settings WHERE key = 'aiRetryCount'").get() as {
      value_json: string;
    } | undefined;
    const retryCount = row ? Number(JSON.parse(row.value_json)) : 1;
    return Math.max(1, Math.min(6, (Number.isInteger(retryCount) ? retryCount : 1) + 1));
  } catch {
    return 2;
  }
}

function usableContentStatus(wordId: number): InitializationStatus | null {
  const row = sqlite.prepare(`SELECT wc.*, w.content_type FROM word_contents wc
    JOIN words w ON w.id = wc.word_id WHERE wc.word_id = ?`).get(wordId) as Record<string, unknown> | undefined;
  if (!row) return null;
  const status = contentStatus(dictionaryContentFromRow(row), String(row.content_type ?? "WORD") as import("@/lib/types").EntryType);
  return status === "FAILED" ? null : status;
}

export function setWordOperationalStatus(wordId: number, requestedStatus: InitializationStatus, now: number): void {
  const fallback = usableContentStatus(wordId);
  sqlite.prepare("UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?")
    .run(fallback ?? requestedStatus, now, wordId);
}
