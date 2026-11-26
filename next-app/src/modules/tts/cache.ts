const MAX_CACHE_SIZE = 200;
const cache = new Map<string, ArrayBuffer>();

export function ttsCacheKey(word: string, accent: string): string {
  return `${accent}:${word.toLowerCase()}`;
}

export function ttsCacheGet(key: string): ArrayBuffer | undefined {
  const value = cache.get(key);
  if (value !== undefined) {
    cache.delete(key);
    cache.set(key, value);
  }
  return value;
}

export function ttsCacheSet(key: string, value: ArrayBuffer): void {
  if (cache.has(key)) cache.delete(key);
  else if (cache.size >= MAX_CACHE_SIZE) {
    const oldest = cache.keys().next().value;
    if (oldest !== undefined) cache.delete(oldest);
  }
  cache.set(key, value);
}
