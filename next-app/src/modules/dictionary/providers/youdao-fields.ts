import type { DictionaryContent } from "@/lib/types";

const POS = new RegExp(`^(${["n", "v", "adj", "adv", "prep", "conj", "int", "pron", "art", "num", "aux", "det", "abbr"].join("|")})\\.\\s*(.+)$`);
const FORM_PATTERNS = [
  [/^复数\s+(.+)$/, "PLURAL"], [/^第三人称单数\s+(.+)$/, "THIRD_PERSON"], [/^现在分词\s+(.+)$/, "PRESENT_PARTICIPLE"],
  [/^过去式\s+(.+)$/, "PAST"], [/^过去分词\s+(.+)$/, "PAST_PARTICIPLE"], [/^比较级\s+(.+)$/, "COMPARATIVE"], [/^最高级\s+(.+)$/, "SUPERLATIVE"],
] as const;
const FORM_LABELS = new Map<string, DictionaryContent["forms"][number]["type"]>([
  ["复数", "PLURAL"], ["第三人称单数", "THIRD_PERSON"], ["现在分词", "PRESENT_PARTICIPLE"],
  ["过去式", "PAST"], ["过去分词", "PAST_PARTICIPLE"], ["比较级", "COMPARATIVE"], ["最高级", "SUPERLATIVE"],
]);
const SECTION_HEADINGS = new Set([
  "网络释义", "英英释义", "专业释义", "同近义词", "同根词", "词源", "短语", "词典短语",
  "双语例句", "原声例句", "权威例句", "百科", "有道翻译",
]);

const dictionarySource = "youdao";
const translationSource = "youdao:translation";
const exampleSource = "youdao:example";
const audioExampleSource = "youdao:audio-example";
const authorityExampleSource = "youdao:authority-example";
const phraseSource = "youdao:phrase";
const networkPhraseSource = "youdao:network";

function isChineseLine(line: string): boolean {
  return /[\u3400-\u9fff]/.test(line) && !/[a-zA-Z]{3,}/.test(line.replace(/《[^》]+》/g, ""));
}

function isSectionHeading(line: string): boolean {
  return SECTION_HEADINGS.has(line.trim()) || /^(更多|查看|以上为机器翻译)/.test(line.trim());
}

function cleanExampleLine(line: string): string {
  return line
    .replace(/^\d+[.、]?\s*/, "")
    .replace(/^\[?点击发音\]?\s*/, "")
    .replace(/\s*点击发音.*$/, "")
    .trim();
}

function matchesTerm(sentence: string, term: string): boolean {
  const normalizedTerm = term.trim().toLocaleLowerCase();
  if (!normalizedTerm) return false;
  if (normalizedTerm.includes(" ")) return sentence.toLocaleLowerCase().includes(normalizedTerm);
  const escaped = normalizedTerm.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(?:^|[^a-z])${escaped}(?:$|[^a-z])`, "i").test(sentence);
}

function decodeHtmlEntities(value: string): string {
  return value
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#x([0-9a-f]+);/gi, (_match, code) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&#(\d+);/g, (_match, code) => String.fromCodePoint(Number(code)));
}

function stripHtmlTags(value: string): string {
  return value.replace(/<[^>]+>/g, "").trim();
}

export function parsePhonetics(lines: string[], term = "", html?: string): DictionaryContent["pronunciations"] {
  const text = lines.join(" "); const result: DictionaryContent["pronunciations"] = [];
  const trimmedTerm = term.trim();
  const audioBase = trimmedTerm ? `https://dict.youdao.com/dictvoice?audio=${encodeURIComponent(trimmedTerm)}` : null;
  let ukPhonetic: string | null = null;
  let usPhonetic: string | null = null;
  if (html) {
    const ukMatch = html.match(/英\s*<span[^>]*class="phonetic"[^>]*>([^<]+)<\/span>/);
    const usMatch = html.match(/美\s*<span[^>]*class="phonetic"[^>]*>([^<]+)<\/span>/);
    if (ukMatch?.[1]) ukPhonetic = decodeHtmlEntities(ukMatch[1]).replace(/[\[\]]/g, "").trim();
    if (usMatch?.[1]) usPhonetic = decodeHtmlEntities(usMatch[1]).replace(/[\[\]]/g, "").trim();
  }
  if (!ukPhonetic) {
    const uk = text.match(/英\s*[\[/]\s*([^\]/]+?)\s*[\]]/) ?? text.match(/英\s*\/\s*([^/]+?)\s*\//);
    if (uk?.[1]) ukPhonetic = uk[1].trim();
  }
  if (!usPhonetic) {
    const us = text.match(/美\s*[\[/]\s*([^\]/]+?)\s*[\]]/) ?? text.match(/美\s*\/\s*([^/]+?)\s*\//);
    if (us?.[1]) usPhonetic = us[1].trim();
  }
  if (ukPhonetic) result.push({ accent: "UK", phonetic: ukPhonetic, audioUrl: audioBase ? `${audioBase}&type=1` : null, source: dictionarySource, isSynthetic: false });
  if (usPhonetic) result.push({ accent: "US", phonetic: usPhonetic, audioUrl: audioBase ? `${audioBase}&type=2` : null, source: dictionarySource, isSynthetic: false });
  return result;
}

export function parseDefinitions(lines: string[], language = "zh-CN"): DictionaryContent["definitions"] {
  let active = false;
  return lines.flatMap((line) => {
    const trimmed = line.trim();
    if (trimmed === "简明" || trimmed === "词典释义") active = true;
    if (isSectionHeading(trimmed) && trimmed !== "词典释义" && trimmed !== "简明") active = false;
    const match = trimmed.match(POS);
    if (!match?.[2]?.trim() || (!active && !POS.test(trimmed))) return [];
    return [{ language, partOfSpeech: match[1]!, text: match[2]!.trim(), source: dictionarySource, isUserEdited: false }];
  });
}

export function parseWordForms(lines: string[]): DictionaryContent["forms"] {
  const result: DictionaryContent["forms"] = [];
  let pending: DictionaryContent["forms"][number]["type"] | null = null;
  for (const rawLine of lines) {
    const line = rawLine.trim();
    for (const [pattern, type] of FORM_PATTERNS) {
      const match = line.match(pattern);
      if (match?.[1]) {
        result.push({ type, value: match[1].trim(), source: dictionarySource });
        pending = null;
        continue;
      }
    }
    const label = FORM_LABELS.get(line);
    if (label) {
      pending = label;
      continue;
    }
    if (pending && line && !isSectionHeading(line) && !/^\d+$/.test(line) && !/^[\u3400-\u9fff]/.test(line)) {
      result.push({ type: pending, value: line, source: dictionarySource });
      pending = null;
    }
  }
  return result;
}

export function parseExamples(lines: string[], term: string): DictionaryContent["examples"] {
  const result: DictionaryContent["examples"] = [];
  let source: string | null = null;
  let pending: DictionaryContent["examples"][number] | null = null;
  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line === "双语例句") { source = exampleSource; continue; }
    if (line === "原声例句") { source = audioExampleSource; continue; }
    if (line === "权威例句") { source = authorityExampleSource; continue; }
    if (source && (line.includes("查看更多") || line === "词典短语" || line === "同近义词" || line === "百科")) source = null;
    if (!source) continue;
    const clean = cleanExampleLine(line);
    if (!clean || /^《[^》]+》$/.test(clean) || /^\d+$/.test(clean)) continue;
    if (pending && isChineseLine(clean)) {
      pending.translation = clean;
      pending = null;
      continue;
    }
    if (!matchesTerm(clean, term) || isChineseLine(clean) || clean.length < 5) continue;
    const sentence = clean.replace(/\s+[\u3400-\u9fff].*$/, "").trim();
    if (sentence.length < 5) continue;
    pending = { sentence, translation: null, source, isUserAdded: false };
    result.push(pending);
  }
  return result;
}

export function parsePhrases(lines: string[]): DictionaryContent["phrases"] {
  const result: DictionaryContent["phrases"] = [];
  let source: string | null = null;
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]!.trim();
    if (line === "网络释义") { source = networkPhraseSource; continue; }
    if (line === "短语" || line === "词典短语") { source = phraseSource; continue; }
    if (source && (line === "双语例句" || line === "原声例句" || line === "权威例句" || line === "同近义词" || line === "百科")) source = null;
    if (!source || !line || /^\d+$/.test(line) || isSectionHeading(line)) continue;
    const next = lines[index + 1]?.trim() ?? "";
    const inline = line.match(/^(.+?)([\u3400-\u9fff].+)$/);
    const phrase = (inline?.[1] ?? line).replace(/^[-•]\s*/, "").trim();
    const translation = (inline?.[2] ?? (/^[\u3400-\u9fff]/.test(next) ? next : "")).replace(/^[；;，,、\s]+/, "").trim();
    if (!/^[a-zA-Z]/.test(phrase) || phrase.length < 2 || phrase.length > 100) continue;
    if (!translation && phrase.split(/\s+/).length < 2) continue;
    result.push({ phrase, translation: translation || null, source });
    if (!inline?.[2] && translation) index += 1;
  }
  return result;
}

/**
 * Extracts the translation of a phrase from the "网络释义" / "词典短语" sections
 * when the page has no dedicated "有道翻译" block. Dictionary pages for phrases
 * usually do not include POS-prefixed lines, so `parseDefinitions` finds
 * nothing; the network-definition entries (e.g. "The proportion of …的比例")
 * are the only usable meaning.
 */
export function parsePhraseDefinition(
  lines: string[],
  term: string,
  language = "zh-CN",
): { text: string; source: string } | null {
  const normalizedTerm = term.trim().toLocaleLowerCase();
  if (!normalizedTerm) return null;
  const readTranslation = (line: string, next: string): string => {
    const inline = line.match(/^(.+?)([…⋯]*[\u3400-\u9fff].+)$/);
    const raw = (inline?.[2] ?? (/^[…⋯]*[\u3400-\u9fff]/.test(next) ? next : "")).replace(/^[；;，,、：:\s]+/, "").trim();
    if (!raw) return "";
    const containsCjk = /[\u3400-\u9fff]/.test(raw);
    if (language.toLowerCase().startsWith("zh") ? !containsCjk : containsCjk) return "";
    return raw;
  };
  const scan = (allowExtension: boolean): { text: string; source: string } | null => {
    let source: string | null = null;
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index]!.trim();
      if (line === "网络释义") { source = networkPhraseSource; continue; }
      if (line === "短语" || line === "词典短语") { source = phraseSource; continue; }
      if (source && (line === "双语例句" || line === "原声例句" || line === "权威例句" || line === "同近义词" || line === "同根词" || line === "百科")) source = null;
      if (!source || !line || /^\d+$/.test(line) || isSectionHeading(line)) continue;
      const phrase = line
        .replace(/^\d+[.、]?\s*/, "")
        .replace(/^[-•]\s*/, "")
        .match(/^([a-zA-Z][a-zA-Z\s'-]*)/)?.[1]?.trim()
        ?? "";
      if (!phrase) continue;
      const normalizedPhrase = phrase.toLocaleLowerCase();
      const exact = normalizedPhrase === normalizedTerm;
      const extension = allowExtension
        && normalizedTerm.includes(" ")
        && normalizedPhrase.startsWith(`${normalizedTerm} `);
      if (!exact && !extension) continue;
      const text = readTranslation(line, lines[index + 1]?.trim() ?? "");
      if (!text) continue;
      return { text, source: source ?? networkPhraseSource };
    }
    return null;
  };
  return scan(false) ?? scan(true);
}

export function parseTranslation(lines: string[], term: string, language = "zh-CN"): { translation: string; source: string } | null {
  const marker = lines.findIndex((line) => line === "有道翻译" || line.includes("有道翻译"));
  if (marker < 0) return null;
  const normalizedTerm = term.trim().toLocaleLowerCase();
  for (const candidate of lines.slice(marker + 1, marker + 8)) {
    const value = candidate.replace(/^[：:、\s]+/, "").trim();
    if (!value || value.toLocaleLowerCase() === normalizedTerm || isSectionHeading(value)) continue;
    if (value.startsWith("以上为机器翻译") || value === "长、整句建议使用人工翻译") continue;
    if (language.toLowerCase().startsWith("zh") && /[\u3400-\u9fff]/.test(value)) return { translation: value, source: translationSource };
    if (!language.toLowerCase().startsWith("zh") && !/[\u3400-\u9fff]/.test(value)) return { translation: value, source: translationSource };
  }
  return null;
}

// --- New: enriched sections from HTML ---

export function parseEnDefinitions(html: string): DictionaryContent["definitions"] {
  const sectionMatch = html.match(/id="tEETrans"[\s\S]*?<\/ul>\s*<\/div>/);
  if (!sectionMatch) return [];
  const section = sectionMatch[0];
  const result: DictionaryContent["definitions"] = [];
  const posBlocks = section.split(/<span class="pos">/);
  if (posBlocks.length > 1) {
    for (let index = 1; index < posBlocks.length; index += 1) {
      const block = posBlocks[index]!;
      const posRaw = decodeHtmlEntities(stripHtmlTags(block.split("</span>")[0] ?? "")).trim().replace(/\.$/, "");
      const pos = posRaw && /^[a-zA-Z]+$/.test(posRaw) ? posRaw : null;
      const defPattern = /<span class="def">([^<]+)<\/span>/g;
      let m: RegExpExecArray | null;
      let found = false;
      while ((m = defPattern.exec(block)) !== null) {
        const defText = decodeHtmlEntities(stripHtmlTags(m[1]!)).trim();
        if (!defText) continue;
        found = true;
        result.push({ language: "en", partOfSpeech: pos, text: defText, source: "youdao:en-definition", isUserEdited: false });
      }
      if (!found) {
        const fallback = block.match(/<span class="def">([^<]+)<\/span>/);
        if (fallback?.[1]) {
          const defText = decodeHtmlEntities(stripHtmlTags(fallback[1])).trim();
          if (defText) result.push({ language: "en", partOfSpeech: pos, text: defText, source: "youdao:en-definition", isUserEdited: false });
        }
      }
    }
    if (result.length) return result;
  }
  const defOnly = /<span class="def">([^<]+)<\/span>/g;
  let m: RegExpExecArray | null;
  while ((m = defOnly.exec(section)) !== null) {
    const defText = decodeHtmlEntities(stripHtmlTags(m[1]!)).trim();
    if (!defText) continue;
    result.push({ language: "en", partOfSpeech: null, text: defText, source: "youdao:en-definition", isUserEdited: false });
  }
  return result;
}

export function parseSynonymsFromHtml(html: string): DictionaryContent["synonyms"] {
  const sectionMatch = html.match(/id="synonyms"[\s\S]*?<\/div>\s*<div id="relWordTab"/);
  const fallback = html.match(/id="synonyms"[\s\S]*?<\/div>/);
  const section = sectionMatch?.[0] ?? fallback?.[0];
  if (!section) return [];
  const result: DictionaryContent["synonyms"] = [];
  const anchorPattern = /<a[^>]*class="search-js"[^>]*>([^<]+)<\/a>/g;
  let m: RegExpExecArray | null;
  while ((m = anchorPattern.exec(section)) !== null) {
    const word = decodeHtmlEntities(m[1]!.trim());
    if (!word || word.length < 2 || word.length > 40) continue;
    if (!/^[a-zA-Z][a-zA-Z\s'-]*$/.test(word)) continue;
    result.push({ word, translation: null, partOfSpeech: null, relation: "SYNONYM", source: "youdao" });
  }
  const seen = new Set<string>();
  return result.filter((item) => {
    const key = item.word.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function parseWordFamilyFromHtml(html: string): DictionaryContent["wordFamily"] {
  const sectionMatch = html.match(/id="relWordTab"[\s\S]*?<\/div>\s*<div id="discriminate"/);
  const fallback = html.match(/id="relWordTab"[\s\S]*?<\/div>/);
  const section = sectionMatch?.[0] ?? fallback?.[0];
  if (!section) return [];
  const result: DictionaryContent["wordFamily"] = [];
  const ROOT_LABEL_RE = /^\s*词根\s*[:：]?\s*$/;
  const posFromLine = (text: string): string | null => {
    const t = text.replace(ROOT_LABEL_RE, "").trim().toLowerCase();
    if (!t) return null;
    if (/^(adj|n|v|adv|prep|conj|int|pron|art|num)\.?$/.test(t)) return t.replace(".", "");
    return null;
  };
  let currentPos: string | null = null;
  const blocks = section.split(/<p class="wordGroup">/);
  for (const block of blocks) {
    const end = block.indexOf("</p>");
    if (end < 0) continue;
    const inner = block.slice(0, end);
    const textOnly = stripHtmlTags(inner);
    if (ROOT_LABEL_RE.test(textOnly) || textOnly.trim() === "词根：") continue;
    const maybePos = posFromLine(textOnly);
    if (maybePos) { currentPos = maybePos; continue; }
    if (!inner.includes("<a")) continue;
    const anchor = inner.match(/<a[^>]*>([^<]+)<\/a>/);
    if (!anchor?.[1]) continue;
    const word = decodeHtmlEntities(anchor[1].trim());
    if (!word || !/^[a-zA-Z][a-zA-Z'-]*$/.test(word)) continue;
    const afterAnchor = inner.slice((anchor.index ?? 0) + anchor[0].length);
    const translation = decodeHtmlEntities(stripHtmlTags(afterAnchor)).trim().replace(/^[；;，,、\s]+/, "") || null;
    result.push({ word, translation, partOfSpeech: currentPos, relation: "WORD_FAMILY", source: "youdao:word-family" });
  }
  const seen = new Set<string>();
  return result.filter((item) => {
    const key = `${item.word.toLowerCase()}|${item.partOfSpeech ?? ""}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function parsePhrasesFromHtml(html: string): DictionaryContent["phrases"] {
  const sectionMatch = html.match(/id="wordGroup"[\s\S]*?<\/div>\s*<div id="synonyms"/);
  const fallback = html.match(/id="wordGroup"[\s\S]*?<\/div>/);
  const section = sectionMatch?.[0] ?? fallback?.[0];
  if (!section) return [];
  const result: DictionaryContent["phrases"] = [];
  const groupPattern = /<p class="wordGroup">[\s\S]*?<a[^>]*>([^<]+)<\/a>([\s\S]*?)<\/p>/g;
  let m: RegExpExecArray | null;
  while ((m = groupPattern.exec(section)) !== null) {
    const phrase = decodeHtmlEntities(m[1]!.trim());
    const translation = decodeHtmlEntities(stripHtmlTags(m[2]!)).trim().replace(/^[；;，,、\s]+/, "") || null;
    if (!phrase || phrase.length < 2 || phrase.length > 80) continue;
    if (!/^[a-zA-Z]/.test(phrase)) continue;
    result.push({ phrase, translation, source: "youdao:phrase" });
  }
  return result;
}
