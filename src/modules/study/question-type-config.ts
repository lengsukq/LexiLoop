import { DEFAULT_QUESTION_TYPE_CONFIG } from "@/lib/config";
import type { QuestionTypeConfig } from "@/lib/types";
import type { QuestionType, StudyMode } from "@/lib/types";

export type QuestionTypeRandom = () => number;

function isSimpleSpellingTerm(term: string): boolean {
  return /^[a-zA-Z]{3,14}$/.test(term);
}

export function isQuestionTypeEligible(
  type: QuestionType,
  extra: { term?: string; hasExample?: boolean },
): boolean {
  if (type === "CLOZE_SENTENCE" && !extra.hasExample) return false;
  if (type === "LETTER_BANK" && !isSimpleSpellingTerm(extra.term ?? "")) return false;
  return true;
}

function modeFallbackPool(mode: StudyMode, taskType: string): QuestionType[] {
  if (mode === "LISTENING") return ["LISTENING_SPELLING", "LISTENING_CHOICE"];
  if (mode === "SPELLING" || mode === "WRONG_WORDS" || taskType === "WRONG") {
    return ["ZH_TO_EN_SPELLING", "LETTER_BANK"];
  }
  if (mode === "SENTENCE_REVIEW") return taskType === "NEW" ? ["EN_TO_ZH"] : ["ZH_TO_EN_SPELLING", "EN_TO_ZH"];
  if (mode === "DUE_REVIEW" || mode === "NEW_WORDS") return ["EN_TO_ZH_CHOICE", "EN_TO_ZH"];
  return ["EN_TO_ZH_CHOICE", "ZH_TO_EN_CHOICE", "ZH_TO_EN_SPELLING", "CLOZE_SENTENCE", "LETTER_BANK", "EN_TO_ZH"];
}

export function normalizeQuestionTypeConfig(input: unknown): QuestionTypeConfig {
  if (!input || typeof input !== "object") return DEFAULT_QUESTION_TYPE_CONFIG;
  const record = input as Record<string, unknown>;
  const result: Record<string, { enabled: boolean; weight: number }> = {};
  for (const [key, fallback] of Object.entries(DEFAULT_QUESTION_TYPE_CONFIG)) {
    const entry = record[key] as { enabled?: unknown; weight?: unknown } | undefined;
    const enabled = typeof entry?.enabled === "boolean" ? entry.enabled : fallback.enabled;
    const weightRaw = typeof entry?.weight === "number" ? entry.weight : fallback.weight;
    const weight = Math.max(1, Math.min(10, Math.round(weightRaw)));
    result[key] = { enabled, weight };
  }
  if (!Object.values(result).some((entry) => entry.enabled)) {
    return DEFAULT_QUESTION_TYPE_CONFIG;
  }
  return result as QuestionTypeConfig;
}

function boundedRandom(random: QuestionTypeRandom): number {
  return Math.min(0.999999, Math.max(0, random()));
}

function weightedPickFromPool(
  pool: QuestionType[],
  extra: { term?: string; hasExample?: boolean },
  config: QuestionTypeConfig,
  random: QuestionTypeRandom,
): QuestionType | null {
  const eligible = pool.filter((type) => config[type]?.enabled && isQuestionTypeEligible(type, extra));
  if (!eligible.length) return null;
  if (eligible.length === 1) return eligible[0]!;
  const weights = eligible.map((type) => Math.max(0.001, config[type]!.weight));
  const total = weights.reduce((sum, weight) => sum + weight, 0);
  let cursor = boundedRandom(random) * total;
  for (let index = 0; index < eligible.length; index += 1) {
    cursor -= weights[index]!;
    if (cursor < 0) return eligible[index]!;
  }
  return eligible[eligible.length - 1]!;
}

export function resolveQuestionType(params: {
  preferred: QuestionType;
  mode: StudyMode;
  taskType: string;
  extra: { term?: string; hasExample?: boolean };
  config: QuestionTypeConfig;
  random?: QuestionTypeRandom;
}): QuestionType {
  const { preferred, mode, taskType, extra, config } = params;
  const random = params.random ?? Math.random;
  if (config[preferred]?.enabled && isQuestionTypeEligible(preferred, extra)) return preferred;
  const fallbackPool = modeFallbackPool(mode, taskType);
  const picked = weightedPickFromPool(fallbackPool, extra, config, random);
  if (picked) return picked;
  const globalPool: QuestionType[] = ["EN_TO_ZH_CHOICE", "ZH_TO_EN_CHOICE", "ZH_TO_EN_SPELLING", "EN_TO_ZH", "LISTENING_CHOICE", "LISTENING_SPELLING", "CLOZE_SENTENCE", "LETTER_BANK"];
  const globalPicked = weightedPickFromPool(globalPool, extra, config, random);
  if (globalPicked) return globalPicked;
  return "EN_TO_ZH_CHOICE";
}

export function resolveAdaptiveQuestionType(params: {
  preferred: QuestionType;
  entryType: string;
  extra: { term?: string; hasExample?: boolean };
  config: QuestionTypeConfig;
  random?: QuestionTypeRandom;
}): QuestionType {
  const { preferred, extra, config } = params;
  const random = params.random ?? Math.random;
  if (config[preferred]?.enabled && isQuestionTypeEligible(preferred, extra)) return preferred;
  const adaptivePool: QuestionType[] = preferred.startsWith("LISTENING")
    ? ["LISTENING_SPELLING", "LISTENING_CHOICE"]
    : ["ZH_TO_EN_SPELLING", "EN_TO_ZH_CHOICE", "ZH_TO_EN_CHOICE", "LETTER_BANK", "CLOZE_SENTENCE", "EN_TO_ZH"];
  const picked = weightedPickFromPool(adaptivePool, extra, config, random);
  return picked ?? "ZH_TO_EN_SPELLING";
}

export function pickQuestionTypeWithConfig(params: {
  preferred: QuestionType;
  mode: StudyMode;
  taskType: string;
  extra: { term?: string; hasExample?: boolean };
  config?: QuestionTypeConfig | null;
  random?: QuestionTypeRandom;
}): QuestionType {
  if (!params.config) return params.preferred;
  return resolveQuestionType({
    preferred: params.preferred,
    mode: params.mode,
    taskType: params.taskType,
    extra: params.extra,
    config: params.config,
    random: params.random,
  });
}
