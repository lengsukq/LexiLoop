"use client";

import Link from "next/link";
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
      setError(reason instanceof Error ? reason.message : "保存配对结果失败");
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
      setError(reason instanceof Error ? reason.message : "创建配对游戏失败");
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
    return <div className="mx-auto max-w-3xl space-y-5 py-2 sm:py-6">
      <div className="flex items-center justify-between">
        <Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回</Link>
        <Badge tone="purple"><Gamepad2 className="size-3.5" />趣味练习</Badge>
      </div>
      <Card className="overflow-hidden">
        <div className="relative overflow-hidden bg-gradient-to-br from-[#af52de] via-[#5856d6] to-[#007aff] px-5 py-8 text-white sm:px-10 sm:py-11">
          <div className="absolute -right-12 -top-12 size-40 rounded-full bg-white/10 blur-3xl" />
          <div className="relative text-center">
            <span className="mx-auto grid size-16 place-items-center rounded-[20px] bg-white/15 shadow-[inset_0_1px_0_rgba(255,255,255,0.25)] backdrop-blur-xl"><Zap className="size-8" /></span>
            <h1 className="mt-5 text-2xl font-bold tracking-tight sm:text-3xl">限时词汇配对</h1>
            <p className="mx-auto mt-2 max-w-xl text-sm leading-relaxed text-white/75 sm:text-[15px]">将英文和中文释义快速配对。活跃错词、近期忘记和模糊的词会优先出现。</p>
          </div>
        </div>
        <CardContent className="space-y-5 py-5 sm:px-8 sm:py-7">
          <div className="grid gap-3 sm:grid-cols-3">
            {PRESETS.map((item) => {
              const active = presetId === item.id;
              return <button key={item.id} type="button" onClick={() => setPresetId(item.id)} className={`ios-press rounded-[18px] border p-4 text-left transition-all ${active ? "border-[#007aff]/45 bg-[#007aff]/[0.08] shadow-[0_8px_30px_rgba(0,122,255,0.12)]" : "glass-inner border-white/40 hover:border-[#007aff]/25 dark:border-white/[0.08]"}`}>
                <div className="flex items-center justify-between"><b className="text-[15px]">{item.name}</b>{active && <CheckCircle2 className="size-4 text-[#007aff]" />}</div>
                <p className="mt-2 text-xs text-[#8e8e93]">{item.pairs} 组 · {item.seconds} 秒</p>
                <p className="mt-1 text-xs text-[#aeaeb2]">{item.desc}</p>
              </button>;
            })}
          </div>
          <div className="grid grid-cols-3 gap-2 rounded-[16px] bg-black/[0.025] p-3 text-center dark:bg-white/[0.035]">
            <div><p className="text-lg font-bold">{preset.pairs}</p><p className="text-xs text-[#8e8e93]">词汇组数</p></div>
            <div><p className="text-lg font-bold">{preset.seconds}s</p><p className="text-xs text-[#8e8e93]">限时时间</p></div>
            <div><p className="text-lg font-bold text-[#ff3b30]">优先</p><p className="text-xs text-[#8e8e93]">错词加入</p></div>
          </div>
          <GameErrorBanner error={error} />
          <Button size="lg" className="w-full" onClick={() => void startGame()} disabled={phase === "loading"}>
            {phase === "loading" ? <Loader2 className="size-5 animate-spin" /> : <Sparkles className="size-5" />}
            {phase === "loading" ? "正在组题…" : "开始配对"}
          </Button>
        </CardContent>
      </Card>
    </div>;
  }

  if (phase === "result" && result) {
    return <div className="mx-auto max-w-2xl space-y-5 py-6">
      <Card className="overflow-hidden">
        <GameResultHero gradient="bg-gradient-to-br from-[#34c759] via-[#0a84ff] to-[#5856d6]" label="本轮得分" score={result.score} elapsedMs={result.elapsedMs} maxCombo={result.maxCombo} />
        <CardContent className="space-y-5 py-6 sm:px-8">
          <GameResultStats firstTryCorrect={result.firstTryCorrect} recovered={result.recovered} missed={result.missed} firstLabel="一次配对" missedLabel="未完成" />
          <GameResultAccuracy accuracy={result.accuracy} label="首次配对正确率" />
          <GameSummary items={summaryItems} />
          <LeaderboardPanel leaderboard={result.leaderboard} />
          {(result.recovered > 0 || result.missed > 0) && <GameMistakeCallout>错配或超时词条已按“忘记”记录，后续会优先出现在错词强化和下一轮配对中。</GameMistakeCallout>}
          <div className="grid gap-2 sm:grid-cols-2">
            <Button size="lg" onClick={() => { setPhase("setup"); setSession(null); setResult(null); }}><RotateCcw className="size-5" />再来一轮</Button>
            <Link href="/" className={buttonClass("outline", "lg")}><ArrowLeft className="size-5" />返回首页</Link>
          </div>
        </CardContent>
      </Card>
    </div>;
  }

  if (!session) return null;
  const progress = matched.size / Math.max(1, session.pairCount) * 100;

  return <div className="mx-auto max-w-4xl space-y-3 pb-3 sm:space-y-5 sm:py-4">
    <GamePlayHeader remainingMs={remainingMs} combo={combo} exit={<Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />退出</Link>} />
    <div className="space-y-2">
      <div className="flex justify-between text-xs text-[#8e8e93]"><span>已配对 {matched.size}/{session.pairCount}</span><span>错配 {mistakeCount}</span></div>
      <Progress value={progress} />
    </div>

    <Card className="overflow-hidden">
      <CardHeader className="pb-2"><CardTitle>点击英文与对应释义</CardTitle></CardHeader>
      <CardContent className="grid grid-cols-2 gap-2 pb-4 sm:gap-4 sm:px-7 sm:pb-7">
        <div className="space-y-2 sm:space-y-3">
          {words.map((item) => <MatchCard key={item.itemId} side="word" item={item} selected={selected} matched={matched.has(item.itemId)} wrong={wrongFlash.has(`word:${item.itemId}`)} onClick={() => selectCard("word", item)} />)}
        </div>
        <div className="space-y-2 sm:space-y-3">
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
  return <button type="button" disabled={matched} onClick={onClick} className={`ios-press relative flex min-h-[58px] w-full items-center rounded-[15px] border px-3 py-2.5 text-left transition-all duration-200 sm:min-h-[68px] sm:rounded-[18px] sm:px-4 ${matched ? "pointer-events-none scale-95 border-[#34c759]/20 bg-[#34c759]/[0.08] opacity-0" : wrong ? "animate-[shake_0.35s_ease-in-out] border-[#ff3b30] bg-[#ff3b30]/10 text-[#d70015] dark:text-[#ff453a]" : active ? "border-[#007aff] bg-[#007aff]/10 shadow-[0_6px_24px_rgba(0,122,255,0.18)]" : "glass-inner border-white/45 hover:border-[#007aff]/35 dark:border-white/[0.08]"}`}>
    {side === "word" ? <span className="min-w-0"><b className="block break-words text-[15px] sm:text-[17px]">{item.term}</b>{priority && <small className="mt-0.5 block text-[10px] font-semibold text-[#ff3b30]">重点复习</small>}</span> : <span className="line-clamp-3 text-[13px] leading-snug sm:text-[14px]">{item.definition}</span>}
    {active && <span className="absolute right-2 top-2 size-2 rounded-full bg-[#007aff]" />}
    {wrong && <XCircle className="absolute right-2 top-2 size-4 text-[#ff3b30]" />}
  </button>;
}
