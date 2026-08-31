"use client";

import { useMemo } from "react";
import { BookOpen, Ear, Eye, Keyboard, Minus, Plus, RotateCcw } from "lucide-react";
import type { AppSettings, QuestionType } from "@/lib/types";
import { QUESTION_TYPES } from "@/lib/types";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { Toggle, type SettingsUpdater } from "../settings-shared";
import { toast } from "@/components/ui";

const TYPE_META: Record<QuestionType, { title: string; hint: string }> = {
  EN_TO_ZH: { title: "自评认词", hint: "看英文判断是否认识" },
  EN_TO_ZH_CHOICE: { title: "英选中", hint: "看英文选释义" },
  ZH_TO_EN_CHOICE: { title: "中选英", hint: "看释义选英文" },
  ZH_TO_EN_SPELLING: { title: "拼写", hint: "看释义拼写英文" },
  LISTENING_CHOICE: { title: "听音选词", hint: "听发音选词" },
  LISTENING_SPELLING: { title: "听音拼写", hint: "听发音拼写" },
  CLOZE_SENTENCE: { title: "完形填空", hint: "例句挖空 · 需例句" },
  LETTER_BANK: { title: "字母拼词", hint: "打乱字母拼回 · 需纯字母词" },
};

type Group = { label: string; icon: typeof Eye; types: QuestionType[] };

const GROUPS: Group[] = [
  { label: "看词认义", icon: Eye, types: ["EN_TO_ZH", "EN_TO_ZH_CHOICE", "ZH_TO_EN_CHOICE"] },
  { label: "拼写输出", icon: Keyboard, types: ["ZH_TO_EN_SPELLING", "LETTER_BANK"] },
  { label: "听力训练", icon: Ear, types: ["LISTENING_CHOICE", "LISTENING_SPELLING"] },
  { label: "语境运用", icon: BookOpen, types: ["CLOZE_SENTENCE"] },
];

const PRESETS: Array<{ label: string; weights: Partial<Record<QuestionType, number>> }> = [
  { label: "均衡", weights: { EN_TO_ZH: 5, EN_TO_ZH_CHOICE: 5, ZH_TO_EN_CHOICE: 5, ZH_TO_EN_SPELLING: 5, LISTENING_CHOICE: 5, LISTENING_SPELLING: 5, CLOZE_SENTENCE: 5, LETTER_BANK: 5 } },
  { label: "记忆为主", weights: { EN_TO_ZH_CHOICE: 8, ZH_TO_EN_CHOICE: 7, EN_TO_ZH: 5, ZH_TO_EN_SPELLING: 4 } },
  { label: "拼写强化", weights: { ZH_TO_EN_SPELLING: 9, LETTER_BANK: 8, CLOZE_SENTENCE: 7 } },
  { label: "听力强化", weights: { LISTENING_CHOICE: 9, LISTENING_SPELLING: 9 } },
];

const SEG_COLORS: Record<QuestionType, string> = {
  EN_TO_ZH: "bg-[#0a84ff]",
  EN_TO_ZH_CHOICE: "bg-[#30d158]",
  ZH_TO_EN_CHOICE: "bg-[#ff9f0a]",
  ZH_TO_EN_SPELLING: "bg-[#ff3b30]",
  LISTENING_CHOICE: "bg-[#af52de]",
  LISTENING_SPELLING: "bg-[#5e5ce6]",
  CLOZE_SENTENCE: "bg-[#00c7be]",
  LETTER_BANK: "bg-[#ffcc02]",
};

export function QuestionTypeSettings({ settings, update }: { settings: AppSettings; update: SettingsUpdater }) {
  const config = settings.questionTypeConfig;
  const totalWeight = useMemo(() => {
    if (!config) return 0;
    return (Object.values(config) as Array<{ enabled: boolean; weight: number }>).filter((e) => e.enabled).reduce((s, e) => s + e.weight, 0);
  }, [config]);

  if (!config) return null;

  const enabledCount = (Object.values(config) as Array<{ enabled: boolean }>).filter((e) => e.enabled).length;

  function handleToggle(type: QuestionType, next: boolean) {
    if (!next && enabledCount <= 1) {
      toast.error("至少保留一种题型", "无法全部关闭");
      return;
    }
    update("questionTypeConfig", { ...config, [type]: { ...config[type]!, enabled: next, weight: config[type]!.weight } });
  }

  function handleWeight(type: QuestionType, w: number) {
    const clamped = Math.max(1, Math.min(10, Math.round(w)));
    update("questionTypeConfig", { ...config, [type]: { ...config[type]!, enabled: config[type]!.enabled, weight: clamped } });
  }

  function applyPreset(weights: Partial<Record<QuestionType, number>>) {
    const next = { ...config } as typeof config;
    for (const t of QUESTION_TYPES) if (weights[t] !== undefined) next[t] = { ...next[t]!, weight: weights[t]! };
    update("questionTypeConfig", next);
  }

  function resetAll() {
    const next = { ...config } as typeof config;
    for (const t of QUESTION_TYPES) next[t] = { enabled: true, weight: 5 };
    update("questionTypeConfig", next);
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>答题题型</CardTitle>
            <p className="mt-1 max-w-[52ch] text-xs leading-relaxed text-tertiary-label">选你想练的题型，权重越大越常考。关掉的题型在新开始的学习中不再出现。</p>
          </div>
          <Button variant="outline" size="sm" onClick={resetAll}><RotateCcw className="size-3.5" />重置均衡</Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-1.5">
          {PRESETS.map((p) => (
            <button
              key={p.label}
              type="button"
              onClick={() => applyPreset(p.weights)}
              className="rounded-full border border-black/10 bg-white px-3 py-1.5 text-xs font-medium text-secondary-label hover:border-accent/30 hover:text-label dark:border-white/10 dark:bg-white/[0.06]"
            >
              {p.label}
            </button>
          ))}
        </div>

        <div className="space-y-1.5">
          <div className="flex h-2 overflow-hidden rounded-full bg-black/[0.06] dark:bg-white/10">
            {QUESTION_TYPES.map((t) => {
              const e = config[t]!;
              const pct = totalWeight ? (e.enabled ? e.weight / totalWeight : 0) * 100 : 0;
              if (pct <= 0) return null;
              return <div key={t} className={`${SEG_COLORS[t]} transition-all`} style={{ width: `${pct}%` }} title={`${TYPE_META[t].title} ${Math.round(pct)}%`} />;
            })}
          </div>
          <div className="flex flex-wrap gap-x-3 gap-y-1">
            {QUESTION_TYPES.filter((t) => config[t]!.enabled).map((t) => (
              <span key={t} className="inline-flex items-center gap-1.5 text-[11px] text-tertiary-label">
                <span className={`size-2 rounded-full ${SEG_COLORS[t]}`} />{TYPE_META[t].title}
              </span>
            ))}
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          {GROUPS.map((group) => (
            <div key={group.label} className="rounded-[16px] border border-black/[0.06] bg-white/[0.7] p-3 dark:border-white/[0.08] dark:bg-white/[0.04]">
              <div className="mb-2.5 flex items-center gap-1.5 text-xs font-semibold tracking-wide text-secondary-label">
                <group.icon className="size-3.5" />{group.label}
                <span className="ml-auto text-[11px] font-normal text-tertiary-label">{group.types.filter((t) => config[t]!.enabled).length}/{group.types.length} 已启用</span>
              </div>
              <div className="space-y-2">
                {group.types.map((type) => {
                  const entry = config[type]!;
                  const meta = TYPE_META[type];
                  const pct = totalWeight ? Math.round((entry.enabled ? entry.weight / totalWeight : 0) * 100) : 0;
                  return (
                    <div
                      key={type}
                      className={`flex items-center gap-2 rounded-[12px] border px-2.5 py-2 transition-colors ${entry.enabled ? "border-black/[0.06] bg-white dark:border-white/[0.08] dark:bg-white/[0.04]" : "border-black/[0.04] bg-black/[0.02] opacity-60 dark:border-white/5"}`}
                    >
                      <div className="min-w-0 flex-1">
                        <div className="text-sm font-medium leading-none">{meta.title}</div>
                        <div className="mt-0.5 truncate text-xs text-tertiary-label">{meta.hint}</div>
                      </div>
                      <div className={`flex items-center gap-1 rounded-full border bg-white px-1 py-1 dark:bg-white/10 ${entry.enabled ? "border-black/10 dark:border-white/10" : "border-black/5 opacity-60"}`}>
                        <button
                          type="button"
                          disabled={!entry.enabled}
                          onClick={() => handleWeight(type, entry.weight - 1)}
                          className="grid size-6 place-items-center rounded-full hover:bg-black/5 disabled:opacity-30 dark:hover:bg-white/10"
                          aria-label="降低权重"
                        >
                          <Minus className="size-3" />
                        </button>
                        <span className="min-w-6 text-center text-xs font-semibold tabular-nums">{entry.weight}</span>
                        <button
                          type="button"
                          disabled={!entry.enabled}
                          onClick={() => handleWeight(type, entry.weight + 1)}
                          className="grid size-6 place-items-center rounded-full hover:bg-black/5 disabled:opacity-30 dark:hover:bg-white/10"
                          aria-label="增加权重"
                        >
                          <Plus className="size-3" />
                        </button>
                      </div>
                      <span className={`hidden min-w-9 text-right text-xs tabular-nums sm:block ${entry.enabled ? "text-tertiary-label" : "text-black/30 dark:text-white/30"}`}>{pct}%</span>
                      <Toggle label="" checked={entry.enabled} onChange={(v) => handleToggle(type, v)} />
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
        <p className="text-xs leading-relaxed text-tertiary-label">提示：完形填空需要例句、字母拼词仅对 3–14 个纯字母的单词生效；不满足条件时会自动用同组其他题型替补。</p>
      </CardContent>
    </Card>
  );
}
