"use client";

import Link from "next/link";
import { Ear, RotateCcw } from "lucide-react";
import { GameSummary, type SummaryItem } from "@/components/game-summary";
import { LeaderboardPanel } from "@/components/leaderboard-panel";
import { GameMistakeCallout, GameResultAccuracy, GameResultHero, GameResultStats } from "@/components/game-result";
import { Button, Card, CardContent, buttonClass } from "@/components/ui";
import type { PhoneticAccent, PhoneticGameResult } from "./types";

export function PhoneticResult({ result, accent, items, onRestart, onExit }: {
  result: PhoneticGameResult;
  accent: PhoneticAccent;
  items: SummaryItem[];
  onRestart: () => void;
  onExit: () => void;
}) {
  return <div className="mx-auto max-w-2xl space-y-5 py-5">
    <Card className="overflow-hidden">
      <GameResultHero gradient="bg-gradient-to-br from-[#00c7be] via-[#007aff] to-[#5856d6]" label={`${accent === "US" ? "美式" : "英式"}音标训练得分`} score={result.score} elapsedMs={result.elapsedMs} maxCombo={result.maxCombo} heroPadding="py-10" labelTone="text-white/75" />
      <CardContent className="space-y-5 py-6 sm:px-8">
        <GameResultStats firstTryCorrect={result.firstTryCorrect} recovered={result.recovered} missed={result.missed} missedLabel="超时或跳过" />
        <GameResultAccuracy accuracy={result.accuracy} />
        <GameSummary items={items} />
        <LeaderboardPanel leaderboard={result.leaderboard} />
        {(result.recovered > 0 || result.missed > 0) && <GameMistakeCallout>答错或跳过的单词已记入错词状态，下一轮音标训练会优先出现。</GameMistakeCallout>}
        <div className="grid gap-2 sm:grid-cols-2">
          <Button size="lg" onClick={onRestart}><RotateCcw className="size-5" />再来一轮</Button>
          <button type="button" className={buttonClass("outline", "lg")} onClick={onExit}><Ear className="size-5" />更换口音</button>
        </div>
        <Link href="/games" className={`${buttonClass("ghost")} w-full`}>返回全部游戏</Link>
      </CardContent>
    </Card>
  </div>;
}
