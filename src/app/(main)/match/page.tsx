"use client";

import Link from "next/link";
import { errorMessage } from "@/lib/format";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ArrowLeft, CheckCircle2, Gamepad2, Loader2, RotateCcw,
  Sparkles, XCircle, Zap,
} from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { shuffle } from "@/lib/array";
import type { GamePhase } from "@/lib/game-types";
import { playCachedTts, preloadTtsBatch } from "@/lib/tts-client";
import { useActiveStopwatch } from "@/lib/use-active-stopwatch";
import { useGameCountdown } from "@/lib/use-game-countdown";
import { useGameScoring } from "@/lib/use-game-scoring";
import type { LeaderboardSummary } from "@/lib/types";
import { GameSummary, type SummaryItem } from "@/components/game-summary";
import { GameErrorBanner, GamePlayHeader, GameSavingOverlay } from "@/components/game-hud";
import { GameMistakeCallout, GameResultAccuracy, GameResultHero, GameResultStats } from "@/components/game-result";
import { GameMistakeFlashcards } from "@/components/game-mistake-flashcards";
import { LeaderboardPanel } from "@/components/leaderboard-panel";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Progress, buttonClass } from "@/components/ui";

interface PairItem {
  itemId: number;
  wordId: number;
  term: string;
  definition: string;
  priority: "WRONG" | "RECENT_MISTAKE" | "DUE" | "NORMAL";
}

interface MatchSession {
  sessionId: number;
  pairCount: number;
  durationSeconds: number;
  pairs: PairItem[];
}

interface MatchResult {
  sessionId: number;
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

type Side = "word" | "definition";
type Selection = { side: Side; itemId: number } | null;

const PRESETS = [
  { id: "relaxed", name: "轻松热身", pairs: 5, seconds: 90, desc: "词少、时间充足" },
  { id: "standard", name: "标准挑战", pairs: 6, seconds: 60, desc: "适合每日练习" },
  { id: "sprint", name: "极速冲刺", pairs: 8, seconds: 45, desc: "高强度限时配对" },
] as const;

export default function MatchPage() {
  const [presetId, setPresetId] = useState<(typeof PRESETS)[number]["id"]>("standard");
  const [phase, setPhase] = useState<GamePhase>("setup");
  const [session, setSession] = useState<MatchSession | null>(null);
  const [words, setWords] = useState<PairItem[]>([]);
  const [definitions, setDefinitions] = useState<PairItem[]>([]);
  const [selected, setSelected] = useState<Selection>(null);
  const [matched, setMatched] = useState<Set<number>>(new Set());
  const [wrongFlash, setWrongFlash] = useState<Set<string>>(new Set());
  const [result, setResult] = useState<MatchResult | null>(null);
  const [error, setError] = useState("");
  const [summaryItems, setSummaryItems] = useState<SummaryItem[]>([]);
  const [showFlashcards, setShowFlashcards] = useState(false);

  const {
    combo, mistakeCount,
    incrementCombo, recordMistake,
    reset: resetScoring, getMaxCombo, getMistakeCount, hasMistake,
  } = useGameScoring();

  const sessionRef = useRef<MatchSession | null>(null);
  const matchedRef = useRef<Set<number>>(new Set());
  const finishingRef = useRef(false);
  const { reset: resetActiveTimer, capture: captureActiveDuration } = useActiveStopwatch(phase === "playing");

  const finishGame = useCallback(async () => {
    const current = sessionRef.current;
    if (!current || finishingRef.current) return;
    finishingRef.current = true;
    setPhase("saving");
    setSelected(null);
    setError("");

    const elapsedMs = captureActiveDuration();
    setSummaryItems(current.pairs.map((item) => {
      const matched = matchedRef.current.has(item.itemId);
      const hadMistake = hasMistake(item.itemId);
      return {
        wordId: item.wordId,
        term: item.term,
        definition: item.definition,
        status: matched ? (hadMistake ? "recovered" : "correct") : "missed",
      } satisfies SummaryItem;
    }));
    try {
      const saved = await apiFetch<MatchResult>(`/api/match/sessions/${current.sessionId}/complete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          elapsedMs,
          durationSeconds: current.durationSeconds,
          mistakeCount: getMistakeCount(),
          maxCombo: getMaxCombo(),
          results: current.pairs.map((item) => ({
            itemId: item.itemId,
            wordId: item.wordId,
            matched: matchedRef.current.has(item.itemId),
            hadMistake: hasMistake(item.itemId),
            durationMs: Math.round(elapsedMs / Math.max(1, current.pairCount)),
          })),
        }),
      });
      setResult(saved);
      setPhase("result");
    } catch (reason) {
      setError(errorMessage(reason, "保存配对结果失败"));
      setPhase("save-error");
      finishingRef.current = false;
    }
  }, [captureActiveDuration, getMaxCombo, getMistakeCount, hasMistake]);

  const { remainingMs, start: startCountdown } = useGameCountdown(phase === "playing" && Boolean(session), () => void finishGame());

  useEffect(() => {
    if (phase !== "playing" || !session) return;
    void preloadTtsBatch(session.pairs.map((item) => ({ text: item.term, accent: "US" })));
  }, [phase, session]);

  async function startGame() {
    const preset = PRESETS.find((item) => item.id === presetId) ?? PRESETS[1];
    setPhase("loading");
    setError("");
    setResult(null);
    try {
      const created = await apiFetch<MatchSession>("/api/match/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pairCount: preset.pairs, durationSeconds: preset.seconds }),
      });
      sessionRef.current = created;
      matchedRef.current = new Set();
      finishingRef.current = false;
      resetScoring();
      resetActiveTimer();
      startCountdown(created.durationSeconds * 1000);
      setSession(created);
      setWords(shuffle(created.pairs));
      setDefinitions(shuffle(created.pairs));
      setMatched(new Set());
      setWrongFlash(new Set());
      setSelected(null);
      setSummaryItems([]);
      setPhase("playing");
    } catch (reason) {
      setError(errorMessage(reason, "创建配对游戏失败"));
      setPhase("setup");
    }
  }

  function selectCard(side: Side, item: PairItem) {
    if (phase !== "playing" || matchedRef.current.has(item.itemId) || wrongFlash.size > 0) return;
    if (side === "word") void playCachedTts(item.term, "US");
    if (!selected) {
      setSelected({ side, itemId: item.itemId });
      return;
    }
    if (selected.side === side) {
      setSelected(selected.itemId === item.itemId ? null : { side, itemId: item.itemId });
      return;
    }

    if (selected.itemId === item.itemId) {
      const nextMatched = new Set(matchedRef.current);
      nextMatched.add(item.itemId);
      matchedRef.current = nextMatched;
      setMatched(nextMatched);
      incrementCombo();
      setSelected(null);
      if (session && nextMatched.size >= session.pairCount) {
        window.setTimeout(() => void finishGame(), 280);
      }
      return;
    }

    recordMistake(selected.itemId, item.itemId);
    const flash = new Set([`${selected.side}:${selected.itemId}`, `${side}:${item.itemId}`]);
    setWrongFlash(flash);
    window.setTimeout(() => {
      setWrongFlash(new Set());
      setSelected(null);
    }, 460);
  }

  const preset = PRESETS.find((item) => item.id === presetId) ?? PRESETS[1];

  if (phase === "setup" || phase === "loading") {
    return <div className="mx-auto max-w-3xl space-y-4 py-2 sm:space-y-5 sm:py-5">
      <div className="flex items-center justify-between">
        <Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回</Link>
        <Badge tone="purple"><Gamepad2 className="size-3.5" />趣味练习</Badge>
      </div>
      <Card className="overflow-hidden rounded-[24px]">
        <div className="relative overflow-hidden bg-gradient-to-br from-[#af52de] via-[#5856d6] to-[#007aff] px-5 py-7 text-white shadow-[inset_0_1.5px_0_rgba(255,255,255,0.3)] sm:px-8 sm:py-9">
          <div className="absolute -right-12 -top-12 size-40 rounded-full bg-white/10 blur-2xl pointer-events-none" />
          <div className="relative text-center">
            <span className="mx-auto grid size-13 place-items-center rounded-[16px] bg-white/20 shadow-xs backdrop-blur-md"><Zap className="size-6.5" /></span>
            <h1 className="mt-3.5 text-xl font-bold tracking-tight sm:text-2xl">限时词汇配对</h1>
            <p className="mx-auto mt-1.5 max-w-lg text-xs leading-relaxed text-white/80 sm:text-[13.5px]">将英文和中文释义快速配对。活跃错词、近期忘记和模糊的词会优先出现。</p>
          </div>
        </div>
        <CardContent className="space-y-4 py-4 sm:px-7 sm:py-6">
          <div className="grid gap-2.5 sm:grid-cols-3">
            {PRESETS.map((item) => {
              const active = presetId === item.id;
              return <button key={item.id} type="button" onClick={() => setPresetId(item.id)} className={`ios-press rounded-[16px] border p-3.5 text-left transition-all ${active ? "border-accent/50 bg-accent/[0.08] shadow-[0_4px_16px_rgba(0,122,255,0.10)]" : "border-black/[0.08] bg-white/60 hover:bg-white hover:border-black/[0.12] dark:border-white/[0.09] dark:bg-white/[0.04]"}`}>
                <div className="flex items-center justify-between"><b className="text-[14px] font-semibold">{item.name}</b>{active && <CheckCircle2 className="size-4 text-accent" />}</div>
                <p className="mt-1.5 text-xs text-quaternary-label num-tabular">{item.pairs} 组 · {item.seconds} 秒</p>
                <p className="mt-0.5 text-[11px] text-tertiary-label">{item.desc}</p>
              </button>;
            })}
          </div>
          <div className="grid grid-cols-3 gap-2 rounded-[14px] bg-black/[0.03] p-2.5 text-center dark:bg-white/[0.04]">
            <div><p className="num-tabular text-base font-bold sm:text-lg">{preset.pairs}</p><p className="text-[11px] text-quaternary-label">词汇组数</p></div>
            <div><p className="num-tabular text-base font-bold sm:text-lg">{preset.seconds}s</p><p className="text-[11px] text-quaternary-label">限时时间</p></div>
            <div><p className="text-base font-bold text-danger sm:text-lg">优先</p><p className="text-[11px] text-quaternary-label">错词加入</p></div>
          </div>
          <GameErrorBanner error={error} />
          <Button size="lg" className="w-full" onClick={() => void startGame()} disabled={phase === "loading"}>
            {phase === "loading" ? <Loader2 className="size-4.5 animate-spin" /> : <Sparkles className="size-4.5" />}
            {phase === "loading" ? "正在组题…" : "开始配对"}
          </Button>
        </CardContent>
      </Card>
    </div>;
  }

  if (phase === "result" && result) {
    const mistakeItems = summaryItems.filter((item) => item.status !== "correct");
    return <div className="mx-auto max-w-2xl space-y-4 py-5">
      <Card className="overflow-hidden rounded-[24px]">
        <GameResultHero gradient="bg-gradient-to-br from-success via-[#007aff] to-[#5856d6]" label="本轮得分" score={result.score} elapsedMs={result.elapsedMs} maxCombo={result.maxCombo} />
        <CardContent className="space-y-4 py-5 sm:px-7">
          <GameResultStats firstTryCorrect={result.firstTryCorrect} recovered={result.recovered} missed={result.missed} firstLabel="一次配对" missedLabel="未完成" />
          <GameResultAccuracy accuracy={result.accuracy} label="首次配对正确率" />
          
          {mistakeItems.length > 0 && (
            <div className="rounded-[16px] border border-warning/25 bg-warning/[0.06] p-3.5 flex flex-col sm:flex-row items-center justify-between gap-3 shadow-xs">
              <div>
                <p className="text-[13.5px] font-bold text-warning-deep flex items-center gap-1.5">
                  <Sparkles className="size-3.5 text-warning" />
                  趁热打铁 · 错词专项记忆
                </p>
                <p className="mt-0.5 text-xs text-secondary-label">本轮有 {mistakeItems.length} 个词条配对失误，建议使用闪卡速记强化吸收。</p>
              </div>
              <Button size="sm" onClick={() => setShowFlashcards(true)} className="whitespace-nowrap w-full sm:w-auto text-xs">
                <Sparkles className="size-3.5" />
                30秒错词速记 ({mistakeItems.length})
              </Button>
            </div>
          )}

          <GameSummary items={summaryItems} />
          <LeaderboardPanel leaderboard={result.leaderboard} />
          {(result.recovered > 0 || result.missed > 0) && <GameMistakeCallout>错配或超时词条已按“忘记”记录，后续会优先出现在错词强化和下一轮配对中。</GameMistakeCallout>}
          <div className="grid gap-2 sm:grid-cols-2">
            <Button size="lg" onClick={() => { setPhase("setup"); setSession(null); setResult(null); }}><RotateCcw className="size-4.5" />再来一轮</Button>
            <Link href="/" className={buttonClass("outline", "lg")}><ArrowLeft className="size-4.5" />返回首页</Link>
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
    </div>;
  }

  if (!session) return null;
  const progress = matched.size / Math.max(1, session.pairCount) * 100;

  return <div className="mx-auto max-w-4xl space-y-3 pb-3 sm:space-y-4 sm:py-3">
    <GamePlayHeader remainingMs={remainingMs} combo={combo} exit={<Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />退出</Link>} />
    <div className="space-y-1.5">
      <div className="flex justify-between text-xs text-quaternary-label num-tabular"><span>已配对 {matched.size}/{session.pairCount}</span><span>错配 {mistakeCount}</span></div>
      <Progress value={progress} />
    </div>

    <Card className="overflow-hidden rounded-[24px]">
      <CardHeader className="pb-2"><CardTitle>点击英文与对应释义</CardTitle></CardHeader>
      <CardContent className="grid grid-cols-2 gap-2 pb-4 sm:gap-3.5 sm:px-6 sm:pb-6">
        <div className="space-y-2 sm:space-y-2.5">
          {words.map((item) => <MatchCard key={item.itemId} side="word" item={item} selected={selected} matched={matched.has(item.itemId)} wrong={wrongFlash.has(`word:${item.itemId}`)} onClick={() => selectCard("word", item)} />)}
        </div>
        <div className="space-y-2 sm:space-y-2.5">
          {definitions.map((item) => <MatchCard key={item.itemId} side="definition" item={item} selected={selected} matched={matched.has(item.itemId)} wrong={wrongFlash.has(`definition:${item.itemId}`)} onClick={() => selectCard("definition", item)} />)}
        </div>
      </CardContent>
    </Card>

    <GameErrorBanner error={error} onRetry={() => void finishGame()} />
    {phase === "saving" && <GameSavingOverlay />}
  </div>;
}

function MatchCard({ side, item, selected, matched, wrong, onClick }: {
  side: Side;
  item: PairItem;
  selected: Selection;
  matched: boolean;
  wrong: boolean;
  onClick: () => void;
}) {
  const active = selected?.side === side && selected.itemId === item.itemId;
  const priority = side === "word" && item.priority !== "NORMAL";
  return <button type="button" disabled={matched} onClick={onClick} className={`ios-press relative flex min-h-[54px] w-full items-center rounded-[14px] border px-3 py-2 text-left transition-all duration-200 sm:min-h-[62px] sm:rounded-[16px] sm:px-3.5 ${matched ? "pointer-events-none scale-95 opacity-0 duration-300" : wrong ? "animate-shake border-danger/50 bg-danger/[0.08] text-danger-deep" : active ? "border-accent bg-accent/[0.09] shadow-[0_2px_12px_rgba(0,122,255,0.18)] scale-[1.01]" : "border-black/[0.08] bg-white/70 hover:bg-white hover:border-accent/40 dark:border-white/[0.09] dark:bg-white/[0.05] dark:hover:bg-white/[0.09]"}`}>
    {side === "word" ? <span className="min-w-0"><b className="block break-words text-[15px] font-semibold sm:text-[16px]">{item.term}</b>{priority && <small className="mt-0.5 block text-[10px] font-semibold text-danger">重点复习</small>}</span> : <span className="line-clamp-3 break-words text-[13px] leading-snug sm:text-[13.5px] text-secondary-label">{item.definition}</span>}
    {active && <span className="absolute right-2.5 top-2.5 size-2 rounded-full bg-accent" />}
    {wrong && <XCircle className="absolute right-2.5 top-2.5 size-4 text-danger" />}
  </button>;
}

