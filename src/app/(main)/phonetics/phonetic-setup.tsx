"use client";

import Link from "next/link";
import { ArrowLeft, AudioLines, Ear, Headphones, Loader2, TimerReset } from "lucide-react";
import { Badge, Button, Card, CardContent, buttonClass } from "@/components/ui";
import type { PhoneticAccent, PhoneticPhase } from "./types";

export function PhoneticSetup({
  accent,
  phase,
  error,
  onAccentChange,
  onStart,
}: {
  accent: PhoneticAccent;
  phase: PhoneticPhase;
  error: string;
  onAccentChange: (accent: PhoneticAccent) => void;
  onStart: () => void;
}) {
  const loading = phase === "loading";
  return <div className="mx-auto max-w-3xl space-y-4 py-2 sm:space-y-5 sm:py-5">
    <div className="flex items-center justify-between">
      <Link href="/games" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回游戏</Link>
      <Badge tone="blue"><AudioLines className="size-3.5" />音标专项</Badge>
    </div>

    <Card className="overflow-hidden rounded-[24px]">
      <div className="relative overflow-hidden bg-gradient-to-br from-[#00c7be] via-accent to-[#5856d6] px-5 py-7 text-center text-white shadow-[inset_0_1.5px_0_rgba(255,255,255,0.3)] sm:px-8 sm:py-9">
        <div className="absolute -right-16 -top-16 size-52 rounded-full bg-white/10 blur-2xl pointer-events-none" />
        <span className="relative mx-auto grid size-14 place-items-center rounded-[18px] bg-white/20 shadow-xs backdrop-blur-md"><Ear className="size-7" /></span>
        <h1 className="relative mt-3.5 text-2xl font-bold tracking-tight">音标辨音训练营</h1>
        <p className="relative mx-auto mt-1.5 max-w-lg text-xs leading-relaxed text-white/80 sm:text-[13.5px]">通过听音、辨认音标和反向匹配单词，建立“声音—音标—拼写”之间的联系。</p>
      </div>

      <CardContent className="space-y-5 py-5 sm:px-7 sm:py-6">
        <div>
          <p className="text-xs font-semibold text-secondary-label">选择训练口音</p>
          <div className="mt-2.5 grid grid-cols-2 gap-2.5">
            {(["US", "UK"] as const).map((value) => <button
              key={value}
              type="button"
              onClick={() => onAccentChange(value)}
              className={`ios-press rounded-[16px] border p-3.5 text-left transition-all ${accent === value ? "border-accent/50 bg-accent/[0.08] shadow-[0_4px_16px_rgba(0,122,255,0.10)]" : "border-black/[0.08] bg-white/60 hover:bg-white hover:border-black/[0.12] dark:border-white/[0.09] dark:bg-white/[0.04]"}`}
            >
              <b className="text-[15px] font-semibold">{value === "US" ? "美式发音" : "英式发音"}</b>
              <p className="mt-0.5 text-xs text-quaternary-label">{value === "US" ? "优先使用 US 音标" : "优先使用 UK 音标"}</p>
            </button>)}
          </div>
        </div>

        <div className="grid gap-2.5 sm:grid-cols-3">
          <div className="rounded-[14px] bg-accent/[0.05] p-3"><Headphones className="size-4.5 text-accent" /><b className="mt-2 block text-[13.5px] font-semibold">听音选音标</b><p className="mt-0.5 text-xs leading-relaxed text-quaternary-label">训练耳朵识别声音对应的音标。</p></div>
          <div className="rounded-[14px] bg-[#00c7be]/[0.06] p-3"><AudioLines className="size-4.5 text-[#00a59d]" /><b className="mt-2 block text-[13.5px] font-semibold">音标选单词</b><p className="mt-0.5 text-xs leading-relaxed text-quaternary-label">看到音标后反向回忆单词。</p></div>
          <div className="rounded-[14px] bg-[#5856d6]/[0.05] p-3"><TimerReset className="size-4.5 text-[#5856d6]" /><b className="mt-2 block text-[13.5px] font-semibold">75 秒挑战</b><p className="mt-0.5 text-xs leading-relaxed text-quaternary-label">每轮 10 题，错词和薄弱词优先。</p></div>
        </div>

        {error && <div className="rounded-[12px] bg-danger/[0.06] p-2.5 text-xs text-danger-deep">{error}</div>}
        <Button size="lg" className="w-full" onClick={onStart} disabled={loading}>{loading ? <Loader2 className="size-4.5 animate-spin" /> : <Ear className="size-4.5" />}开始音标训练</Button>
        <p className="text-center text-xs text-tertiary-label">该游戏不占用今日复习队列；错答仍会进入错词强化。</p>
      </CardContent>
    </Card>
  </div>;
}
