import { DAY_MS } from "@/lib/time";

const TIMEZONE = (typeof process !== "undefined" ? process.env?.APP_TIMEZONE : undefined) ?? "Asia/Shanghai";
const dateKeyFormatter = new Intl.DateTimeFormat("en-CA", {
  timeZone: TIMEZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** 本地时区日期键，形如 "2026-08-08"。 */
export function dateKey(timestamp: number): string {
  return dateKeyFormatter.format(new Date(timestamp));
}

/** 本地时区当天零点的时间戳。 */
export function startOfLocalDay(timestamp: number): number {
  const [year, month, day] = dateKey(timestamp).split("-").map(Number);
  return new Date(year ?? 0, (month ?? 1) - 1, day ?? 1).getTime();
}

/** 前一天（按 DAY_MS 回退）的日期键。 */
export function previousDateKey(now: number): string {
  return dateKey(now - DAY_MS);
}

/** 本地时区的日序数（自 1970-01-01 起的天数），用于跨日间隔计算。 */
export function localDayOrdinal(timestamp: number): number {
  const parts = dateKeyFormatter.formatToParts(new Date(timestamp));
  const year = Number(parts.find((part) => part.type === "year")?.value ?? 0);
  const month = Number(parts.find((part) => part.type === "month")?.value ?? 1);
  const day = Number(parts.find((part) => part.type === "day")?.value ?? 1);
  return Math.floor(Date.UTC(year, month - 1, day) / DAY_MS);
}
