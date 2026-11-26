import { ARTICLE_DEFAULT_RECOMMENDED_LIMIT } from "@/lib/config";
import type { ArticleCandidate, ArticleImportPreview } from "@/lib/types/article-import";

/** Composite key entryType\0normalizedTerm：跨 WORD/PHRASE/SENTENCE 选中不串 key。 */
export function articleCandidateKey(candidate: Pick<ArticleCandidate, "entryType" | "normalizedTerm">): string {
  const normalized = candidate.normalizedTerm.normalize("NFKC").toLowerCase();
  return `${candidate.entryType ?? "WORD"}\u0000${normalized}`;
}

export function mergeArticleCandidates(candidates: ArticleCandidate[]): ArticleCandidate[] {
  const mergedByKey = new Map<string, ArticleCandidate>();
  for (const candidate of candidates) {
    const key = articleCandidateKey(candidate);
    const existing = mergedByKey.get(key);
    if (!existing) {
      mergedByKey.set(key, { ...candidate });
      continue;
    }
    existing.occurrences += candidate.occurrences;
    if ((candidate.difficulty ?? 0) > (existing.difficulty ?? 0)) {
      existing.difficulty = candidate.difficulty;
      existing.cefrLevel = candidate.cefrLevel ?? existing.cefrLevel;
      existing.frequency = candidate.frequency ?? existing.frequency;
    }
    if (!existing.aiReason && candidate.aiReason) existing.aiReason = candidate.aiReason;
    if (!existing.sourceSentence && candidate.sourceSentence) existing.sourceSentence = candidate.sourceSentence;
    if (!existing.aiCard && candidate.aiCard) existing.aiCard = candidate.aiCard;
    if (candidate.status === "KNOWN") existing.status = "KNOWN";
  }
  return [...mergedByKey.values()];
}

/** AI 推荐词缀：有 aiReason 的优先，否则取前 limit 个待学单词。 */
export function fallbackRecommendedTerms(merged: ArticleCandidate[], limit = ARTICLE_DEFAULT_RECOMMENDED_LIMIT): string[] {
  const aiPicked = merged
    .filter((c) => c.status === "CANDIDATE" && c.entryType === "WORD" && c.aiReason)
    .map((c) => c.normalizedTerm.toLowerCase());
  if (aiPicked.length > 0) return aiPicked;
  return merged
    .filter((c) => c.status === "CANDIDATE" && c.entryType === "WORD")
    .map((c) => c.normalizedTerm.toLowerCase())
    .slice(0, limit);
}

/** 拼接多个 batch preview 的 aiError：同 token 只算一次，避免同批多个段重复展示。 */
export function mergeAiErrors(previews: Array<{ previewToken: string; aiError?: string | null }>): string | null {
  const seen = new Set<string>();
  const messages: string[] = [];
  for (const preview of previews) {
    const message = preview.aiError?.trim();
    if (!message) continue;
    // 同一 previewToken 视为同一批次，只保留一次；不同批次相同文案合并计数。
    const dedupeKey = `${preview.previewToken} ${message}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    messages.push(message);
  }
  if (messages.length === 0) return null;
  const counted = new Map<string, number>();
  for (const message of messages) counted.set(message, (counted.get(message) ?? 0) + 1);
  return [...counted.entries()]
    .map(([message, count]) => (count > 1 ? `${message}（${count} 批）` : message))
    .join("；");
}

/** 客户端合并多个 batch preview（分段导入的增量展示与重试后重合并共用）。 */
export function mergeArticlePreviews(previews: ArticleImportPreview[]): ArticleImportPreview | null {
  if (previews.length === 0) return null;
  if (previews.length === 1) return previews[0]!;
  // 同一批的多个段共享同一个 preview 对象/Token：先按 token 去重，
  // 否则 aiError、wordCount/charCount 会按段数重复累加。
  const deduped = [...new Map(previews.map((p) => [p.previewToken, p])).values()];
  const merged = mergeArticleCandidates(deduped.flatMap((p) => p.candidates));
  const phraseCount = merged.filter((c) => c.entryType === "PHRASE").length;
  const sentenceCount = merged.filter((c) => c.entryType === "SENTENCE").length;
  const knownCount = merged.filter((c) => c.status === "KNOWN").length;
  const first = deduped[0]!;
  const aiApplied = deduped.some((p) => p.aiApplied) || merged.some((c) => c.aiReason != null || c.aiCard != null);
  const fallback = fallbackRecommendedTerms(merged);
  const recommendedKeys = recommendedCandidateKeys(merged, fallback);
  const uniqueCount = merged.filter((c) => (c.entryType ?? "WORD") === "WORD").length || merged.length;
  const totalWordCount = deduped.reduce((a, p) => a + p.articleStats.wordCount, 0);
  const totalCharCount = deduped.reduce((a, p) => a + p.articleStats.charCount, 0);
  return {
    previewToken: first.previewToken,
    filename: first.filename,
    articleStats: {
      charCount: totalCharCount,
      wordCount: totalWordCount || uniqueCount * 2,
      uniqueCount,
      knownCount,
      unknownCount: merged.filter((c) => c.status === "CANDIDATE").length,
      phraseCount,
      sentenceCount,
    },
    candidates: merged,
    recommendedTerms: fallback,
    recommendedKeys,
    aiApplied,
    aiError: mergeAiErrors(deduped),
    totalCandidates: merged.length,
    knownCount,
    expiresAt: first.expiresAt,
  };
}
/** 初次选中 key：服务端给了 recommendedKeys 就用它，否则按推荐词缀+全部短语/句子拼。 */
export function initialSelectionKeys(data: { recommendedKeys?: string[]; recommendedTerms: string[]; candidates: ArticleCandidate[] }): Set<string> {
  const keys = data.recommendedKeys?.length
    ? data.recommendedKeys.map((k) => k.toLowerCase())
    : recommendedCandidateKeys(
        data.candidates,
        data.recommendedTerms.length ? data.recommendedTerms : fallbackRecommendedTerms(data.candidates),
      ).map((k) => k.toLowerCase());
  return new Set(keys);
}
/** 推荐选中 key：单词只选推荐词缀，短语/句子全部待学都选。 */
export function recommendedCandidateKeys(merged: ArticleCandidate[], recommendedTerms: string[]): string[] {
  const recommendedSet = new Set(recommendedTerms);
  const wordKeys = merged
    .filter((c) => c.status === "CANDIDATE" && c.entryType === "WORD" && recommendedSet.has(c.normalizedTerm.toLowerCase()))
    .map((c) => articleCandidateKey(c));
  const phraseKeys = merged
    .filter((c) => c.status === "CANDIDATE" && c.entryType !== "WORD")
    .map((c) => articleCandidateKey(c));
  return [...wordKeys, ...phraseKeys];
}
