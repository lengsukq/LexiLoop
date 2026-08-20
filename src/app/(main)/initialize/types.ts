export interface StatusData {
  summary: Record<string, number>;
  wordSummary: Record<string, number>;
}

export interface InitializationTask {
  id: number;
  taskType: string;
  status: string;
  mode: string;
  attemptCount: number;
  maxAttempts: number;
  lastError: string | null;
  lastErrorCode: string | null;
  createdAt: number;
  updatedAt: number;
  completedAt: number | null;
}

export interface InitializationWord {
  wordId: number;
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  status: string;
  taskCount: number;
  completedTaskCount: number;
  failedTaskCount: number;
  activeTaskCount: number;
  updatedAt: number;
  errorSummary: string | null;
  tasks: InitializationTask[];
}

export interface JobAttempt {
  id: number;
  providerId: string;
  status: string;
  durationMs: number;
  fieldsReturned: string[];
  errorCode: string | null;
  errorMessage: string | null;
  metadata: {
    model?: string;
    promptVersion?: string;
    schemaVersion?: number;
    inputTokens?: number | null;
    outputTokens?: number | null;
    qualityScore?: number;
    finishReason?: string | null;
  } | null;
  createdAt: number;
}

export interface JobDetails {
  job: {
    id: number;
    wordId: number;
    term: string;
    normalizedTerm: string;
    sourceLanguage: string;
    targetLanguage: string;
    taskType: string;
    status: string;
    mode: string;
    priority: number;
    attemptCount: number;
    maxAttempts: number;
    lastError: string | null;
    lastErrorCode: string | null;
    availableAt: number | null;
    lockedAt: number | null;
    lockedBy: string | null;
    createdAt: number;
    updatedAt: number;
    completedAt: number | null;
  };
  attempts: JobAttempt[];
  contentFields: Record<string, boolean>;
}

export const MODE_LABELS: Record<string, string> = {
  SKIP_INITIALIZED: "跳过已初始化",
  FILL_MISSING_FIELDS: "补全缺失字段",
  FORCE_OVERWRITE: "强制覆盖",
};

export const TASK_TYPE_LABELS: Record<string, string> = {
  INITIALIZE: "词条补全",
  MNEMONIC: "中文助记",
  EXAMPLE_TRANSLATIONS: "翻译补全",
};

const CONTENT_FIELD_LABELS: Record<string, string> = {
  definitions: "释义",
  pronunciations: "发音",
  examples: "例句",
  phrases: "搭配",
  forms: "词形",
  synonyms: "近义词",
  antonyms: "反义词",
  wordFamily: "同根词",
  confusedWords: "易混词",
  roots: "词根",
  affixes: "词缀",
  tags: "标签",
  summary: "概要",
  learning: "学习提示",
  sentenceAnalysis: "句子分析",
};

export function contentFieldLabel(key: string): string {
  return CONTENT_FIELD_LABELS[key] ?? key;
}

export function formatTs(ts: number | string | null | undefined): string {
  if (!ts) return "—";
  return new Date(ts).toLocaleString("zh-CN");
}

export function durationText(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${Math.floor(ms / 60000)}m ${Math.floor((ms % 60000) / 1000)}s`;
}
