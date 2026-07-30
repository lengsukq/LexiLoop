import { db, sqlite } from "@/db/client";
import { settings } from "@/db/schema";
import { DEFAULT_SETTINGS } from "@/lib/config";
import type { AppSettings, LlmPurposeId } from "@/lib/types";
import { z } from "zod";

const settingsSchema = z.object({
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
  ecdictEnabled: z.boolean(),
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
  translationProviderOrder: z.array(z.enum(["merriam-webster", "dictionaryapi.dev", "ecdict", "ai", "mymemory", "tencent-translate", "youdao"])).max(10),
  llmConfig: z.object({
    providers: z.array(z.object({
      id: z.string().min(1),
      name: z.string().min(1),
      apiType: z.enum(["openai", "anthropic"]),
      baseUrl: z.string(),
      apiKey: z.string(),
      models: z.array(z.string().trim().min(1).max(200)).max(1000).default([]),
      defaultModel: z.string().trim().max(200).default(""),
    })),
    purposes: z.record(
      z.string(),
      z.object({
        enabled: z.boolean(),
        providerId: z.string(),
        model: z.string(),
        retryProviderId: z.string().trim().max(200).optional(),
        retryModel: z.string().trim().max(200).optional(),
        temperature: z.number().min(0).max(1).optional(),
        maxOutputTokens: z.number().int().min(500).max(200000).optional(),
        timeoutMs: z.number().int().min(5000).max(300000).optional(),
      }),
    ),
  }),
});

export const partialSettingsSchema = settingsSchema.partial().strict();

const SETTINGS_CACHE_TTL_MS = 30_000;
let settingsCache: { value: AppSettings; expiresAt: number } | null = null;

export function invalidateSettingsCache(): void {
  settingsCache = null;
}

/** A retry can deliberately switch both provider and model without altering the saved primary binding. */
export function settingsForAiAttempt(
  settings: AppSettings,
  attemptCount: number,
  purposeId: LlmPurposeId = "IMPORT_ENRICHMENT",
): AppSettings {
  const purpose = settings.llmConfig.purposes[purposeId];
  const retryModel = purpose.retryModel?.trim();
  if (attemptCount <= 1 || !retryModel) return settings;
  const retryProviderId = purpose.retryProviderId?.trim() || purpose.providerId;
  return {
    ...settings,
    llmConfig: {
      ...settings.llmConfig,
      purposes: {
        ...settings.llmConfig.purposes,
        [purposeId]: { ...purpose, providerId: retryProviderId, model: retryModel },
      },
    },
  };
}

export async function getSettings(): Promise<AppSettings> {
  if (settingsCache && Date.now() < settingsCache.expiresAt) return settingsCache.value;
  const rows = await db.select().from(settings);
  const values: Record<string, unknown> = {};
  for (const row of rows) values[row.key] = row.valueJson;
  // Migrate legacy single playbackSpeed into per-category speeds when the new
  // fields have never been saved individually.
  const legacySpeed = typeof values.playbackSpeed === "number" ? values.playbackSpeed : null;
  if (legacySpeed !== null) {
    delete values.playbackSpeed;
    for (const key of ["wordSpeed", "phraseSpeed", "sentenceSpeed"]) {
      if (values[key] === undefined) values[key] = legacySpeed;
    }
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
  sqlite.transaction(() => {
    for (const [key, value] of Object.entries(values)) upsert.run(key, JSON.stringify(value), now);
  })();
  invalidateSettingsCache();
  return getSettings();
}
