import { Plus } from "lucide-react";
import type { AppSettings, LlmProviderConfig, LlmPurposeId } from "@/lib/types";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { PURPOSE_META, type ProviderOperationState } from "../settings-shared";
import { ProviderCard } from "./provider-card";
import { PurposeCard } from "./purpose-card";

type PurposeConfig = AppSettings["llmConfig"]["purposes"][LlmPurposeId];

export function AiSettingsTab({
  settings,
  providerTests,
  providerModels,
  providerTestModels,
  onAddProvider,
  onUpdateProviderField,
  onUpdateProviderModels,
  onFetchProviderModels,
  onTestProvider,
  onProviderTestModelChange,
  onRemoveProvider,
  onUpdatePurpose,
}: {
  settings: AppSettings;
  providerTests: Record<number, ProviderOperationState>;
  providerModels: Record<number, ProviderOperationState>;
  providerTestModels: Record<number, string>;
  onAddProvider: () => void;
  onUpdateProviderField: (index: number, field: keyof LlmProviderConfig, value: string) => void;
  onUpdateProviderModels: (index: number, value: string) => void;
  onFetchProviderModels: (index: number) => Promise<void>;
  onTestProvider: (index: number) => Promise<void>;
  onProviderTestModelChange: (index: number, model: string) => void;
  onRemoveProvider: (index: number) => void;
  onUpdatePurpose: (purposeId: LlmPurposeId, field: keyof PurposeConfig, value: unknown) => void;
}) {
  return (
    <Card>
      <CardHeader><CardTitle>大模型配置</CardTitle></CardHeader>
      <CardContent className="space-y-5">
        <p className="text-sm text-secondary-label">配置 AI 模型生成词汇学习内容和每日建议；发音继续由 Edge TTS 独立负责。</p>
        <section className="space-y-3">
          <div className="flex items-center justify-between"><h3 className="text-sm font-semibold uppercase tracking-wider text-secondary-label">Provider 管理</h3><Button variant="outline" size="sm" onClick={onAddProvider}><Plus className="size-4" />添加 Provider</Button></div>
          {!settings.llmConfig.providers.length && <p className="text-xs text-tertiary-label">暂无配置，请添加一个 Provider。</p>}
          {settings.llmConfig.providers.map((provider, index) => <ProviderCard key={provider.id} provider={provider} index={index} modelState={providerModels[index]} testState={providerTests[index]} testModel={providerTestModels[index] ?? provider.defaultModel ?? ""} onUpdateField={onUpdateProviderField} onUpdateModels={onUpdateProviderModels} onFetchModels={onFetchProviderModels} onTest={onTestProvider} onTestModelChange={onProviderTestModelChange} onRemove={onRemoveProvider} />)}
        </section>
        <section className="space-y-4">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-secondary-label">用途绑定</h3>
          {PURPOSE_META.map((purpose) => <PurposeCard key={purpose.id} purposeId={purpose.id} label={purpose.label} description={purpose.description} config={settings.llmConfig.purposes[purpose.id]} settings={settings} onUpdate={onUpdatePurpose} />)}
        </section>
      </CardContent>
    </Card>
  );
}
