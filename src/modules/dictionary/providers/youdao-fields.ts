import type { DictionaryContent } from "@/lib/types";

const POS = new RegExp(`^(${["n", "v", "adj", "adv", "prep", "conj", "int", "pron", "art", "num", "aux", "det", "abbr"].join("|")})\\.\\s*(.+)$`);
const FORM_PATTERNS = [
  [/^复数\s+(.+)$/, "PLURAL"], [/^第三人称单数\s+(.+)$/, "THIRD_PERSON"], [/^现在分词\s+(.+)$/, "PRESENT_PARTICIPLE"],
  [/^过去式\s+(.+)$/, "PAST"], [/^过去分词\s+(.+)$/, "PAST_PARTICIPLE"], [/^比较级\s+(.+)$/, "COMPARATIVE"], [/^最高级\s+(.+)$/, "SUPERLATIVE"],
] as const;

export function parsePhonetics(lines: string[]): DictionaryContent["pronunciations"] {
  const text = lines.join(" "); const result: DictionaryContent["pronunciations"] = [];
  const uk = text.match(/英\s*[\[/]\s*([^\]/]+?)\s*[\]]/) ?? text.match(/英\s*\/\s*([^/]+?)\s*\//);
  const us = text.match(/美\s*[\[/]\s*([^\]/]+?)\s*[\]]/) ?? text.match(/美\s*\/\s*([^/]+?)\s*\//);
  if (uk?.[1]) result.push({ accent: "UK", phonetic: uk[1].trim(), audioUrl: null, source: "youdao", isSynthetic: false });
  if (us?.[1]) result.push({ accent: "US", phonetic: us[1].trim(), audioUrl: null, source: "youdao", isSynthetic: false });
  return result;
}
export function parseDefinitions(lines: string[]): DictionaryContent["definitions"] {
  return lines.flatMap((line) => { const match = line.match(POS); if (!match?.[2]?.trim()) return []; return [{ language: "zh-CHS", partOfSpeech: match[1]!, text: match[2]!.trim(), source: "youdao", isUserEdited: false }]; });
}
export function parseWordForms(lines: string[]): DictionaryContent["forms"] {
  return lines.flatMap((line) => { for (const [pattern, type] of FORM_PATTERNS) { const match = line.match(pattern); if (match?.[1]) return [{ type, value: match[1].trim(), source: "youdao" }]; } return []; }) as DictionaryContent["forms"];
}
export function parseExamples(lines: string[], term: string): DictionaryContent["examples"] {
  const result: DictionaryContent["examples"] = []; const lower = term.toLowerCase(); let active = false; let pending = false;
  for (const line of lines) {
    if (line.includes("双语例句") || line.includes("原声例句") || line.includes("权威例句")) { active = true; continue; }
    if (active && (line.includes("查看更多") || line.includes("词典短语") || line.includes("同近义词"))) break;
    if (!active) continue;
    if (line.includes("点击发音") || /^[\u4e00-\u9fff\s，。；：、！？]+$/.test(line)) { if (pending && result.length && !result.at(-1)!.translation) result.at(-1)!.translation = line.replace(/点击发音.*$/, "").trim(); pending = false; continue; }
    const clean = line.replace(/^\d+\s*/, "").trim(); if (!clean.toLowerCase().includes(lower)) continue;
    const sentence = clean.replace(/\[?点击发音\]?.*$/, "").replace(/\s+[\u4e00-\u9fff].*$/, "").trim();
    if (sentence.length > 5) { result.push({ sentence, translation: null, source: "youdao", isUserAdded: false }); pending = true; }
  }
  return result;
}
export function parsePhrases(lines: string[]): DictionaryContent["phrases"] {
  const result: DictionaryContent["phrases"] = []; let active = false;
  for (const line of lines) {
    if (line.includes("短语") || line.includes("词典短语") || line.includes("网络释义")) { active = true; continue; }
    if (active && (line.includes("双语例句") || line.includes("同近义词") || line.includes("英英释义") || line.includes("查看更多"))) break;
    if (!active) continue;
    const clean = line.replace(/^-\s*/, "").replace(/^\d+\s*/, "").trim(); if (!clean || clean.length < 3) continue;
    const match = clean.match(/^(.+?)([\u4e00-\u9fff].+)$/);
    if (match) { const phrase = match[1]!.trim(); const translation = match[2]!.trim().replace(/^[；;，,、\s]+/, ""); if (phrase.length > 1 && phrase.length < 80 && translation) result.push({ phrase, translation, source: "youdao" }); }
    else if (/^[a-zA-Z]/.test(clean) && clean.length < 60 && clean.split(/\s+/).length >= 2) result.push({ phrase: clean, translation: null, source: "youdao" });
  }
  return result;
}
