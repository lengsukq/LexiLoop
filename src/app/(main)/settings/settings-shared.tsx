import type { AppSettings, LlmPurposeId, LlmProviderConfig } from "@/lib/types";
import { AlertCircle, CheckCircle2 } from "lucide-react";
import { Input } from "@/components/ui";

export type SettingsTab = "study" | "ai" | "data";
export type TestState = "idle" | "testing" | "success" | "error";

export interface EcdictStatus {
  installed: boolean;
  enabled: boolean;
  fileSize: number;
  path: string;
  downloadUrl: string;
}

export interface ProviderOperationState {
  state: "idle" | "loading" | "testing" | "success" | "error";
  message: string;
}

export interface ModelPickerState {
  providerIndex: number;
  models: string[];
  selected: string[];
}

export const PURPOSE_META: Array<{ id: LlmPurposeId; label: string; description: string }> = [
  { id: "IMPORT_ENRICHMENT", label: "AI 词条初始化", description: "为导入词条生成完整、结构化的学习内容" },
  { id: "STUDY_PLAN", label: "生成学习计划", description: "根据学习进度生成每日计划" },
  { id: "SUGGESTION", label: "每日学习建议", description: "回顾昨日质量并生成今日必做题" },
];

export const SETTINGS_TABS: Array<{ id: SettingsTab; label: string }> = [
  { id: "study", label: "学习计划" },
  { id: "ai", label: "AI 模型" },
  { id: "data", label: "数据管理" },
];

export function configuredModels(provider: LlmProviderConfig): string[] {
  return [...new Set([...(provider.models ?? []), provider.defaultModel ?? ""].filter(Boolean))];
}

export function parseModels(value: string): string[] {
  return [...new Set(value.split(/[\n,]/).map((model) => model.trim()).filter(Boolean))];
}

export function formatBytes(value: number): string {
  if (!value) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  const index = Math.min(units.length - 1, Math.floor(Math.log(value) / Math.log(1024)));
  return `${(value / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`;
}

export type SettingsUpdater = <K extends keyof AppSettings>(key: K, value: AppSettings[K]) => void;

export function NumberField({
  label,
  value,
  min,
  max,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  onChange: (value: number) => void;
}) {
  return (
    <label className="space-y-1.5">
      <span className="text-sm font-medium leading-none">{label}</span>
      <Input
        type="number"
        min={min}
        max={max}
        value={value}
        onChange={(event) => onChange(Math.max(min, Math.min(max, Number(event.target.value) || 0)))}
      />
    </label>
  );
}

export function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <label className="flex items-center gap-2 text-sm font-medium leading-none">
      <span>{label}</span>
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        className="size-4 accent-[#007aff]"
      />
    </label>
  );
}

export function FeedbackBanner({ type, message }: { type: "error" | "success"; message: string }) {
  const error = type === "error";
  return (
    <div className={`flex items-center gap-2 rounded-[18px] border p-4 text-sm backdrop-blur-xl ${
      error
        ? "border-[#ff3b30]/15 bg-[#ff3b30]/[0.08] text-[#d70015] shadow-[0_8px_32px_rgba(255,59,48,0.08)] dark:text-[#ff453a]"
        : "border-[#34c759]/15 bg-[#34c759]/[0.08] text-[#248a3d] shadow-[0_8px_32px_rgba(52,199,89,0.08)] dark:text-[#30d158]"
    }`}>
      {error ? <AlertCircle className="size-4 shrink-0" /> : <CheckCircle2 className="size-4 shrink-0" />}
      {message}
    </div>
  );
}
