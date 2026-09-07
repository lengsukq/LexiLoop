"use client";

import { useState } from "react";
import { ArrowLeft } from "lucide-react";
import { AnimatePresence, motion } from "framer-motion";
import { Badge, Card, CardContent, Progress, Segmented, buttonClass } from "@/components/ui";
import { GameErrorBanner, GamePlayHeader, GameSavingOverlay } from "@/components/game-hud";
import { PhoneticLearn } from "./phonetic-learn";
import { PhoneticQuestion } from "./phonetic-question";
import { PhoneticResult } from "./phonetic-result";
import { PhoneticSetup } from "./phonetic-setup";
import { usePhoneticGame } from "./use-phonetic-game";

export default function PhoneticsPage() {
  const game = usePhoneticGame();
  const [activeTab, setActiveTab] = useState<"learn" | "train">("learn");

  if (game.phase === "result" && game.result) {
    return <PhoneticResult
      result={game.result}
      accent={game.accent}
      items={game.summaryItems}
      onRestart={() => void game.start()}
      onExit={game.exit}
    />;
  }

  if (game.phase !== "setup" && game.phase !== "loading") {
    if (!game.session || !game.current) return null;
    const progress = game.index / Math.max(1, game.session.items.length) * 100;

    return <div className="mx-auto max-w-3xl space-y-3 pb-3 sm:space-y-5 sm:py-4">
      <GamePlayHeader remainingMs={game.remainingMs} combo={game.combo} exit={<button type="button" className={buttonClass("ghost", "sm")} onClick={game.exit}><ArrowLeft className="size-4" />退出</button>} />

      <div className="space-y-2">
        <div className="flex justify-between text-xs text-quaternary-label"><span>音标训练 · 第 {game.index + 1}/{game.session.items.length} 题</span><span>错答 {game.mistakeCount}</span></div>
        <Progress value={progress} />
      </div>

      <Card className="liquid-glass-elevated liquid-glass-specular overflow-hidden border-border/80 shadow-[0_12px_36px_rgba(0,0,0,0.06)] dark:shadow-[0_18px_42px_rgba(0,0,0,0.3)]">
        <div className="relative overflow-hidden border-b border-white/20 bg-gradient-to-r from-accent/12 via-[#00c7be]/12 to-[#5856d6]/15 px-5 py-4.5 backdrop-blur-xl sm:px-7 dark:border-white/[0.08] dark:from-accent/20 dark:via-[#00c7be]/20 dark:to-[#5856d6]/20">
          <div className="pointer-events-none absolute -right-12 -top-12 size-36 rounded-full bg-accent/20 blur-2xl" />
          <div className="relative flex items-center justify-between gap-3">
            <div>
              <b className="block text-[16px] font-bold text-label">音标辨音训练营</b>
              <small className="text-secondary-label">{game.accent === "US" ? "美式发音" : "英式发音"} · 声音、音标和拼写联动</small>
            </div>
            <Badge tone="blue" className="font-semibold">{game.accent}</Badge>
          </div>
        </div>
        <CardContent className="min-h-[430px] py-6 sm:px-8 sm:py-8">
          <AnimatePresence mode="wait">
            <motion.div
              key={game.index}
              initial={{ opacity: 0, y: 10, scale: 0.99 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: -10, scale: 0.99 }}
              transition={{ duration: 0.2, ease: [0.16, 1, 0.3, 1] }}
            >
              <PhoneticQuestion
                item={game.current}
                wrongChoice={game.wrongChoice}
                correctFeedback={game.correctFeedback}
                audioError={game.audioError}
                onChoose={game.choose}
                onPlay={game.playCurrent}
                onSkip={game.skip}
              />
            </motion.div>
          </AnimatePresence>
        </CardContent>
      </Card>

      <GameErrorBanner error={game.error} onRetry={() => void game.finish()} />
      {game.phase === "saving" && <GameSavingOverlay />}
    </div>;
  }

  return <div className="mx-auto max-w-5xl space-y-4">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <Segmented
        value={activeTab}
        onChange={setActiveTab}
        options={[
          { value: "learn", label: "学习专区" },
          { value: "train", label: "听辨训练" },
        ]}
      />
      <span className="text-xs text-tertiary-label">{activeTab === "learn" ? "48 音标 · 讲透会区分" : "75 秒 · 声音-音标-拼写联动"}</span>
    </div>
    {activeTab === "learn" ? (
      <PhoneticLearn />
    ) : (
      <PhoneticSetup
        accent={game.accent}
        phase={game.phase}
        error={game.error}
        onAccentChange={game.setAccent}
        onStart={() => void game.start()}
      />
    )}
  </div>;
}
