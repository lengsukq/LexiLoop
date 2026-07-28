import { sqlite } from "@/db/client";
import { formatAiProviderError } from "@/modules/ai-tasks/provider-error";
import { getSettings, settingsForAiAttempt } from "@/modules/settings/service";
import { tencentTranslateBatch, TencentTranslateError, type TencentTranslateConfig } from "@/lib/tencent-translate-client";
import { z } from "zod";

const outputSchema = z.object({
  translations: z.array(z.object({
    index: z.number().int().nonnegative(),
    translation: z.string().trim().min(1).max(2000),
  })).max(50),
}).strict();

interface TranslationInputItem {
  index: number;
  sentence: string;
}

interface TranslationProviderConfig {
  apiType: "openai" | "anthropic";
  baseUrl: string;
  apiKey: string;
  model: string;
  timeoutMs: number;
  providerId: string;
}

export class TranslationServiceError extends Error {
  constructor(public readonly code: string, message: string, public readonly status: number) {
    super(message);
  }
}

function normalizeBaseUrl(baseUrl: string): string {
  return baseUrl.trim().replace(/\/+$/, "");
}

function parseJsonObject(text: string): unknown {
  const trimmed = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  return JSON.parse(trimmed);
}

async function translationProvider(attemptCount: number): Promise<TranslationProviderConfig> {
  const settings = settingsForAiAttempt(await getSettings(), attemptCount);
  const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  if (!purpose.enabled) throw new Error("AI_DISABLED");
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) {
    throw new Error("AI_CONFIG_INCOMPLETE");
  }
  return {
    apiType: provider.apiType,
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
    model: purpose.model,
    timeoutMs: purpose.timeoutMs ?? 30_000,
    providerId: provider.id,
  };
}

/** Returns Tencent Translate config if enabled and configured, otherwise null. */
async function tencentTranslateProvider(): Promise<TencentTranslateConfig | null> {
  const settings = await getSettings();
  if (!settings.tencentTranslateEnabled) return null;
  if (!settings.tencentTranslateSecretId.trim() || !settings.tencentTranslateSecretKey.trim()) return null;
  return {
    secretId: settings.tencentTranslateSecretId.trim(),
    secretKey: settings.tencentTranslateSecretKey.trim(),
    projectId: settings.tencentTranslateProjectId,
  };
}

async function requestTranslations(input: {
  apiType: "openai" | "anthropic";
  baseUrl: string;
  apiKey: string;
  model: string;
  timeoutMs: number;
  targetLanguage: string;
  items: TranslationInputItem[];
}): Promise<Map<number, string>> {
  const prompt = `你是严谨的语言学习翻译助手。把下面每条源语言内容翻译成 ${input.targetLanguage}。\n\n` +
    `要求：翻译自然、准确、适合背单词；保留原文的语气、时态和专有名词；只输出翻译，不解释。\n` +
    `必须只输出 JSON：{"translations":[{"index":0,"translation":"翻译"}]}。index 必须与输入一致，不能遗漏或新增。\n\n` +
    JSON.stringify(input.items);
  const baseUrl = normalizeBaseUrl(input.baseUrl);
  let response: Response;
  if (input.apiType === "anthropic") {
    response = await fetch(`${baseUrl}/messages`, {
      method: "POST",
      signal: AbortSignal.timeout(input.timeoutMs),
      headers: { "content-type": "application/json", "x-api-key": input.apiKey, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({
        model: input.model,
        max_tokens: 2_000,
        temperature: 0.2,
        system: "Return only one valid JSON object. Do not use Markdown.",
        messages: [{ role: "user", content: prompt }],
      }),
    });
  } else {
    response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      signal: AbortSignal.timeout(input.timeoutMs),
      headers: { "content-type": "application/json", authorization: `Bearer ${input.apiKey}` },
      body: JSON.stringify({
        model: input.model,
        messages: [
          { role: "system", content: "Return only one valid JSON object. Do not use Markdown." },
          { role: "user", content: prompt },
        ],
        temperature: 0.2,
        max_tokens: 2_000,
      }),
    });
  }
  const rawBody = await response.text().catch(() => "");
  const body = (() => {
    try { return JSON.parse(rawBody) as Record<string, unknown>; }
    catch { return null; }
  })();
  if (!response.ok) {
    const message = body && typeof body.error === "object" && body.error
      ? String((body.error as Record<string, unknown>).message ?? `HTTP ${response.status}`)
      : formatAiProviderError(response.status, rawBody);
    throw new TranslationServiceError("AI_REQUEST_FAILED", message, 502);
  }
  const text = input.apiType === "anthropic"
    ? (Array.isArray(body?.content) ? body.content.map((item) => typeof item === "object" && item ? String((item as Record<string, unknown>).text ?? "") : "").join("") : "")
    : (() => {
      const choices = Array.isArray(body?.choices) ? body.choices as Array<Record<string, unknown>> : [];
      const message = choices[0]?.message;
      return message && typeof message === "object" ? String((message as Record<string, unknown>).content ?? "") : "";
    })();
  if (!text.trim()) throw new TranslationServiceError("AI_EMPTY_RESPONSE", "AI 没有返回翻译内容。", 422);
  let output: z.infer<typeof outputSchema>;
  try {
    output = outputSchema.parse(parseJsonObject(text));
  } catch {
    throw new TranslationServiceError("AI_RESPONSE_INVALID", "AI 返回的翻译格式无效，请重试或更换模型。", 422);
  }
  const allowed = new Set(input.items.map((item) => item.index));
  return new Map(output.translations
    .filter((item) => allowed.has(item.index))
    .map((item) => [item.index, item.translation]));
}

export async function translateMissingDefinitions(wordId: number, attemptCount = 1): Promise<{ translated: number; remaining: number }> {
  const word = sqlite.prepare("SELECT source_language, target_language FROM words WHERE id = ?").get(wordId) as {
    source_language: string;
    target_language: string;
  } | undefined;
  if (!word) throw new Error("WORD_NOT_FOUND");
  if (word.source_language === word.target_language) return { translated: 0, remaining: 0 };

  const contentRow = sqlite.prepare("SELECT definitions_json FROM word_contents WHERE word_id = ?").get(wordId) as {
    definitions_json: string;
  } | undefined;
  const definitions = contentRow
    ? JSON.parse(contentRow.definitions_json || "[]") as Array<Record<string, unknown>>
    : [];
  const sourceDefinitions = definitions.filter((definition) =>
    definition.language === word.source_language && typeof definition.text === "string" && definition.text.trim(),
  );
  const targetCount = definitions.filter((definition) =>
    definition.language === word.target_language && typeof definition.text === "string" && definition.text.trim(),
  ).length;
  const missingCount = Math.max(0, sourceDefinitions.length - targetCount);
  if (!sourceDefinitions.length || missingCount === 0) return { translated: 0, remaining: missingCount };

  const pendingDefinitions = sourceDefinitions.slice(0, 20);
  const items = pendingDefinitions.map((definition, index) => ({
    index,
    sentence: String(definition.text).trim(),
  }));

  // Try Tencent Translate first, fall back to LLM
  let translated: Map<number, string>;
  let translationSourceId = "tencent-translate";
  const tencent = await tencentTranslateProvider();
  if (tencent) {
    try {
      translated = await tencentTranslateBatch(items, word.source_language, word.target_language, tencent);
    } catch (error) {
      if (error instanceof TencentTranslateError && error.status === 429) throw error;
      const provider = await translationProvider(attemptCount);
      translationSourceId = provider.providerId;
      translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
    }
    if (!translated.size) {
      const provider = await translationProvider(attemptCount);
      translationSourceId = provider.providerId;
      translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
    }
  } else {
    const provider = await translationProvider(attemptCount);
    translationSourceId = provider.providerId;
    translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
  }

  const latest = sqlite.prepare("SELECT definitions_json FROM word_contents WHERE word_id = ?").get(wordId) as {
    definitions_json: string;
  } | undefined;
  const latestDefinitions = latest
    ? JSON.parse(latest.definitions_json || "[]") as Array<Record<string, unknown>>
    : [];
  const existingTargetTexts = new Set(latestDefinitions
    .filter((definition) => definition.language === word.target_language)
    .map((definition) => String(definition.text ?? "").trim().toLocaleLowerCase())
    .filter(Boolean));
  let translatedCount = 0;

  for (const [index, translation] of translated) {
    const sourceDefinition = pendingDefinitions[index];
    const normalizedTranslation = translation.trim().toLocaleLowerCase();
    if (!sourceDefinition || !normalizedTranslation || existingTargetTexts.has(normalizedTranslation)) continue;
    latestDefinitions.push({
      language: word.target_language,
      partOfSpeech: sourceDefinition.partOfSpeech ?? null,
      text: translation.trim(),
      source: `ai:translation:${translationSourceId}`,
      isUserEdited: false,
      ...(typeof sourceDefinition.senseId === "string" ? { senseId: sourceDefinition.senseId } : {}),
      ...(typeof sourceDefinition.register === "string" ? { register: sourceDefinition.register } : {}),
      ...(typeof sourceDefinition.usageNote === "string" ? { usageNote: sourceDefinition.usageNote } : {}),
    });
    existingTargetTexts.add(normalizedTranslation);
    translatedCount += 1;
  }

  if (translatedCount) {
    sqlite.prepare("UPDATE word_contents SET definitions_json = ?, content_version = content_version + 1, updated_at = ? WHERE word_id = ?")
      .run(JSON.stringify(latestDefinitions), Date.now(), wordId);
  }
  const finalTargetCount = latestDefinitions.filter((definition) =>
    definition.language === word.target_language && typeof definition.text === "string" && definition.text.trim(),
  ).length;
  return {
    translated: translatedCount,
    remaining: Math.max(0, sourceDefinitions.length - finalTargetCount),
  };
}

export async function translateMissingExamples(wordId: number, attemptCount = 1): Promise<{ translated: number; remaining: number }> {
  const word = sqlite.prepare("SELECT target_language FROM words WHERE id = ?").get(wordId) as { target_language: string } | undefined;
  if (!word) throw new Error("WORD_NOT_FOUND");
  const contentRow = sqlite.prepare("SELECT examples_json FROM word_contents WHERE word_id = ?").get(wordId) as { examples_json: string } | undefined;
  const examples = contentRow ? JSON.parse(contentRow.examples_json || "[]") as Array<Record<string, unknown>> : [];
  const missing = examples
    .map((example, index) => ({ index, sentence: typeof example.sentence === "string" ? example.sentence.trim() : "", translation: example.translation }))
    .filter((example) => example.sentence && (example.translation === null || example.translation === undefined || example.translation === ""));
  if (!missing.length) return { translated: 0, remaining: 0 };

  const items = missing.map(({ index, sentence }) => ({ index, sentence }));

  // Try Tencent Translate first, fall back to LLM
  let translated: Map<number, string>;
  const tencent = await tencentTranslateProvider();
  if (tencent) {
    try {
      translated = await tencentTranslateBatch(items, "en", word.target_language, tencent);
    } catch (error) {
      if (error instanceof TencentTranslateError && error.status === 429) throw error;
      const provider = await translationProvider(attemptCount);
      translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
    }
    if (!translated.size) {
      const provider = await translationProvider(attemptCount);
      translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
    }
  } else {
    const provider = await translationProvider(attemptCount);
    translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
  }

  // Re-read immediately before writing so a manual translation added in another
  // tab is never overwritten by this convenience action.
  const latest = sqlite.prepare("SELECT examples_json FROM word_contents WHERE word_id = ?").get(wordId) as { examples_json: string } | undefined;
  const latestExamples = latest ? JSON.parse(latest.examples_json || "[]") as Array<Record<string, unknown>> : [];
  let translatedCount = 0;
  for (const [index, translation] of translated) {
    const example = latestExamples[index];
    if (!example || typeof example.sentence !== "string" || (example.translation !== null && example.translation !== undefined && example.translation !== "")) continue;
    example.translation = translation;
    translatedCount += 1;
  }
  if (translatedCount) {
    sqlite.prepare("UPDATE word_contents SET examples_json = ?, content_version = content_version + 1, updated_at = ? WHERE word_id = ?")
      .run(JSON.stringify(latestExamples), Date.now(), wordId);
  }
  const remaining = latestExamples.filter((example) => typeof example.sentence === "string" && !String(example.translation ?? "").trim()).length;
  return { translated: translatedCount, remaining };
}

/** Fill the short Chinese translation shown in the word header without touching a user-provided value. */
export async function translateMissingSummary(wordId: number, attemptCount = 1): Promise<{ translated: boolean }> {
  const word = sqlite.prepare("SELECT target_language FROM words WHERE id = ?").get(wordId) as { target_language: string } | undefined;
  if (!word) throw new Error("WORD_NOT_FOUND");
  const contentRow = sqlite.prepare("SELECT summary_json FROM word_contents WHERE word_id = ?").get(wordId) as { summary_json: string } | undefined;
  if (!contentRow) return { translated: false };
  const summary = JSON.parse(contentRow.summary_json || "{}") as Record<string, unknown>;
  const shortDefinition = typeof summary.shortDefinition === "string" ? summary.shortDefinition.trim() : "";
  if (!shortDefinition || (typeof summary.translation === "string" && summary.translation.trim())) return { translated: false };

  const items = [{ index: 0, sentence: shortDefinition }];

  // Try Tencent Translate first, fall back to LLM
  let translated: Map<number, string>;
  const tencent = await tencentTranslateProvider();
  if (tencent) {
    try {
      translated = await tencentTranslateBatch(items, "en", word.target_language, tencent);
    } catch (error) {
      if (error instanceof TencentTranslateError && error.status === 429) throw error;
      const provider = await translationProvider(attemptCount);
      translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
    }
    if (!translated.size) {
      const provider = await translationProvider(attemptCount);
      translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
    }
  } else {
    const provider = await translationProvider(attemptCount);
    translated = await requestTranslations({ ...provider, targetLanguage: word.target_language, items });
  }
  const translation = translated.get(0);
  if (!translation) throw new TranslationServiceError("AI_EMPTY_RESPONSE", "AI 没有返回中文释义。", 422);

  // Re-read before writing: a manually added translation always wins.
  const latest = sqlite.prepare("SELECT summary_json FROM word_contents WHERE word_id = ?").get(wordId) as { summary_json: string } | undefined;
  const latestSummary = latest ? JSON.parse(latest.summary_json || "{}") as Record<string, unknown> : null;
  if (!latestSummary || (typeof latestSummary.translation === "string" && latestSummary.translation.trim())) return { translated: false };
  latestSummary.translation = translation;
  sqlite.prepare("UPDATE word_contents SET summary_json = ?, content_version = content_version + 1, updated_at = ? WHERE word_id = ?")
    .run(JSON.stringify(latestSummary), Date.now(), wordId);
  return { translated: true };
}

/** One queue task completes missing definition, header, and example translations for a word. */
export async function translateMissingWordContent(wordId: number, attemptCount = 1): Promise<void> {
  await translateMissingDefinitions(wordId, attemptCount);
  await translateMissingSummary(wordId, attemptCount);
  await translateMissingExamples(wordId, attemptCount);
}
