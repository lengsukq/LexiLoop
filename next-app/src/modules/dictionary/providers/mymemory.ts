import type { DictionaryProvider } from "../provider";
import { fetchDictionaryUpstream } from "../proxy-fetch";
import type { LookupInput } from "@/lib/types";

interface MyMemoryResponse {
  responseStatus?: number;
  responseDetails?: string;
  responseData?: { translatedText?: string; match?: number };
  matches?: Array<{ translation?: string; match?: number }>;
}

const SUPPORTED = new Set(["en", "zh-CN", "zh-TW", "nl", "ja", "ko", "fr", "de", "es", "it", "pt", "ru"]);

export class MyMemoryProvider implements DictionaryProvider {
  readonly id = "mymemory";
  supports(input: LookupInput) { return SUPPORTED.has(input.sourceLanguage) && SUPPORTED.has(input.targetLanguage); }

  async lookup(input: LookupInput) {
    try {
      const url = new URL("https://api.mymemory.translated.net/get");
      url.searchParams.set("q", input.term);
      url.searchParams.set("langpair", `${input.sourceLanguage}|${input.targetLanguage}`);
      const response = await fetchDictionaryUpstream(
        {
          target: "mymemory",
          term: input.term,
          sourceLanguage: input.sourceLanguage,
          targetLanguage: input.targetLanguage,
          timeoutMs: 8_000,
        },
        () => fetch(url, { signal: AbortSignal.timeout(8_000), headers: { "user-agent": "LexiLoop/1.0" } }),
      );
      if (response.status === 429) return { content: null, errorCode: "RATE_LIMITED", errorMessage: "翻译服务限流", transient: true };
      if (!response.ok) return { content: null, errorCode: `HTTP_${response.status}`, errorMessage: `翻译服务返回 ${response.status}`, transient: response.status >= 500 };
      const data = await response.json() as MyMemoryResponse;
      const primary = data.responseData?.translatedText?.trim();
      if (!primary || primary.toLocaleLowerCase() === input.term.toLocaleLowerCase()) {
        return { content: null, errorCode: "EMPTY_RESULT", errorMessage: data.responseDetails ?? "没有可用翻译" };
      }
      const values = [primary, ...(data.matches ?? []).filter((item) => (item.match ?? 0) >= 0.85).map((item) => item.translation?.trim()).filter((item): item is string => Boolean(item))];
      const unique = [...new Set(values)].slice(0, 4);
      return {
        content: {
          definitions: unique.map((text) => ({ language: input.targetLanguage, partOfSpeech: null, text, source: this.id, isUserEdited: false })),
        },
      };
    } catch (error) {
      const timeout = error instanceof DOMException && error.name === "TimeoutError";
      return { content: null, errorCode: timeout ? "TIMEOUT" : "NETWORK_ERROR", errorMessage: String(error), transient: true };
    }
  }
}
