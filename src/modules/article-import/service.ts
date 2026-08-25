import crypto from "node:crypto";
import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import {
  ARTICLE_AI_CANDIDATE_LIMIT,
  ARTICLE_SNIPPET_CHARS,
  IMPORT_PREVIEW_TTL_MS,
  MAX_ARTICLE_CANDIDATES,
  MAX_ARTICLE_CHARS,
  MIN_ARTICLE_CHARS,
} from "@/lib/config";
import type { ArticleCandidate, ArticleImportPreview, ArticleStats, VocabularyLevel } from "@/lib/types";
import { getSettings } from "@/modules/settings/service";
import { aiSelectTerms } from "./ai-select";
import { extractArticleTerms } from "./extract";

export interface CreateArticlePreviewInput {
  articleText: string;
  sourceLanguage?: string;
  targetLanguage?: string;
}

function clampArticleText(raw: string): string {
  const text = raw.normalize("NFKC");
  if (text.trim().length < MIN_ARTICLE_CHARS) throw new ApiError("VALIDATION_ERROR", `文章至少需要 ${MIN_ARTICLE_CHARS} 个字符。`);
  if (text.length > MAX_ARTICLE_CHARS) throw new ApiError("VALIDATION_ERROR", `文章不能超过 ${MAX_ARTICLE_CHARS} 字符。`);
  return text;
}

export async function createArticlePreview(input: CreateArticlePreviewInput): Promise<ArticleImportPreview> {
  const rawText = clampArticleText(input.articleText);
  const sourceLanguage = (input.sourceLanguage ?? "en").trim() || "en";
  const targetLanguage = (input.targetLanguage ?? "zh-CN").trim() || "zh-CN";

  const { cleaned, wordCount, extracted } = extractArticleTerms(rawText);

  if (extracted.length === 0) throw new ApiError("VALIDATION_ERROR", "未能从文章中提取到有效单词，请检查是否为英文文章。");

  const now = Date.now();
  await sqlite.prepare("DELETE FROM import_previews WHERE expires_at < ?").run(now);

  const existingRows = await sqlite.prepare(
    "SELECT normalized_term FROM words WHERE source_language = ? AND target_language = ?",
  ).all(sourceLanguage, targetLanguage) as Array<{ normalized_term: string }>;
  const existingSet = new Set(existingRows.map((row) => row.normalized_term.toLowerCase()));

  const settings = await getSettings();
  const vocabularyLevel = (settings.vocabularyLevel ?? "AUTO") as VocabularyLevel;

  const knownSample = existingRows.slice(0, 30).map((row) => row.normalized_term);
  const totalKnown = existingRows.length;

  const truncated = extracted.slice(0, MAX_ARTICLE_CANDIDATES);

  const candidates: ArticleCandidate[] = truncated.map((item) => ({
    term: item.term,
    normalizedTerm: item.normalizedTerm,
    occurrences: item.occurrences,
    status: existingSet.has(item.normalizedTerm.toLowerCase()) ? "KNOWN" : "CANDIDATE",
    aiReason: null,
    difficulty: null,
    cefrLevel: null,
    frequency: null,
  }));

  const aiCandidates = candidates
    .filter((item) => item.status === "CANDIDATE")
    .slice(0, ARTICLE_AI_CANDIDATE_LIMIT)
    .map((item) => ({ term: item.term, normalizedTerm: item.normalizedTerm, occurrences: item.occurrences }));

  let aiApplied = false;
  let aiError: string | null = null;
  let recommendedTerms: string[] = candidates.filter((c) => c.status === "CANDIDATE").map((c) => c.normalizedTerm.toLowerCase());

  if (aiCandidates.length > 0) {
    const snippet = cleaned.slice(0, ARTICLE_SNIPPET_CHARS);
    const result = await aiSelectTerms({
      articleText: snippet,
      candidates: aiCandidates,
      knownSample,
      totalKnown,
      vocabularyLevel,
    });
    if (result.applied && result.selected.length > 0) {
      aiApplied = true;
      const selectedSet = new Set(result.selected.map((s) => s.term.toLowerCase()));
      const normalizedSelectedSet = new Set(result.selected.map((s) => s.term.normalize("NFKC").toLowerCase()));
      const metaByTerm = new Map(result.selected.map((s) => [s.term.toLowerCase(), s] as const));
      const metaByNorm = new Map(result.selected.map((s) => [s.term.normalize("NFKC").toLowerCase(), s] as const));

      for (const c of candidates) {
        const key = c.term.toLowerCase();
        const normKey = c.normalizedTerm.toLowerCase();
        const meta = metaByTerm.get(key) ?? metaByNorm.get(normKey) ?? null;
        if (meta) {
          c.aiReason = meta.reason;
          c.difficulty = meta.difficulty;
          c.cefrLevel = meta.cefrLevel;
          c.frequency = meta.frequency;
        }
      }

      recommendedTerms = candidates
        .filter((c) => selectedSet.has(c.term.toLowerCase()) || normalizedSelectedSet.has(c.normalizedTerm.toLowerCase()))
        .map((c) => c.normalizedTerm.toLowerCase());
    } else if (result.error) {
      aiError = result.error;
    }
  }

  const articleStats: ArticleStats = {
    charCount: rawText.length,
    wordCount,
    uniqueCount: extracted.length,
    knownCount: candidates.filter((c) => c.status === "KNOWN").length,
    unknownCount: candidates.filter((c) => c.status === "CANDIDATE").length,
  };

  const token = crypto.randomUUID();
  const expiresAt = new Date(now + IMPORT_PREVIEW_TTL_MS);
  const filename = `article:${crypto.createHash("sha256").update(rawText).digest("hex").slice(0, 8)}`;

  const rowsForImport = candidates.map((c, index) => ({
    rowNumber: index + 1,
    term: c.term,
    normalizedTerm: c.normalizedTerm,
    sourceLanguage,
    targetLanguage,
    sourceLanguageName: sourceLanguage === "en" ? "英语" : sourceLanguage,
    targetLanguageName: targetLanguage === "zh-CN" ? "简体中文" : targetLanguage,
    entryType: "WORD" as const,
    sourceCreatedAt: null,
    status: c.status === "KNOWN" ? ("EXISTING" as const) : ("NEW" as const),
    errors: [] as string[],
    _article: { occurrences: c.occurrences, aiReason: c.aiReason, difficulty: c.difficulty, cefrLevel: c.cefrLevel, frequency: c.frequency },
  }));

  await sqlite.prepare(
    "INSERT INTO import_previews(token, filename, file_hash, rows_json, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).run(
    token,
    filename,
    crypto.createHash("sha256").update(rawText).digest("hex"),
    JSON.stringify(rowsForImport),
    expiresAt.getTime(),
    now,
  );

  return {
    previewToken: token,
    filename,
    articleStats,
    candidates,
    recommendedTerms,
    aiApplied,
    aiError,
    totalCandidates: candidates.length,
    knownCount: articleStats.knownCount,
    expiresAt: expiresAt.toISOString(),
  };
}

export async function getArticlePreview(token: string) {
  const row = await sqlite.prepare("SELECT * FROM import_previews WHERE token = ? AND expires_at > ? LIMIT 1").get(token, Date.now()) as
    | { token: string; filename: string; file_hash: string; rows_json: string; expires_at: number; created_at: number }
    | undefined;
  return row ?? null;
}
