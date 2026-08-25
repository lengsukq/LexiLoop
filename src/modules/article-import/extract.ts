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

export function extractArticleTerms(articleText: string): ArticleExtractResult {
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

    const normalized = normalizeTerm(stripped, "en");
    if (normalized.length < 2 || normalized.length > 30) continue;
    if (STOPWORDS.has(normalized)) continue;

    const key = identityKey(normalized, "en", "zh-CN");
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
