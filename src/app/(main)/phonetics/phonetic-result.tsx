"use client";

import Link from "next/link";
import { Ear, Flame, RotateCcw, Trophy } from "lucide-react";
import { LeaderboardPanel } from "@/components/leaderboard-panel";
import { Button, Card, CardContent, Progress, buttonClass } from "@/components/ui";
import type { PhoneticAccent, PhoneticGameResult } from "./types";

export function PhoneticResult({ result, accent, onRestart, onExit }: {
  result: PhoneticGameResult;
  accent: PhoneticAccent;
  onRestart: () => void;
  onExit: () => void;
}) {
  return <div className="mx-auto max-w-2xl space-y-5 py-5">
    <Card className="overflow-hidden">
      <div className="bg-gradient-to-br from-[#00c7be] via-[#007aff] to-[#5856d6] px-5 py-10 text-center text-white sm:py-12">
        <span className="mx-auto grid size-20 place-items-center rounded-full bg-white/15 backdrop-blur-xl"><Trophy className="size-10" /></span>
        <p className="mt-5 text-sm font-semibold text-white/75">{accent === "US" ? "美式" : "英式"}音标训练得分</p>
        <h1 className="mt-1 text-5xl font-black tracking-tight">{result.score}</h1>
        <p className="mt-2 text-sm text-white/70">用时 {(result.elapsedMs / 1000).toFixed(1)} 秒 · 最长 {result.maxCombo} 连击</p>
      </div>
      <CardContent className="space-y-5 py-6 sm:px-8">
        <div className="grid grid-cols-3 gap-3 text-center">
          <div className="rounded-[16px] bg-[#34c759]/[0.08] p-3"><p className="text-2xl font-bold text-[#248a3d] dark:text-[#30d158]">{result.firstTryCorrect}</p><p className="text-xs text-[#8e8e93]">一次正确</p></div>
          <div className="rounded-[16px] bg-[#ff9500]/[0.08] p-3"><p className="text-2xl font-bold text-[#c93400] dark:text-[#ff9f0a]">{result.recovered}</p><p className="text-xs text-[#8e8e93]">纠正完成</p></div>
          <div className="rounded-[16px] bg-[#ff3b30]/[0.08] p-3"><p className="text-2xl font-bold text-[#d70015] dark:text-[#ff453a]">{result.missed}</p><p className="text-xs text-[#8e8e93]">超时或跳过</p></div>
        </div>
        <div><div className="mb-2 flex justify-between text-sm"><span className="text-[#6e6e73] dark:text-[#98989d]">首次正确率</span><b>{result.accuracy}%</b></div><Progress value={result.accuracy} /></div>
        <LeaderboardPanel leaderboard={result.leaderboard} />
        {(result.recovered > 0 || result.missed > 0) && <div className="flex items-start gap-3 rounded-[16px] bg-[#ff9500]/[0.08] p-4"><Flame className="mt-0.5 size-5 shrink-0 text-[#ff9500]" /><p className="text-sm leading-relaxed text-[#8a3b00] dark:text-[#ff9f0a]">答错或跳过的单词已记入错词状态，下一轮音标训练会优先出现。</p></div>}
        <div className="grid gap-2 sm:grid-cols-2">
          <Button size="lg" onClick={onRestart}><RotateCcw className="size-5" />再来一轮</Button>
          <button type="button" className={buttonClass("outline", "lg")} onClick={onExit}><Ear className="size-5" />更换口音</button>
        </div>
        <Link href="/games" className={`${buttonClass("ghost")} w-full`}>返回全部游戏</Link>
      </CardContent>
    </Card>
  </div>;
}
