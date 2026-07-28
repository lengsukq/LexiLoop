export const DAY_MS = 24 * 60 * 60 * 1000;
const TIMEZONE = process.env.APP_TIMEZONE ?? "Asia/Shanghai";

export function suggestionDateKey(timestamp: number): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(timestamp));
}

export function previousSuggestionDateKey(now: number): string {
  return suggestionDateKey(now - DAY_MS);
}
