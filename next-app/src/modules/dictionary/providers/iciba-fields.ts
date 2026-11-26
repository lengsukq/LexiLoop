import type { DictionaryContent } from "@/lib/types";

const source = "iciba";
const enSource = "iciba:en-definition";
const collinsSource = "iciba:collins";
const exampleSource = "iciba:example";
const phraseSource = "iciba:phrase";

export interface IcibaWordInfo {
  baesInfo?: {
    word_name?: string;
    exchange?: Record<string, string[]>;
    symbols?: Array<{
      ph_en?: string; ph_am?: string; ph_en_mp3?: string; ph_am_mp3?: string;
      parts?: Array<{ part?: string; means?: string[] }>;
    }>;
    baesElse?: unknown;
    word_tag?: number[];
    frequence?: number;
  };
  bidec?: {
    parts?: Array<{
      part_name?: string;
      means?: Array<{ word_mean?: string; sentences?: Array<{ en?: string; cn?: string }> }>;
    }>;
  };
  exchanges?: string[];
  synonym?: Array<{
    part_name?: string;
    means?: Array<{ word_mean?: string; cis?: string[] }>;
  }>;
  phrase?: Array<{
    cizu_name?: string;
    jx?: Array<{ jx_en_mean?: string; jx_cn_mean?: string; lj?: Array<{ lj_ly?: string; lj_ls?: string }> }>;
  }>;
  ee_mean?: Array<{
    part_name?: string;
    means?: Array<{ word_mean?: string; sentences?: Array<{ sentence?: string }> }>;
  }>;
  collins?: Array<{
    entry?: Array<{
      def?: string; tran?: string; posp?: string;
      example?: Array<{ ex?: string; tran?: string }>;
    }>;
  }>;
  new_sentence?: Array<{
    sentences?: Array<{ en?: string; cn?: string }>;
  }>;
  derivation?: Array<{ yuyuan_name?: string }>;
  sameAnalysis?: Array<{ word_list?: string; part_name?: string; means?: string[] }>;
  trade_means?: unknown;
  [key: string]: unknown;
}

function stripTags(value: string): string {
  return value.replace(/<[^>]+>/g, "").trim();
}

function decodeEntities(value: string): string {
  return value
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#x([0-9a-f]+);/gi, (_m, c) => String.fromCodePoint(Number.parseInt(c, 16)))
    .replace(/&#(\d+);/g, (_m, c) => String.fromCodePoint(Number(c)));
}

function normalizePos(raw: string): string | null {
  const t = raw.trim().replace(/\.$/, "").toLowerCase();
  if (!t) return null;
  const map: Record<string, string> = {
    "n": "n", "noun": "n", "v": "v", "verb": "v", "vt": "v", "vi": "v",
    "adj": "adj", "adv": "adv", "prep": "prep", "conj": "conj",
    "int": "int", "pron": "pron", "art": "art", "num": "num",
  };
  return map[t] ?? t;
}

export function parseIcibaDefinitions(info: IcibaWordInfo, targetLanguage: string): DictionaryContent["definitions"] {
  const result: DictionaryContent["definitions"] = [];
  const seen = new Set<string>();

  // baesInfo: concise zh definitions
  for (const sym of info.baesInfo?.symbols ?? []) {
    for (const part of sym.parts ?? []) {
      const pos = normalizePos(part.part ?? "");
      for (const rawMean of part.means ?? []) {
        const text = decodeEntities(stripTags(rawMean)).trim();
        if (!text) continue;
        const key = `zh|${pos ?? ""}|${text}`;
        if (seen.has(key)) continue;
        seen.add(key);
        result.push({ language: targetLanguage, partOfSpeech: pos, text, source, isUserEdited: false });
      }
    }
  }

  // bidec: detailed zh definitions (dedup-merged, not fallback-only; strip </seg> tags)
  for (const part of info.bidec?.parts ?? []) {
    const pos = normalizePos(part.part_name ?? "");
    for (const mean of part.means ?? []) {
      let text = decodeEntities(stripTags(mean.word_mean ?? "")).trim();
      text = text.replace(/<\/seg>/gi, "").trim();
      if (!text) continue;
      if (pos === null && /^_no_$/i.test((part.part_name ?? "").trim())) continue;
      const key = `zh|${pos ?? ""}|${text}`;
      if (seen.has(key)) continue;
      seen.add(key);
      result.push({ language: targetLanguage, partOfSpeech: pos, text, source: "iciba:bidec", isUserEdited: false });
    }
  }

  // ee_mean: English definitions
  for (const group of info.ee_mean ?? []) {
    const groupPos = normalizePos(group.part_name ?? "");
    for (const mean of group.means ?? []) {
      const raw = decodeEntities(stripTags(mean.word_mean ?? "")).trim().replace(/^\d+\.\s*/, "");
      if (!raw) continue;
      const key = `en|${groupPos ?? ""}|${raw}`;
      if (seen.has(key)) continue;
      seen.add(key);
      result.push({ language: "en", partOfSpeech: groupPos, text: raw, source: enSource, isUserEdited: false });
    }
  }

  // collins
  for (const block of info.collins ?? []) {
    for (const entry of block.entry ?? []) {
      const def = decodeEntities(stripTags(entry.def ?? "")).trim();
      const tran = decodeEntities(stripTags(entry.tran ?? "")).trim();
      const posp = entry.posp ? normalizePos(entry.posp.replace(/-.*$/, "")) : null;
      if (def) {
        const key = `en|${posp ?? ""}|${def}`;
        if (!seen.has(key)) { seen.add(key); result.push({ language: "en", partOfSpeech: posp, text: def, source: collinsSource, isUserEdited: false }); }
      }
      if (tran) {
        const key = `zh|${posp ?? ""}|${tran}`;
        if (!seen.has(key)) { seen.add(key); result.push({ language: targetLanguage, partOfSpeech: posp, text: tran, source: collinsSource, isUserEdited: false }); }
      }
    }
  }

  return result;
}

export function parseIcibaPhonetics(info: IcibaWordInfo): DictionaryContent["pronunciations"] {
  const sym = info.baesInfo?.symbols?.[0];
  if (!sym) return [];
  const result: DictionaryContent["pronunciations"] = [];
  if (sym.ph_en?.trim()) {
    result.push({ accent: "UK", phonetic: sym.ph_en.trim(), audioUrl: sym.ph_en_mp3?.trim() || null, source, isSynthetic: false });
  }
  if (sym.ph_am?.trim()) {
    result.push({ accent: "US", phonetic: sym.ph_am.trim(), audioUrl: sym.ph_am_mp3?.trim() || null, source, isSynthetic: false });
  }
  return result;
}

export function parseIcibaForms(info: IcibaWordInfo): DictionaryContent["forms"] {
  const result: DictionaryContent["forms"] = [];
  const exchange = info.baesInfo?.exchange;
  if (exchange) {
    const mapping: Array<[string, DictionaryContent["forms"][number]["type"]]> = [
      ["word_pl", "PLURAL"], ["word_third", "THIRD_PERSON"], ["word_past", "PAST"],
      ["word_done", "PAST_PARTICIPLE"], ["word_ing", "PRESENT_PARTICIPLE"],
      ["word_er", "COMPARATIVE"], ["word_est", "SUPERLATIVE"],
      ["word_adj", "OTHER"],
    ];
    for (const [key, type] of mapping) {
      const values = exchange[key];
      if (!values?.length) continue;
      for (const v of values) {
        const val = v.trim();
        if (!val) continue;
        result.push({ type, value: val, source });
      }
    }
  }
  const seen = new Set<string>();
  return result.filter((item) => {
    const key = `${item.type}|${item.value.toLowerCase()}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function parseIcibaExamples(info: IcibaWordInfo): DictionaryContent["examples"] {
  const result: DictionaryContent["examples"] = [];
  const seen = new Set<string>();

  const push = (en: string, cn: string | null) => {
    const sentence = decodeEntities(stripTags(en)).trim().replace(/\s*<\/seg>\s*/gi, " ").replace(/\s+/g, " ").trim();
    if (!sentence || sentence.length < 5) return;
    let translation: string | null = null;
    if (cn) {
      translation = decodeEntities(stripTags(cn)).trim().replace(/\s*<\/seg>\s*/gi, " ").replace(/\s+/g, " ").trim() || null;
    }
    const key = sentence.toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    result.push({ sentence, translation, source: exampleSource, isUserAdded: false });
  };

  // bidec sentences (authoritative)
  for (const part of info.bidec?.parts ?? []) {
    for (const mean of part.means ?? []) {
      for (const s of mean.sentences ?? []) {
        if (s.en) push(s.en, s.cn ?? null);
      }
    }
  }
  // ee_mean sentences (has only en, no translation)
  for (const group of info.ee_mean ?? []) {
    for (const mean of group.means ?? []) {
      for (const s of mean.sentences ?? []) {
        const en = (s as { sentence?: string }).sentence;
        if (en) push(en, null);
      }
    }
  }
  // new_sentence
  for (const block of info.new_sentence ?? []) {
    for (const s of block.sentences ?? []) {
      if (s.en) push(s.en, s.cn ?? null);
    }
  }
  // collins examples
  for (const block of info.collins ?? []) {
    for (const entry of block.entry ?? []) {
      for (const ex of entry.example ?? []) {
        if (ex.ex) push(ex.ex, ex.tran ?? null);
      }
    }
  }
  // phrase example sentences (lj)
  for (const p of info.phrase ?? []) {
    for (const jx of p.jx ?? []) {
      for (const lj of jx.lj ?? []) {
        if (lj.lj_ly) push(lj.lj_ly, lj.lj_ls ?? null);
      }
    }
  }

  return result.slice(0, 20);
}

export function parseIcibaPhrases(info: IcibaWordInfo): DictionaryContent["phrases"] {
  const result: DictionaryContent["phrases"] = [];
  const seen = new Set<string>();
  for (const p of info.phrase ?? []) {
    const phrase = decodeEntities(stripTags(p.cizu_name ?? "")).trim();
    if (!phrase || phrase.length < 2 || phrase.length > 80) continue;
    // jx may have multiple translations; take first
    const jx = p.jx?.[0];
    const translation = jx ? decodeEntities(stripTags(jx.jx_cn_mean ?? "")).trim() || null : null;
    const key = phrase.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push({ phrase, translation, source: phraseSource });
  }
  return result;
}

export function parseIcibaSynonyms(info: IcibaWordInfo): DictionaryContent["synonyms"] {
  const result: DictionaryContent["synonyms"] = [];
  const seen = new Set<string>();
  for (const group of info.synonym ?? []) {
    for (const mean of group.means ?? []) {
      for (const cis of mean.cis ?? []) {
        const word = decodeEntities(stripTags(cis)).trim();
        if (!word || word.length < 2 || word.length > 40) continue;
        if (!/^[a-zA-Z][a-zA-Z\s'-]*$/.test(word)) continue;
        const key = word.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        result.push({ word, translation: null, partOfSpeech: normalizePos(group.part_name ?? ""), relation: "SYNONYM", source });
      }
    }
  }
  return result;
}

export function parseIcibaWordFamily(): DictionaryContent["wordFamily"] {
  return [];
}

export function parseIcibaRoots(info: IcibaWordInfo): DictionaryContent["roots"] {
  const result: DictionaryContent["roots"] = [];
  for (const d of info.derivation ?? []) {
    const text = decodeEntities(stripTags(d.yuyuan_name ?? "")).trim();
    if (!text) continue;
    result.push({ root: info.baesInfo?.word_name ?? "", meaning: text, origin: null, source });
  }
  return result;
}

export function parseIcibaConfusedWords(info: IcibaWordInfo): DictionaryContent["confusedWords"] {
  const result: DictionaryContent["confusedWords"] = [];
  const seen = new Set<string>();
  for (const item of info.sameAnalysis ?? []) {
    const words = (item.word_list ?? "").split(/[,，]/).map((w) => w.trim()).filter(Boolean);
    for (const w of words) {
      if (!/^[a-zA-Z][a-zA-Z\s'-]*$/.test(w)) continue;
      const key = w.toLowerCase();
      if (seen.has(key)) continue;
      if (key === (info.baesInfo?.word_name ?? "").toLowerCase()) continue;
      seen.add(key);
      const idx = words.indexOf(w);
      const diff = item.means?.[idx] ? decodeEntities(stripTags(item.means[idx]!)).trim() : null;
      result.push({ word: w, translation: null, partOfSpeech: null, relation: "CONFUSED", source, difference: diff });
    }
  }
  return result;
}

export function parseIcibaSummary(info: IcibaWordInfo): DictionaryContent["summary"] {
  let frequency: DictionaryContent["summary"]["frequency"] = null;
  const freq = info.baesInfo?.frequence;
  if (typeof freq === "number") {
    if (freq >= 5) frequency = "VERY_COMMON";
    else if (freq === 4) frequency = "COMMON";
    else if (freq === 3) frequency = "NORMAL";
    else if (freq > 0) frequency = "RARE";
  }
  const firstMean = info.baesInfo?.symbols?.[0]?.parts?.[0]?.means?.[0];
  const shortDefinition = firstMean ? decodeEntities(stripTags(firstMean)).trim().slice(0, 120) || null : null;
  return { shortDefinition, translation: null, cefrLevel: null, frequency };
}

export function parseIcibaTags(info: IcibaWordInfo): string[] {
  const tags: string[] = [];
  const wordTag = info.baesInfo?.word_tag ?? [];
  const tagMap: Record<number, string> = { 1: "CET4", 2: "CET6", 3: "考研", 4: "初中", 5: "高中", 6: "COMMON" };
  for (const t of wordTag) {
    const label = tagMap[t];
    if (label && label !== "COMMON") tags.push(label);
  }
  return [...new Set(tags)];
}
