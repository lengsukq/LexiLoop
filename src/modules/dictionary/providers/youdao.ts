import type { DictionaryContent, LookupInput } from "@/lib/types";
import type { DictionaryProvider } from "../provider";
import { mergeDictionaryContent } from "../content";

type YoudaoEndpoint = {
  id: "dict.youdao.com" | "youdao.com/result";
  buildUrl: (term: string) => URL;
};

type YoudaoEndpointAttempt = {
  endpoint: YoudaoEndpoint["id"];
  status: "SUCCESS" | "EMPTY" | "FAILED";
  statusCode?: number;
  errorCode?: string;
  errorMessage?: string;
};

const YOUDAO_ENDPOINTS: YoudaoEndpoint[] = [
  {
    id: "dict.youdao.com",
    buildUrl: (term) => new URL(`https://dict.youdao.com/w/eng/${encodeURIComponent(term)}`),
  },
  {
    id: "youdao.com/result",
    buildUrl: (term) => {
      const url = new URL("https://www.youdao.com/result");
      url.searchParams.set("word", term);
      url.searchParams.set("lang", "en");
      return url;
    },
  },
];

const YOUDAO_SUPPORTED_FIELDS = new Set([
  "definitions",
  "pronunciations.phonetic",
  "examples",
  "phrases",
  "forms",
]);

/**
 * 有道词典网页端 Provider
 *
 * 依次解析 dict.youdao.com 与 youdao.com/result 页面 HTML，无需 API 密钥。
 * 提取音标、词性、释义、例句、短语、词形变化等数据。
 */
export class YoudaoProvider implements DictionaryProvider {
  readonly id = "youdao";

  supports(input: LookupInput): boolean {
    return input.entryType === "WORD" && input.sourceLanguage.toLowerCase().startsWith("en");
  }

  async lookup(input: LookupInput) {
    const endpointAttempts: YoudaoEndpointAttempt[] = [];
    let accumulated: DictionaryContent | null = null;
    let successfulEndpoint: YoudaoEndpoint["id"] | null = null;

    for (const endpoint of YOUDAO_ENDPOINTS) {
      const result = await lookupEndpoint(endpoint, input.term);
      endpointAttempts.push(result.attempt);

      if (!result.content) continue;

      successfulEndpoint = endpoint.id;
      accumulated = mergeDictionaryContent(accumulated, result.content);

      // The primary endpoint is sufficient only when it returned every requested
      // field that this provider is capable of supplying. Otherwise continue to
      // the fallback endpoint and merge any missing data it can provide.
      if (satisfiesRequestedFields(accumulated, input)) {
        return {
          content: accumulated,
          metadata: {
            sourceEndpoint: endpoint.id,
            fallbackUsed: endpoint.id !== YOUDAO_ENDPOINTS[0]!.id,
            endpointAttempts,
          },
        };
      }
    }

    // A partially parsed response is still useful. The pipeline will project it
    // to the requested fields and can continue with the next Provider if needed.
    if (accumulated && hasAnyContent(accumulated)) {
      return {
        content: accumulated,
        metadata: {
          sourceEndpoint: successfulEndpoint ?? undefined,
          fallbackUsed: endpointAttempts.length > 1,
          endpointAttempts,
        },
      };
    }

    const failures = endpointAttempts.filter((attempt) => attempt.status === "FAILED");
    const allEmpty = endpointAttempts.length > 0 && failures.length === 0;
    return {
      content: null,
      errorCode: allEmpty ? "NOT_FOUND" : "ALL_ENDPOINTS_FAILED",
      errorMessage: allEmpty
        ? "有道词典的主页面和备用页面都没有返回可解析的词条内容"
        : endpointAttempts
            .map((attempt) => `${attempt.endpoint}: ${attempt.errorCode ?? attempt.status}${attempt.errorMessage ? ` (${attempt.errorMessage})` : ""}`)
            .join("; "),
      transient: failures.some((attempt) => isTransientAttempt(attempt)),
      metadata: {
        fallbackUsed: endpointAttempts.length > 1,
        endpointAttempts,
      },
    };
  }
}

async function lookupEndpoint(endpoint: YoudaoEndpoint, term: string): Promise<{
  content: Partial<DictionaryContent> | null;
  attempt: YoudaoEndpointAttempt;
}> {
  const url = endpoint.buildUrl(term);

  try {
    const response = await fetch(url.toString(), {
      redirect: "follow",
      signal: AbortSignal.timeout(10_000),
      headers: {
        accept: "text/html,application/xhtml+xml",
        "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
        "cache-control": "no-cache",
        "user-agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      },
    });

    if (!response.ok) {
      return {
        content: null,
        attempt: {
          endpoint: endpoint.id,
          status: "FAILED",
          statusCode: response.status,
          errorCode: `HTTP_${response.status}`,
          errorMessage: `页面返回 ${response.status}`,
        },
      };
    }

    const html = await response.text();
    const content = parseYoudaoHtml(html, term);
    if (!content || !hasAnyContent(content)) {
      return {
        content: null,
        attempt: {
          endpoint: endpoint.id,
          status: "EMPTY",
          statusCode: response.status,
          errorCode: html.trim() ? "UNPARSABLE_RESPONSE" : "EMPTY_RESPONSE",
          errorMessage: html.trim() ? "页面存在内容，但未解析出词典字段" : "页面内容为空",
        },
      };
    }

    return {
      content,
      attempt: {
        endpoint: endpoint.id,
        status: "SUCCESS",
        statusCode: response.status,
      },
    };
  } catch (error) {
    const timeout = isTimeoutError(error);
    return {
      content: null,
      attempt: {
        endpoint: endpoint.id,
        status: "FAILED",
        errorCode: timeout ? "TIMEOUT" : "NETWORK_ERROR",
        errorMessage: error instanceof Error ? error.message : String(error),
      },
    };
  }
}

function parseYoudaoHtml(html: string, term: string): Partial<DictionaryContent> | null {
  const lines = extractTextLines(html);
  if (lines.length === 0) return null;

  return {
    pronunciations: parsePhonetics(lines),
    definitions: parseDefinitions(lines),
    forms: parseWordForms(lines),
    examples: parseExamples(lines, term),
    phrases: parsePhrases(lines),
    tags: [],
  };
}

function hasAnyContent(content: Partial<DictionaryContent>): boolean {
  return Boolean(
    content.definitions?.length
      || content.pronunciations?.length
      || content.forms?.length
      || content.examples?.length
      || content.phrases?.length,
  );
}

function satisfiesRequestedFields(content: DictionaryContent, input: LookupInput): boolean {
  const requested = (input.requestedFields ?? []).filter((field) => YOUDAO_SUPPORTED_FIELDS.has(field));
  if (requested.length === 0) return content.definitions.length > 0 || content.pronunciations.length > 0;

  return requested.every((field) => {
    if (field === "definitions") return content.definitions.length > 0;
    if (field === "pronunciations.phonetic") return content.pronunciations.some((item) => Boolean(item.phonetic));
    if (field === "examples") return content.examples.length > 0;
    if (field === "phrases") return content.phrases.length > 0;
    if (field === "forms") return content.forms.length > 0;
    return true;
  });
}

function isTimeoutError(error: unknown): boolean {
  return error instanceof Error && (error.name === "TimeoutError" || error.name === "AbortError");
}

function isTransientAttempt(attempt: YoudaoEndpointAttempt): boolean {
  return attempt.errorCode === "TIMEOUT"
    || attempt.errorCode === "NETWORK_ERROR"
    || Boolean(attempt.statusCode && attempt.statusCode >= 500);
}

// ---- Helper functions ----

function extractTextLines(html: string): string[] {
  // Remove script and style blocks
  let text = html
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/<noscript[^>]*>[\s\S]*?<\/noscript>/gi, "");

  // Replace block-level tags with newlines to preserve line structure
  text = text.replace(/<br\s*\/?>/gi, "\n");
  text = text.replace(/<\/(div|p|li|ul|ol|h[1-6]|section|article|tr|td|th|dl|dt|dd|blockquote|pre)[^>]*>/gi, "\n");
  text = text.replace(/<(div|p|li|ul|ol|h[1-6]|section|article|tr|td|th|dl|dt|dd|blockquote|pre)[^>]*>/gi, "\n");

  // Strip remaining HTML tags
  text = text.replace(/<[^>]+>/g, "");

  // Decode HTML entities
  text = text
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_match, code) => String.fromCodePoint(Number(code)))
    // Handle bold/strong markers (often used for the search term)
    .replace(/\*\*/g, "");

  // Split into lines, trim, and filter empty ones
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

/**
 * POS (part of speech) prefixes used in Chinese-English dictionaries
 */
const POS_PREFIXES = [
  "n",
  "v",
  "adj",
  "adv",
  "prep",
  "conj",
  "int",
  "pron",
  "art",
  "num",
  "aux",
  "det",
  "abbr",
] as const;

const POS_PATTERN = new RegExp(`^(${POS_PREFIXES.join("|")})\\.\\s*(.+)$`);

function parsePhonetics(lines: string[]): DictionaryContent["pronunciations"] {
  const pronunciations: DictionaryContent["pronunciations"] = [];
  const fullText = lines.join(" ");

  // Support two phonetic formats:
  //   英/ ˈbɒdi /     (youdao.com/result)
  //   英 [ˈbrəʊʃə(r)] (dict.youdao.com/w/eng/)

  // UK: 英/ ... /  or  英 [...]
  const ukMatch = fullText.match(/英\s*[\[/]\s*([^\]/]+?)\s*[\]]/) ?? fullText.match(/英\s*\/\s*([^/]+?)\s*\//);
  if (ukMatch?.[1]) {
    pronunciations.push({
      accent: "UK",
      phonetic: ukMatch[1].trim(),
      audioUrl: null,
      source: "youdao",
      isSynthetic: false,
    });
  }

  // US: 美/ ... /  or  美 [...]
  const usMatch = fullText.match(/美\s*[\[/]\s*([^\]/]+?)\s*[\]]/) ?? fullText.match(/美\s*\/\s*([^/]+?)\s*\//);
  if (usMatch?.[1]) {
    pronunciations.push({
      accent: "US",
      phonetic: usMatch[1].trim(),
      audioUrl: null,
      source: "youdao",
      isSynthetic: false,
    });
  }

  return pronunciations;
}

function parseDefinitions(lines: string[]): DictionaryContent["definitions"] {
  const definitions: DictionaryContent["definitions"] = [];

  for (const line of lines) {
    const match = line.match(POS_PATTERN);
    if (match) {
      const partOfSpeech = match[1] ?? "";
      const text = match[2]?.trim() ?? "";
      if (text) {
        definitions.push({
          language: "zh-CHS",
          partOfSpeech,
          text,
          source: "youdao",
          isUserEdited: false,
        });
      }
    }
  }

  return definitions;
}

interface FormPattern {
  pattern: RegExp;
  type: string;
}

const FORM_PATTERNS: FormPattern[] = [
  { pattern: /^复数\s+(.+)$/, type: "PLURAL" },
  { pattern: /^第三人称单数\s+(.+)$/, type: "THIRD_PERSON" },
  { pattern: /^现在分词\s+(.+)$/, type: "PRESENT_PARTICIPLE" },
  { pattern: /^过去式\s+(.+)$/, type: "PAST" },
  { pattern: /^过去分词\s+(.+)$/, type: "PAST_PARTICIPLE" },
  { pattern: /^比较级\s+(.+)$/, type: "COMPARATIVE" },
  { pattern: /^最高级\s+(.+)$/, type: "SUPERLATIVE" },
];

function parseWordForms(lines: string[]): DictionaryContent["forms"] {
  const forms: DictionaryContent["forms"] = [];

  for (const line of lines) {
    for (const { pattern, type } of FORM_PATTERNS) {
      const match = line.match(pattern);
      if (match?.[1]) {
        const value = match[1].trim();
        if (value) {
          forms.push({
            type: type as DictionaryContent["forms"][number]["type"],
            value,
            source: "youdao",
          });
        }
        break;
      }
    }
  }

  return forms;
}

/**
 * Extract example sentences from the page.
 * After the "双语例句" section, look for numbered items containing
 * English sentences with the search term (often bolded).
 */
function parseExamples(lines: string[], term: string): DictionaryContent["examples"] {
  const examples: DictionaryContent["examples"] = [];
  const termLower = term.toLowerCase();

  let inBilingualSection = false;
  let inAudioSentence = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;

    // Detect section start
    if (line.includes("双语例句") || line.includes("原声例句") || line.includes("权威例句")) {
      inBilingualSection = true;
      continue;
    }

    // Detect end of section (next major section)
    if (inBilingualSection && (line.includes("查看更多") || line.includes("词典短语") || line.includes("同近义词"))) {
      break;
    }

    if (!inBilingualSection) continue;

    // Skip pure Chinese lines, audio markers, and non-sentence lines
    if (line.includes("点击发音") || /^[\u4e00-\u9fff\s，。；：、！？]+$/.test(line)) {
      // Check if previous line was an English sentence (for paired sentences)
      if (inAudioSentence && examples.length > 0) {
        const lastExample = examples[examples.length - 1]!;
        if (!lastExample.translation) {
          lastExample.translation = line.replace(/点击发音.*$/, "").trim();
        }
      }
      inAudioSentence = false;
      continue;
    }

    // Strip leading numbers like "1", "2", etc.
    const cleanLine = line.replace(/^\d+\s*/, "").trim();

    // Check if it looks like an English sentence containing the term
    if (cleanLine.toLowerCase().includes(termLower)) {
      // Clean up: remove trailing audio markers and Chinese text
      const sentence = cleanLine
        .replace(/\[?点击发音\]?.*$/, "")
        .replace(/\s+[\u4e00-\u9fff].*$/, "")
        .trim();

      if (sentence && sentence.length > 5) {
        examples.push({
          sentence,
          translation: null,
          source: "youdao",
          isUserAdded: false,
        });
        inAudioSentence = true;
      }
    }
  }

  return examples;
}

/**
 * Extract phrases from the "词典短语" or "短语" sections.
 * Pattern: "1body fluid  体液 ; 津液 ; 组织液体"
 */
function parsePhrases(lines: string[]): DictionaryContent["phrases"] {
  const phrases: DictionaryContent["phrases"] = [];
  let inPhraseSection = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]!;

    // Detect phrase section
    if (line.includes("短语") || line.includes("词典短语") || line.includes("网络释义")) {
      inPhraseSection = true;
      continue;
    }

    // End of section
    if (inPhraseSection && (line.includes("双语例句") || line.includes("同近义词") || line.includes("英英释义") || line.includes("查看更多"))) {
      break;
    }

    if (!inPhraseSection) continue;

    // Match numbered entries: "1body fluid" or "1main body" or "1Body Horror"
    // These might also have the format "- 1body fluid"
    const cleanLine = line.replace(/^-\s*/, "").replace(/^\d+\s*/, "").trim();
    if (!cleanLine || cleanLine.length < 3) continue;

    // Try to split into phrase and translation
    // Patterns: "phrase翻译" or "phrase  翻译" or "phrase; 翻译"
    const translationMatch = cleanLine.match(/^(.+?)([\u4e00-\u9fff].+)$/);
    if (translationMatch) {
      const phrase = translationMatch[1]!.trim();
      const translation = translationMatch[2]!.trim().replace(/^[；;，,、\s]+/, "");
      if (phrase && translation && phrase.length > 1) {
        // Filter out non-phrase entries
        if (!phrase.match(/^[\d\s./]+$/) && phrase.length < 80) {
          phrases.push({
            phrase,
            translation,
            source: "youdao",
          });
        }
      }
    } else if (cleanLine.match(/^[a-zA-Z]/) && cleanLine.length < 60 && cleanLine.split(/\s+/).length >= 2) {
      // Entry without Chinese translation (e.g., "Body Horror")
      // Only add if it looks like a multi-word expression
      const wordCount = cleanLine.split(/\s+/).length;
      if (wordCount >= 2) {
        phrases.push({
          phrase: cleanLine,
          translation: null,
          source: "youdao",
        });
      }
    }
  }

  return phrases;
}
