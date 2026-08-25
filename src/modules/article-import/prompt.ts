import type { VocabularyLevel } from "@/lib/types";

const LEVEL_HINT: Record<VocabularyLevel, string> = {
  AUTO: "根据用户的已知词情况自适应判断；常见基础词不要选。",
  CET4: "用户约 CET-4 水平：A1-B1 基础词视为已知，不选；重点选 B2 及以上。",
  CET6: "用户约 CET-6 水平：B1 及以下视为已知，不选；重点选 B2-C1。",
  KY: "用户约考研水平：B1 及以下视为已知，不选；重点选 B2-C1 学术/形近易混词。",
  IELTS: "用户约雅思 6.5+ 水平：B2 及以下视为已知，不选；重点选 C1-C2 与学术词汇。",
  TOEFL: "用户约托福 90+ 水平：B2 及以下视为已知，不选；重点选 C1-C2 学术与低频词。",
};

export function buildArticleSelectionPrompt(input: {
  articleText: string;
  candidates: Array<{ term: string; normalizedTerm: string; occurrences: number }>;
  knownSample: string[];
  totalKnown: number;
  vocabularyLevel: VocabularyLevel;
}): { systemPrompt: string; userPrompt: string } {
  const systemPrompt = "只输出有效 JSON，不要输出任何解释或 markdown。";

  const articleSnippet = input.articleText.slice(0, 8000);

  const userPrompt = [
    "你是词汇筛选助手。根据文章与候选词，选出值得该用户学习的单词。",
    `用户水平：${input.vocabularyLevel} — ${LEVEL_HINT[input.vocabularyLevel]}`,
    `用户已掌握词数：${input.totalKnown}，示例：${input.knownSample.slice(0, 30).join(", ") || "无"}`,
    "规则：已掌握/过于常见/停用词不选；优先选对理解文章关键且对该水平有学习价值的词；每个 reason 不超过 20 字。",
    "输出 JSON 格式：{\"selected\":[{\"term\":string,\"reason\":string,\"difficulty\":1-5,\"cefrLevel\":\"A1\"|\"A2\"|\"B1\"|\"B2\"|\"C1\"|\"C2\"|null,\"frequency\":\"VERY_COMMON\"|\"COMMON\"|\"NORMAL\"|\"RARE\"|null}]}",
    "",
    `<article>${articleSnippet}</article>`,
    `<candidates>${JSON.stringify(input.candidates)}</candidates>`,
  ].join("\n");

  return { systemPrompt, userPrompt };
}

export function parseJsonLoose(text: string): unknown | null {
  const trimmed = text.trim();
  if (!trimmed) return null;
  try {
    return JSON.parse(trimmed) as unknown;
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start === -1 || end === -1 || end <= start) return null;
    try {
      return JSON.parse(trimmed.slice(start, end + 1)) as unknown;
    } catch {
      return null;
    }
  }
}
