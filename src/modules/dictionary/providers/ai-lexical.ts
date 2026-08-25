import { z } from "zod";
import type { AppSettings, LookupInput } from "@/lib/types";
import type { DictionaryProvider, ProviderResult } from "../provider";
import { extractJson } from "@/lib/json";
import { normalizeAiOutput } from "./ai-lexical-normalize";
import { AI_LEXICAL_PROMPT_VERSION, AI_LEXICAL_SCHEMA_VERSION, outputSchema } from "./ai-lexical-schema";
import { promptFor } from "./ai-lexical-prompt";
import { requestAnthropic, requestOpenAiCompatible } from "./ai-lexical-transport";
import { qualityScore, semanticIssues, toContent } from "./ai-lexical-content";

const normalized = (value: string) => value.normalize("NFKC").trim().replace(/\s+/g, " ").toLocaleLowerCase();

export class AiLexicalProvider implements DictionaryProvider {
  readonly id: string;
  private readonly settings: AppSettings;

  constructor(settings: AppSettings) {
    this.settings = settings;
    const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
    this.id = `ai:${purpose.providerId}:${purpose.model}`;
  }

  supports(): boolean { return this.settings.llmConfig.purposes.IMPORT_ENRICHMENT.enabled; }

  async lookup(input: LookupInput): Promise<ProviderResult> {
    const purpose = this.settings.llmConfig.purposes.IMPORT_ENRICHMENT;
    if (!purpose.enabled) return { content: null, errorCode: "AI_DISABLED", errorMessage: "AI 词条初始化未启用" };
    const provider = this.settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
    if (!provider) return { content: null, errorCode: "AI_PROVIDER_MISSING", errorMessage: "AI Provider 未找到或已被删除" };
    if (!provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) return { content: null, errorCode: "AI_CONFIG_INCOMPLETE", errorMessage: "AI 提供商、API Key、接口地址或模型未配置完整" };
    const options = {
      temperature: purpose.temperature ?? 0.2,
      maxOutputTokens: purpose.maxOutputTokens ?? 200_000,
      timeoutMs: purpose.timeoutMs ?? 180_000,
      thinkingEnabled: purpose.thinkingEnabled ?? false,
      thinkingBudgetTokens: purpose.thinkingBudgetTokens,
      reasoningEffort: purpose.reasoningEffort,
    };
    let rawText = "";
    try {
      const prompt = promptFor(input);
      const response = provider.apiType === "anthropic" ? await requestAnthropic(provider.baseUrl, provider.apiKey, purpose.model, prompt, options) : await requestOpenAiCompatible(provider.id, provider.baseUrl, provider.apiKey, purpose.model, prompt, options);
      rawText = response.text;
      if (["length", "max_tokens"].includes((response.finishReason ?? "").toLocaleLowerCase())) return { content: null, errorCode: "AI_OUTPUT_TRUNCATED", errorMessage: "AI 输出因 Token 上限被截断，请提高输出 Token 配置。", metadata: { model: purpose.model, rawResponse: rawText.slice(0, 4000) } };
      const parsed = outputSchema.parse(normalizeAiOutput(extractJson(rawText)));
      if (normalized(parsed.term) !== normalized(input.term)) return { content: null, errorCode: "AI_TERM_MISMATCH", errorMessage: `模型返回了其他词条：${parsed.term}`, metadata: { model: purpose.model, rawResponse: rawText.slice(0, 4000) } };
      const issues = semanticIssues(parsed, input);
      if (issues.length) return { content: null, errorCode: "AI_SEMANTIC_INVALID", errorMessage: issues.join("；"), metadata: { model: purpose.model, rawResponse: rawText.slice(0, 4000) } };
      const score = qualityScore(parsed, input);
      if (score < 45) return { content: null, errorCode: "AI_QUALITY_LOW", errorMessage: `AI 内容质量评分过低：${score}`, metadata: { model: purpose.model, rawResponse: rawText.slice(0, 4000) } };
      const source = `ai:${provider.id}:${purpose.model}`;
      return { content: toContent(parsed, input, source), metadata: { model: purpose.model, promptVersion: AI_LEXICAL_PROMPT_VERSION, schemaVersion: AI_LEXICAL_SCHEMA_VERSION, inputTokens: response.inputTokens, outputTokens: response.outputTokens, qualityScore: score, finishReason: response.finishReason } };
    } catch (error) {
      const annotated = error as Error & { transient?: boolean; code?: string };
      const timeout = error instanceof DOMException && error.name === "TimeoutError";
      return { content: null, errorCode: annotated.code ?? (timeout ? "AI_TIMEOUT" : error instanceof z.ZodError || error instanceof SyntaxError ? "AI_SCHEMA_INVALID" : "AI_REQUEST_FAILED"), errorMessage: error instanceof z.ZodError ? `AI 返回结构不符合要求：${error.issues.map((issue) => issue.path.join(".")).slice(0, 5).join("、")}` : error instanceof SyntaxError ? `AI 返回的 JSON 无法解析：${error.message}` : String(error), transient: timeout || Boolean(annotated.transient), metadata: rawText ? { model: purpose.model, rawResponse: rawText.slice(0, 4000) } : undefined };
    }
  }
}
