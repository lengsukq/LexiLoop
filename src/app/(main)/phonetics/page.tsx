"use client";

import { ArrowLeft } from "lucide-react";
import { Badge, Card, CardContent, Progress, buttonClass } from "@/components/ui";
import { GameErrorBanner, GamePlayHeader, GameSavingOverlay } from "@/components/game-hud";
import { PhoneticQuestion } from "./phonetic-question";
import { PhoneticResult } from "./phonetic-result";
import { PhoneticSetup } from "./phonetic-setup";
import { usePhoneticGame } from "./use-phonetic-game";

export default function PhoneticsPage() {
  const game = usePhoneticGame();

  if (game.phase === "setup" || game.phase === "loading") {
    return <PhoneticSetup
      accent={game.accent}
      phase={game.phase}
      error={game.error}
      onAccentChange={game.setAccent}
      onStart={() => void game.start()}
    />;
  }

  if (game.phase === "result" && game.result) {
    return <PhoneticResult
      result={game.result}
      accent={game.accent}
      items={game.summaryItems}
      onRestart={() => void game.start()}
      onExit={game.exit}
    />;
  }

  if (!game.session || !game.current) return null;
  const progress = game.index / Math.max(1, game.session.items.length) * 100;

  return <div className="mx-auto max-w-3xl space-y-3 pb-3 sm:space-y-5 sm:py-4">
    <GamePlayHeader remainingMs={game.remainingMs} combo={game.combo} exit={<button type="button" className={buttonClass("ghost", "sm")} onClick={game.exit}><ArrowLeft className="size-4" />退出</button>} />

    <div className="space-y-2">
      <div className="flex justify-between text-xs text-[#8e8e93]"><span>音标训练 · 第 {game.index + 1}/{game.session.items.length} 题</span><span>错答 {game.mistakeCount}</span></div>
      <Progress value={progress} />
    </div>

    <Card className="overflow-hidden">
      <div className="bg-gradient-to-r from-[#00c7be] via-[#007aff] to-[#5856d6] px-5 py-4 text-white sm:px-7">
        <div className="flex items-center justify-between gap-3">
          <div><b className="block text-[16px]">音标辨音训练营</b><small className="text-white/75">{game.accent === "US" ? "美式发音" : "英式发音"} · 声音、音标和拼写联动</small></div>
          <Badge tone="glass">{game.accent}</Badge>
        </div>
      </div>
      <CardContent className="min-h-[430px] py-6 sm:px-8 sm:py-8">
        <PhoneticQuestion
          item={game.current}
          wrongChoice={game.wrongChoice}
          correctFeedback={game.correctFeedback}
          audioError={game.audioError}
          onChoose={game.choose}
          onPlay={game.playCurrent}
          onSkip={game.skip}
        />
      </CardContent>
    </Card>

    <GameErrorBanner error={game.error} onRetry={() => void game.finish()} />
    {game.phase === "saving" && <GameSavingOverlay />}
  </div>;
}
