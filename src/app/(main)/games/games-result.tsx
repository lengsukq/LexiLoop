import { Gamepad2, RotateCcw } from "lucide-react";
import { Button, Card, CardContent, buttonClass } from "@/components/ui";
import { GameSummary, type SummaryItem } from "@/components/game-summary";
import { GameMistakeCallout, GameResultAccuracy, GameResultHero, GameResultStats } from "@/components/game-result";
import { LeaderboardPanel } from "@/components/leaderboard-panel";
import { GAME_CONFIG, type GameMode, type GameResult } from "./games-config";

export function GamesResultView({ mode, result, summaryItems, onReplay, onChooseOther }: {
  mode: GameMode;
  result: GameResult;
  summaryItems: SummaryItem[];
  onReplay: () => void;
  onChooseOther: () => void;
}) {
  const config = GAME_CONFIG[mode];
  return (
    <div className="mx-auto max-w-2xl space-y-5 py-5">
      <Card className="overflow-hidden">
        <GameResultHero gradient={`bg-gradient-to-br ${config.gradient}`} label={`${config.title}得分`} score={result.score} elapsedMs={result.elapsedMs} maxCombo={result.maxCombo} />
        <CardContent className="space-y-5 py-6 sm:px-8">
          <GameResultStats firstTryCorrect={result.firstTryCorrect} recovered={result.recovered} missed={result.missed} missedLabel="超时未完成" />
          <GameResultAccuracy accuracy={result.accuracy} />
          <GameSummary items={summaryItems} />
          <LeaderboardPanel leaderboard={result.leaderboard} />
          {(result.recovered > 0 || result.missed > 0) && <GameMistakeCallout>错答或超时词条已记录为错词，后续小游戏和错词强化会优先抽取。</GameMistakeCallout>}
          <div className="grid gap-2 sm:grid-cols-2">
            <Button size="lg" onClick={onReplay}><RotateCcw className="size-5" />再来一轮</Button>
            <button type="button" className={buttonClass("outline", "lg")} onClick={onChooseOther}><Gamepad2 className="size-5" />选择其他游戏</button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
