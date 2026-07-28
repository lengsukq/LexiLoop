import { sqlite } from "@/db/client";
import { formatAiProviderError } from "@/modules/ai-tasks/provider-error";
import { getSettings, settingsForAiAttempt } from "@/modules/settings/service";
import { z } from "zod";

const outputSchema = z.object({
  translations: z.array(z.object({
    index: z.number().int().nonnegative(),
    translation: z.string().trim().min(1).max(2000),
  })).max(50),
}).strict();

interface MissingExample {
  index: number;
  sentence: string;
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

async function requestTranslations(input: {
  apiType: "openai" | "anthropic";
  baseUrl: string;
  apiKey: string;
  model: string;
  timeoutMs: number;
  targetLanguage: string;
  examples: MissingExample[];
}): Promise<Map<number, string>> {
  const prompt = `你是严谨的语言学习翻译助手。把下面每条英文内容翻译成 ${input.targetLanguage}。\n\n` +
    `要求：翻译自然、准确、适合背单词；保留原文的语气、时态和专有名词；只输出翻译，不解释。\n` +
    `必须只输出 JSON：{"translations":[{"index":0,"translation":"翻译"}]}。index 必须与输入一致，不能遗漏或新增。\n\n` +
    JSON.stringify(input.examples);
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
  const allowed = new Set(input.examples.map((example) => example.index));
  return new Map(output.translations
    .filter((item) => allowed.has(item.index))
    .map((item) => [item.index, item.translation]));
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

  const settings = settingsForAiAttempt(await getSettings(), attemptCount);
  const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  if (!purpose.enabled) throw new Error("AI_DISABLED");
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) throw new Error("AI_CONFIG_INCOMPLETE");

  const translated = await requestTranslations({
    apiType: provider.apiType,
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
    model: purpose.model,
    timeoutMs: purpose.timeoutMs ?? 30_000,
    targetLanguage: word.target_language,
    examples: missing.map(({ index, sentence }) => ({ index, sentence })),
  });

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

  const settings = settingsForAiAttempt(await getSettings(), attemptCount);
  const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  if (!purpose.enabled) throw new Error("AI_DISABLED");
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) throw new Error("AI_CONFIG_INCOMPLETE");

  const translated = await requestTranslations({
    apiType: provider.apiType,
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
    model: purpose.model,
    timeoutMs: purpose.timeoutMs ?? 30_000,
    targetLanguage: word.target_language,
    examples: [{ index: 0, sentence: shortDefinition }],
  });
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

/** One queue task completes every missing short/header or example translation for a word. */
export async function translateMissingWordContent(wordId: number, attemptCount = 1): Promise<void> {
  await translateMissingSummary(wordId, attemptCount);
  await translateMissingExamples(wordId, attemptCount);
}
