import type { DictionaryContent, LookupInput } from "@/lib/types";
import type { DictionaryProvider } from "../provider";
import { hasAnyIcibaContent, parseIcibaHtml } from "./iciba-parser";

const SUPPORTED_FIELDS = new Set([
  "definitions", "pronunciations.phonetic", "pronunciations.audio",
  "examples", "phrases", "forms", "synonyms", "antonyms", "wordFamily", "roots", "affixes", "summary", "tags",
]);

export class IcibaProvider implements DictionaryProvider {
  readonly id = "iciba";
  supports(input: LookupInput): boolean {
    return ["WORD", "PHRASE"].includes(input.entryType) && input.sourceLanguage.toLowerCase().startsWith("en");
  }

  async lookup(input: LookupInput): Promise<{ content: Partial<DictionaryContent> | null; errorCode?: string; errorMessage?: string; transient?: boolean }> {
    if (!SUPPORTED_FIELDS.size) return { content: null, errorCode: "NOT_SUPPORTED", errorMessage: "iciba provider不提供任何字段" };
    try {
      const url = `https://www.iciba.com/word?w=${encodeURIComponent(input.term.trim())}`;
      const response = await fetch(url, {
        redirect: "follow",
        signal: AbortSignal.timeout(10_000),
        headers: {
          accept: "text/html,application/xhtml+xml",
          "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
          "cache-control": "no-cache",
          "user-agent": "Mozilla/5.0 LexiLoop",
        },
      });
      if (!response.ok) {
        const transient = response.status >= 500;
        return { content: null, errorCode: `HTTP_${response.status}`, errorMessage: `金山词霸页面返回 ${response.status}`, transient };
      }
      const html = await response.text();
      const content = parseIcibaHtml(html, { term: input.term, targetLanguage: input.targetLanguage });
      if (!content || !hasAnyIcibaContent(content)) {
        return {
          content: null,
          errorCode: html.trim() ? "UNPARSABLE_RESPONSE" : "EMPTY_RESPONSE",
          errorMessage: html.trim() ? "页面存在内容，但未解析出金山词霸词条字段" : "金山词霸页面内容为空",
        };
      }
      return { content };
    } catch (error) {
      const timeout = error instanceof Error && (error.name === "TimeoutError" || error.name === "AbortError");
      return {
        content: null,
        errorCode: timeout ? "TIMEOUT" : "NETWORK_ERROR",
        errorMessage: error instanceof Error ? error.message : String(error),
        transient: timeout || (error instanceof Error && error.message.includes("fetch")),
      };
    }
  }
}
