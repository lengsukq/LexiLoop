import { db, sqlite } from "@/db/client";
import { settings } from "@/db/schema";
import { DEFAULT_SETTINGS } from "@/lib/config";
import type { AppSettings } from "@/lib/types";
import { z } from "zod";

const settingsSchema = z.object({
  dailyNewWords: z.number().int().min(0).max(100),
  dailyWrongWordLimit: z.number().int().min(0).max(100),
  dailyDueReviewLimit: z.number().int().min(1).max(500),
  targetRetentionRate: z.number().min(0.7).max(0.99),
  defaultAccent: z.enum(["US", "UK", "GENERAL"]),
  playbackSpeed: z.number().min(0.5).max(2),
  autoPlayPronunciation: z.boolean(),
  dictionaryApiEnabled: z.boolean(),
  myMemoryEnabled: z.boolean(),
  ecdictEnabled: z.boolean(),
  backgroundConcurrency: z.number().int().min(1).max(10),
  llmConfig: z.object({
    providers: z.array(z.object({
      id: z.string().min(1),
      name: z.string().min(1),
      apiType: z.enum(["openai", "anthropic"]),
      baseUrl: z.string(),
      apiKey: z.string(),
    })),
    purposes: z.record(
      z.string(),
      z.object({
        enabled: z.boolean(),
        providerId: z.string(),
        model: z.string(),
        temperature: z.number().min(0).max(1).optional(),
        maxOutputTokens: z.number().int().min(500).max(200000).optional(),
        timeoutMs: z.number().int().min(5000).max(300000).optional(),
      }),
    ),
  }),
});

export const partialSettingsSchema = settingsSchema.partial().strict();

export async function getSettings(): Promise<AppSettings> {
  const rows = await db.select().from(settings);
  const values: Record<string, unknown> = {};
  for (const row of rows) values[row.key] = row.valueJson;
  return settingsSchema.parse({ ...DEFAULT_SETTINGS, ...values }) as AppSettings;
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
  return getSettings();
}
