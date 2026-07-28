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

function normalizeAccent(accent: string): string {
  const normalized = accent.trim().toUpperCase();
  return normalized === "UK" || normalized === "GENERAL" ? normalized : "US";
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

async function loadTtsAudio(term: string, accent: string): Promise<Blob | null> {
  const normalizedAccent = normalizeAccent(accent);
  const key = audioCacheKey(term, normalizedAccent);
  const cached = await readCachedAudio(key);
  if (cached) return cached;

  const existingRequest = pendingAudio.get(key);
  if (existingRequest) return existingRequest;

  const request = (async () => {
    try {
      const response = await fetch(`/api/tts?word=${encodeURIComponent(term)}&accent=${encodeURIComponent(normalizedAccent)}`);
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

export async function playCachedTts(term: string, accent = "US"): Promise<boolean> {
  const blob = await loadTtsAudio(term, accent);
  if (!blob) return false;

  stopActiveAudio();
  const objectUrl = URL.createObjectURL(blob);
  const audio = new Audio(objectUrl);
  activeAudio = audio;
  activeObjectUrl = objectUrl;
  audio.playbackRate = 1;

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
