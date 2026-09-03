import { ARTICLE_MAX_SEGMENTS, ARTICLE_SEGMENTS_PER_BATCH_MAX, ARTICLE_SEGMENT_MAX_CHARS, ARTICLE_SEGMENT_TARGET_CHARS } from "@/lib/config";
import { normalizeTerm, identityKey } from "@/modules/imports/normalizer";

export const STOPWORDS = new Set([
  "a","an","the","and","or","but","if","then","else","when","while","of","to","in","on","at","by","for","with","about","against","between","into","through","during","before","after","above","below","from","up","down","out","over","under","again","further","once",
  "i","me","my","mine","you","your","yours","he","him","his","she","her","hers","it","its","we","us","our","ours","they","them","their","theirs",
  "is","am","are","was","were","be","been","being","have","has","had","do","does","did","will","would","shall","should","may","might","must","can","could",
  "this","that","these","those","there","here","what","which","who","whom","why","how","as","so","than","too","very","just","also","only","even","not","no","nor","own","same","such",
]);

export interface ExtractedTerm {
  term: string;
  normalizedTerm: string;
  occurrences: number;
}

export interface ArticleExtractResult {
  cleaned: string;
  wordCount: number;
  extracted: ExtractedTerm[];
}

function cleanArticle(raw: string): string {
  return raw.normalize("NFKC").replace(/\r\n/g, "\n").replace(/[ \t]+/g, " ").trim();
}

export function extractSentences(cleaned: string): string[] {
  try {
    const segmenter = new (Intl as unknown as { Segmenter: new (l:string, o:unknown)=>{segment:(s:string)=>Iterable<{segment:string}>} }).Segmenter("en", { granularity: "sentence" });
    const raw = [...segmenter.segment(cleaned)].map((s) => s.segment.trim()).filter(Boolean);
    if (raw.length) return raw;
  } catch {}
  const parts = cleaned.match(/[^.!?。！？]+[.!?。！？]+/g) ?? [];
  const rest = cleaned.replace(/[^.!?。！？]+[.!?。！？]+/g, "").trim();
  const out = parts.map((s) => s.trim());
  if (rest) out.push(rest);
  return out.filter(Boolean);
}

export function extractArticleTerms(articleText: string, sourceLanguage = "en", targetLanguage = "zh-CN"): ArticleExtractResult {
  const cleaned = cleanArticle(articleText);
  const rawTokens = cleaned.match(/[A-Za-z][A-Za-z'-]*/g) ?? [];
  const wordCount = rawTokens.length;

  const counts = new Map<string, { term: string; count: number }>();

  for (const token of rawTokens) {
    const stripped = token.replace(/^'+|'+$/g, "").replace(/^-+|-+$/g, "");
    if (stripped.length < 2 || stripped.length > 30) continue;
    if (/^\d+$/.test(stripped)) continue;
    const lower = stripped.toLowerCase();
    if (STOPWORDS.has(lower)) continue;

    const normalized = normalizeTerm(stripped, sourceLanguage);
    if (normalized.length < 2 || normalized.length > 30) continue;
    if (STOPWORDS.has(normalized)) continue;

    const key = identityKey(normalized, sourceLanguage, targetLanguage);
    const existing = counts.get(key);
    if (existing) existing.count += 1;
    else counts.set(key, { term: stripped, count: 1 });
  }

  const extracted: ExtractedTerm[] = [...counts.entries()]
    .map(([key, value]) => {
      const normalizedTerm = key.split("\u0000")[0] ?? value.term.toLowerCase();
      return { term: value.term, normalizedTerm, occurrences: value.count };
    })
    .sort((a, b) => b.occurrences - a.occurrences || b.term.length - a.term.length || a.term.localeCompare(b.term));

  return { cleaned, wordCount, extracted };
}


export interface ParagraphSegment {
  id: string;
  index: number;
  text: string;
  charCount: number;
}

function splitIntoParagraphs(normalized: string): string[] {
  const withParagraphs = normalized.split(/\n\s*\n/).map((s) => s.trim()).filter(Boolean);
  if (withParagraphs.length > 1) return withParagraphs;
  // single block but with single newlines: treat each non-empty line as paragraph
  const lines = normalized.split(/\n/).map((s) => s.trim()).filter(Boolean);
  if (lines.length >= 2 && normalized.includes("\n")) return lines;
  return [normalized.trim()].filter(Boolean);
}

export function segmentArticleParagraphs(articleText: string, opts?: { maxSegments?: number; targetChars?: number; maxChars?: number }): ParagraphSegment[] {
  const maxSegments = opts?.maxSegments ?? ARTICLE_MAX_SEGMENTS;
  const targetChars = opts?.targetChars ?? ARTICLE_SEGMENT_TARGET_CHARS;
  const maxChars = opts?.maxChars ?? ARTICLE_SEGMENT_MAX_CHARS;
  const raw = articleText.normalize("NFKC").replace(/\r\n/g, "\n").trim();
  if (!raw) return [];
  const paras = splitIntoParagraphs(raw);
  // 轻量合并：仅当末段极短（<60字符）时拼到前一段，避免极短尾段单独请求
  // 尊重用户按空行划分的段落意图，不对中间段落做激进合并
  const TAIL_MERGE_THRESHOLD = 60;
  while (paras.length > 1 && paras[paras.length - 1]!.length < TAIL_MERGE_THRESHOLD) {
    const tail = paras.pop()!;
    paras[paras.length - 1] = paras[paras.length - 1]! + "\n\n" + tail;
  }
  // split overlong paragraphs by sentences
  const out: string[] = [];
  for (const para of paras) {
    if (para.length <= maxChars) {
      out.push(para);
      continue;
    }
    const sentences = extractSentences(para);
    if (sentences.length <= 1) {
      // hard slice by targetChars
      for (let i = 0; i < para.length; i += targetChars) out.push(para.slice(i, i + targetChars).trim());
      continue;
    }
    let buf = "";
    for (const s of sentences) {
      if (buf.length + s.length + 1 > targetChars && buf) {
        out.push(buf.trim());
        buf = s;
      } else {
        buf = buf ? buf + " " + s : s;
      }
      if (buf.length >= maxChars) {
        out.push(buf.trim());
        buf = "";
      }
    }
    if (buf.trim()) out.push(buf.trim());
  }
  // cap to maxSegments by merging smallest neighbors
  let segments = out.map((text, index) => ({ id: `seg-${index + 1}`, index, text, charCount: text.length }));
  while (segments.length > maxSegments) {
    let minIdx = 0;
    let minSum = Infinity;
    for (let i = 0; i < segments.length - 1; i++) {
      const sum = segments[i]!.charCount + segments[i + 1]!.charCount;
      if (sum < minSum) { minSum = sum; minIdx = i; }
    }
    const a = segments[minIdx]!;
    const b = segments[minIdx + 1]!;
    const mergedSeg = { id: a.id, index: a.index, text: a.text + "\n\n" + b.text, charCount: a.charCount + 2 + b.charCount };
    segments = [...segments.slice(0, minIdx), mergedSeg, ...segments.slice(minIdx + 2)].map((s, idx) => ({ ...s, index: idx, id: `seg-${idx + 1}` }));
  }
  return segments.map((s, idx) => ({ ...s, index: idx, id: `seg-${idx + 1}` }));
}

export function batchesForSegments(segments: ParagraphSegment[], segmentsPerBatch: number): Array<{ batchIndex: number; segmentIds: string[]; charCount: number }> {
  const perBatch = Math.max(1, Math.min(ARTICLE_SEGMENTS_PER_BATCH_MAX, segmentsPerBatch));
  const batches: Array<{ batchIndex: number; segmentIds: string[]; charCount: number }> = [];
  for (let i = 0; i < segments.length; i += perBatch) {
    const slice = segments.slice(i, i + perBatch);
    batches.push({ batchIndex: batches.length, segmentIds: slice.map((s) => s.id), charCount: slice.reduce((a, s) => a + s.charCount, 0) });
  }
  return batches;
}

