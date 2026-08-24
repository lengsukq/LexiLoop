import { Loader2, RefreshCw, Trash2, Zap } from "lucide-react";
import type { LlmProviderConfig } from "@/lib/types";
import { Button, Input, Select } from "@/components/ui";
import { configuredModels, type ProviderOperationState } from "../settings-shared";

export function ProviderCard({
  provider,
  index,
  modelState,
  testState,
  testModel,
  onUpdateField,
  onUpdateModels,
  onFetchModels,
  onTest,
  onTestModelChange,
  onRemove,
}: {
  provider: LlmProviderConfig;
  index: number;
  modelState?: ProviderOperationState;
  testState?: ProviderOperationState;
  testModel: string;
  onUpdateField: (index: number, field: keyof LlmProviderConfig, value: string) => void;
  onUpdateModels: (index: number, value: string) => void;
  onFetchModels: (index: number) => Promise<void>;
  onTest: (index: number) => Promise<void>;
  onTestModelChange: (index: number, model: string) => void;
  onRemove: (index: number) => void;
}) {
  return (
    <div className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_8px_32px_rgba(0,0,0,0.04)] backdrop-blur-xl dark:border-white/[0.08] dark:bg-white/[0.04]">
      <div className="flex items-start justify-between gap-2">
        <div className="grid flex-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <ProviderTextField label="名称" value={provider.name} placeholder="例如: 我的 OpenAI" onChange={(value) => onUpdateField(index, "name", value)} />
          <label className="space-y-1.5">
            <span className="text-xs font-medium text-secondary-label">API 类型</span>
            <Select className="w-full" value={provider.apiType} onChange={(event) => onUpdateField(index, "apiType", event.target.value)}>
              <option value="openai">OpenAI 兼容</option>
              <option value="anthropic">Anthropic</option>
            </Select>
          </label>
          <ProviderTextField
            label="接口地址"
            value={provider.baseUrl}
            placeholder={provider.apiType === "openai" ? "https://api.openai.com/v1" : "https://api.anthropic.com/v1"}
            onChange={(value) => onUpdateField(index, "baseUrl", value)}
          />
          <ProviderTextField label="API Key" value={provider.apiKey} placeholder="sk-..." type="password" onChange={(value) => onUpdateField(index, "apiKey", value)} />
        </div>
        <Button variant="ghost" size="sm" className="shrink-0 text-danger" onClick={() => onRemove(index)} aria-label="移除 Provider"><Trash2 className="size-4" /></Button>
      </div>

      <label className="mt-3 block space-y-1.5">
        <span className="text-xs font-medium text-secondary-label">可保存模型</span>
        <Input value={(provider.models ?? []).join(", ")} onChange={(event) => onUpdateModels(index, event.target.value)} placeholder="从 Models 接口获取，或手动输入（用逗号分隔）" />
        <div className="flex flex-wrap items-center gap-2">
          <Button variant="outline" size="sm" type="button" onClick={() => void onFetchModels(index)} disabled={modelState?.state === "loading"}>
            {modelState?.state === "loading" ? <Loader2 className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />}从 Models 接口获取
          </Button>
          <span className="text-xs text-tertiary-label">读取当前 Provider 的 `/models` 并加入清单。</span>
          <OperationMessage operation={modelState} />
        </div>
      </label>

      <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-black/[0.06] pt-3 dark:border-white/[0.08]">
        <Select compact className="w-56" value={testModel} onChange={(event) => onTestModelChange(index, event.target.value)}>
          <option value="">选择已保存的模型</option>
          {configuredModels(provider).map((model) => <option key={model} value={model}>{model}</option>)}
        </Select>
        <Button variant="outline" size="sm" onClick={() => void onTest(index)} disabled={testState?.state === "testing"}>
          {testState?.state === "testing" ? <Loader2 className="size-3.5 animate-spin" /> : <Zap className="size-3.5" />}测试连接
        </Button>
        <OperationMessage operation={testState} />
      </div>
    </div>
  );
}

function ProviderTextField({ label, value, placeholder, type = "text", onChange }: {
  label: string;
  value: string;
  placeholder: string;
  type?: "text" | "password";
  onChange: (value: string) => void;
}) {
  return <label className="space-y-1.5"><span className="text-xs font-medium text-secondary-label">{label}</span><Input type={type} value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} /></label>;
}

function OperationMessage({ operation }: { operation?: ProviderOperationState }) {
  if (!operation || operation.state === "idle" || operation.state === "loading" || operation.state === "testing") return null;
  return <span className={`text-xs ${operation.state === "success" ? "text-success" : "text-danger"}`}>{operation.message}</span>;
}
