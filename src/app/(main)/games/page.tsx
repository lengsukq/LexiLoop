"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import {
  ArrowLeft, AudioLines, Blocks, Brain, CheckCircle2, Flame, Gamepad2, Hammer, Headphones,
  Layers, Loader2, Puzzle, RotateCcw, Volume2, XCircle, Zap,
} from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { playCachedTts, preloadTtsBatch } from "@/lib/tts-client";
import { useActiveStopwatch } from "@/lib/use-active-stopwatch";
import { useGameCountdown } from "@/lib/use-game-countdown";
import { useGameScoring } from "@/lib/use-game-scoring";
import type { GameAnswerState, GamePhase } from "@/lib/game-types";
import { Badge, Button, Card, CardContent, Progress, buttonClass } from "@/components/ui";
import { GameSummary, type SummaryItem } from "@/components/game-summary";
import { GameErrorBanner, GamePlayHeader, GameSavingOverlay } from "@/components/game-hud";
import { GameMistakeCallout, GameResultAccuracy, GameResultHero, GameResultStats } from "@/components/game-result";
import { LeaderboardPanel } from "@/components/leaderboard-panel";
import type { LeaderboardSummary } from "@/lib/types";
import { WhackAMole } from "./whack-a-mole";
import { WordStack } from "./word-stack";
import { WordTetris } from "./word-tetris";
import type { GameItem } from "./types";

const GAME_MODES = ["WORD_BUILDER", "LISTENING_PICK", "MEANING_BLITZ", "WHACK_A_MOLE", "WORD_STACK", "WORD_TETRIS"] as const;
type GameMode = (typeof GAME_MODES)[number];

const TETRIS_DANGER_CAP = 5;

interface GameSession {
  sessionId: number;
  mode: GameMode;
  durationSeconds: number;
  items: GameItem[];
}

interface GameResult {
  sessionId: number;
  mode: GameMode;
  score: number;
  firstTryCorrect: number;
  recovered: number;
  missed: number;
  total: number;
  accuracy: number;
  mistakeCount: number;
  maxCombo: number;
  elapsedMs: number;
  leaderboard?: LeaderboardSummary;
}

const CONFIG: Record<GameMode, {
  title: string;
  subtitle: string;
  rule: string;
  icon: React.ReactNode;
  gradient: string;
}> = {
  WORD_BUILDER: {
    title: "单词拼图",
    subtitle: "根据释义组合字母",
    rule: "点击打乱的字母拼出英文词条",
    icon: <Puzzle className="size-7" />,
    gradient: "from-[#ff9500] to-[#ff6961]",
  },
  LISTENING_PICK: {
    title: "听音辨词",
    subtitle: "听发音快速选词",
    rule: "听到发音后，从四个词中选出正确答案",
    icon: <Headphones className="size-7" />,
    gradient: "from-[#5ac8fa] to-[#007aff]",
  },
  MEANING_BLITZ: {
    title: "词义冲刺",
    subtitle: "限时选择正确释义",
    rule: "看到英文后，快速选择对应的中文释义",
    icon: <Brain className="size-7" />,
    gradient: "from-[#af52de] to-[#5856d6]",
  },
  WHACK_A_MOLE: {
    title: "词汇地鼠",
    subtitle: "锤出正确单词",
    rule: "看释义，在地鼠缩回前锤中正确单词",
    icon: <Hammer className="size-7" />,
    gradient: "from-[#34c759] to-[#00c7be]",
  },
  WORD_STACK: {
    title: "单词堆堆乐",
    subtitle: "点词块搭高塔",
    rule: "看释义，点选滚动词块堆高塔",
    icon: <Layers className="size-7" />,
    gradient: "from-[#ff2d55] to-[#ff9500]",
  },
  WORD_TETRIS: {
    title: "词汇俄罗斯方块",
    subtitle: "点词块消堆叠",
    rule: "看释义，点中下落的正确单词",
    icon: <Blocks className="size-7" />,
    gradient: "from-[#5856d6] to-[#af52de]",
  },
};

function validMode(value: string | null): value is GameMode {
  return Boolean(value && GAME_MODES.includes(value as GameMode));
}

function GamesPageContent() {
  const searchParams = useSearchParams();
  const initialMode = validMode(searchParams.get("mode")) ? searchParams.get("mode") as GameMode : null;
  const [mode, setMode] = useState<GameMode | null>(initialMode);
  const [phase, setPhase] = useState<GamePhase>("setup");
  const [session, setSession] = useState<GameSession | null>(null);
  const [index, setIndex] = useState(0);
  const [builtLetterIds, setBuiltLetterIds] = useState<string[]>([]);
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
  const dragStateRef = useRef<{ startX: number; startY: number; startId: string; startZone: "pool" | "built"; active: boolean } | null>(null);
  const suppressClickRef = useRef(false);
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
      setError(reason instanceof Error ? reason.message : "保存小游戏结果失败");
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
      setBuiltLetterIds([]);
      setWrongChoice(null);
      setRevealed(false);
      setSolvedTerms([]);
      setSummaryItems([]);
      setTetrisDanger(0);
      setPhase("playing");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "创建小游戏失败");
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
    setBuiltLetterIds([]);
    setWrongChoice(null);
    if (!session || index >= session.items.length - 1) {
      window.setTimeout(() => void finishGame(), 260);
      return;
    }
    window.setTimeout(() => setIndex((value) => value + 1), 220);
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
    if (!session || index >= session.items.length - 1) {
      window.setTimeout(() => void finishGame(), 260);
      return;
    }
    window.setTimeout(() => setIndex((value) => value + 1), 220);
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
    markMistake(current);
    setWrongChoice(choice);
    window.setTimeout(() => setWrongChoice(null), 420);
  }

  function applyTile(id: string, zone: string) {
    if (zone === "pool") setBuiltLetterIds((ids) => ids.includes(id) ? ids : [...ids, id]);
    else setBuiltLetterIds((ids) => ids.filter((value) => value !== id));
  }

  function handleTilePointerDown(event: React.PointerEvent, id: string, zone: "pool" | "built") {
    if (!current || revealed || phase !== "playing") return;
    suppressClickRef.current = false;
    dragStateRef.current = { startX: event.clientX, startY: event.clientY, startId: id, startZone: zone, active: false };
  }

  function handleTileClick(id: string, zone: "pool" | "built") {
    if (suppressClickRef.current) {
      suppressClickRef.current = false;
      return;
    }
    if (!current || revealed || phase !== "playing") return;
    applyTile(id, zone);
  }

  function handleDragMove(event: React.PointerEvent | PointerEvent) {
    const state = dragStateRef.current;
    if (!state || !current || revealed) return;
    if (!state.active) {
      if (Math.hypot(event.clientX - state.startX, event.clientY - state.startY) < 10) return;
      state.active = true;
      suppressClickRef.current = true;
      applyTile(state.startId, state.startZone);
    }
    const element = document.elementFromPoint(event.clientX, event.clientY);
    const tile = element instanceof Element ? element.closest("[data-letter-id]") : null;
    if (!tile) return;
    const id = tile.getAttribute("data-letter-id") ?? "";
    const zone = tile.getAttribute("data-letter-zone") ?? "";
    if (id) applyTile(id, zone);
  }

  const dragMoveRef = useRef(handleDragMove);
  useEffect(() => {
    dragMoveRef.current = handleDragMove;
  });

  useEffect(() => {
    const onMove = (event: PointerEvent) => dragMoveRef.current(event);
    const endDrag = () => { dragStateRef.current = null; };
    window.addEventListener("pointermove", onMove, true);
    window.addEventListener("pointerup", endDrag, true);
    window.addEventListener("pointercancel", endDrag, true);
    return () => {
      window.removeEventListener("pointermove", onMove, true);
      window.removeEventListener("pointerup", endDrag, true);
      window.removeEventListener("pointercancel", endDrag, true);
    };
  }, []);

  function submitWord() {
    if (!current || revealed) return;
    const answer = builtLetterIds.map((id) => current.letters.find((letter) => letter.id === id)?.value ?? "").join("");
    if (answer.toLocaleLowerCase() === current.term.toLocaleLowerCase()) {
      advanceSolved(current);
      return;
    }
    markMistake(current);
    setWrongChoice("__word__");
    window.setTimeout(() => {
      setWrongChoice(null);
      setBuiltLetterIds([]);
    }, 440);
  }

  function revealWord() {
    if (!current || revealed) return;
    captureItemDuration();
    pauseCountdown();
    markMistake(current);
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
    setBuiltLetterIds([]);
    setWrongChoice(null);
    if (!session || index >= session.items.length - 1) {
      window.setTimeout(() => void finishGame(), 260);
      return;
    }
    window.setTimeout(() => setIndex((value) => value + 1), 220);
  }

  if (phase === "setup" || phase === "loading") {
    return <div className="mx-auto max-w-4xl space-y-5 py-2 sm:py-6">
      <div className="flex items-center justify-between">
        <Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回</Link>
        <Badge tone="purple"><Gamepad2 className="size-3.5" />趣味训练</Badge>
      </div>
      <Card className="overflow-hidden">
        <div className="relative overflow-hidden bg-gradient-to-br from-[#5856d6] via-[#007aff] to-[#5ac8fa] px-5 py-8 text-center text-white sm:px-10 sm:py-11">
          <div className="absolute -right-16 -top-16 size-48 rounded-full bg-white/10 blur-3xl" />
          <span className="relative mx-auto grid size-16 place-items-center rounded-[20px] bg-white/15 backdrop-blur-xl"><Zap className="size-8" /></span>
          <h1 className="relative mt-5 text-2xl font-bold tracking-tight sm:text-3xl">趣味英语训练</h1>
          <p className="relative mx-auto mt-2 max-w-xl text-sm leading-relaxed text-white/75 sm:text-[15px]">独立于每日复习队列。错词、近期忘记和模糊的词会优先出现在小游戏中。</p>
        </div>
        <CardContent className="space-y-5 py-5 sm:px-8 sm:py-7">
          <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
            <Link href="/match" className="ios-press glass-inner group flex items-center gap-4 rounded-[18px] border border-white/40 p-4 transition-all hover:border-[#af52de]/35 hover:shadow-[0_10px_32px_rgba(175,82,222,0.12)] dark:border-white/[0.08]">
              <span className="grid size-12 shrink-0 place-items-center rounded-[15px] bg-gradient-to-br from-[#af52de] to-[#5856d6] text-white shadow-lg"><Gamepad2 className="size-6" /></span>
              <span className="min-w-0"><b className="block text-[16px]">限时词汇配对</b><small className="mt-1 block text-[13px] text-[#8e8e93]">英文与释义组队配对 · 连击计分</small></span>
            </Link>
            <Link href="/phonetics" className="ios-press glass-inner group flex items-center gap-4 rounded-[18px] border border-white/40 p-4 transition-all hover:border-[#00c7be]/35 hover:shadow-[0_10px_32px_rgba(0,199,190,0.12)] dark:border-white/[0.08]">
              <span className="grid size-12 shrink-0 place-items-center rounded-[15px] bg-gradient-to-br from-[#00c7be] to-[#007aff] text-white shadow-lg"><AudioLines className="size-6" /></span>
              <span className="min-w-0"><b className="block text-[16px]">音标辨音训练</b><small className="mt-1 block text-[13px] text-[#8e8e93]">听音、音标与单词三向匹配</small></span>
            </Link>
            {GAME_MODES.map((gameMode) => {
              const config = CONFIG[gameMode];
              return <button key={gameMode} type="button" onClick={() => void startGame(gameMode)} disabled={phase === "loading"} className="ios-press glass-inner group flex items-center gap-4 rounded-[18px] border border-white/40 p-4 text-left transition-all hover:border-[#007aff]/35 hover:shadow-[0_10px_32px_rgba(0,122,255,0.12)] disabled:opacity-50 dark:border-white/[0.08]">
                <span className={`grid size-12 shrink-0 place-items-center rounded-[15px] bg-gradient-to-br ${config.gradient} text-white shadow-lg`}>{phase === "loading" && mode === gameMode ? <Loader2 className="size-6 animate-spin" /> : config.icon}</span>
                <span className="min-w-0"><b className="block text-[16px]">{config.title}</b><small className="mt-1 block text-[13px] text-[#8e8e93]">{config.subtitle}</small></span>
              </button>;
            })}
          </div>
          <GameErrorBanner error={error} />
        </CardContent>
      </Card>
    </div>;
  }

  if (phase === "result" && result && mode) {
    const config = CONFIG[mode];
    return <div className="mx-auto max-w-2xl space-y-5 py-5">
      <Card className="overflow-hidden">
        <GameResultHero gradient={`bg-gradient-to-br ${config.gradient}`} label={`${config.title}得分`} score={result.score} elapsedMs={result.elapsedMs} maxCombo={result.maxCombo} />
        <CardContent className="space-y-5 py-6 sm:px-8">
          <GameResultStats firstTryCorrect={result.firstTryCorrect} recovered={result.recovered} missed={result.missed} missedLabel="超时未完成" />
          <GameResultAccuracy accuracy={result.accuracy} />
          <GameSummary items={summaryItems} />
          <LeaderboardPanel leaderboard={result.leaderboard} />
          {(result.recovered > 0 || result.missed > 0) && <GameMistakeCallout>错答或超时词条已记录为错词，后续小游戏和错词强化会优先抽取。</GameMistakeCallout>}
          <div className="grid gap-2 sm:grid-cols-2">
            <Button size="lg" onClick={() => void startGame(mode)}><RotateCcw className="size-5" />再来一轮</Button>
            <button type="button" className={buttonClass("outline", "lg")} onClick={() => { setPhase("setup"); setSession(null); setResult(null); }}><Gamepad2 className="size-5" />选择其他游戏</button>
          </div>
        </CardContent>
      </Card>
    </div>;
  }

  if (!session || !current || !mode) return null;
  const config = CONFIG[mode];
  const progress = index / Math.max(1, session.items.length) * 100;
  const builtLetters = builtLetterIds.map((id) => current.letters.find((letter) => letter.id === id)).filter(Boolean) as Array<{ id: string; value: string }>;

  return <div className="mx-auto max-w-3xl space-y-3 pb-3 sm:space-y-5 sm:py-4">
    <GamePlayHeader remainingMs={remainingMs} combo={combo} exit={<button type="button" className={buttonClass("ghost", "sm")} onClick={() => { setPhase("setup"); setSession(null); }}><ArrowLeft className="size-4" />退出</button>} />
    <div className="space-y-2"><div className="flex justify-between text-xs text-[#8e8e93]"><span>{config.title} · 第 {index + 1}/{session.items.length} 题</span><span>错答 {mistakeCount}</span></div><Progress value={progress} /></div>

    <Card className="overflow-hidden">
      <div className={`bg-gradient-to-r ${config.gradient} px-5 py-4 text-white sm:px-7`}><div className="flex items-center gap-3"><span className="grid size-10 place-items-center rounded-[13px] bg-white/15">{config.icon}</span><span><b className="block text-[16px]">{config.title}</b><small className="text-white/70">{config.rule}</small></span></div></div>
      <CardContent className="min-h-[420px] py-6 sm:px-8 sm:py-8">
        {current.priority !== "NORMAL" && <div className="mb-4 flex justify-center"><Badge tone="red"><Flame className="size-3.5" />重点复习词</Badge></div>}

        {mode === "WORD_BUILDER" && <div className="text-center">
          <p className="text-[13px] text-[#8e8e93]">根据释义拼出英文</p>
          <h1 className="mx-auto mt-3 max-w-xl text-xl font-bold leading-relaxed sm:text-2xl">{current.definition}</h1>
          <button type="button" onClick={() => void playCachedTts(current.term, "US")} className="ios-press mx-auto mt-4 grid size-12 place-items-center rounded-full bg-[#ff9500]/12 text-[#ff9500] shadow-[0_6px_20px_rgba(255,149,0,0.12)]"><Volume2 className="size-5" /></button>
          {revealed ? <div className="animate-scale-in mx-auto mt-5 max-w-xl">
            <div className="rounded-[18px] border-2 border-[#ff9500]/40 bg-[#ff9500]/[0.06] px-4 py-6">
              <p className="text-[13px] font-medium text-[#ff9500]">正确答案 · 计时已暂停</p>
              <div className="mt-4 flex flex-wrap justify-center gap-1.5">
                {current.term.split("").map((char, charIndex) => <span key={`${char}-${charIndex}`} className="grid size-12 place-items-center rounded-[14px] bg-gradient-to-br from-[#ff9500] to-[#ff6961] text-lg font-bold uppercase text-white shadow-md">{char}</span>)}
              </div>
              <p className="mt-4 text-sm leading-relaxed text-[#8e8e93]">记住它的拼写，然后继续下一题。该词已记入错词，之后会优先复习。</p>
            </div>
            <Button size="lg" className="mt-5 w-full sm:w-auto" onClick={confirmRevealed}><CheckCircle2 className="size-5" />记住了，继续</Button>
          </div> : <>
            <div className="touch-none select-none">
              <div className={`mx-auto mt-5 flex min-h-16 max-w-xl flex-wrap items-center justify-center gap-2 rounded-[18px] border-2 border-dashed px-4 py-3 ${wrongChoice === "__word__" ? "border-[#ff3b30] bg-[#ff3b30]/[0.06]" : "border-[#007aff]/20 bg-[#007aff]/[0.04]"}`}>
                {builtLetters.length ? builtLetters.map((letter) => <button key={letter.id} type="button" data-letter-id={letter.id} data-letter-zone="built" onPointerDown={(event) => handleTilePointerDown(event, letter.id, "built")} onClick={() => handleTileClick(letter.id, "built")} className="ios-press touch-none grid size-11 place-items-center rounded-[12px] bg-[#007aff] text-lg font-bold uppercase text-white shadow-md">{letter.value}</button>) : <span className="text-sm text-[#aeaeb2]">点按或滑动字母拼写</span>}
              </div>
              <div className="mx-auto mt-6 flex max-w-xl flex-wrap justify-center gap-2">
                {current.letters.map((letter) => {
                  const used = builtLetterIds.includes(letter.id);
                  return <button key={letter.id} type="button" aria-disabled={used} data-letter-id={letter.id} data-letter-zone="pool" onPointerDown={(event) => handleTilePointerDown(event, letter.id, "pool")} onClick={() => handleTileClick(letter.id, "pool")} className={`ios-press touch-none grid size-12 place-items-center rounded-[14px] border border-black/[0.06] bg-white/70 text-lg font-bold uppercase shadow-sm dark:border-white/[0.08] dark:bg-white/[0.06] ${used ? "opacity-20" : ""}`}>{letter.value}</button>;
                })}
              </div>
            </div>
            <div className="mx-auto mt-7 grid max-w-md grid-cols-[auto_auto_1fr] gap-2"><Button variant="outline" onClick={() => setBuiltLetterIds([])} disabled={!builtLetterIds.length}>清空</Button><Button variant="outline" onClick={revealWord} className="text-[#ff3b30] dark:text-[#ff453a]"><XCircle className="size-4" />不认识</Button><Button onClick={submitWord} disabled={builtLetterIds.length !== current.letters.length}><CheckCircle2 className="size-4" />提交答案</Button></div>
          </>}
        </div>}

        {mode === "LISTENING_PICK" && <div className="text-center">
          <p className="text-[13px] text-[#8e8e93]">听发音，选择正确的英文词条</p>
          <button type="button" onClick={() => void playCachedTts(current.term, "US")} className="ios-press mx-auto mt-6 grid size-24 place-items-center rounded-full bg-[#5ac8fa]/12 text-[#007aff] shadow-[0_10px_36px_rgba(0,122,255,0.12)]"><Volume2 className="size-11" /></button>
          <p className="mt-3 text-xs text-[#aeaeb2]">点击可重复播放</p>
          <ChoiceGrid choices={current.choices} wrongChoice={wrongChoice} onChoose={chooseAnswer} definitions={current.choiceDefinitions} />
        </div>}

        {mode === "MEANING_BLITZ" && <div className="text-center">
          <p className="text-[13px] text-[#8e8e93]">选择最准确的中文释义</p>
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
  return <div className="mx-auto mt-8 grid max-w-xl gap-3 sm:grid-cols-2">{choices.map((choice) => <button key={choice} type="button" onClick={() => onChoose(choice)} disabled={Boolean(wrongChoice)} className={`ios-press min-h-16 rounded-[17px] border px-4 py-3 text-left transition-all ${wrongChoice === choice ? "border-[#ff3b30] bg-[#ff3b30]/10 text-[#d70015] dark:text-[#ff453a]" : "glass-inner border-white/45 hover:border-[#007aff]/35 hover:shadow-[0_8px_28px_rgba(0,122,255,0.1)] dark:border-white/[0.08]"}`}>{wrongChoice === choice && <XCircle className="mr-2 inline size-4" />}<span className="min-w-0 break-words font-semibold">{choice}</span>{definitions?.[choice] && <span className="mt-1 line-clamp-2 block text-xs font-normal leading-snug text-[#8e8e93]">{definitions[choice]}</span>}</button>)}</div>;
}
