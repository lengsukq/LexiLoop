"use client";

import type { ReactNode } from "react";
import { Flame, Trophy } from "lucide-react";
import { Progress } from "@/components/ui";

/**
 * Gradient hero at the top of a result screen. `gradient` is the full background
 * class (e.g. "bg-gradient-to-br from-[#34c759] via-[#0a84ff] to-[#5856d6]").
 * `heroPadding`/`labelTone` keep per-game spacing/opacity differences intact.
 */
export function GameResultHero({ gradient, label, score, elapsedMs, maxCombo, heroPadding = "py-9", labelTone = "text-white/70" }: {
  gradient: string;
  label: string;
  score: number;
  elapsedMs: number;
  maxCombo: number;
  heroPadding?: string;
  labelTone?: string;
}) {
  return <div className={`${gradient} px-5 ${heroPadding} text-center text-white sm:py-12`}>
    <span className="mx-auto grid size-20 place-items-center rounded-full bg-white/15 backdrop-blur-xl"><Trophy className="size-10" /></span>
    <p className={`mt-5 text-sm font-semibold ${labelTone}`}>{label}</p>
    <h1 className="mt-1 text-5xl font-black tracking-tight">{score}</h1>
    <p className="mt-2 text-sm text-white/70">用时 {(elapsedMs / 1000).toFixed(1)} 秒 · 最长 {maxCombo} 连击</p>
  </div>;
}

/** Three-cell stat grid (first-try / recovered / missed) with configurable labels. */
export function GameResultStats({ firstTryCorrect, recovered, missed, firstLabel = "一次正确", recoveredLabel = "纠正完成", missedLabel = "未完成" }: {
  firstTryCorrect: number;
  recovered: number;
  missed: number;
  firstLabel?: string;
  recoveredLabel?: string;
  missedLabel?: string;
}) {
  return <div className="grid grid-cols-3 gap-3 text-center">
    <div className="rounded-[16px] bg-[#34c759]/[0.08] p-3"><p className="text-2xl font-bold text-[#248a3d] dark:text-[#30d158]">{firstTryCorrect}</p><p className="text-xs text-[#8e8e93]">{firstLabel}</p></div>
    <div className="rounded-[16px] bg-[#ff9500]/[0.08] p-3"><p className="text-2xl font-bold text-[#c93400] dark:text-[#ff9f0a]">{recovered}</p><p className="text-xs text-[#8e8e93]">{recoveredLabel}</p></div>
    <div className="rounded-[16px] bg-[#ff3b30]/[0.08] p-3"><p className="text-2xl font-bold text-[#d70015] dark:text-[#ff453a]">{missed}</p><p className="text-xs text-[#8e8e93]">{missedLabel}</p></div>
  </div>;
}

/** First-try accuracy row with a progress bar. */
export function GameResultAccuracy({ accuracy, label = "首次正确率" }: { accuracy: number; label?: string }) {
  return <div>
    <div className="mb-2 flex items-center justify-between text-sm"><span className="text-[#6e6e73] dark:text-[#98989d]">{label}</span><b>{accuracy}%</b></div>
    <Progress value={accuracy} />
  </div>;
}

/** Orange callout reminding that mistaken/missed words were recorded. */
export function GameMistakeCallout({ children }: { children: ReactNode }) {
  return <div className="flex items-start gap-3 rounded-[16px] bg-[#ff9500]/[0.08] p-4">
    <Flame className="mt-0.5 size-5 shrink-0 text-[#ff9500]" />
    <p className="text-sm leading-relaxed text-[#8a3b00] dark:text-[#ff9f0a]">{children}</p>
  </div>;
}
