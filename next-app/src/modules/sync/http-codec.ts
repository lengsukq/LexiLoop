import { gunzipSync, gzipSync } from "node:zlib";
import { NextResponse } from "next/server";
import { ApiError } from "@/lib/api";
import { MAX_DECOMPRESSED_PUSH_BYTES } from "./types";

const GZIP_MAGIC_0 = 0x1f;
const GZIP_MAGIC_1 = 0x8b;

function isGzipBuffer(buf: Buffer): boolean {
  return buf.length >= 2 && buf[0] === GZIP_MAGIC_0 && buf[1] === GZIP_MAGIC_1;
}

/**
 * Reads a JSON request body that may be plain UTF-8 JSON or GZip-compressed
 * (`Content-Encoding: gzip` or GZip magic header), enforcing a strict decompressed size cap.
 */
export async function readJsonRequestMaybeGzip(request: Request): Promise<unknown> {
  const arrayBuffer = await request.arrayBuffer();
  const rawBuffer = Buffer.from(arrayBuffer);
  if (rawBuffer.length === 0) return {};

  const encoding = (request.headers.get("content-encoding") ?? "").toLowerCase();
  const shouldGunzip = encoding.includes("gzip") || isGzipBuffer(rawBuffer);

  let utf8Buffer: Buffer;
  if (shouldGunzip) {
    try {
      utf8Buffer = gunzipSync(rawBuffer, { maxOutputLength: MAX_DECOMPRESSED_PUSH_BYTES });
    } catch (error) {
      const code = (error as { code?: string } | null)?.code;
      if (code === "ERR_BUFFER_TOO_LARGE") {
        throw new ApiError("SYNC_PAYLOAD_TOO_LARGE", "解压后的同步分片超过体积上限。", 413);
      }
      throw new ApiError("SYNC_INVALID_PAYLOAD", "GZip 同步载荷解压失败。", 400);
    }
  } else {
    if (rawBuffer.length > MAX_DECOMPRESSED_PUSH_BYTES) {
      throw new ApiError("SYNC_PAYLOAD_TOO_LARGE", "同步分片体积超过上限。", 413);
    }
    utf8Buffer = rawBuffer;
  }

  try {
    return JSON.parse(utf8Buffer.toString("utf8")) as unknown;
  } catch {
    throw new ApiError("SYNC_INVALID_PAYLOAD", "同步载荷不是有效的 JSON。", 400);
  }
}

/**
 * Serializes a `{ success: true, data }` JSON response, compressing with GZip
 * when the client signals `Accept-Encoding: gzip`.
 */
export function okMaybeGzip<T>(request: Request, data: T): NextResponse {
  const jsonText = JSON.stringify({ success: true, data });
  const accept = (request.headers.get("accept-encoding") ?? "").toLowerCase();
  if (!accept.includes("gzip")) {
    return new NextResponse(jsonText, {
      status: 200,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  }

  const compressed = gzipSync(Buffer.from(jsonText, "utf8"));
  return new NextResponse(compressed, {
    status: 200,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Encoding": "gzip",
      "Vary": "Accept-Encoding",
      "Cache-Control": "no-store",
    },
  });
}
