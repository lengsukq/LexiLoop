import { afterEach, describe, expect, it, vi } from "vitest";
import { preloadTts, preloadTtsBatch } from "@/lib/tts-client";

function audioResponse(): Response {
  return new Response(new Blob(["audio"]), { status: 200, headers: { "Content-Type": "audio/mpeg" } });
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("TTS preload", () => {
  it("loads audio without creating or playing an Audio element", async () => {
    const fetchMock = vi.fn().mockResolvedValue(audioResponse());
    const audioMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    vi.stubGlobal("Audio", audioMock);

    await expect(preloadTts("hello", "US")).resolves.toBe(true);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(audioMock).not.toHaveBeenCalled();
  });

  it("deduplicates concurrent requests for the same text and accent", async () => {
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const fetchMock = vi.fn().mockImplementation(async () => {
      await gate;
      return audioResponse();
    });
    vi.stubGlobal("fetch", fetchMock);

    const first = preloadTts("hello", "US");
    const second = preloadTts(" hello ", "us");
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    release();

    await expect(Promise.all([first, second])).resolves.toEqual([true, true]);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("limits batch concurrency and skips empty or duplicate items", async () => {
    let inFlight = 0;
    let maxInFlight = 0;
    const fetchMock = vi.fn().mockImplementation(async () => {
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await new Promise((resolve) => setTimeout(resolve, 0));
      inFlight -= 1;
      return audioResponse();
    });
    vi.stubGlobal("fetch", fetchMock);

    await preloadTtsBatch([
      { text: "one", accent: "US" },
      { text: "two", accent: "US" },
      { text: "three", accent: "US" },
      { text: "one", accent: "us" },
      { text: "  " },
    ]);

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(maxInFlight).toBeLessThanOrEqual(2);
  });

  it("does not permanently block a later retry after a preload failure", async () => {
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new Error("network unavailable"))
      .mockResolvedValueOnce(audioResponse());
    vi.stubGlobal("fetch", fetchMock);

    await expect(preloadTts("retry me")).resolves.toBe(false);
    await expect(preloadTts("retry me")).resolves.toBe(true);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
