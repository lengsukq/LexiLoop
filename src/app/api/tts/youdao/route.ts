import { NextRequest } from "next/server";
import { fetchYoudaoAudio } from "@/modules/tts/service";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: NextRequest) {
  const word = request.nextUrl.searchParams.get("word");
  const accent = request.nextUrl.searchParams.get("accent") ?? "US";

  if (!word) {
    return new Response(JSON.stringify({ error: "缺少 'word' 参数" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const result = await fetchYoudaoAudio({ word, accent });

    if (!result.ok) {
      return new Response(JSON.stringify({ error: result.error }), {
        status: 502,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(result.audio, {
      status: 200,
      headers: {
        "Content-Type": "audio/mpeg",
        "Cache-Control": "public, max-age=86400",
      },
    });
  } catch {
    return new Response(JSON.stringify({ error: "有道发音获取异常，请检查网络连接。" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}
