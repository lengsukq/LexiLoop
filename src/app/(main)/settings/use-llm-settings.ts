import { useState, type Dispatch, type SetStateAction } from "react";
import { errorMessage } from "@/lib/format";
import { apiFetch } from "@/lib/client-api";
import type { AppSettings, LlmAiConfig, LlmProviderConfig } from "@/lib/types";
import { parseModels, type ModelPickerState, type ProviderOperationState } from "./settings-shared";

type SettingsSetter = Dispatch<SetStateAction<AppSettings | null>>;

function operation(state: ProviderOperationState["state"], message = ""): ProviderOperationState {
  return { state, message };
}

export function useLlmSettings(settings: AppSettings | null, setSettings: SettingsSetter) {
  const [providerTests, setProviderTests] = useState<Record<number, ProviderOperationState>>({});
  const [providerTestModels, setProviderTestModels] = useState<Record<number, string>>({});
  const [providerModels, setProviderModels] = useState<Record<number, ProviderOperationState>>({});
  const [modelPicker, setModelPicker] = useState<ModelPickerState | null>(null);
  const [modelFilter, setModelFilter] = useState("");

  function updateAi(field: keyof LlmAiConfig, value: unknown) {
    setSettings((current) => current ? {
      ...current,
      llmConfig: {
        ...current.llmConfig,
        ai: { ...current.llmConfig.ai, [field]: value },
      },
    } : current);
  }

  function addProvider() {
    setSettings((current) => {
      if (!current) return current;
      const provider: LlmProviderConfig = {
        id: `provider-${Date.now()}`,
        name: "",
        apiType: "openai",
        baseUrl: "",
        apiKey: "",
        models: [],
        defaultModel: "",
      };
      return { ...current, llmConfig: { ...current.llmConfig, providers: [...current.llmConfig.providers, provider] } };
    });
  }

  function updateProviderField(index: number, field: keyof LlmProviderConfig, value: string) {
    setSettings((current) => current ? {
      ...current,
      llmConfig: {
        ...current.llmConfig,
        providers: current.llmConfig.providers.map((provider, providerIndex) => providerIndex === index ? { ...provider, [field]: value } : provider),
      },
    } : current);
  }

  function updateProviderModels(index: number, value: string) {
    const models = parseModels(value);
    setSettings((current) => current ? {
      ...current,
      llmConfig: {
        ...current.llmConfig,
        providers: current.llmConfig.providers.map((provider, providerIndex) => {
          if (providerIndex !== index) return provider;
          const defaultModel = models.includes(provider.defaultModel ?? "") ? provider.defaultModel : models[0] ?? "";
          return { ...provider, models, defaultModel };
        }),
      },
    } : current);
  }

  function removeProviderModel(index: number, model: string) {
    setSettings((current) => {
      if (!current) return current;
      const provider = current.llmConfig.providers[index];
      if (!provider) return current;
      const models = (provider.models ?? []).filter((item) => item !== model);
      const defaultModel = provider.defaultModel === model ? models[0] ?? "" : provider.defaultModel;
      const providers = current.llmConfig.providers.map((item, i) => i === index ? { ...item, models, defaultModel: defaultModel ?? "" } : item);
      let ai = current.llmConfig.ai;
      if (ai.model === model && ai.providerId === provider.id) ai = { ...ai, model: defaultModel ?? "" };
      if (ai.retryModel === model) {
        const retryProvider = providers.find((p) => p.id === (ai.retryProviderId || ai.providerId));
        const fallback = retryProvider?.defaultModel || retryProvider?.models?.[0] || "";
        ai = { ...ai, retryModel: ai.retryModel === model ? fallback : ai.retryModel };
      }
      return { ...current, llmConfig: { ...current.llmConfig, providers, ai } };
    });
  }

  function removeProvider(index: number) {
    setSettings((current) => {
      if (!current) return current;
      const removed = current.llmConfig.providers[index];
      if (!removed) return current;
      let ai = current.llmConfig.ai;
      if (ai.providerId === removed.id) ai = { ...ai, enabled: false, providerId: "" };
      if (ai.retryProviderId === removed.id) ai = { ...ai, retryProviderId: "", retryModel: "" };
      return {
        ...current,
        llmConfig: {
          ...current.llmConfig,
          providers: current.llmConfig.providers.filter((_, providerIndex) => providerIndex !== index),
          ai,
        },
      };
    });
  }

  function changeProviderTestModel(index: number, model: string) {
    setProviderTestModels((current) => ({ ...current, [index]: model }));
    updateProviderField(index, "defaultModel", model);
  }

  async function testProvider(index: number) {
    const provider = settings?.llmConfig.providers[index];
    if (!provider) return;
    const model = providerTestModels[index] || provider.defaultModel || provider.models?.[0] || "";
    if (!model) {
      setProviderTests((current) => ({ ...current, [index]: operation("error", "请先获取或添加一个模型") }));
      return;
    }
    setProviderTests((current) => ({ ...current, [index]: operation("testing") }));
    try {
      const result = await apiFetch<{ model: string; durationMs: number }>("/api/settings/test-provider", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ apiType: provider.apiType, baseUrl: provider.baseUrl, apiKey: provider.apiKey, model }),
      });
      setProviderTests((current) => ({ ...current, [index]: operation("success", `${result.model} 响应正常（${result.durationMs}ms）`) }));
    } catch (reason) {
      setProviderTests((current) => ({ ...current, [index]: operation("error", errorMessage(reason, "连接失败")) }));
    }
  }

  async function fetchProviderModels(index: number) {
    const provider = settings?.llmConfig.providers[index];
    if (!provider) return;
    if (!provider.baseUrl.trim() || !provider.apiKey.trim()) {
      setProviderModels((current) => ({ ...current, [index]: operation("error", "请先填写接口地址和 API Key") }));
      return;
    }
    setProviderModels((current) => ({ ...current, [index]: operation("loading") }));
    try {
      const result = await apiFetch<{ models: string[] }>("/api/settings/models", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ apiType: provider.apiType, baseUrl: provider.baseUrl, apiKey: provider.apiKey }),
      });
      const existing = new Set(provider.models ?? []);
      setModelPicker({ providerIndex: index, models: result.models, selected: result.models.filter((model) => !existing.has(model)) });
      setModelFilter("");
      setProviderModels((current) => ({ ...current, [index]: operation("success", `已读取 ${result.models.length} 个模型，请选择后加入。`) }));
    } catch (reason) {
      setProviderModels((current) => ({ ...current, [index]: operation("error", errorMessage(reason, "读取模型失败")) }));
    }
  }

  function toggleModel(model: string) {
    setModelPicker((current) => !current ? current : current.selected.includes(model)
      ? { ...current, selected: current.selected.filter((item) => item !== model) }
      : { ...current, selected: [...current.selected, model] });
  }

  function selectAllModels() {
    if (!modelPicker || !settings) return;
    const provider = settings.llmConfig.providers[modelPicker.providerIndex];
    const existing = new Set(provider?.models ?? []);
    setModelPicker({ ...modelPicker, selected: modelPicker.models.filter((model) => !existing.has(model)) });
  }

  function applyModelSelection() {
    if (!modelPicker) return;
    setSettings((current) => {
      if (!current) return current;
      const provider = current.llmConfig.providers[modelPicker.providerIndex];
      if (!provider) return current;
      const models = [...new Set([...(provider.models ?? []), ...modelPicker.selected])];
      const providers = current.llmConfig.providers.map((item, index) => index === modelPicker.providerIndex
        ? { ...item, models, defaultModel: item.defaultModel || models[0] || "" }
        : item);
      return { ...current, llmConfig: { ...current.llmConfig, providers } };
    });
    setProviderModels((current) => ({ ...current, [modelPicker.providerIndex]: operation("success", `已加入 ${modelPicker.selected.length} 个模型，请保存设置。`) }));
    setModelPicker(null);
  }

  return {
    providerTests,
    providerTestModels,
    providerModels,
    modelPicker,
    modelFilter,
    setModelFilter,
    setModelPicker,
    updateAi,
    addProvider,
    updateProviderField,
    updateProviderModels,
    removeProviderModel,
    removeProvider,
    changeProviderTestModel,
    testProvider,
    fetchProviderModels,
    toggleModel,
    selectAllModels,
    applyModelSelection,
  };
}
