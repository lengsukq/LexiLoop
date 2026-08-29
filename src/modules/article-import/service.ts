import crypto from "node:crypto";
import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import {
  ARTICLE_AI_CANDIDATE_LIMIT,
  ARTICLE_PHRASE_LIMIT,
  ARTICLE_SENTENCE_LIMIT,
  ARTICLE_SENTENCE_MIN_CHARS,
  ARTICLE_SNIPPET_CHARS,
  IMPORT_PREVIEW_TTL_MS,
  MAX_ARTICLE_CANDIDATES,
  MAX_ARTICLE_CHARS,
  MIN_ARTICLE_CHARS,
} from "@/lib/config";
import type { ArticleCandidate, ArticleImportPreview, ArticleStats, ExamTarget, VocabularyLevel } from "@/lib/types";
import { getSettings } from "@/modules/settings/service";
import { aiSelectTerms } from "./ai-select";
import { extractArticleTerms, extractSentences } from "./extract";
import { normalizeTerm } from "@/modules/imports/normalizer";
import type { ArticleAiCard } from "@/lib/types/article-import";

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

  const { cleaned, wordCount, extracted } = extractArticleTerms(rawText, sourceLanguage, targetLanguage);

  if (extracted.length === 0) throw new ApiError("VALIDATION_ERROR", "未能从文章中提取到有效单词，请检查是否为英文文章。");

  const now = Date.now();
  await sqlite.prepare("DELETE FROM import_previews WHERE expires_at < ?").run(now);

  const existingRows = await sqlite.prepare(
    "SELECT normalized_term, content_type FROM words WHERE source_language = ? AND target_language = ?",
  ).all(sourceLanguage, targetLanguage) as Array<{ normalized_term: string; content_type: string }>;
  const existingByKey = new Set(existingRows.map((row) => `${row.content_type ?? "WORD"}\u0000${row.normalized_term.toLowerCase()}`));
  const existingWordSet = new Set(existingRows.filter((r) => (r.content_type ?? "WORD") === "WORD").map((row) => row.normalized_term.toLowerCase()));

  const settings = await getSettings();
  const vocabularyLevel = (settings.vocabularyLevel ?? "AUTO") as VocabularyLevel;
  const examTargets = (settings.examTargets ?? (vocabularyLevel !== "AUTO" ? [vocabularyLevel as unknown as ExamTarget] : [])) as ExamTarget[];

  const knownSample = existingRows.slice(0, 30).map((row) => row.normalized_term);
  const totalKnown = existingRows.length;

  const sentencesRaw = extractSentences(cleaned).filter((s) => s.length >= ARTICLE_SENTENCE_MIN_CHARS).slice(0, 40);
  const truncated = extracted.slice(0, MAX_ARTICLE_CANDIDATES);

  const candidates: ArticleCandidate[] = truncated.map((item) => ({
    term: item.term,
    normalizedTerm: item.normalizedTerm,
    occurrences: item.occurrences,
    status: existingWordSet.has(item.normalizedTerm.toLowerCase()) ? "KNOWN" : "CANDIDATE",
    entryType: "WORD" as const,
    sourceSentence: null,
    aiReason: null,
    difficulty: null,
    cefrLevel: null,
    frequency: null,
    aiCard: null,
  }));

  const termToSentence = new Map<string, string>();
  for (const item of candidates) {
    if (!item.sourceSentence) {
      const hit = sentencesRaw.find((s) => s.toLowerCase().includes(item.term.toLowerCase()));
      if (hit) (item as unknown as { sourceSentence: string | null }).sourceSentence = hit;
    }
    termToSentence.set(item.normalizedTerm.toLowerCase(), (item.sourceSentence as string | null) ?? "");
  }
  const aiCandidates = candidates
    .filter((item) => item.status === "CANDIDATE")
    .slice(0, ARTICLE_AI_CANDIDATE_LIMIT)
    .map((item) => ({ term: item.term, normalizedTerm: item.normalizedTerm, occurrences: item.occurrences, sourceSentence: (item.sourceSentence as string | null) ?? undefined }));

  let aiApplied = false;
  let aiError: string | null = null;
  let recommendedTerms: string[] = candidates.filter((c) => c.status === "CANDIDATE").map((c) => c.normalizedTerm.toLowerCase());

  function toCard(phrase: { literalTranslation: string; freeTranslation: string; keyVocab: Array<{ term: string; pos: string | null; meaning: string }>; grammarPattern: string | null; grammarNotes: string[]; nuance: string | null }): ArticleAiCard {
    return {
      literalTranslation: phrase.literalTranslation,
      freeTranslation: phrase.freeTranslation,
      keyVocab: phrase.keyVocab,
      grammarPattern: phrase.grammarPattern,
      grammarNotes: phrase.grammarNotes,
      nuance: phrase.nuance,
    };
  }


  if (aiCandidates.length > 0) {
    const snippet = cleaned.slice(0, ARTICLE_SNIPPET_CHARS);
    const result = await aiSelectTerms({
      articleText: snippet + (sentencesRaw.length ? "\n\n<sentences>" + JSON.stringify(sentencesRaw.slice(0, 15)) + "</sentences>" : ""),
      candidates: aiCandidates,
      knownSample,
      totalKnown,
      examTargets,
      vocabularyLevel,
    });
    if (result.applied) {
      const hasContent = (result.words.length > 0) || (result.phrases.length > 0) || (result.sentences.length > 0);
      if (hasContent) aiApplied = true;
      const metaByTerm = new Map(result.words.map((s) => [s.term.toLowerCase(), s] as const));
      const metaByNorm = new Map(result.words.map((s) => [s.term.normalize("NFKC").toLowerCase(), s] as const));
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
      const selectedSet = new Set(result.words.map((s) => s.term.toLowerCase()));
      const normalizedSelectedSet = new Set(result.words.map((s) => s.term.normalize("NFKC").toLowerCase()));
      if (result.words.length > 0) {
        recommendedTerms = candidates
          .filter((c) => selectedSet.has(c.term.toLowerCase()) || normalizedSelectedSet.has(c.normalizedTerm.toLowerCase()))
          .map((c) => c.normalizedTerm.toLowerCase());
      }
      // Build PHRASE/SENTENCE candidates from AI outputs (dedupe by normalizedTerm, capped)
      const seenKeys = new Set(candidates.map((c) => `${c.entryType}\u0000${c.normalizedTerm.toLowerCase()}`));
      for (const ph of result.phrases.slice(0, ARTICLE_PHRASE_LIMIT)) {
        const norm = normalizeTerm(ph.term, sourceLanguage);
        const key = `PHRASE\u0000${norm.toLowerCase()}`;
        if (seenKeys.has(key) || existingByKey.has(key)) continue;
        const existingNorm = existingByKey.has(key);
        candidates.push({
          term: ph.term,
          normalizedTerm: norm,
          occurrences: 1,
          status: existingNorm ? "KNOWN" : "CANDIDATE",
          entryType: "PHRASE",
          sourceSentence: sentencesRaw.find((s) => s.toLowerCase().includes(ph.term.toLowerCase())) ?? null,
          aiReason: ph.reason,
          difficulty: ph.difficulty,
          cefrLevel: ph.cefrLevel,
          frequency: null,
          aiCard: toCard(ph),
        });
        seenKeys.add(key);
      }
      for (const se of result.sentences.slice(0, ARTICLE_SENTENCE_LIMIT)) {
        const sent = se.sentence.trim();
        const norm = normalizeTerm(sent, sourceLanguage);
        const key = `SENTENCE\u0000${norm.toLowerCase()}`;
        if (seenKeys.has(key) || existingByKey.has(key)) continue;
        const existingNorm = existingByKey.has(key);
        candidates.push({
          term: sent,
          normalizedTerm: norm,
          occurrences: 1,
          status: existingNorm ? "KNOWN" : "CANDIDATE",
          entryType: "SENTENCE",
          sourceSentence: sent,
          aiReason: null,
          difficulty: null,
          cefrLevel: null,
          frequency: null,
          aiCard: {
            literalTranslation: se.literalTranslation,
            freeTranslation: se.freeTranslation,
            keyVocab: se.keyVocab,
            grammarPattern: se.grammarPattern,
            grammarNotes: se.grammarNotes,
            nuance: se.nuance,
          },
        });
        seenKeys.add(key);
      }

      if (result.error) aiError = result.error;
    } else if (result.error) {
      aiError = result.error;
    }
  }

  const phraseCount = candidates.filter((c) => c.entryType === "PHRASE").length;
  const sentenceCount = candidates.filter((c) => c.entryType === "SENTENCE").length;
  const articleStats: ArticleStats = {
    charCount: rawText.length,
    wordCount,
    uniqueCount: extracted.length,
    knownCount: candidates.filter((c) => c.status === "KNOWN").length,
    unknownCount: candidates.filter((c) => c.status === "CANDIDATE").length,
    phraseCount,
    sentenceCount,
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
    entryType: c.entryType,
    sourceCreatedAt: null,
    status: c.status === "KNOWN" ? ("EXISTING" as const) : ("NEW" as const),
    errors: [] as string[],
    _article: { occurrences: c.occurrences, aiReason: c.aiReason, difficulty: c.difficulty, cefrLevel: c.cefrLevel, frequency: c.frequency, entryType: c.entryType, sourceSentence: c.sourceSentence ?? null, aiCard: c.aiCard ?? null },
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

  const recommendedKeys = candidates
    .filter((c) => c.status === "CANDIDATE" && recommendedTerms.includes(c.normalizedTerm.toLowerCase()) && c.entryType === "WORD")
    .map((c) => `${c.entryType}\u0000${c.normalizedTerm.toLowerCase()}`)
    .concat(candidates.filter((c) => c.status === "CANDIDATE" && c.entryType !== "WORD").map((c) => `${c.entryType}\u0000${c.normalizedTerm.toLowerCase()}`));
  return {
    previewToken: token,
    filename,
    articleStats,
    candidates,
    recommendedTerms,
    recommendedKeys,
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
