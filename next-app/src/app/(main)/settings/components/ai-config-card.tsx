import { RefreshCw } from "lucide-react";
import type { AppSettings, LlmAiConfig } from "@/lib/types";
import { Badge, Input, Select } from "@/components/ui";
import { configuredModels } from "../settings-shared";

export function AiConfigCard({
  config,
  settings,
  onUpdate,
}: {
  config: LlmAiConfig;
  settings: AppSettings;
  onUpdate: (field: keyof LlmAiConfig, value: unknown) => void;
}) {
  const provider = settings.llmConfig.providers.find((item) => item.id === config.providerId);
  const models = provider ? configuredModels(provider) : [];
  const retryProvider = settings.llmConfig.providers.find((item) => item.id === config.retryProviderId) ?? provider;
  const retryModels = retryProvider ? configuredModels(retryProvider) : [];

  return (
    <div className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_8px_32px_rgba(0,0,0,0.04)] backdrop-blur-xl dark:border-white/[0.08] dark:bg-white/[0.04]">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0 flex-1"><p className="text-sm font-medium">AI 服务</p><p className="text-xs text-tertiary-label">单一配置供词条初始化、粘贴文章、翻译与建议共用</p></div>
        <label className="flex shrink-0 items-center gap-2 text-sm">
          <span className="text-secondary-label">{config.enabled ? "已启用" : "已禁用"}</span>
          <input type="checkbox" checked={config.enabled} onChange={(event) => onUpdate("enabled", event.target.checked)} className="size-4 accent-accent" />
        </label>
      </div>

      {config.enabled && (
        <div className="mt-4 space-y-4">
          <div className="flex flex-wrap items-end gap-3">
            <label className="min-w-[10rem] flex-1 space-y-1.5">
              <span className="text-xs font-medium text-secondary-label">提供商</span>
              <Select className="w-full" value={config.providerId} onChange={(event) => updateProvider(event.target.value, settings, onUpdate)}>
                {settings.llmConfig.providers.length === 0 && <option value="">-- 请先添加 Provider --</option>}
                {settings.llmConfig.providers.map((item) => <option key={item.id} value={item.id}>{item.name || item.id}</option>)}
              </Select>
            </label>
            <label className="min-w-[12rem] flex-[2] space-y-1.5">
              <span className="text-xs font-medium text-secondary-label">模型</span>
              <Select className="w-full" value={config.model} onChange={(event) => onUpdate("model", event.target.value)}>
                {models.length === 0 && <option value="">请先在 Provider 中保存模型</option>}
                {models.map((model) => <option key={model} value={model}>{model}</option>)}
              </Select>
            </label>
            <CompactNumber label="温度" value={config.temperature ?? 0.2} min={0} max={1} step={0.1} width="w-20" onChange={(value) => onUpdate("temperature", value)} />
            <CompactNumber label="输出 Token" value={config.maxOutputTokens ?? 20000} min={500} max={200000} step={100} width="w-24" onChange={(value) => onUpdate("maxOutputTokens", value)} />
            <CompactNumber label="超时(秒)" value={(config.timeoutMs ?? 180000) / 1000} min={5} max={300} width="w-20" onChange={(value) => onUpdate("timeoutMs", value * 1000)} />
          </div>
          <ThinkingToggle config={config} onUpdate={onUpdate} />
          <RetryPolicy settings={settings} config={config} providerId={provider?.id ?? ""} retryProviderId={retryProvider?.id ?? ""} retryModels={retryModels} onUpdate={onUpdate} />
        </div>
      )}
    </div>
  );
}

function ThinkingToggle({ config, onUpdate }: { config: LlmAiConfig; onUpdate: (field: keyof LlmAiConfig, value: unknown) => void }) {
  const enabled = Boolean(config.thinkingEnabled);
  return (
    <div className="rounded-2xl border border-black/[0.06] bg-white/[0.6] p-3.5 dark:border-white/[0.08] dark:bg-white/[0.04]">
      <label className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-medium">启用思考</p>
          <p className="mt-0.5 text-xs leading-5 text-tertiary-label">默认关闭以避免 Vercel 免费版 10s 超时；开启后耗时与费用显著增加</p>
        </div>
        <input type="checkbox" checked={enabled} onChange={(event) => onUpdate("thinkingEnabled", event.target.checked)} className="size-4 accent-accent" />
      </label>
      {enabled && (
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <label className="space-y-1.5">
            <span className="text-xs font-medium text-secondary-label">思考预算 Token</span>
            <Input type="number" min={1024} max={20000} step={256} value={config.thinkingBudgetTokens ?? 4000} onChange={(event) => onUpdate("thinkingBudgetTokens", Math.max(1024, Math.min(20000, Number(event.target.value) || 4000)))} />
          </label>
          <label className="space-y-1.5">
            <span className="text-xs font-medium text-secondary-label">推理强度（可选）</span>
            <Select value={config.reasoningEffort ?? ""} onChange={(event) => onUpdate("reasoningEffort", event.target.value || undefined)}>
              <option value="">自动</option>
              <option value="minimal">minimal</option>
              <option value="low">low</option>
              <option value="medium">medium</option>
              <option value="high">high</option>
            </Select>
          </label>
        </div>
      )}
    </div>
  );
}

function updateProvider(providerId: string, settings: AppSettings, onUpdate: (field: keyof LlmAiConfig, value: unknown) => void) {
  const provider = settings.llmConfig.providers.find((item) => item.id === providerId);
  onUpdate("providerId", providerId);
  if (provider) onUpdate("model", provider.defaultModel || provider.models?.[0] || "");
}

function CompactNumber({ label, value, min, max, step, width, onChange }: { label: string; value: number; min: number; max: number; step?: number; width: string; onChange: (value: number) => void }) {
  return <label className={`space-y-1.5 ${width}`}><span className="text-xs font-medium text-secondary-label">{label}</span><Input type="number" min={min} max={max} step={step} value={value} onChange={(event) => onChange(Number(event.target.value))} /></label>;
}

function RetryPolicy({ settings, config, providerId, retryProviderId, retryModels, onUpdate }: { settings: AppSettings; config: LlmAiConfig; providerId: string; retryProviderId: string; retryModels: string[]; onUpdate: (field: keyof LlmAiConfig, value: unknown) => void }) {
  return <div className="rounded-2xl border border-warning/15 bg-warning/[0.055] p-3.5 dark:border-warning/20 dark:bg-warning/[0.08]">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div className="flex items-start gap-2.5"><RefreshCw className="mt-0.5 size-4 shrink-0 text-[#d97706] dark:text-warning" /><div><p className="text-sm font-medium">失败重试策略</p><p className="mt-0.5 text-xs leading-5 text-[#8e6a35] dark:text-[#d6ad70]">第 2 次及之后可切换 Provider；留空则继续使用主模型。</p></div></div><Badge tone="amber">自动切换</Badge></div>
    <div className="mt-3 grid gap-3 sm:grid-cols-2">
      <label className="space-y-1.5"><span className="text-xs font-medium text-secondary-label">重试 Provider</span><Select className="w-full" value={config.retryProviderId ?? ""} onChange={(event) => updateRetryProvider(event.target.value, settings, providerId, onUpdate)}><option value="">与主 Provider 相同</option>{settings.llmConfig.providers.filter((item) => item.id !== providerId).map((item) => <option key={item.id} value={item.id}>{item.name || item.id}</option>)}</Select></label>
      <label className="space-y-1.5"><span className="text-xs font-medium text-secondary-label">重试模型</span><Select className="w-full" value={config.retryModel ?? ""} onChange={(event) => onUpdate("retryModel", event.target.value)} disabled={!retryProviderId}><option value="">{retryProviderId === providerId ? "与主模型相同" : "选择重试模型"}</option>{retryModels.map((model) => <option key={model} value={model}>{model}</option>)}</Select></label>
    </div>
  </div>;
}

function updateRetryProvider(retryProviderId: string, settings: AppSettings, providerId: string, onUpdate: (field: keyof LlmAiConfig, value: unknown) => void) {
  const selected = settings.llmConfig.providers.find((item) => item.id === retryProviderId)
    ?? settings.llmConfig.providers.find((item) => item.id === providerId);
  onUpdate("retryProviderId", retryProviderId);
  onUpdate("retryModel", selected?.defaultModel || selected?.models?.[0] || "");
}
