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

export function parsePhonetics(lines: string[], term = ""): DictionaryContent["pronunciations"] {
  const text = lines.join(" "); const result: DictionaryContent["pronunciations"] = [];
  const trimmedTerm = term.trim();
  const audioBase = trimmedTerm ? `https://dict.youdao.com/dictvoice?audio=${encodeURIComponent(trimmedTerm)}` : null;
  const uk = text.match(/英\s*[\[/]\s*([^\]/]+?)\s*[\]]/) ?? text.match(/英\s*\/\s*([^/]+?)\s*\//);
  const us = text.match(/美\s*[\[/]\s*([^\]/]+?)\s*[\]]/) ?? text.match(/美\s*\/\s*([^/]+?)\s*\//);
  if (uk?.[1]) result.push({ accent: "UK", phonetic: uk[1].trim(), audioUrl: audioBase ? `${audioBase}&type=1` : null, source: dictionarySource, isSynthetic: false });
  if (us?.[1]) result.push({ accent: "US", phonetic: us[1].trim(), audioUrl: audioBase ? `${audioBase}&type=2` : null, source: dictionarySource, isSynthetic: false });
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
    // "…" (U+2026) is not in the CJK block, so allow a leading ellipsis on the
    // meaning side ("The proportion of …的比例").
    const inline = line.match(/^(.+?)([…⋯]*[\u3400-\u9fff].+)$/);
    const raw = (inline?.[2] ?? (/^[…⋯]*[\u3400-\u9fff]/.test(next) ? next : "")).replace(/^[；;，,、：:\s]+/, "").trim();
    if (!raw) return "";
    // The meaning must be on the correct side of the language boundary.
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
      // Only accept entries that extend the term ("the proportion of sth" for
      // "the proportion of"); the reverse direction could match a shorter
      // entry ("put up") and claim its meaning for a longer phrase.
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
