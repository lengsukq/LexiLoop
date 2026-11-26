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

function timeoutFor(entryType: string): number {
  return entryType === "WORD" ? 8000 : 10000;
}

function jitterMs(): number {
  return 120 + Math.floor(Math.random() * 280);
}

function shouldRetryOnce(attempt: YoudaoAttempt): boolean {
  if (attempt.errorCode === "TIMEOUT" || attempt.errorCode === "NETWORK_ERROR") return true;
  return false;
}

function scoreContent(content: DictionaryContent, input: LookupInput): number {
  if (satisfiesRequestedFields(content, input)) return 1000;
  if (!hasAnyContent(content)) return 0;
  let score = 0;
  score += content.definitions.length * 5;
  score += content.examples.length * 3;
  score += content.phrases.length * 2;
  score += content.pronunciations.length * 4;
  score += content.synonyms.length;
  score += content.wordFamily.length;
  if (content.summary?.translation) score += 8;
  if (content.summary?.shortDefinition) score += 4;
  return score;
}

export class YoudaoProvider implements DictionaryProvider {
  readonly id = "youdao";
  supports(input: LookupInput): boolean {
    return ["WORD", "PHRASE", "SENTENCE"].includes(input.entryType) && input.sourceLanguage.toLowerCase().startsWith("en");
  }
  async lookup(input: LookupInput) {
    const primary = input.entryType === "WORD" ? ENDPOINTS[0]! : ENDPOINTS[1]!;
    const secondary = input.entryType === "WORD" ? ENDPOINTS[1]! : ENDPOINTS[0]!;

    const results = await Promise.all([
      lookupEndpointWithRetry(primary, input),
      lookupEndpointWithRetry(secondary, input),
    ]);

    const attempts: YoudaoAttempt[] = results.flatMap((r) => r.attempts);
    const candidates: Array<{ endpoint: YoudaoEndpoint["id"]; content: DictionaryContent }> = [];
    for (const r of results) {
      if (r.content && hasAnyContent(r.content)) candidates.push({ endpoint: r.endpoint, content: r.content as DictionaryContent });
    }

    if (!candidates.length) {
      const failures = attempts.filter((a) => a.status === "FAILED");
      const allEmpty = attempts.length > 0 && failures.length === 0;
      return {
        content: null,
        errorCode: allEmpty ? "NOT_FOUND" : "ALL_ENDPOINTS_FAILED",
        errorMessage: allEmpty ? "有道词典的主页面和备用页面都没有返回可解析的词条内容" : attempts.map((a) => `${a.endpoint}: ${a.errorCode ?? a.status}${a.errorMessage ? ` (${a.errorMessage})` : ""}`).join("; "),
        transient: failures.some(isTransientAttempt),
        metadata: { fallbackUsed: true, endpointAttempts: attempts },
      };
    }

    // 择优：优先满足 requestedFields，其次按字段完整度打分
    candidates.sort((a, b) => scoreContent(b.content, input) - scoreContent(a.content, input));
    const best = candidates[0]!;
    const merged = candidates.length > 1 ? mergeDictionaryContent(candidates[0]!.content, candidates[1]!.content) : best.content;

    // 若任一候选满足请求字段，直接返回最饱满的合并结果；否则也返回合并后最饱满结果
    const finalContent = merged;
    const fallbackUsed = candidates.length > 1 || best.endpoint !== primary.id;
    return { content: finalContent, metadata: { sourceEndpoint: best.endpoint, fallbackUsed, endpointAttempts: attempts } };
  }
}

async function lookupEndpointWithRetry(
  endpoint: YoudaoEndpoint,
  input: LookupInput,
): Promise<{ endpoint: YoudaoEndpoint["id"]; content: Partial<DictionaryContent> | null; attempts: YoudaoAttempt[] }> {
  const first = await lookupEndpoint(endpoint, input);
  if (first.content) return { endpoint: endpoint.id, content: first.content, attempts: [first.attempt] };
  if (!shouldRetryOnce(first.attempt)) return { endpoint: endpoint.id, content: null, attempts: [first.attempt] };
  await new Promise<void>((resolve) => setTimeout(resolve, jitterMs()));
  const second = await lookupEndpoint(endpoint, input);
  return { endpoint: endpoint.id, content: second.content, attempts: [first.attempt, second.attempt] };
}

async function lookupEndpoint(endpoint: YoudaoEndpoint, input: LookupInput): Promise<{ content: Partial<DictionaryContent> | null; attempt: YoudaoAttempt }> {
  try {
    const response = await fetch(endpoint.buildUrl(input.term), { redirect: "follow", signal: AbortSignal.timeout(timeoutFor(input.entryType)), headers: { accept: "text/html,application/xhtml+xml", "accept-language": "zh-CN,zh;q=0.9,en;q=0.8", "cache-control": "no-cache", "user-agent": "Mozilla/5.0 LexiLoop" } });
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
