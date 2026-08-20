/** Extract a user-facing message from an unknown catch reason, with a fallback. */
export function errorMessage(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}

/** Format a duration in milliseconds as a compact `m:ss` clock string. */
export function formatClockTime(ms: number): string {
  const seconds = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
