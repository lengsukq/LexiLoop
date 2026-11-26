"use client";

import { useState } from "react";
import Link from "next/link";
import { Ear, RotateCcw, Sparkles } from "lucide-react";
import { GameSummary, type SummaryItem } from "@/components/game-summary";
import { LeaderboardPanel } from "@/components/leaderboard-panel";
import { GameMistakeCallout, GameResultAccuracy, GameResultHero, GameResultStats } from "@/components/game-result";
import { GameMistakeFlashcards } from "@/components/game-mistake-flashcards";
import { Button, Card, CardContent, buttonClass } from "@/components/ui";
import type { PhoneticAccent, PhoneticGameResult } from "./types";

export function PhoneticResult({ result, accent, items, onRestart, onExit }: {
  result: PhoneticGameResult;
  accent: PhoneticAccent;
  items: SummaryItem[];
  onRestart: () => void;
  onExit: () => void;
}) {
  const [showFlashcards, setShowFlashcards] = useState(false);
  const mistakeItems = items.filter((item) => item.status !== "correct");

  return <div className="mx-auto max-w-2xl space-y-5 py-5">
    <Card className="overflow-hidden">
      <GameResultHero gradient="bg-gradient-to-br from-[#00c7be] via-accent to-[#5856d6]" label={`${accent === "US" ? "美式" : "英式"}音标训练得分`} score={result.score} elapsedMs={result.elapsedMs} maxCombo={result.maxCombo} heroPadding="py-10" labelTone="text-white/75" />
      <CardContent className="space-y-5 py-6 sm:px-8">
        <GameResultStats firstTryCorrect={result.firstTryCorrect} recovered={result.recovered} missed={result.missed} missedLabel="超时或跳过" />
        <GameResultAccuracy accuracy={result.accuracy} />
        
        {mistakeItems.length > 0 && (
          <div className="rounded-[18px] border border-warning/20 bg-warning/[0.08] p-4 flex flex-col sm:flex-row items-center justify-between gap-3 shadow-[0_4px_16px_rgba(255,149,0,0.06)]">
            <div>
              <p className="text-sm font-bold text-warning-deep flex items-center gap-1.5">
                <Sparkles className="size-4 text-warning" />
                趁热打铁 · 错词专项记忆
              </p>
              <p className="mt-0.5 text-xs text-secondary-label">本轮有 {mistakeItems.length} 个音标失误词条，建议使用闪卡速记吸收助记。</p>
            </div>
            <Button size="sm" onClick={() => setShowFlashcards(true)} className="whitespace-nowrap w-full sm:w-auto">
              <Sparkles className="size-3.5" />
              30秒错词速记 ({mistakeItems.length})
            </Button>
          </div>
        )}

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

    {showFlashcards && (
      <GameMistakeFlashcards
        open={showFlashcards}
        onClose={() => setShowFlashcards(false)}
        mistakes={mistakeItems}
      />
    )}
  </div>;
}
