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
  return <div className="mx-auto max-w-3xl space-y-5 py-2 sm:py-6">
    <div className="flex items-center justify-between">
      <Link href="/games" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回游戏</Link>
      <Badge tone="blue"><AudioLines className="size-3.5" />音标专项</Badge>
    </div>

    <Card className="overflow-hidden">
      <div className="relative overflow-hidden bg-gradient-to-br from-[#00c7be] via-[#007aff] to-[#5856d6] px-5 py-9 text-center text-white sm:px-10 sm:py-12">
        <div className="absolute -right-16 -top-16 size-52 rounded-full bg-white/10 blur-3xl" />
        <span className="relative mx-auto grid size-20 place-items-center rounded-[24px] bg-white/15 shadow-xl backdrop-blur-xl"><Ear className="size-10" /></span>
        <h1 className="relative mt-5 text-3xl font-black tracking-tight">音标辨音训练营</h1>
        <p className="relative mx-auto mt-3 max-w-xl text-sm leading-relaxed text-white/80">通过听音、辨认音标和反向匹配单词，建立“声音—音标—拼写”之间的联系。</p>
      </div>

      <CardContent className="space-y-6 py-6 sm:px-8">
        <div>
          <p className="text-sm font-semibold">选择训练口音</p>
          <div className="mt-3 grid grid-cols-2 gap-3">
            {(["US", "UK"] as const).map((value) => <button
              key={value}
              type="button"
              onClick={() => onAccentChange(value)}
              className={`ios-press rounded-[18px] border p-4 text-left transition ${accent === value ? "border-[#007aff]/40 bg-[#007aff]/[0.09] shadow-[0_8px_28px_rgba(0,122,255,0.1)]" : "glass-inner border-white/45 dark:border-white/[0.08]"}`}
            >
              <b className="text-lg">{value === "US" ? "美式发音" : "英式发音"}</b>
              <p className="mt-1 text-xs text-[#8e8e93]">{value === "US" ? "优先使用 US / 通用音标" : "优先使用 UK / 通用音标"}</p>
            </button>)}
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-3">
          <div className="rounded-[16px] bg-[#007aff]/[0.07] p-4"><Headphones className="size-5 text-[#007aff]" /><b className="mt-3 block text-sm">听音选音标</b><p className="mt-1 text-xs leading-relaxed text-[#8e8e93]">训练耳朵识别声音对应的音标。</p></div>
          <div className="rounded-[16px] bg-[#00c7be]/[0.08] p-4"><AudioLines className="size-5 text-[#00a59d]" /><b className="mt-3 block text-sm">音标选单词</b><p className="mt-1 text-xs leading-relaxed text-[#8e8e93]">看到音标后反向回忆单词。</p></div>
          <div className="rounded-[16px] bg-[#5856d6]/[0.07] p-4"><TimerReset className="size-5 text-[#5856d6]" /><b className="mt-3 block text-sm">75 秒挑战</b><p className="mt-1 text-xs leading-relaxed text-[#8e8e93]">每轮 10 题，错词和薄弱词优先。</p></div>
        </div>

        {error && <div className="rounded-[14px] bg-[#ff3b30]/[0.08] p-3 text-sm text-[#d70015] dark:text-[#ff453a]">{error}</div>}
        <Button size="lg" className="w-full" onClick={onStart} disabled={loading}>{loading ? <Loader2 className="size-5 animate-spin" /> : <Ear className="size-5" />}开始音标训练</Button>
        <p className="text-center text-xs text-[#aeaeb2]">该游戏不占用今日复习队列；错答仍会进入错词强化。</p>
      </CardContent>
    </Card>
  </div>;
}
