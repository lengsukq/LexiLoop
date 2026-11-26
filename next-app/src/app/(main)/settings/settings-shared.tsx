import { AlertCircle, CheckCircle2 } from "lucide-react";

import type { AppSettings, LlmProviderConfig } from "@/lib/types";

import { Input } from "@/components/ui";

export type SettingsTab = "study" | "ai" | "data";
export const SETTINGS_TABS: Array<{ id: SettingsTab; label: string }> = [
  { id: "study", label: "学习计划" },
  { id: "ai", label: "AI 模型" },
  { id: "data", label: "数据管理" },
];
export type TestState = "idle" | "testing" | "success" | "error";

export interface ProviderOperationState {
  state: "idle" | "loading" | "testing" | "success" | "error";
  message: string;
}

export interface ModelPickerState {
  providerIndex: number;
  models: string[];
  selected: string[];
}

export function configuredModels(provider: LlmProviderConfig): string[] {
  return [...new Set([...(provider.models ?? []), provider.defaultModel ?? ""].filter(Boolean))];
}

export function parseModels(value: string): string[] {
  return [...new Set(value.split(/[\n,]/).map((model) => model.trim()).filter(Boolean))];
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
    <span className="inline-flex select-none items-center gap-2 text-sm font-medium leading-none">
      <span>{label}</span>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-[26px] w-[44px] shrink-0 cursor-pointer items-center rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/50 ${
          checked
            ? "bg-gradient-to-b from-[#0a84ff] to-[#007aff] shadow-[0_2px_8px_rgba(0,122,255,0.35),inset_0_1px_0_rgba(255,255,255,0.25)]"
            : "bg-black/[0.12] shadow-[inset_0_1px_3px_rgba(0,0,0,0.1)] dark:bg-white/[0.16]"
        }`}
      >
        <span
          className={`size-[22px] rounded-full bg-white shadow-[0_2px_5px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.9)] transition-transform duration-200 ${
            checked ? "translate-x-[20px]" : "translate-x-[2px]"
          }`}
        />
      </button>
    </span>
  );
}

export function FeedbackBanner({ type, message }: { type: "error" | "success"; message: string }) {
  const error = type === "error";
  return (
    <div className={`flex items-center gap-2 rounded-[18px] border p-4 text-sm backdrop-blur-xl ${
      error
        ? "border-danger/15 bg-danger/[0.08] text-danger-deep shadow-[0_8px_32px_rgba(255,59,48,0.08)] dark:text-danger"
        : "border-success/15 bg-success/[0.08] text-success-deep shadow-[0_8px_32px_rgba(52,199,89,0.08)] dark:text-success"
    }`}>
      {error ? <AlertCircle className="size-4 shrink-0" /> : <CheckCircle2 className="size-4 shrink-0" />}
      {message}
    </div>
  );
}
