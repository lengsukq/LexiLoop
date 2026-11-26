import { Plus } from "lucide-react";
import type { AppSettings, LlmProviderConfig } from "@/lib/types";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { ProviderOperationState } from "../settings-shared";
import { AiConfigCard } from "./ai-config-card";
import { ProviderCard } from "./provider-card";

export function AiSettingsTab({
  settings,
  providerTests,
  providerModels,
  providerTestModels,
  onAddProvider,
  onUpdateProviderField,
  onUpdateProviderModels,
  onRemoveProviderModel,
  onFetchProviderModels,
  onTestProvider,
  onProviderTestModelChange,
  onRemoveProvider,
  onUpdateAi,
}: {
  settings: AppSettings;
  providerTests: Record<number, ProviderOperationState>;
  providerModels: Record<number, ProviderOperationState>;
  providerTestModels: Record<number, string>;
  onAddProvider: () => void;
  onUpdateProviderField: (index: number, field: keyof LlmProviderConfig, value: string) => void;
  onUpdateProviderModels: (index: number, value: string) => void;
  onRemoveProviderModel: (index: number, model: string) => void;
  onFetchProviderModels: (index: number) => Promise<void>;
  onTestProvider: (index: number) => Promise<void>;
  onProviderTestModelChange: (index: number, model: string) => void;
  onRemoveProvider: (index: number) => void;
  onUpdateAi: (field: keyof AppSettings["llmConfig"]["ai"], value: unknown) => void;
}) {
  return (
    <Card>
      <CardHeader><CardTitle>大模型配置</CardTitle></CardHeader>
      <CardContent className="space-y-5">
        <p className="text-sm text-secondary-label">单一 AI 配置供全部功能共用；发音继续由 Edge TTS 独立负责。</p>
        <section className="space-y-3">
          <div className="flex items-center justify-between"><h3 className="text-sm font-semibold uppercase tracking-wider text-secondary-label">Provider 管理</h3><Button variant="outline" size="sm" onClick={onAddProvider}><Plus className="size-4" />添加 Provider</Button></div>
          {!settings.llmConfig.providers.length && <p className="text-xs text-tertiary-label">暂无配置，请添加一个 Provider。</p>}
          {settings.llmConfig.providers.map((provider, index) => <ProviderCard key={provider.id} provider={provider} index={index} modelState={providerModels[index]} testState={providerTests[index]} testModel={providerTestModels[index] ?? provider.defaultModel ?? ""} onUpdateField={onUpdateProviderField} onUpdateModels={onUpdateProviderModels} onRemoveModel={onRemoveProviderModel} onFetchModels={onFetchProviderModels} onTest={onTestProvider} onTestModelChange={onProviderTestModelChange} onRemove={onRemoveProvider} />)}
        </section>
        <section className="space-y-3">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-secondary-label">AI 配置</h3>
          <AiConfigCard config={settings.llmConfig.ai} settings={settings} onUpdate={onUpdateAi} />
        </section>
      </CardContent>
    </Card>
  );
}
