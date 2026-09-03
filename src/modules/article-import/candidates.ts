import { ARTICLE_DEFAULT_RECOMMENDED_LIMIT } from "@/lib/config";
import type { ArticleCandidate } from "@/lib/types/article-import";

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
