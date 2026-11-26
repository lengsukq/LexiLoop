const DB_NAME = "lexiloop-client-cache";
const DB_VERSION = 1;
const STORE_NAME = "tts-audio";

interface CachedTtsAudio {
  key: string;
  blob: Blob;
  cachedAt: number;
}

let databasePromise: Promise<IDBDatabase | null> | null = null;
const pendingAudio = new Map<string, Promise<Blob | null>>();
let activeAudio: HTMLAudioElement | null = null;
let activeObjectUrl: string | null = null;

export interface TtsPreloadItem {
  text: string;
  accent?: string;
}

export type TtsCategory = "word" | "phrase" | "sentence";

export interface TtsSpeedConfig {
  word: number;
  phrase: number;
  sentence: number;
}

let speedConfig: TtsSpeedConfig | null = null;
let speedFetchPromise: Promise<void> | null = null;

/** Manually set per-category playback speeds (e.g. after saving settings). */
export function configureTtsSpeeds(speeds: TtsSpeedConfig): void {
  speedConfig = { ...speeds };
}

/** Invalidate cached speeds so the next playback re-fetches from the server. */
export function invalidateTtsSpeeds(): void {
  speedConfig = null;
  speedFetchPromise = null;
}

async function ensureSpeedConfig(): Promise<void> {
  if (speedConfig) return;
  if (!speedFetchPromise) {
    speedFetchPromise = (async () => {
      try {
        const response = await fetch("/api/settings", { headers: { accept: "application/json" }, cache: "no-store" });
        if (!response.ok) return;
        const payload = await response.json().catch(() => null) as { success?: boolean; data?: { wordSpeed?: number; phraseSpeed?: number; sentenceSpeed?: number } } | null;
        const data = payload?.success ? payload.data : null;
        speedConfig = {
          word: typeof data?.wordSpeed === "number" ? data.wordSpeed : 1,
          phrase: typeof data?.phraseSpeed === "number" ? data.phraseSpeed : 1,
          sentence: typeof data?.sentenceSpeed === "number" ? data.sentenceSpeed : 1,
        };
      } catch {
        // Network failures fall back to normal speed.
      }
    })();
  }
  await speedFetchPromise;
}

async function resolveSpeed(category: TtsCategory): Promise<number> {
  await ensureSpeedConfig();
  const rate = speedConfig?.[category];
  return typeof rate === "number" && rate > 0 ? rate : 1;
}

/** Map a word entry type to its TTS playback category. */
export function entryTypeToTtsCategory(entryType: string): TtsCategory {
  if (entryType === "SENTENCE") return "sentence";
  if (entryType === "PHRASE") return "phrase";
  return "word";
}

function normalizeAccent(accent: string): string {
  const normalized = accent.trim().toUpperCase();
  return normalized === "UK" ? normalized : "US";
}

function audioCacheKey(term: string, accent: string): string {
  const normalizedTerm = term.trim().normalize("NFKC").toLocaleLowerCase("en-US");
  return `v1:${normalizeAccent(accent)}:${normalizedTerm}`;
}

function openAudioDatabase(): Promise<IDBDatabase | null> {
  if (typeof window === "undefined" || typeof window.indexedDB === "undefined") {
    return Promise.resolve(null);
  }
  if (databasePromise) return databasePromise;

  databasePromise = new Promise((resolve) => {
    const request = window.indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(STORE_NAME)) {
        database.createObjectStore(STORE_NAME, { keyPath: "key" });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => resolve(null);
    request.onblocked = () => resolve(null);
  });

  return databasePromise;
}

async function readCachedAudio(key: string): Promise<Blob | null> {
  const database = await openAudioDatabase();
  if (!database) return null;

  return new Promise((resolve) => {
    const transaction = database.transaction(STORE_NAME, "readonly");
    const request = transaction.objectStore(STORE_NAME).get(key);
    request.onsuccess = () => {
      const record = request.result as CachedTtsAudio | undefined;
      resolve(record?.blob instanceof Blob && record.blob.size > 0 ? record.blob : null);
    };
    request.onerror = () => resolve(null);
    transaction.onabort = () => resolve(null);
  });
}

async function writeCachedAudio(key: string, blob: Blob): Promise<void> {
  const database = await openAudioDatabase();
  if (!database) return;

  await new Promise<void>((resolve) => {
    const transaction = database.transaction(STORE_NAME, "readwrite");
    transaction.objectStore(STORE_NAME).put({ key, blob, cachedAt: Date.now() } satisfies CachedTtsAudio);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => resolve();
    transaction.onabort = () => resolve();
  });
}

async function fetchAndCacheAudio(key: string, url: string): Promise<Blob | null> {
  const cached = await readCachedAudio(key);
  if (cached) return cached;

  const existingRequest = pendingAudio.get(key);
  if (existingRequest) return existingRequest;

  const request = (async () => {
    try {
      const response = await fetch(url);
      if (!response.ok) return null;

      const blob = await response.blob();
      if (blob.size === 0) return null;
      await writeCachedAudio(key, blob);
      return blob;
    } catch {
      return null;
    } finally {
      pendingAudio.delete(key);
    }
  })();

  pendingAudio.set(key, request);
  return request;
}

async function loadTtsAudio(term: string, accent: string): Promise<Blob | null> {
  const normalizedAccent = normalizeAccent(accent);
  const key = audioCacheKey(term, normalizedAccent);
  return fetchAndCacheAudio(key, `/api/tts?word=${encodeURIComponent(term)}&accent=${encodeURIComponent(normalizedAccent)}`);
}

async function loadYoudaoAudio(term: string, accent: string): Promise<Blob | null> {
  const normalizedAccent = normalizeAccent(accent);
  const normalizedTerm = term.trim().normalize("NFKC").toLocaleLowerCase("en-US");
  if (!normalizedTerm) return null;
  const key = `youdao:v1:${normalizedAccent}:${normalizedTerm}`;
  return fetchAndCacheAudio(key, `/api/tts/youdao?word=${encodeURIComponent(term)}&accent=${encodeURIComponent(normalizedAccent)}`);
}

export async function preloadTts(text: string, accent = "US"): Promise<boolean> {
  if (!text.trim()) return false;
  try {
    return Boolean(await loadTtsAudio(text, accent));
  } catch {
    return false;
  }
}

export async function preloadTtsBatch(items: readonly TtsPreloadItem[], maxConcurrent = 2): Promise<void> {
  const uniqueItems = new Map<string, TtsPreloadItem>();
  for (const item of items) {
    if (!item.text.trim()) continue;
    const normalizedAccent = normalizeAccent(item.accent ?? "US");
    uniqueItems.set(audioCacheKey(item.text, normalizedAccent), { text: item.text, accent: normalizedAccent });
  }

  const queue = [...uniqueItems.values()];
  if (queue.length === 0) return;
  const workerCount = Math.min(Math.max(1, Math.floor(maxConcurrent) || 1), queue.length);
  let cursor = 0;

  await Promise.all(Array.from({ length: workerCount }, async () => {
    while (cursor < queue.length) {
      const item = queue[cursor];
      cursor += 1;
      if (item) await preloadTts(item.text, item.accent);
    }
  }));
}

function stopActiveAudio(): void {
  if (activeAudio) {
    activeAudio.pause();
    activeAudio.src = "";
    activeAudio = null;
  }
  if (activeObjectUrl) {
    URL.revokeObjectURL(activeObjectUrl);
    activeObjectUrl = null;
  }
}

async function playBlob(blob: Blob, playbackRate: number): Promise<boolean> {
  stopActiveAudio();
  const objectUrl = URL.createObjectURL(blob);
  const audio = new Audio(objectUrl);
  activeAudio = audio;
  activeObjectUrl = objectUrl;
  audio.playbackRate = playbackRate;

  const release = () => {
    if (activeAudio === audio) stopActiveAudio();
  };
  audio.addEventListener("ended", release, { once: true });
  audio.addEventListener("error", release, { once: true });

  try {
    await audio.play();
    return true;
  } catch {
    release();
    return false;
  }
}

export async function playCachedTts(term: string, accent = "US", category: TtsCategory = "word"): Promise<boolean> {
  const [blob, playbackRate] = await Promise.all([loadTtsAudio(term, accent), resolveSpeed(category)]);
  if (!blob) return false;
  return playBlob(blob, playbackRate);
}

/**
 * Playback helper that prefers Youdao real-human audio when `preferYoudao`
 * is true, falling back to Edge TTS if the Youdao audio is unavailable.
 */
export async function playEntryTtsPreferYoudao(term: string, entryType: string, accent = "US", preferYoudao = false): Promise<boolean> {
  const playbackRate = await resolveSpeed(entryTypeToTtsCategory(entryType));
  let blob = preferYoudao ? await loadYoudaoAudio(term, accent) : null;
  if (!blob) blob = await loadTtsAudio(term, accent);
  if (!blob) return false;
  return playBlob(blob, playbackRate);
}

/**
 * Generic playback helper: resolves the TTS category from the entry type
 * (WORD / PHRASE / SENTENCE) and plays with the configured per-category speed.
 */
export async function playEntryTts(term: string, entryType: string, accent = "US"): Promise<boolean> {
  return playCachedTts(term, accent, entryTypeToTtsCategory(entryType));
}
