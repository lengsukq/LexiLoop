import type { DictionaryContent, LookupInput } from "@/lib/types";
import type { DictionaryProvider } from "../provider";
import { mergeDictionaryContent } from "../content";
import { hasAnyContent, parseYoudaoHtml } from "./youdao-parser";

type YoudaoEndpoint = { id: "dict.youdao.com" | "youdao.com/result"; buildUrl: (term: string) => URL };
type YoudaoAttempt = { endpoint: YoudaoEndpoint["id"]; status: "SUCCESS" | "EMPTY" | "FAILED"; statusCode?: number; errorCode?: string; errorMessage?: string };
const ENDPOINTS: YoudaoEndpoint[] = [
  { id: "dict.youdao.com", buildUrl: (term) => new URL(`https://dict.youdao.com/w/eng/${encodeURIComponent(term)}`) },
  { id: "youdao.com/result", buildUrl: (term) => { const url = new URL("https://www.youdao.com/result"); url.searchParams.set("word", term); url.searchParams.set("lang", "en"); return url; } },
];
const SUPPORTED_FIELDS = new Set([
  "definitions", "pronunciations.phonetic", "pronunciations.audio",
  "examples", "phrases", "forms", "synonyms", "antonyms", "wordFamily", "roots", "affixes", "summary", "tags",
]);

export class YoudaoProvider implements DictionaryProvider {
  readonly id = "youdao";
  supports(input: LookupInput): boolean {
    return ["WORD", "PHRASE", "SENTENCE"].includes(input.entryType) && input.sourceLanguage.toLowerCase().startsWith("en");
  }
  async lookup(input: LookupInput) {
    const endpoints = input.entryType === "WORD" ? ENDPOINTS : [ENDPOINTS[1]!, ENDPOINTS[0]!];
    const attempts: YoudaoAttempt[] = []; let accumulated: DictionaryContent | null = null; let successful: YoudaoEndpoint["id"] | null = null;
    for (const endpoint of endpoints) {
      const result = await lookupEndpoint(endpoint, input); attempts.push(result.attempt); if (!result.content) continue;
      successful = endpoint.id; accumulated = mergeDictionaryContent(accumulated, result.content);
      if (satisfiesRequestedFields(accumulated, input)) return { content: accumulated, metadata: { sourceEndpoint: endpoint.id, fallbackUsed: endpoint.id !== endpoints[0]!.id, endpointAttempts: attempts } };
    }
    if (accumulated && hasAnyContent(accumulated)) return { content: accumulated, metadata: { sourceEndpoint: successful ?? undefined, fallbackUsed: attempts.length > 1, endpointAttempts: attempts } };
    const failures = attempts.filter((attempt) => attempt.status === "FAILED"); const allEmpty = attempts.length > 0 && failures.length === 0;
    return { content: null, errorCode: allEmpty ? "NOT_FOUND" : "ALL_ENDPOINTS_FAILED", errorMessage: allEmpty ? "有道词典的主页面和备用页面都没有返回可解析的词条内容" : attempts.map((attempt) => `${attempt.endpoint}: ${attempt.errorCode ?? attempt.status}${attempt.errorMessage ? ` (${attempt.errorMessage})` : ""}`).join("; "), transient: failures.some(isTransientAttempt), metadata: { fallbackUsed: attempts.length > 1, endpointAttempts: attempts } };
  }
}

async function lookupEndpoint(endpoint: YoudaoEndpoint, input: LookupInput): Promise<{ content: Partial<DictionaryContent> | null; attempt: YoudaoAttempt }> {
  try {
    const response = await fetch(endpoint.buildUrl(input.term), { redirect: "follow", signal: AbortSignal.timeout(10_000), headers: { accept: "text/html,application/xhtml+xml", "accept-language": "zh-CN,zh;q=0.9,en;q=0.8", "cache-control": "no-cache", "user-agent": "Mozilla/5.0 LexiLoop" } });
    if (!response.ok) return { content: null, attempt: { endpoint: endpoint.id, status: "FAILED", statusCode: response.status, errorCode: `HTTP_${response.status}`, errorMessage: `页面返回 ${response.status}` } };
    const html = await response.text(); const content = parseYoudaoHtml(html, { term: input.term, entryType: input.entryType, targetLanguage: input.targetLanguage });
    if (!content || !hasAnyContent(content)) return { content: null, attempt: { endpoint: endpoint.id, status: "EMPTY", statusCode: response.status, errorCode: html.trim() ? "UNPARSABLE_RESPONSE" : "EMPTY_RESPONSE", errorMessage: html.trim() ? "页面存在内容，但未解析出词典字段" : "页面内容为空" } };
    return { content, attempt: { endpoint: endpoint.id, status: "SUCCESS", statusCode: response.status } };
  } catch (error) {
    const timeout = error instanceof Error && (error.name === "TimeoutError" || error.name === "AbortError");
    return { content: null, attempt: { endpoint: endpoint.id, status: "FAILED", errorCode: timeout ? "TIMEOUT" : "NETWORK_ERROR", errorMessage: error instanceof Error ? error.message : String(error) } };
  }
}
function satisfiesRequestedFields(content: DictionaryContent, input: LookupInput): boolean {
  const requested = (input.requestedFields ?? []).filter((field) => SUPPORTED_FIELDS.has(field));
  if (!requested.length) {
    if (input.entryType === "SENTENCE") return Boolean(content.summary.translation || content.definitions.length || content.examples.length);
    if (input.entryType === "PHRASE") return Boolean(content.definitions.length || content.phrases.length);
    return content.definitions.length > 0 || content.pronunciations.length > 0;
  }
  return requested.every((field) => {
    if (field === "definitions") return content.definitions.length > 0;
    if (field === "pronunciations.phonetic" || field === "pronunciations.audio") return content.pronunciations.some((item) => Boolean(item.phonetic));
    if (field === "summary") return Boolean(content.summary.translation || content.summary.shortDefinition);
    if (field === "synonyms") return content.synonyms.length > 0;
    if (field === "antonyms") return content.antonyms.length > 0;
    if (field === "wordFamily") return content.wordFamily.length > 0;
    if (field === "roots") return content.roots.length > 0;
    if (field === "affixes") return content.affixes.length > 0;
    if (field === "tags") return content.tags.length > 0;
    return content[field === "examples" ? "examples" : field === "phrases" ? "phrases" : "forms"].length > 0;
  });
}
function isTransientAttempt(attempt: YoudaoAttempt): boolean { return attempt.errorCode === "TIMEOUT" || attempt.errorCode === "NETWORK_ERROR" || Boolean(attempt.statusCode && attempt.statusCode >= 500); }
