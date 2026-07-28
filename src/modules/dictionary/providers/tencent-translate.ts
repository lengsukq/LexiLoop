import type { DictionaryProvider } from "../provider";
import type { LookupInput } from "@/lib/types";
import { tencentTranslateText, TencentTranslateError, type TencentTranslateConfig } from "@/lib/tencent-translate-client";

const SUPPORTED = new Set(["en", "zh-CN", "zh-TW", "zh", "ja", "ko", "fr", "de", "es", "it", "pt", "ru", "ar", "th", "vi"]);

export class TencentTranslateProvider implements DictionaryProvider {
  readonly id = "tencent-translate";
  private config: TencentTranslateConfig;

  constructor(config: TencentTranslateConfig) {
    this.config = config;
  }

  supports(input: LookupInput) {
    return SUPPORTED.has(input.sourceLanguage) && SUPPORTED.has(input.targetLanguage);
  }

  async lookup(input: LookupInput) {
    try {
      const translated = await tencentTranslateText(input.term, input.sourceLanguage, input.targetLanguage, this.config);
      if (!translated.trim() || translated.trim().toLocaleLowerCase() === input.term.toLocaleLowerCase()) {
        return { content: null, errorCode: "EMPTY_RESULT", errorMessage: "腾讯翻译未返回有效结果" };
      }
      return {
        content: {
          definitions: [{ language: input.targetLanguage, partOfSpeech: null, text: translated.trim(), source: this.id, isUserEdited: false }],
        },
      };
    } catch (error) {
      if (error instanceof TencentTranslateError) {
        const transient = error.status === 429 || error.status >= 500;
        return { content: null, errorCode: error.code, errorMessage: error.message, transient };
      }
      const timeout = error instanceof DOMException && error.name === "TimeoutError";
      return { content: null, errorCode: timeout ? "TIMEOUT" : "NETWORK_ERROR", errorMessage: String(error), transient: true };
    }
  }
}
