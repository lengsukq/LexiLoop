import { useState } from "react";
import { Gamepad2, RotateCcw, Sparkles } from "lucide-react";
import { Button, Card, CardContent, buttonClass } from "@/components/ui";
import { GameSummary, type SummaryItem } from "@/components/game-summary";
import { GameMistakeCallout, GameResultAccuracy, GameResultHero, GameResultStats } from "@/components/game-result";
import { GameMistakeFlashcards } from "@/components/game-mistake-flashcards";
import { LeaderboardPanel } from "@/components/leaderboard-panel";
import { GAME_CONFIG, type GameMode, type GameResult } from "./games-config";

export function GamesResultView({ mode, result, summaryItems, onReplay, onChooseOther }: {
  mode: GameMode;
  result: GameResult;
  summaryItems: SummaryItem[];
  onReplay: () => void;
  onChooseOther: () => void;
}) {
  const [showFlashcards, setShowFlashcards] = useState(false);
  const config = GAME_CONFIG[mode];
  const mistakeItems = summaryItems.filter((item) => item.status !== "correct");

  return (
    <div className="mx-auto max-w-2xl space-y-5 py-5">
      <Card className="overflow-hidden">
        <GameResultHero gradient={`bg-gradient-to-br ${config.gradient}`} label={`${config.title}得分`} score={result.score} elapsedMs={result.elapsedMs} maxCombo={result.maxCombo} />
        <CardContent className="space-y-5 py-6 sm:px-8">
          <GameResultStats firstTryCorrect={result.firstTryCorrect} recovered={result.recovered} missed={result.missed} missedLabel="超时未完成" />
          <GameResultAccuracy accuracy={result.accuracy} />
          
          {mistakeItems.length > 0 && (
            <div className="rounded-[18px] border border-warning/20 bg-warning/[0.08] p-4 flex flex-col sm:flex-row items-center justify-between gap-3 shadow-[0_4px_16px_rgba(255,149,0,0.06)]">
              <div>
                <p className="text-sm font-bold text-warning-deep flex items-center gap-1.5">
                  <Sparkles className="size-4 text-warning" />
                  趁热打铁 · 错词专项记忆
                </p>
                <p className="mt-0.5 text-xs text-secondary-label">本轮有 {mistakeItems.length} 个词条失误，建议使用闪卡速记深度吸收助记。</p>
              </div>
              <Button size="sm" onClick={() => setShowFlashcards(true)} className="whitespace-nowrap w-full sm:w-auto">
                <Sparkles className="size-3.5" />
                30秒错词速记 ({mistakeItems.length})
              </Button>
            </div>
          )}

          <GameSummary items={summaryItems} />
          <LeaderboardPanel leaderboard={result.leaderboard} />
          {(result.recovered > 0 || result.missed > 0) && <GameMistakeCallout>错答或超时词条已记录为错词，后续小游戏和错词强化会优先抽取。</GameMistakeCallout>}
          <div className="grid gap-2 sm:grid-cols-2">
            <Button size="lg" onClick={onReplay}><RotateCcw className="size-5" />再来一轮</Button>
            <button type="button" className={buttonClass("outline", "lg")} onClick={onChooseOther}><Gamepad2 className="size-5" />选择其他游戏</button>
          </div>
        </CardContent>
      </Card>

      {showFlashcards && (
        <GameMistakeFlashcards
          open={showFlashcards}
          onClose={() => setShowFlashcards(false)}
          mistakes={mistakeItems}
        />
      )}
    </div>
  );
}
