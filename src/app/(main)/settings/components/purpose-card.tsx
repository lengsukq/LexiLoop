import { RefreshCw } from "lucide-react";
import type { AppSettings, LlmPurposeId } from "@/lib/types";
import { Badge, Input, Select } from "@/components/ui";
import { configuredModels } from "../settings-shared";

type PurposeConfig = AppSettings["llmConfig"]["purposes"][LlmPurposeId];

export function PurposeCard({
  purposeId,
  label,
  description,
  config,
  settings,
  onUpdate,
}: {
  purposeId: LlmPurposeId;
  label: string;
  description: string;
  config: PurposeConfig;
  settings: AppSettings;
  onUpdate: (purposeId: LlmPurposeId, field: keyof PurposeConfig, value: unknown) => void;
}) {
  const provider = settings.llmConfig.providers.find((item) => item.id === config.providerId);
  const models = provider ? configuredModels(provider) : [];
  const retryProvider = settings.llmConfig.providers.find((item) => item.id === config.retryProviderId) ?? provider;
  const retryModels = retryProvider ? configuredModels(retryProvider) : [];
  const reserved = purposeId === "STUDY_PLAN";

  return (
    <div className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_8px_32px_rgba(0,0,0,0.04)] backdrop-blur-xl dark:border-white/[0.08] dark:bg-white/[0.04]">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0 flex-1"><p className="text-sm font-medium">{label}</p><p className="text-xs text-tertiary-label">{description}{reserved ? " · 功能预留，当前版本不会调用模型" : ""}</p></div>
        <label className="flex shrink-0 items-center gap-2 text-sm">
          <span className="text-secondary-label">{reserved ? "预留" : config.enabled ? "已启用" : "已禁用"}</span>
          <input type="checkbox" checked={reserved ? false : config.enabled} onChange={(event) => onUpdate(purposeId, "enabled", event.target.checked)} disabled={reserved} className="size-4 accent-accent" />
        </label>
      </div>

      {!reserved && config.enabled && (
        <div className="mt-4 space-y-4">
          <div className="flex flex-wrap items-end gap-3">
            <label className="min-w-[10rem] flex-1 space-y-1.5">
              <span className="text-xs font-medium text-secondary-label">提供商</span>
              <Select className="w-full" value={config.providerId} onChange={(event) => updateProvider(purposeId, event.target.value, settings, onUpdate)}>
                {settings.llmConfig.providers.length === 0 && <option value="">-- 请先添加 Provider --</option>}
                {settings.llmConfig.providers.map((item) => <option key={item.id} value={item.id}>{item.name || item.id}</option>)}
              </Select>
            </label>
            <label className="min-w-[12rem] flex-[2] space-y-1.5">
              <span className="text-xs font-medium text-secondary-label">模型</span>
              <Input value={config.model} onChange={(event) => onUpdate(purposeId, "model", event.target.value)} list={`models-${purposeId}-${provider?.id ?? "none"}`} placeholder={models.length ? "选择或输入模型名称" : "输入模型名称"} />
              <datalist id={`models-${purposeId}-${provider?.id ?? "none"}`}>{models.map((model) => <option key={model} value={model} />)}</datalist>
            </label>
            {purposeId === "IMPORT_ENRICHMENT" && <ImportEnrichmentFields config={config} purposeId={purposeId} onUpdate={onUpdate} />}
          </div>
          <RetryPolicy settings={settings} purposeId={purposeId} config={config} providerId={provider?.id ?? ""} retryProviderId={retryProvider?.id ?? ""} retryModels={retryModels} onUpdate={onUpdate} />
        </div>
      )}
    </div>
  );
}

function updateProvider(purposeId: LlmPurposeId, providerId: string, settings: AppSettings, onUpdate: (purposeId: LlmPurposeId, field: keyof PurposeConfig, value: unknown) => void) {
  const provider = settings.llmConfig.providers.find((item) => item.id === providerId);
  onUpdate(purposeId, "providerId", providerId);
  if (provider) onUpdate(purposeId, "model", provider.defaultModel || provider.models?.[0] || "");
}

function ImportEnrichmentFields({ config, purposeId, onUpdate }: { config: PurposeConfig; purposeId: LlmPurposeId; onUpdate: (purposeId: LlmPurposeId, field: keyof PurposeConfig, value: unknown) => void }) {
  return <>
    <CompactNumber label="温度" value={config.temperature ?? 0.2} min={0} max={1} step={0.1} width="w-20" onChange={(value) => onUpdate(purposeId, "temperature", value)} />
    <CompactNumber label="输出 Token" value={config.maxOutputTokens ?? 200000} min={500} max={200000} step={100} width="w-24" onChange={(value) => onUpdate(purposeId, "maxOutputTokens", value)} />
    <CompactNumber label="超时(秒)" value={(config.timeoutMs ?? 180000) / 1000} min={5} max={300} width="w-20" onChange={(value) => onUpdate(purposeId, "timeoutMs", value * 1000)} />
  </>;
}

function CompactNumber({ label, value, min, max, step, width, onChange }: { label: string; value: number; min: number; max: number; step?: number; width: string; onChange: (value: number) => void }) {
  return <label className={`space-y-1.5 ${width}`}><span className="text-xs font-medium text-secondary-label">{label}</span><Input type="number" min={min} max={max} step={step} value={value} onChange={(event) => onChange(Number(event.target.value))} /></label>;
}

function RetryPolicy({ settings, purposeId, config, providerId, retryProviderId, retryModels, onUpdate }: { settings: AppSettings; purposeId: LlmPurposeId; config: PurposeConfig; providerId: string; retryProviderId: string; retryModels: string[]; onUpdate: (purposeId: LlmPurposeId, field: keyof PurposeConfig, value: unknown) => void }) {
  return <div className="rounded-2xl border border-warning/15 bg-warning/[0.055] p-3.5 dark:border-warning/20 dark:bg-warning/[0.08]">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-start gap-2.5"><RefreshCw className="mt-0.5 size-4 shrink-0 text-[#d97706] dark:text-warning" /><div><p className="text-sm font-medium">失败重试策略</p><p className="mt-0.5 text-xs leading-5 text-[#8e6a35] dark:text-[#d6ad70]">第 2 次及之后可切换 Provider；留空则继续使用主模型。</p></div></div><Badge tone="amber">自动切换</Badge></div>
    <div className="mt-3 grid gap-3 sm:grid-cols-2">
      <label className="space-y-1.5"><span className="text-xs font-medium text-secondary-label">重试 Provider</span><Select className="w-full" value={config.retryProviderId ?? ""} onChange={(event) => updateRetryProvider(event.target.value, settings, purposeId, providerId, onUpdate)}><option value="">与主 Provider 相同</option>{settings.llmConfig.providers.filter((item) => item.id !== providerId).map((item) => <option key={item.id} value={item.id}>{item.name || item.id}</option>)}</Select></label>
      <label className="space-y-1.5"><span className="text-xs font-medium text-secondary-label">重试模型</span><Select className="w-full" value={config.retryModel ?? ""} onChange={(event) => onUpdate(purposeId, "retryModel", event.target.value)} disabled={!retryProviderId}><option value="">{retryProviderId === providerId ? "与主模型相同" : "选择重试模型"}</option>{retryModels.map((model) => <option key={model} value={model}>{model}</option>)}</Select></label>
    </div>
  </div>;
}

function updateRetryProvider(retryProviderId: string, settings: AppSettings, purposeId: LlmPurposeId, providerId: string, onUpdate: (purposeId: LlmPurposeId, field: keyof PurposeConfig, value: unknown) => void) {
  const selected = settings.llmConfig.providers.find((item) => item.id === retryProviderId)
    ?? settings.llmConfig.providers.find((item) => item.id === providerId);
  onUpdate(purposeId, "retryProviderId", retryProviderId);
  onUpdate(purposeId, "retryModel", selected?.defaultModel || selected?.models?.[0] || "");
}
