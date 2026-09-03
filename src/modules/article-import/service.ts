import crypto from "node:crypto";
import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import {
  ARTICLE_AI_CANDIDATE_LIMIT,
  ARTICLE_MAX_SEGMENTS,
  ARTICLE_PHRASE_LIMIT,
  ARTICLE_SENTENCE_LIMIT,
  ARTICLE_SENTENCE_MIN_CHARS,
  ARTICLE_SNIPPET_CHARS,
  IMPORT_PREVIEW_TTL_MS,
  MAX_ARTICLE_CANDIDATES,
  MAX_ARTICLE_CHARS,
  MIN_ARTICLE_CHARS,
} from "@/lib/config";
import { extractArticleTerms, extractSentences } from "./extract";
import { fallbackRecommendedTerms, mergeArticleCandidates, recommendedCandidateKeys } from "./candidates";
import type { ArticleCandidate, ArticleImportPreview, ArticleStats, ExamTarget, VocabularyLevel } from "@/lib/types";
import { getSettings } from "@/modules/settings/service";
import { aiSelectTerms } from "./ai-select";
import { normalizeTerm } from "@/modules/imports/normalizer";
import type { ArticleAiCard } from "@/lib/types/article-import";

export interface CreateArticlePreviewInput {
  articleText: string;
  sourceLanguage?: string;
  targetLanguage?: string;
  examTargets?: ExamTarget[];
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
  const settingsExamTargets = (settings.examTargets ?? (vocabularyLevel !== "AUTO" ? [vocabularyLevel as unknown as ExamTarget] : [])) as ExamTarget[];
  const examTargets = (Array.isArray(input.examTargets) ? input.examTargets : settingsExamTargets) as ExamTarget[];

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

export async function mergeArticlePreviews(tokens: string[]): Promise<ArticleImportPreview> {
  if (!tokens.length) throw new ApiError("VALIDATION_ERROR", "请选择至少一个段落预览进行合并。");
  if (tokens.length > ARTICLE_MAX_SEGMENTS) throw new ApiError("VALIDATION_ERROR", `最多合并 ${ARTICLE_MAX_SEGMENTS} 个段落。`);
  const now = Date.now();
  type Row = { token: string; filename: string; file_hash: string; rows_json: string; expires_at: number };
  const rows: Row[] = [];
  for (const token of tokens) {
    const row = await sqlite.prepare("SELECT token, filename, file_hash, rows_json, expires_at FROM import_previews WHERE token = ? AND expires_at > ? LIMIT 1").get(token, now) as Row | undefined;
    if (!row) throw new ApiError("IMPORT_PREVIEW_EXPIRED", `段落预览已过期或不存在：${token.slice(0, 8)}`);
    rows.push(row);
  }
  // Parse candidates from rows_json (ImportPreviewRow shape with _article)
  const allCandidates: ArticleCandidate[] = [];
  let aiApplied = false;
  const aiErrors: string[] = [];
  let sourceLanguage = "en";
  let targetLanguage = "zh-CN";
  let sourceLanguageName = "英语";
  let targetLanguageName = "简体中文";
  let totalWordCount = 0;
  let totalCharCount = 0;
  let fileHashBase = "";
  for (const row of rows) {
    const parsed = JSON.parse(row.rows_json) as Array<{ term: string; normalizedTerm: string; sourceLanguage: string; targetLanguage: string; sourceLanguageName: string; targetLanguageName: string; entryType: string; status: string; _article?: { occurrences: number; aiReason: string | null; difficulty: number | null; cefrLevel: string | null; frequency: string | null; entryType: string; sourceSentence: string | null; aiCard: ArticleAiCard | null } }>;
    if (parsed.length === 0) continue;
    // capture langs from first row
    if (rows.indexOf(row) === 0) {
      sourceLanguage = parsed[0]!.sourceLanguage ?? "en";
      targetLanguage = parsed[0]!.targetLanguage ?? "zh-CN";
      sourceLanguageName = parsed[0]!.sourceLanguageName ?? "英语";
      targetLanguageName = parsed[0]!.targetLanguageName ?? "简体中文";
      fileHashBase = row.file_hash;
    }
    for (const r of parsed) {
      const a = r._article;
      allCandidates.push({
        term: r.term,
        normalizedTerm: r.normalizedTerm,
        occurrences: a?.occurrences ?? 1,
        status: r.status === "EXISTING" ? "KNOWN" : "CANDIDATE",
        entryType: (a?.entryType ?? r.entryType ?? "WORD") as ArticleCandidate["entryType"],
        sourceSentence: a?.sourceSentence ?? null,
        aiReason: a?.aiReason ?? null,
        difficulty: a?.difficulty ?? null,
        cefrLevel: a?.cefrLevel ?? null,
        frequency: a?.frequency ?? null,
        aiCard: a?.aiCard ?? null,
      });
    }
    // also need to recover preview-level aiApplied/recommendedTerms: infer from candidates with aiReason
    // and from separate in-memory: we stored recommendedTerms/recommendedKeys only in preview response, not in rows_json.
    // So we reconstruct: candidates with aiReason/difficulty are considered recommended.
  }
  const deduped = mergeArticleCandidates(allCandidates);
  // Re-evaluate KNOWN against DB (in case dedup mixed)
  const existingRows = await sqlite.prepare("SELECT normalized_term, content_type FROM words WHERE source_language = ? AND target_language = ?").all(sourceLanguage, targetLanguage) as Array<{ normalized_term: string; content_type: string }>;
  const existingByKey = new Set(existingRows.map((r) => `${r.content_type ?? "WORD"}\u0000${r.normalized_term.toLowerCase()}`));
  for (const c of deduped) {
    const k = `${c.entryType ?? "WORD"}\u0000${c.normalizedTerm.toLowerCase()}`;
    if (existingByKey.has(k) || (existingByKey.has(`WORD\u0000${c.normalizedTerm.toLowerCase()}`) && c.entryType === "WORD")) {
      c.status = "KNOWN";
    }
  }
  // Cap phrases/sentences globally by difficulty
  const words = deduped.filter((c) => (c.entryType ?? "WORD") === "WORD");
  let phrases = deduped.filter((c) => c.entryType === "PHRASE").sort((a, b) => (b.difficulty ?? 0) - (a.difficulty ?? 0));
  let sentences = deduped.filter((c) => c.entryType === "SENTENCE").sort((a, b) => (b.difficulty ?? 0) - (a.difficulty ?? 0));
  if (phrases.length > ARTICLE_PHRASE_LIMIT) phrases = phrases.slice(0, ARTICLE_PHRASE_LIMIT);
  if (sentences.length > ARTICLE_SENTENCE_LIMIT) sentences = sentences.slice(0, ARTICLE_SENTENCE_LIMIT);
  const merged = [...words, ...phrases, ...sentences];
  // Stats
  const knownCount = merged.filter((c) => c.status === "KNOWN").length;
  const phraseCount = phrases.length;
  const sentenceCount = sentences.length;
  // wordCount/charCount: sum across segments (approximate via occurrences for wordCount, use charCount from merged text lengths)
  // Use allCandidates occurrences sum as wordCount proxy
  totalWordCount = allCandidates.filter((c) => (c.entryType ?? "WORD") === "WORD").reduce((a, c) => a + c.occurrences, 0);
  totalCharCount = rows.reduce((a, r) => {
    try { const p = JSON.parse(r.rows_json) as Array<{ _article?: { sourceSentence?: string | null } }>; return a + p.length * 6; } catch { return a; }
  }, 0);
  // Fallback: compute from dedup text
  if (totalCharCount < 100) totalCharCount = merged.reduce((a, c) => a + c.term.length + 2, 0);
  aiApplied = merged.some((c) => c.aiReason != null || c.aiCard != null);
  const fallbackRecommended = fallbackRecommendedTerms(merged);
  const recommendedKeys = recommendedCandidateKeys(merged, fallbackRecommended);
  const uniqueCount = merged.filter((c) => (c.entryType ?? "WORD") === "WORD").length || merged.length;
  const articleStats: ArticleStats = {
    charCount: totalCharCount,
    wordCount: totalWordCount || uniqueCount * 2,
    uniqueCount,
    knownCount,
    unknownCount: merged.filter((c) => c.status === "CANDIDATE").length,
    phraseCount,
    sentenceCount,
  };
  const token = crypto.randomUUID();
  const expiresAt = new Date(now + IMPORT_PREVIEW_TTL_MS);
  const filename = `article-merge:${crypto.createHash("sha256").update(fileHashBase + tokens.join("|")).digest("hex").slice(0, 8)}`;
  const rowsForImport = merged.map((c, index) => ({
    rowNumber: index + 1,
    term: c.term,
    normalizedTerm: c.normalizedTerm,
    sourceLanguage,
    targetLanguage,
    sourceLanguageName,
    targetLanguageName,
    entryType: c.entryType,
    sourceCreatedAt: null,
    status: c.status === "KNOWN" ? ("EXISTING" as const) : ("NEW" as const),
    errors: [] as string[],
    _article: { occurrences: c.occurrences, aiReason: c.aiReason, difficulty: c.difficulty, cefrLevel: c.cefrLevel, frequency: c.frequency, entryType: c.entryType, sourceSentence: c.sourceSentence ?? null, aiCard: c.aiCard ?? null },
  }));
  await sqlite.prepare("INSERT INTO import_previews(token, filename, file_hash, rows_json, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)").run(token, filename, crypto.createHash("sha256").update(rowsForImport.map((r) => r.normalizedTerm).join("|")).digest("hex"), JSON.stringify(rowsForImport), expiresAt.getTime(), now);
  return {
    previewToken: token,
    filename,
    articleStats,
    candidates: merged,
    recommendedTerms: fallbackRecommended,
    recommendedKeys,
    aiApplied,
    aiError: aiErrors.length ? aiErrors.join("；") : null,
    totalCandidates: merged.length,
    knownCount,
    expiresAt: expiresAt.toISOString(),
  };
}
