"use client";

import { ArrowLeft, Clock3, Flame, Loader2 } from "lucide-react";
import { Badge, Card, CardContent, Progress, buttonClass } from "@/components/ui";
import { PhoneticQuestion } from "./phonetic-question";
import { PhoneticResult } from "./phonetic-result";
import { PhoneticSetup } from "./phonetic-setup";
import { usePhoneticGame } from "./use-phonetic-game";

function formatTime(ms: number): string {
  const seconds = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

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
      onRestart={() => void game.start()}
      onExit={game.exit}
    />;
  }

  if (!game.session || !game.current) return null;
  const progress = game.index / Math.max(1, game.session.items.length) * 100;
  const urgent = game.remainingMs <= 10_000;

  return <div className="mx-auto max-w-3xl space-y-3 pb-3 sm:space-y-5 sm:py-4">
    <div className="flex items-center justify-between gap-3">
      <button type="button" className={buttonClass("ghost", "sm")} onClick={game.exit}><ArrowLeft className="size-4" />退出</button>
      <div className={`flex items-center gap-2 rounded-full px-4 py-2 font-mono text-lg font-bold ${urgent ? "animate-pulse bg-[#ff3b30]/10 text-[#ff3b30]" : "bg-[#007aff]/10 text-[#007aff] dark:text-[#0a84ff]"}`}><Clock3 className="size-5" />{formatTime(game.remainingMs)}</div>
      <Badge tone={game.combo >= 3 ? "amber" : "slate"}><Flame className="size-3.5" />{game.combo} 连击</Badge>
    </div>

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

    {game.error && <div className="flex items-center justify-between gap-3 rounded-[14px] bg-[#ff3b30]/[0.08] p-3 text-sm text-[#d70015] dark:text-[#ff453a]"><span>{game.error}</span><button type="button" className="font-semibold" onClick={() => void game.finish()}>重试保存</button></div>}
    {game.phase === "saving" && <div className="fixed inset-0 z-50 grid place-items-center bg-black/20 backdrop-blur-sm"><div className="liquid-glass-elevated rounded-[22px] px-7 py-6 text-center"><Loader2 className="mx-auto size-8 animate-spin text-[#007aff]" /><p className="mt-3 text-sm font-semibold">正在结算并更新错词…</p></div></div>}
  </div>;
}
