import { getSettings } from "@/modules/settings/service";
import { PROVIDER_CAPABILITIES } from "@/modules/dictionary/pipeline";
import type { InitializationField, InitializationProviderId } from "@/lib/types";

export async function getInitializationOptions() {
  const settings = await getSettings();
  const aiPurpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  const aiProvider = settings.llmConfig.providers.find((provider) => provider.id === aiPurpose.providerId);
  const mwDictionaryReady = Boolean(settings.merriamWebsterDictionaryKey.trim());
  const mwThesaurusReady = Boolean(settings.merriamWebsterThesaurusKey.trim());
  const providers: Array<{
    id: InitializationProviderId;
    label: string;
    available: boolean;
    enabled: boolean;
    reason: string | null;
    capabilities: InitializationField[];
  }> = [
    {
      id: "merriam-webster",
      label: "Merriam-Webster",
      enabled: settings.merriamWebsterEnabled,
      available: settings.merriamWebsterEnabled && (mwDictionaryReady || mwThesaurusReady),
      reason: !settings.merriamWebsterEnabled ? "请先在设置中启用" : !mwDictionaryReady && !mwThesaurusReady ? "尚未配置 API Key" : null,
      capabilities: [
        ...(mwDictionaryReady ? PROVIDER_CAPABILITIES["merriam-webster"].filter((field) => !["synonyms", "antonyms"].includes(field)) : []),
        ...(mwThesaurusReady ? (["synonyms", "antonyms"] as InitializationField[]) : []),
      ],
    },
    {
      id: "dictionaryapi.dev",
      label: "DictionaryAPI.dev",
      enabled: settings.dictionaryApiEnabled,
      available: settings.dictionaryApiEnabled,
      reason: settings.dictionaryApiEnabled ? null : "请先在设置中启用",
      capabilities: PROVIDER_CAPABILITIES["dictionaryapi.dev"],
    },
    {
      id: "ai",
      label: "AI 词条初始化",
      enabled: aiPurpose.enabled,
      available: Boolean(aiPurpose.enabled && aiProvider?.apiKey.trim() && aiProvider.baseUrl.trim() && aiPurpose.model.trim()),
      reason: !aiPurpose.enabled ? "AI 词条初始化未启用" : !aiProvider ? "AI Provider 不存在" : !aiProvider.apiKey.trim() || !aiProvider.baseUrl.trim() || !aiPurpose.model.trim() ? "AI 配置不完整" : null,
      capabilities: PROVIDER_CAPABILITIES.ai,
    },
    {
      id: "mymemory",
      label: "MyMemory 翻译",
      enabled: settings.myMemoryEnabled,
      available: settings.myMemoryEnabled,
      reason: settings.myMemoryEnabled ? null : "请先在设置中启用",
      capabilities: PROVIDER_CAPABILITIES.mymemory,
    },
    {
      id: "tencent-translate",
      label: "腾讯翻译",
      enabled: settings.tencentTranslateEnabled,
      available: settings.tencentTranslateEnabled && Boolean(settings.tencentTranslateSecretId.trim()) && Boolean(settings.tencentTranslateSecretKey.trim()),
      reason: !settings.tencentTranslateEnabled ? "请先在设置中启用" : !settings.tencentTranslateSecretId.trim() || !settings.tencentTranslateSecretKey.trim() ? "尚未配置 API 密钥" : null,
      capabilities: PROVIDER_CAPABILITIES["tencent-translate"],
    },
    {
      id: "youdao",
      label: "有道词典",
      enabled: settings.youdaoEnabled,
      available: settings.youdaoEnabled,
      reason: settings.youdaoEnabled ? null : "请先在设置中启用",
      capabilities: PROVIDER_CAPABILITIES.youdao,
    },
  ];
  return { providers };
}
