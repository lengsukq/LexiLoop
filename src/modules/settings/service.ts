import { sqlite } from "@/db/client";
import { DEFAULT_SETTINGS } from "@/lib/config";
import type { AppSettings } from "@/lib/types";
import { z } from "zod";

const aiConfigSchema = z.object({
  enabled: z.boolean(),
  providerId: z.string(),
  model: z.string(),
  retryProviderId: z.string().trim().max(200).optional(),
  retryModel: z.string().trim().max(200).optional(),
  temperature: z.number().min(0).max(1).optional(),
  maxOutputTokens: z.number().int().min(500).max(200000).optional(),
  timeoutMs: z.number().int().min(5000).max(300000).optional(),
  thinkingEnabled: z.boolean().default(false),
  thinkingBudgetTokens: z.number().int().min(1024).max(20000).optional(),
  reasoningEffort: z.enum(["minimal", "low", "medium", "high"]).optional(),
});

function coalesceLegacyLlmConfig(value: unknown): unknown {
  if (!value || typeof value !== "object") return value;
  const record = value as Record<string, unknown>;
  if (!record.purposes || typeof record.purposes !== "object") return value;
  const purposes = record.purposes as Record<string, unknown>;
  let picked: unknown = null;
  for (const key of ["IMPORT_ENRICHMENT", "SUGGESTION", "STUDY_PLAN", "TTS"]) {
    const entry = purposes[key] as { enabled?: boolean; providerId?: string } | undefined;
    if (entry?.enabled && typeof entry.providerId === "string" && entry.providerId.trim()) {
      picked = entry;
      break;
    }
  }
  if (!picked) {
    for (const entry of Object.values(purposes)) {
      if (entry && typeof entry === "object" && typeof (entry as { providerId?: unknown }).providerId === "string" && String((entry as { providerId: string }).providerId).trim()) {
        picked = entry;
        break;
      }
    }
  }
  const { purposes: _purposes, ...rest } = record;
  void _purposes;
  return { ...rest, ai: (picked as object) ?? { enabled: false, providerId: "", model: "", thinkingEnabled: false } };
}

const settingsSchema = z.object({
  vocabularyLevel: z.enum(["AUTO", "CET4", "CET6", "KY", "IELTS", "TOEFL"]).default("AUTO"),
  examTargets: z.array(z.enum(["CET4", "CET6", "KY", "IELTS", "TOEFL"])).max(5).default([]),
  dailyNewWords: z.number().int().min(0).max(100),
  dailyWrongWordLimit: z.number().int().min(0).max(100),
  dailyDueReviewLimit: z.number().int().min(1).max(500),
  targetRetentionRate: z.number().min(0.7).max(0.99),
  choiceRevealDelaySeconds: z.number().int().min(0).max(60),
  defaultAccent: z.preprocess((value) => value === "GENERAL" ? "US" : value, z.enum(["US", "UK"])),
  wordSpeed: z.number().min(0.5).max(2).default(1),
  phraseSpeed: z.number().min(0.5).max(2).default(1),
  sentenceSpeed: z.number().min(0.5).max(2).default(1),
  autoPlayPronunciation: z.boolean(),
  dictionaryApiEnabled: z.boolean(),
  myMemoryEnabled: z.boolean(),
  merriamWebsterEnabled: z.boolean(),
  merriamWebsterDictionaryKey: z.string(),
  merriamWebsterThesaurusKey: z.string(),
  backgroundConcurrency: z.number().int().min(1).max(10),
  aiRetryCount: z.number().int().min(0).max(5),
  tencentTranslateEnabled: z.boolean(),
  tencentTranslateSecretId: z.string(),
  tencentTranslateSecretKey: z.string(),
  tencentTranslateProjectId: z.number().int().min(0).max(999999),
  youdaoEnabled: z.boolean(),
  icibaEnabled: z.boolean(),
  translationProviderOrder: z.array(z.enum(["merriam-webster", "dictionaryapi.dev", "ai", "mymemory", "tencent-translate", "youdao", "iciba"])).max(10),
  llmConfig: z.preprocess(coalesceLegacyLlmConfig, z.object({
    providers: z.array(z.object({
      id: z.string().min(1),
      name: z.string().min(1),
      apiType: z.enum(["openai", "anthropic"]),
      baseUrl: z.string(),
      apiKey: z.string(),
      models: z.array(z.string().trim().min(1).max(200)).max(1000).default([]),
      defaultModel: z.string().trim().max(200).default(""),
    })),
    ai: aiConfigSchema,
  })),
});

export const partialSettingsSchema = z.preprocess(
  (value: unknown) => {
    if (!value || typeof value !== "object") return value;
    const record = value as Record<string, unknown>;
    if (record.llmConfig && typeof record.llmConfig === "object") {
      return { ...record, llmConfig: coalesceLegacyLlmConfig(record.llmConfig) };
    }
    return value;
  },
  settingsSchema.partial().strict(),
);

const SETTINGS_CACHE_TTL_MS = 30_000;
let settingsCache: { value: AppSettings; expiresAt: number } | null = null;

export function invalidateSettingsCache(): void {
  settingsCache = null;
}

export function settingsForAiAttempt(
  settings: AppSettings,
  attemptCount: number,
): AppSettings {
  const ai = settings.llmConfig.ai;
  const retryModel = ai.retryModel?.trim();
  if (attemptCount <= 1 || !retryModel) return settings;
  const retryProviderId = ai.retryProviderId?.trim() || ai.providerId;
  return {
    ...settings,
    llmConfig: {
      ...settings.llmConfig,
      ai: { ...ai, providerId: retryProviderId, model: retryModel },
    },
  };
}

export async function getSettings(): Promise<AppSettings> {
  if (settingsCache && Date.now() < settingsCache.expiresAt) return settingsCache.value;
  const rows = await sqlite.prepare("SELECT key, value_json FROM settings").all() as Array<{ key: string; value_json: string }>;
  const values: Record<string, unknown> = {};
  for (const row of rows) values[row.key] = JSON.parse(row.value_json) as unknown;
  const legacySpeed = typeof values.playbackSpeed === "number" ? values.playbackSpeed : null;
  if (legacySpeed !== null) {
    delete values.playbackSpeed;
    for (const key of ["wordSpeed", "phraseSpeed", "sentenceSpeed"]) {
      if (values[key] === undefined) values[key] = legacySpeed;
    }
  }
  if (!Array.isArray(values.examTargets) && typeof values.vocabularyLevel === "string") {
    const lvl = values.vocabularyLevel as string;
    if (lvl !== "AUTO" && ["CET4", "CET6", "KY", "IELTS", "TOEFL"].includes(lvl)) values.examTargets = [lvl];
    else if (lvl === "AUTO") values.examTargets = [];
  }
  const result = settingsSchema.parse({ ...DEFAULT_SETTINGS, ...values }) as AppSettings;
  settingsCache = { value: result, expiresAt: Date.now() + SETTINGS_CACHE_TTL_MS };
  return result;
}

export async function updateSettings(input: unknown): Promise<AppSettings> {
  const values = partialSettingsSchema.parse(input);
  const now = Date.now();
  const upsert = sqlite.prepare(`INSERT INTO settings(key, value_json, updated_at)
    VALUES (?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at`);
  await sqlite.transaction(async () => {
    for (const [key, value] of Object.entries(values)) await upsert.run(key, JSON.stringify(value), now);
  })();
  invalidateSettingsCache();
  return getSettings();
}
