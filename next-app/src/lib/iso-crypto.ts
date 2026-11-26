/**
 * Browser/Node isomorphic Web Crypto & UTF-8 helpers so shared modules in
 * `src/modules/**` can bundle cleanly for client-side Local Browser Mode.
 */

function requireCrypto(): Crypto {
  if (typeof globalThis.crypto === "undefined") {
    throw new Error("Web Crypto API is unavailable in this runtime.");
  }
  return globalThis.crypto;
}

function bytesToHex(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i += 1) {
    out += bytes[i]!.toString(16).padStart(2, "0");
  }
  return out;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

export function randomUuid(): string {
  const cryptoApi = requireCrypto();
  if (typeof cryptoApi.randomUUID === "function") {
    return cryptoApi.randomUUID();
  }
  const bytes = new Uint8Array(16);
  cryptoApi.getRandomValues(bytes);
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  const hex = bytesToHex(bytes);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function randomHexToken(length = 16): string {
  const bytes = new Uint8Array(Math.ceil(length / 2));
  requireCrypto().getRandomValues(bytes);
  return bytesToHex(bytes).slice(0, length);
}

export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await requireCrypto().subtle.digest("SHA-256", toArrayBuffer(data));
  return bytesToHex(new Uint8Array(digest));
}

export async function hmacSha256Raw(key: string | Uint8Array, data: string): Promise<Uint8Array> {
  const encoder = new TextEncoder();
  const keyBytes = typeof key === "string" ? encoder.encode(key) : key;
  const subtle = requireCrypto().subtle;
  const cryptoKey = await subtle.importKey(
    "raw",
    toArrayBuffer(keyBytes),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await subtle.sign("HMAC", cryptoKey, toArrayBuffer(encoder.encode(data)));
  return new Uint8Array(sig);
}

export async function hmacSha256Hex(key: string | Uint8Array, data: string): Promise<string> {
  return bytesToHex(await hmacSha256Raw(key, data));
}

export function utf8ByteLength(text: string): number {
  return new TextEncoder().encode(text).byteLength;
}
