"use client";

import { useSearchParams } from "next/navigation";
import { errorMessage } from "@/lib/format";
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { ArrowLeft, Flame, Volume2, XCircle } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { playCachedTts, preloadTtsBatch } from "@/lib/tts-client";
import { useActiveStopwatch } from "@/lib/use-active-stopwatch";
import { useGameCountdown } from "@/lib/use-game-countdown";
import { useGameScoring } from "@/lib/use-game-scoring";
import type { GameAnswerState, GamePhase } from "@/lib/game-types";
import { Badge, Card, CardContent, Progress, buttonClass } from "@/components/ui";
import type { SummaryItem } from "@/components/game-summary";
import { GameErrorBanner, GamePlayHeader, GameSavingOverlay } from "@/components/game-hud";
import { getGameConfig, validMode, type GameMode, type GameResult, type GameSession } from "./games-config";
import { GamesSetup } from "./games-setup";
import { GamesResultView } from "./games-result";
import { WordBuilder } from "./word-builder";
import { WhackAMole } from "./whack-a-mole";
import { WordStack } from "./word-stack";
import { WordTetris } from "./word-tetris";
import type { GameItem } from "./types";
import "./games-motion.css";

const TETRIS_DANGER_CAP = 5;

function GamesPageContent() {
  const searchParams = useSearchParams();
  const initialMode = validMode(searchParams.get("mode")) ? searchParams.get("mode") as GameMode : null;
  const [mode, setMode] = useState<GameMode | null>(initialMode);
  const [phase, setPhase] = useState<GamePhase>("setup");
  const [session, setSession] = useState<GameSession | null>(null);
  const [index, setIndex] = useState(0);
  const [wrongChoice, setWrongChoice] = useState<string | null>(null);
  const [result, setResult] = useState<GameResult | null>(null);
  const [error, setError] = useState("");
  const [solvedTerms, setSolvedTerms] = useState<string[]>([]);
  const [summaryItems, setSummaryItems] = useState<SummaryItem[]>([]);
  const [revealed, setRevealed] = useState(false);
  const [tetrisDanger, setTetrisDanger] = useState(0);

  const {
    combo, mistakeCount,
    incrementCombo, resetCombo, flagMistakeItems, recordMistake,
    reset: resetScoring, getMaxCombo, getMistakeCount, hasMistake,
  } = useGameScoring();

  const sessionRef = useRef<GameSession | null>(null);
  const answersRef = useRef<Map<number, GameAnswerState>>(new Map());
  const finishingRef = useRef(false);
  const autoPlayedRef = useRef<number | null>(null);
  const autoStartRef = useRef(false);
  const tetrisDangerRef = useRef(0);

  const finishGame = useCallback(async () => {
    const currentSession = sessionRef.current;
    if (!currentSession || finishingRef.current) return;
    finishingRef.current = true;
    setPhase("saving");
    setError("");
    const answers = currentSession.items.map((item) => answersRef.current.get(item.itemId) ?? {
      itemId: item.itemId,
      wordId: item.wordId,
      solved: false,
      hadMistake: true,
      durationMs: 0,
    });
    const elapsedMs = answers.reduce((sum, answer) => sum + answer.durationMs, 0);
    setSummaryItems(currentSession.items.map((item) => {
      const answer = answersRef.current.get(item.itemId);
      const solved = answer?.solved ?? false;
      const hadMistake = answer?.hadMistake ?? true;
      return {
        wordId: item.wordId,
        term: item.term,
        definition: item.definition,
        status: solved ? (hadMistake ? "recovered" : "correct") : "missed",
      } satisfies SummaryItem;
    }));
    try {
      const saved = await apiFetch<GameResult>(`/api/games/sessions/${currentSession.sessionId}/complete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mode: currentSession.mode,
          answers,
          elapsedMs,
          mistakeCount: getMistakeCount(),
          maxCombo: getMaxCombo(),
        }),
      });
      setResult(saved);
      setPhase("result");
    } catch (reason) {
      setError(errorMessage(reason, "保存小游戏结果失败"));
      setPhase("save-error");
      finishingRef.current = false;
    }
  }, [getMaxCombo, getMistakeCount]);

  const { remainingMs, start: startCountdown, pause: pauseCountdown, resume: resumeCountdown } = useGameCountdown(phase === "playing" && Boolean(session), () => void finishGame());

  const current = session?.items[index] ?? null;
  const { reset: resetItemTimer, capture: captureItemDuration } = useActiveStopwatch(Boolean(phase === "playing" && current && !revealed));
  useEffect(() => {
    if (phase !== "playing" || !session) return;
    void preloadTtsBatch(session.items.slice(index, index + 5).map((item) => ({ text: item.term, accent: "US" })));
  }, [index, phase, session]);

  useEffect(() => {
    if (!current) return;
    resetItemTimer();
    if ((session?.mode === "LISTENING_PICK" || session?.mode === "MEANING_BLITZ") && autoPlayedRef.current !== current.itemId) {
      autoPlayedRef.current = current.itemId;
      const timer = window.setTimeout(() => void playCachedTts(current.term, "US"), 180);
      return () => window.clearTimeout(timer);
    }
  }, [current, resetItemTimer, session?.mode]);

  const startGame = useCallback(async (selectedMode: GameMode) => {
    setMode(selectedMode);
    setPhase("loading");
    setError("");
    setResult(null);
    try {
      const created = await apiFetch<GameSession>("/api/games/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode: selectedMode }),
      });
      sessionRef.current = created;
      answersRef.current = new Map();
      tetrisDangerRef.current = 0;
      finishingRef.current = false;
      autoPlayedRef.current = null;
      resetScoring();
      startCountdown(created.durationSeconds * 1000);
      setSession(created);
      setIndex(0);
      setWrongChoice(null);
      setRevealed(false);
      setSolvedTerms([]);
      setSummaryItems([]);
      setTetrisDanger(0);
      setPhase("playing");
    } catch (reason) {
      setError(errorMessage(reason, "创建小游戏失败"));
      setPhase("setup");
    }
  }, [resetScoring, startCountdown]);

  useEffect(() => {
    if (!initialMode || autoStartRef.current) return;
    autoStartRef.current = true;
    void startGame(initialMode);
  }, [initialMode, startGame]);

  function markMistake(item: GameItem) {
    recordMistake(item.itemId);
  }

  function advanceToNext() {
    setWrongChoice(null);
    if (!session || index >= session.items.length - 1) {
      window.setTimeout(() => void finishGame(), 260);
      return;
    }
    window.setTimeout(() => setIndex((value) => value + 1), 220);
  }

  function advanceSolved(item: GameItem) {
    incrementCombo();
    setSolvedTerms((terms) => [...terms, item.term]);
    answersRef.current.set(item.itemId, {
      itemId: item.itemId,
      wordId: item.wordId,
      solved: true,
      hadMistake: hasMistake(item.itemId),
      durationMs: captureItemDuration(),
    });
    advanceToNext();
  }

  function advanceFailed(item: GameItem) {
    flagMistakeItems(item.itemId);
    resetCombo();
    answersRef.current.set(item.itemId, {
      itemId: item.itemId,
      wordId: item.wordId,
      solved: false,
      hadMistake: true,
      durationMs: captureItemDuration(),
    });
    advanceToNext();
  }

  function handleTetrisSolved(item: GameItem) {
    tetrisDangerRef.current = Math.max(0, tetrisDangerRef.current - 1);
    setTetrisDanger(tetrisDangerRef.current);
    advanceSolved(item);
  }

  function handleTetrisLand(word: string) {
    tetrisDangerRef.current += 1;
    setTetrisDanger(tetrisDangerRef.current);
    if (tetrisDangerRef.current >= TETRIS_DANGER_CAP) {
      window.setTimeout(() => void finishGame(), 350);
      return;
    }
    if (current && word === current.term) advanceFailed(current);
  }

  function chooseAnswer(choice: string) {
    if (!current || !session || wrongChoice) return;
    void playCachedTts(current.term, "US");
    const correct = session.mode === "MEANING_BLITZ" ? current.definition : current.term;
    if (choice === correct) {
      advanceSolved(current);
      return;
    }
    recordMistake(current.itemId);
    setWrongChoice(choice);
    window.setTimeout(() => setWrongChoice(null), 420);
  }

  function revealWord() {
    if (!current || revealed) return;
    captureItemDuration();
    pauseCountdown();
    recordMistake(current.itemId);
    setRevealed(true);
    void playCachedTts(current.term, "US");
  }

  function confirmRevealed() {
    if (!current || !revealed) return;
    resumeCountdown();
    answersRef.current.set(current.itemId, {
      itemId: current.itemId,
      wordId: current.wordId,
      solved: false,
      hadMistake: true,
      durationMs: captureItemDuration(),
    });
    setRevealed(false);
    advanceToNext();
  }

  function exitToSetup() {
    setPhase("setup");
    setSession(null);
    setResult(null);
  }

  if (phase === "setup" || phase === "loading") {
    return <GamesSetup loading={phase === "loading"} loadingMode={mode} error={error} onStart={(selectedMode) => void startGame(selectedMode)} />;
  }

  if (phase === "result" && result && mode) {
    return (
      <GamesResultView
        mode={mode}
        result={result}
        summaryItems={summaryItems}
        onReplay={() => void startGame(mode)}
        onChooseOther={exitToSetup}
      />
    );
  }

  if (!session || !current || !mode) return null;
  const config = getGameConfig(mode);
  const progress = index / Math.max(1, session.items.length) * 100;

  return <div className="mx-auto max-w-3xl space-y-3 pb-3 sm:space-y-5 sm:py-4">
    <GamePlayHeader remainingMs={remainingMs} combo={combo} exit={<button type="button" className={buttonClass("ghost", "sm")} onClick={exitToSetup}><ArrowLeft className="size-4" />退出</button>} />
    <div className="space-y-2"><div className="flex justify-between text-xs text-quaternary-label"><span>{config.title} · 第 {index + 1}/{session.items.length} 题</span><span>错答 {mistakeCount}</span></div><Progress value={progress} /></div>

    <Card className="overflow-hidden">
      <div className={`bg-gradient-to-r ${config.gradient} px-5 py-4 text-white sm:px-7`}><div className="flex items-center gap-3"><span className="grid size-10 place-items-center rounded-[13px] bg-white/15">{config.icon}</span><span><b className="block text-[16px]">{config.title}</b><small className="text-white/70">{config.rule}</small></span></div></div>
      <CardContent className="min-h-[420px] py-6 sm:px-8 sm:py-8">
        {current.priority !== "NORMAL" && <div className="mb-4 flex justify-center"><Badge tone="red"><Flame className="size-3.5" />重点复习词</Badge></div>}

        {mode === "WORD_BUILDER" && (
          <WordBuilder
            key={current.itemId}
            item={current}
            revealed={revealed}
            onSolved={() => advanceSolved(current)}
            onMistake={() => recordMistake(current.itemId)}
            onReveal={revealWord}
            onConfirmRevealed={confirmRevealed}
          />
        )}

        {mode === "LISTENING_PICK" && <div className="text-center">
          <p className="text-[13px] text-quaternary-label">听发音，选择正确的英文词条</p>
          <button type="button" onClick={() => void playCachedTts(current.term, "US")} className="ios-press mx-auto mt-6 grid size-24 place-items-center rounded-full bg-[#5ac8fa]/12 text-accent shadow-[0_10px_36px_rgba(0,122,255,0.12)]"><Volume2 className="size-11" /></button>
          <p className="mt-3 text-xs text-tertiary-label">点击可重复播放</p>
          <ChoiceGrid choices={current.choices} wrongChoice={wrongChoice} onChoose={chooseAnswer} definitions={current.choiceDefinitions} />
        </div>}

        {mode === "MEANING_BLITZ" && <div className="text-center">
          <p className="text-[13px] text-quaternary-label">选择最准确的中文释义</p>
          <h1 className="mt-6 break-words text-4xl font-bold tracking-tight sm:text-5xl">{current.term}</h1>
          <ChoiceGrid choices={current.choices} wrongChoice={wrongChoice} onChoose={chooseAnswer} />
        </div>}

        {mode === "WHACK_A_MOLE" && <WhackAMole key={current.itemId} item={current} onSolved={advanceSolved} onMistake={markMistake} onFailed={advanceFailed} />}

        {mode === "WORD_STACK" && <WordStack key={current.itemId} item={current} solvedTerms={solvedTerms} onSolved={advanceSolved} onMistake={markMistake} />}

        {mode === "WORD_TETRIS" && <WordTetris key={current.itemId} item={current} danger={tetrisDanger} dangerCap={TETRIS_DANGER_CAP} onSolved={handleTetrisSolved} onMistake={markMistake} onFailed={advanceFailed} onLand={handleTetrisLand} />}
      </CardContent>
    </Card>

    <GameErrorBanner error={error} onRetry={() => void finishGame()} />
    {phase === "saving" && <GameSavingOverlay />}
  </div>;
}

export default function GamesPage() {
  return <Suspense fallback={null}><GamesPageContent /></Suspense>;
}

function ChoiceGrid({ choices, wrongChoice, onChoose, definitions }: { choices: string[]; wrongChoice: string | null; onChoose: (choice: string) => void; definitions?: Record<string, string> }) {
  return (
    <div className="mx-auto mt-8 grid max-w-xl gap-3 sm:grid-cols-2">
      {choices.map((choice) => (
        <button
          key={choice}
          type="button"
          onClick={() => onChoose(choice)}
          disabled={Boolean(wrongChoice)}
          className={`ios-press min-h-16 rounded-[17px] border px-4 py-3 text-left transition-all ${wrongChoice === choice ? "border-danger bg-danger/10 text-danger-deep" : "glass-inner border-white/45 hover:border-accent/35 hover:shadow-[0_8px_28px_rgba(0,122,255,0.1)] dark:border-white/[0.08]"}`}
        >
          {wrongChoice === choice && <XCircle className="mr-2 inline size-4" />}
          <span className="min-w-0 break-words font-semibold">{choice}</span>
          {definitions?.[choice] && <span className="mt-1 line-clamp-2 block text-xs font-normal leading-snug text-quaternary-label">{definitions[choice]}</span>}
        </button>
      ))}
    </div>
  );
}
