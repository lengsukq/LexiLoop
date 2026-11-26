export type AppMode = "cloud" | "local";

export const LOCAL_MODE_COOKIE_NAME = "lexiloop_mode";
export const LOCAL_MODE_COOKIE_VALUE = "local";
export const LOCAL_MODE_STORAGE_KEY = "lexiloop:mode";
export const APP_MODE_CHANGE_EVENT = "lexiloop:mode-changed";

const COOKIE_MAX_AGE_SECONDS = 365 * 24 * 60 * 60;

function readCookieValue(name: string): string | null {
  if (typeof document === "undefined") return null;
  const prefix = `${name}=`;
  for (const part of document.cookie.split(";")) {
    const trimmed = part.trim();
    if (trimmed.startsWith(prefix)) {
      return decodeURIComponent(trimmed.slice(prefix.length));
    }
  }
  return null;
}

function writeModeCookie(value: string | null): void {
  if (typeof document === "undefined") return;
  const secure = window.location.protocol === "https:" ? "; Secure" : "";
  if (value) {
    document.cookie = `${LOCAL_MODE_COOKIE_NAME}=${encodeURIComponent(value)}; Path=/; Max-Age=${COOKIE_MAX_AGE_SECONDS}; SameSite=Lax${secure}`;
  } else {
    document.cookie = `${LOCAL_MODE_COOKIE_NAME}=; Path=/; Max-Age=0; SameSite=Lax${secure}`;
  }
}

export function readAppMode(): AppMode {
  if (typeof window === "undefined") return "cloud";
  const cookieValue = readCookieValue(LOCAL_MODE_COOKIE_NAME);
  if (cookieValue === LOCAL_MODE_COOKIE_VALUE) return "local";
  if (cookieValue === "cloud") return "cloud";
  try {
    return window.localStorage.getItem(LOCAL_MODE_STORAGE_KEY) === LOCAL_MODE_COOKIE_VALUE
      ? "local"
      : "cloud";
  } catch {
    return "cloud";
  }
}

export function isLocalModeActive(): boolean {
  return readAppMode() === "local";
}

/** Syncs cookie & localStorage on client boot if one persisted while the other drifted. */
export function syncAppModeStorage(): AppMode {
  if (typeof window === "undefined") return "cloud";
  const cookieValue = readCookieValue(LOCAL_MODE_COOKIE_NAME);
  let stored: string | null = null;
  try {
    stored = window.localStorage.getItem(LOCAL_MODE_STORAGE_KEY);
  } catch {
    stored = null;
  }

  if (cookieValue === LOCAL_MODE_COOKIE_VALUE && stored !== LOCAL_MODE_COOKIE_VALUE) {
    try {
      window.localStorage.setItem(LOCAL_MODE_STORAGE_KEY, LOCAL_MODE_COOKIE_VALUE);
    } catch { /* ignore storage quota */ }
    return "local";
  }

  if (!cookieValue && stored === LOCAL_MODE_COOKIE_VALUE) {
    writeModeCookie(LOCAL_MODE_COOKIE_VALUE);
    return "local";
  }

  return cookieValue === LOCAL_MODE_COOKIE_VALUE ? "local" : "cloud";
}

export function setLocalModeClient(): void {
  if (typeof window === "undefined") return;
  writeModeCookie(LOCAL_MODE_COOKIE_VALUE);
  try {
    window.localStorage.setItem(LOCAL_MODE_STORAGE_KEY, LOCAL_MODE_COOKIE_VALUE);
  } catch { /* ignore */ }
  window.dispatchEvent(new CustomEvent(APP_MODE_CHANGE_EVENT, { detail: "local" }));
}

export function clearLocalModeClient(): void {
  if (typeof window === "undefined") return;
  writeModeCookie(null);
  try {
    window.localStorage.removeItem(LOCAL_MODE_STORAGE_KEY);
  } catch { /* ignore */ }
  window.dispatchEvent(new CustomEvent(APP_MODE_CHANGE_EVENT, { detail: "cloud" }));
}
