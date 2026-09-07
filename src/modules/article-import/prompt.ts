import type { ExamTarget, VocabularyLevel } from "@/lib/types";

const AUTO_HINT = "自适应档默认按 CET-4 及以上水平要求：A1-A2 基础词一律视为已知，不选；日常生活极常见词（如 water、snow、eat、big 之类小学词汇）无论出现多少次都不选；只选 B1 及以上、对理解文章关键且有学习价值的词。出现次数多不代表值得学，高频基础词直接排除。";

const EXAM_HINT: Record<ExamTarget, string> = {
  CET4: "CET-4：A1-B1 基础词视为已知，不选；重点选 B2 及以上。",
  CET6: "CET-6：B1 及以下视为已知，不选；重点选 B2-C1。",
  KY: "考研：B1 及以下视为已知，不选；重点选 B2-C1 学术/形近易混词。",
  IELTS: "雅思 6.5+：B2 及以下视为已知，不选；重点选 C1-C2 与学术词汇。",
  TOEFL: "托福 90+：B2 及以下视为已知，不选；重点选 C1-C2 学术与低频词。",
};

const LEGACY_LEVEL_HINT: Record<VocabularyLevel, string> = {
  AUTO: AUTO_HINT,
  CET4: EXAM_HINT.CET4,
  CET6: EXAM_HINT.CET6,
  KY: EXAM_HINT.KY,
  IELTS: EXAM_HINT.IELTS,
  TOEFL: EXAM_HINT.TOEFL,
};

function normalizeExamTargets(input: { examTargets?: ExamTarget[]; vocabularyLevel?: VocabularyLevel }): ExamTarget[] {
  if (Array.isArray(input.examTargets) && input.examTargets.length > 0) return input.examTargets;
  if (Array.isArray(input.examTargets) && input.examTargets.length === 0) return [];
  if (input.vocabularyLevel && input.vocabularyLevel !== "AUTO") return [input.vocabularyLevel as ExamTarget];
  return [];
}

function buildLevelLine(examTargets: ExamTarget[]): string {
  if (examTargets.length === 0) return `用户水平：自适应 — ${AUTO_HINT}`;
  const labels = examTargets.join("、");
  const hints = examTargets.map((t) => EXAM_HINT[t]).join("；");
  return `用户备考：${labels} — ${hints} 多档位时就高不就低，按最高档位划线，低档基础词不选；高频基础词无论出现多少次都不选。`;
}

export function buildArticleSelectionPrompt(input: {
  articleText: string;
  candidates: Array<{ term: string; normalizedTerm: string; occurrences: number; sourceSentence?: string | null }>;
  knownSample: string[];
  totalKnown: number;
  examTargets?: ExamTarget[];
  vocabularyLevel?: VocabularyLevel;
}): { systemPrompt: string; userPrompt: string } {
  const examTargets = normalizeExamTargets(input);
  const systemPrompt = "只输出有效 JSON，不要输出任何解释或 markdown。";
  const articleSnippet = input.articleText.slice(0, 8000);
  const userPrompt = [
    "你是词汇与句法筛选助手。结合文章语境与候选词，选出值得该用户学习的单词、短语与句子。",
    buildLevelLine(examTargets),
    `用户已掌握词数：${input.totalKnown}，示例：${input.knownSample.slice(0, 30).join(", ") || "无"}`,
    "规则：已掌握/过于常见/停用词不选；出现次数多不代表值得学，高频基础词直接排除；优先选对理解文章关键且对该水平有学习价值的内容；每个 reason/nuance 不超过 24 字。选出的单词 words 必须带上准确的 cefrLevel 与 frequency，便于按水平过滤；拿不准是 A1/A2 基础词时宁可不选。",
    "输出 JSON 格式（严格 JSON，无 trailing comma）：",
    '{"words":[{"term":string,"reason":string,"difficulty":1-5,"cefrLevel":"A1"|"A2"|"B1"|"B2"|"C1"|"C2"|null,"frequency":"VERY_COMMON"|"COMMON"|"NORMAL"|"RARE"|null}],'
    + '"phrases":[{"term":string,"reason":string,"difficulty":1-5,"cefrLevel":string|null,"literalTranslation":string,"freeTranslation":string,"keyVocab":[{"term":string,"pos":string|null,"meaning":string}],"grammar":{"pattern":string|null,"notes":string[]},"nuance":string|null}],'
    + '"sentences":[{"sentence":string,"literalTranslation":string,"freeTranslation":string,"keyVocab":[{"term":string,"pos":string|null,"meaning":string}],"grammar":{"pattern":string|null,"notes":string[]},"nuance":string|null}]}',
    "约束：phrases 0-15 个，sentences 0-10 个；短语如 because of 等固定搭配需包含 keyVocab 对 each 词的词性与释义；句子的 grammar 需点出句型/从句；均给出直译与意译。",
    "",
    `<article>${articleSnippet}</article>`,
    `<candidates>${JSON.stringify(input.candidates)}</candidates>`,
  ].join("\n");
  return { systemPrompt, userPrompt };
}

export { LEGACY_LEVEL_HINT as LEVEL_HINT };

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
