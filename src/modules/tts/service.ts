import { WebSocket } from "ws";
import {
  generateSecMsGecToken,
  TRUSTED_CLIENT_TOKEN,
  CHROMIUM_FULL_VERSION,
} from "node-edge-tts/dist/drm.js";
import { ttsCacheGet, ttsCacheKey, ttsCacheSet } from "./cache";

const VOICE_MAP: Record<string, string> = {
  US: "en-US-JennyNeural",
  UK: "en-GB-SoniaNeural",
};

interface TtsOptions {
  word: string;
  accent?: string;
}

export type TtsResult =
  | { ok: true; audio: ArrayBuffer }
  | { ok: false; error: string };

function generateId(): string {
  return crypto.randomUUID().replace(/-/g, "");
}

function escapeXml(unsafe: string): string {
  return unsafe.replace(/[<>&"']/g, (c) => {
    switch (c) {
      case "<": return "&lt;";
      case ">": return "&gt;";
      case "&": return "&amp;";
      case '"': return "&quot;";
      case "'": return "&apos;";
      default: return c;
    }
  });
}

function buildSsml(text: string, voice: string): string {
  const requestId = generateId();
  return [
    `X-RequestId:${requestId}`,
    "Content-Type:application/ssml+xml",
    "Path:ssml",
    "",
    `<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="https://www.w3.org/2001/mstts" xml:lang="en-US">`,
    `<voice name="${voice}">`,
    `<prosody rate="default" pitch="default" volume="default">`,
    escapeXml(text),
    "</prosody>",
    "</voice>",
    "</speak>",
  ].join("\r\n");
}

function buildSpeechConfig(): string {
  const config = JSON.stringify({
    context: {
      synthesis: {
        audio: {
          metadataoptions: {
            sentenceBoundaryEnabled: false,
            wordBoundaryEnabled: false,
          },
          outputFormat: "audio-24khz-48kbitrate-mono-mp3",
        },
      },
    },
  });
  return [
    "Content-Type:application/json; charset=utf-8",
    "Path:speech.config",
    "",
    config,
  ].join("\r\n");
}

function synthesize(text: string, voice: string): Promise<Buffer> {
  const secMsGec = generateSecMsGecToken();
  const chromiumMajor = CHROMIUM_FULL_VERSION.split(".")[0];
  const wsUrl = [
    "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1",
    `?TrustedClientToken=${TRUSTED_CLIENT_TOKEN}`,
    `&Sec-MS-GEC=${secMsGec}`,
    `&Sec-MS-GEC-Version=1-${CHROMIUM_FULL_VERSION}`,
    `&ConnectionId=${generateId()}`,
  ].join("");

  return new Promise((resolve, reject) => {
    const audioChunks: Buffer[] = [];
    let settled = false;

    const ws = new WebSocket(wsUrl, {
      host: "speech.platform.bing.com",
      origin: "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
      headers: {
        "User-Agent": `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${chromiumMajor}.0.0.0 Safari/537.36 Edg/${chromiumMajor}.0.0.0`,
        "Pragma": "no-cache",
        "Cache-Control": "no-cache",
        "Accept-Encoding": "gzip, deflate, br",
        "Accept-Language": "en-US,en;q=0.9",
      },
    });

    const finish = (err?: Error) => {
      if (settled) return;
      settled = true;
      ws.close();
      if (err) reject(err);
      else resolve(Buffer.concat(audioChunks));
    };

    ws.on("open", () => {
      ws.send(buildSpeechConfig());
      ws.send(buildSsml(text, voice));
    });

    ws.on("message", (rawData, isBinary) => {
      if (settled) return;

      if (!isBinary) {
        const message = rawData.toString("utf-8");
        if (message.includes("Path:turn.end")) {
          finish();
        }
        return;
      }

      const data = rawData as Buffer;
      const separator = "Path:audio\r\n";
      const separatorIndex = data.indexOf(separator);
      if (separatorIndex !== -1) {
        const audioContent = data.subarray(separatorIndex + separator.length);
        if (audioContent.length > 0) {
          audioChunks.push(audioContent);
        }
      }
    });

    ws.on("error", (err) => {
      finish(new Error(`WebSocket 连接失败: ${err.message}`));
    });

    ws.on("close", (code) => {
      if (!settled) {
        finish(new Error(
          code === 1006
            ? "WebSocket 连接异常关闭，可能是网络问题"
            : `WebSocket 连接意外关闭 (code: ${code})`,
        ));
      }
    });

    setTimeout(() => finish(new Error("Edge TTS 请求超时")), 15000);
  });
}

export async function generateTtsAudio(options: TtsOptions): Promise<TtsResult> {
  const accent = (options.accent ?? "US") as keyof typeof VOICE_MAP;
  const voice = VOICE_MAP[accent] || "en-US-JennyNeural";
  const cacheKey = ttsCacheKey(options.word, accent);

  const cached = ttsCacheGet(cacheKey);
  if (cached) return { ok: true, audio: cached };

  try {
    const buffer = await synthesize(options.word, voice);

    if (!buffer || buffer.byteLength === 0) {
      return { ok: false, error: "Edge TTS 服务返回了空数据" };
    }

    const arrayBuffer = buffer.buffer.slice(
      buffer.byteOffset,
      buffer.byteOffset + buffer.byteLength,
    ) as ArrayBuffer;
    ttsCacheSet(cacheKey, arrayBuffer);
    return { ok: true, audio: arrayBuffer };
  } catch (err) {
    const message = err instanceof Error ? err.message : "Edge TTS 请求失败";
    return { ok: false, error: message };
  }
}

const YOUDAO_ACCENT_TYPE: Record<string, number> = { UK: 1, US: 2 };

export async function fetchYoudaoAudio(options: TtsOptions): Promise<TtsResult> {
  const accent = (options.accent ?? "US").trim().toUpperCase() === "UK" ? "UK" : "US";
  const cacheKey = `youdao:${ttsCacheKey(options.word, accent)}`;

  const cached = ttsCacheGet(cacheKey);
  if (cached) return { ok: true, audio: cached };

  try {
    const url = `https://dict.youdao.com/dictvoice?audio=${encodeURIComponent(options.word)}&type=${YOUDAO_ACCENT_TYPE[accent]}`;
    const response = await fetch(url, {
      signal: AbortSignal.timeout(10_000),
      headers: { "user-agent": "Mozilla/5.0 LexiLoop", accept: "audio/mpeg,*/*" },
    });

    if (!response.ok) {
      return { ok: false, error: `有道发音返回 ${response.status}` };
    }

    const arrayBuffer = await response.arrayBuffer();
    if (!arrayBuffer || arrayBuffer.byteLength === 0) {
      return { ok: false, error: "有道发音返回空数据" };
    }

    ttsCacheSet(cacheKey, arrayBuffer);
    return { ok: true, audio: arrayBuffer };
  } catch (err) {
    const message = err instanceof Error ? err.message : "有道发音请求失败";
    return { ok: false, error: message };
  }
}
