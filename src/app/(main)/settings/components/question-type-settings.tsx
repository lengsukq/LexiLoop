"use client";

import { useMemo } from "react";
import { RotateCcw } from "lucide-react";
import type { AppSettings, QuestionType } from "@/lib/types";
import { QUESTION_TYPES } from "@/lib/types";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { Toggle, type SettingsUpdater } from "../settings-shared";
import { toast } from "@/components/ui";

const QUESTION_TYPE_LABELS: Record<QuestionType, { title: string; hint: string }> = {
  EN_TO_ZH: { title: "英译中自评", hint: "看英文选是否认识" },
  EN_TO_ZH_CHOICE: { title: "英译中选择", hint: "看英文选释义" },
  ZH_TO_EN_CHOICE: { title: "中译英选择", hint: "看释义选英文" },
  ZH_TO_EN_SPELLING: { title: "中译英拼写", hint: "看释义拼写英文" },
  LISTENING_CHOICE: { title: "听音选择", hint: "听读音选词" },
  LISTENING_SPELLING: { title: "听音拼写", hint: "听读音拼写" },
  CLOZE_SENTENCE: { title: "完形填空", hint: "需例句" },
  LETTER_BANK: { title: "字母拼词", hint: "需 3-14 纯字母" },
};

const PRESETS: Array<{ label: string; weights: Partial<Record<QuestionType, number>> }> = [
  { label: "均衡", weights: { EN_TO_ZH: 5, EN_TO_ZH_CHOICE: 5, ZH_TO_EN_CHOICE: 5, ZH_TO_EN_SPELLING: 5, LISTENING_CHOICE: 5, LISTENING_SPELLING: 5, CLOZE_SENTENCE: 5, LETTER_BANK: 5 } },
  { label: "记忆为主", weights: { EN_TO_ZH_CHOICE: 8, ZH_TO_EN_CHOICE: 7, EN_TO_ZH: 5, ZH_TO_EN_SPELLING: 4 } },
  { label: "拼写强化", weights: { ZH_TO_EN_SPELLING: 9, LETTER_BANK: 8, CLOZE_SENTENCE: 7 } },
  { label: "听力强化", weights: { LISTENING_CHOICE: 9, LISTENING_SPELLING: 9 } },
];

export function QuestionTypeSettings({ settings, update }: { settings: AppSettings; update: SettingsUpdater }) {
  const config = settings.questionTypeConfig;
  const totalWeight = useMemo(() => {
    if (!config) return 0;
    return (Object.values(config) as Array<{ enabled: boolean; weight: number }>).filter((entry) => entry.enabled).reduce((sum, entry) => sum + entry.weight, 0);
  }, [config]);

  if (!config) return null;

  const enabledCount = (Object.values(config) as Array<{ enabled: boolean }>).filter((entry) => entry.enabled).length;

  function handleToggle(type: QuestionType, nextEnabled: boolean) {
    if (!nextEnabled && enabledCount <= 1) {
      toast.error("至少保留一种题型", "无法全部关闭");
      return;
    }
    update("questionTypeConfig", { ...config, [type]: { ...config[type]!, enabled: nextEnabled, weight: config[type]!.weight } });
  }

  function handleWeight(type: QuestionType, weight: number) {
    const clamped = Math.max(1, Math.min(10, Math.round(weight)));
    update("questionTypeConfig", { ...config, [type]: { ...config[type]!, enabled: config[type]!.enabled, weight: clamped } });
  }

  function applyPreset(weights: Partial<Record<QuestionType, number>>) {
    const next = { ...config } as typeof config;
    for (const type of QUESTION_TYPES) {
      if (weights[type] !== undefined) next[type] = { ...next[type]!, weight: weights[type]! };
    }
    update("questionTypeConfig", next);
  }

  function resetAll() {
    const next = { ...config } as typeof config;
    for (const type of QUESTION_TYPES) next[type] = { enabled: true, weight: 5 };
    update("questionTypeConfig", next);
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>答题题型</CardTitle>
            <p className="mt-1 text-xs text-tertiary-label">关闭后新会话不再出现；权重越大出现越频繁（相对比例，无需凑 100）。掌握度分层保留，权重仅在首选被禁用或多选分支时加权兜底。</p>
          </div>
          <Button variant="outline" size="sm" onClick={resetAll}><RotateCcw className="size-3.5" />重置均衡</Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-1.5">
          {PRESETS.map((preset) => (
            <button
              key={preset.label}
              type="button"
              onClick={() => applyPreset(preset.weights)}
              className="rounded-full border border-black/10 bg-white px-3 py-1 text-xs font-medium text-secondary-label hover:border-accent/30 hover:text-label dark:border-white/10 dark:bg-white/[0.06]"
            >
              {preset.label}
            </button>
          ))}
        </div>

        <div className="grid gap-2.5 sm:grid-cols-2">
          {QUESTION_TYPES.map((type) => {
            const entry = config[type]!;
            const meta = QUESTION_TYPE_LABELS[type];
            const percent = totalWeight ? Math.round((entry.enabled ? entry.weight / totalWeight : 0) * 100) : 0;
            return (
              <div
                key={type}
                className={`flex flex-col gap-2 rounded-[14px] border px-3 py-3 transition-colors ${entry.enabled ? "border-black/[0.06] bg-white/[0.6] dark:border-white/[0.08] dark:bg-white/[0.04]" : "border-black/[0.06] bg-black/[0.02] opacity-60 dark:border-white/10"}`}
              >
                <div className="flex items-center justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-sm font-medium leading-none">{meta.title}</div>
                    <div className="mt-1 text-xs text-tertiary-label">{meta.hint} · {type}</div>
                  </div>
                  <Toggle label="" checked={entry.enabled} onChange={(value) => handleToggle(type, value)} />
                </div>
                <div className="flex items-center gap-2">
                  <input
                    type="range"
                    min={1}
                    max={10}
                    value={entry.weight}
                    disabled={!entry.enabled}
                    onChange={(event) => handleWeight(type, Number(event.target.value))}
                    className="h-1 flex-1 accent-[#0a84ff] disabled:opacity-40"
                  />
                  <span className="min-w-7 text-right text-xs font-medium tabular-nums">{entry.weight}</span>
                  <span className="min-w-9 text-right text-xs tabular-nums text-tertiary-label">{percent}%</span>
                </div>
                <div className="h-1.5 overflow-hidden rounded-full bg-black/[0.06] dark:bg-white/10">
                  <div className="h-full rounded-full bg-accent transition-all" style={{ width: `${percent}%`, opacity: entry.enabled ? 1 : 0.35 }} />
                </div>
              </div>
            );
          })}
        </div>
      </CardContent>
    </Card>
  );
}
