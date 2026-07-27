"use client";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { AlertCircle, ArrowLeft, CheckCircle2, Clock3, Headphones, Home, Keyboard, Loader2, RotateCcw, Sparkles, Volume2, XCircle } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import type { DictionaryContent, QuestionType, ReviewRating, StudyMode } from "@/lib/types";
import { Badge, Button, Card, CardContent, Progress, buttonClass } from "@/components/ui";

interface Item {
  itemId: number; position: number; taskType: string; questionType: QuestionType; status: string; skipReason: string | null;
  word: { id: number; term: string; sourceLanguage: string; targetLanguage: string; entryType: string; content: DictionaryContent };
}
interface SessionData {
  resumed: boolean;
  resumeIndex: number;
  session: { id: number; sessionType: string; startedAt: string; completedAt: string | null; plannedCount: number; completedCount: number; correctCount: number; wrongCount: number; skippedCount: number; durationMs: number | null };
  items: Item[];
}
interface AnswerResult { isCorrect: boolean; rating: ReviewRating; expectedAnswer: string; nextDueAt: string | null; scheduledDays: number; masteryScore: number; masteryLevel: string; wrongWordActive: boolean; }
interface Interval { rating: ReviewRating; nextDueAt: string; scheduledDays: number; }

const MODES = new Set<StudyMode>(["DAILY", "NEW_WORDS", "DUE_REVIEW", "WRONG_WORDS", "LISTENING", "SPELLING"]);
const MODE_LABELS: Record<StudyMode, string> = { DAILY: "今日学习", NEW_WORDS: "新词学习", DUE_REVIEW: "到期复习", WRONG_WORDS: "错词强化", LISTENING: "听力拼写", SPELLING: "中文拼写" };

function targetDefinitions(item: Item): string[] {
  const target = item.word.content.definitions.filter((definition) => definition.language === item.word.targetLanguage);
  return (target.length ? target : item.word.content.definitions).map((definition) => definition.text);
}
async function playEdgeTts(term: string, accent: string) {
  try {
    const response = await fetch(`/api/tts?word=${encodeURIComponent(term)}&accent=${encodeURIComponent(accent)}`);
    if (response.ok) {
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url); audio.playbackRate = 1; void audio.play();
    }
  } catch { /* ignore */ }
}
async function playWord(item: Item) {
  await playEdgeTts(item.word.term, "US");
}
function getHintPattern(term: string): string | null {
  if (term.length <= 2) return null;
  const firstLetter = term[0];
  const lastLetter = term[term.length - 1];
  const middleBlanks = term.slice(1, -1).split("").map(() => "_").join(" ");
  return `${firstLetter} ${middleBlanks} ${lastLetter}`;
}

export function StudyClient() {
  const params = useSearchParams();
  const rawMode = params.get("mode") as StudyMode | null;
  const mode: StudyMode = rawMode && MODES.has(rawMode) ? rawMode : "DAILY";
  const started = useRef(false);
  const itemStartedAt = useRef(0);
  const answerIdRef = useRef("");
  const [data, setData] = useState<SessionData | null>(null);
  const [index, setIndex] = useState(0);
  const [revealed, setRevealed] = useState(false);
  const [userAnswer, setUserAnswer] = useState("");
  const [intervals, setIntervals] = useState<Interval[]>([]);
  const [lastResult, setLastResult] = useState<AnswerResult | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  const applySession = useCallback((session: SessionData) => {
    setData(session);
    setIndex(session.resumeIndex);
    setRevealed(false);
    setUserAnswer("");
    setIntervals([]);
    setLastResult(null);
  }, []);

  const start = useCallback(async (forceNew = false) => {
    setError(""); setData(null); setIndex(0); setRevealed(false); setUserAnswer(""); setLastResult(null);
    try {
      const session = await apiFetch<SessionData>("/api/study/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode, resume: !forceNew }),
      });
      applySession(session);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "创建会话失败"); }
  }, [applySession, mode]);
  useEffect(() => { if (!started.current) { started.current = true; void start(); } }, [start]);

  const current = data?.items[index] ?? null;
  useEffect(() => {
    if (current) {
      itemStartedAt.current = Date.now();
      answerIdRef.current = crypto.randomUUID();
    }
  }, [current]);
  const complete = Boolean(data && (data.session.completedAt || data.resumeIndex >= data.items.length));
  const definitions = current ? targetDefinitions(current) : [];
  const exactLocal = current && current.questionType !== "EN_TO_ZH" ? userAnswer.trim().toLocaleLowerCase() === current.word.term.trim().toLocaleLowerCase() : null;

  async function reloadSession(sessionId: number) {
    applySession(await apiFetch<SessionData>(`/api/study/sessions/${sessionId}`));
  }
  async function reveal() {
    if (!current) return;
    setRevealed(true); setLastResult(null);
    try { setIntervals(await apiFetch<Interval[]>("/api/reviews/preview", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ wordId: current.word.id }) })); }
    catch { setIntervals([]); }
  }
  async function rate(rating: ReviewRating) {
    if (!current || !data) return;
    const sessionId = data.session.id;
    setSubmitting(true); setError("");
    try {
      const result = await apiFetch<AnswerResult>("/api/study/answer", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({
        clientAnswerId: answerIdRef.current || crypto.randomUUID(), wordId: current.word.id, studySessionId: sessionId,
        studySessionItemId: current.itemId, rating, questionType: current.questionType,
        userAnswer: userAnswer || undefined,
        durationMs: Math.max(0, Date.now() - itemStartedAt.current),
      }) });
      setLastResult(result);
      await new Promise((resolve) => window.setTimeout(resolve, 650));
      await reloadSession(sessionId);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "提交答案失败"); }
    finally { setSubmitting(false); }
  }
  async function skip() {
    if (!current || !data) return;
    setSubmitting(true); setError("");
    try {
      const session = await apiFetch<SessionData>("/api/study/skip", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ studySessionId: data.session.id, studySessionItemId: current.itemId, reason: "LATER" }),
      });
      applySession(session);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "跳过失败"); }
    finally { setSubmitting(false); }
  }

  if (!data && !error) return <div className="grid min-h-[75vh] place-items-center"><div className="text-center"><Loader2 className="mx-auto size-10 animate-spin text-indigo-500" /><p className="mt-3 text-sm text-slate-500">正在生成 {MODE_LABELS[mode]} 队列…</p></div></div>;
  if (error && !data) return <div className="mx-auto max-w-xl py-20 text-center"><AlertCircle className="mx-auto size-12 text-rose-500" /><h1 className="mt-4 text-xl font-bold">无法开始学习</h1><p className="mt-2 text-sm text-slate-500">{error}</p><div className="mt-6 flex justify-center gap-3"><Button onClick={() => void start()}><RotateCcw className="size-4" />重试</Button><Link href="/" className={buttonClass("outline")}>返回首页</Link></div></div>;
  if (!data) return null;
  if (complete) return <div className="mx-auto max-w-2xl py-12"><Card><CardContent className="py-16 text-center"><span className="mx-auto grid size-20 place-items-center rounded-full bg-emerald-100 text-emerald-600 dark:bg-emerald-950"><CheckCircle2 className="size-10" /></span><h1 className="mt-5 text-2xl font-bold">本轮学习完成</h1><p className="mt-2 text-sm text-slate-500">已处理 {data.session.completedCount} 个任务，正确 {data.session.correctCount} 个，稍后再学 {data.session.skippedCount} 个。</p><div className="mt-7 flex flex-wrap justify-center gap-3"><Button onClick={() => void start(true)}><RotateCcw className="size-4" />生成新一轮</Button><Link href="/" className={buttonClass("outline")}><Home className="size-4" />返回今日</Link></div></CardContent></Card></div>;
  if (!current) return null;

  const progress = data.session.plannedCount ? data.session.completedCount / data.session.plannedCount * 100 : 100;
  const activeMode = MODES.has(data.session.sessionType as StudyMode) ? data.session.sessionType as StudyMode : mode;
  return <div className="mx-auto max-w-3xl space-y-5">
    <div className="flex items-center justify-between"><Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />退出</Link><div className="text-center"><div className="flex items-center justify-center gap-2"><p className="text-sm font-semibold">{MODE_LABELS[activeMode]}</p>{data.resumed && <Badge tone="amber">继续上次</Badge>}</div><p className="text-xs text-slate-400">已处理 {data.session.completedCount} / {data.session.plannedCount}</p></div><Badge tone={current.taskType === "WRONG" ? "red" : current.taskType === "NEW" ? "purple" : "blue"}>{current.taskType}</Badge></div>
    <Progress value={progress} />
    <Card className="min-h-[520px] overflow-hidden"><CardContent className="flex min-h-[520px] flex-col px-6 py-8 sm:px-10">
      <div className="flex items-center justify-between text-xs text-slate-400"><span>{current.word.entryType === "WORD" ? "单词" : "短语"}</span><span>{current.word.sourceLanguage} → {current.word.targetLanguage}</span></div>
      <div className="flex flex-1 flex-col items-center justify-center text-center">
        {current.questionType === "EN_TO_ZH" ? <><p className="text-sm text-slate-400">回忆它的含义</p><h1 className="mt-4 text-5xl font-bold tracking-tight sm:text-6xl">{current.word.term}</h1><Pronunciation item={current} /></> : current.questionType === "ZH_TO_EN_SPELLING" ? <><span className="grid size-14 place-items-center rounded-2xl bg-amber-100 text-amber-600 dark:bg-amber-950"><Keyboard className="size-7" /></span><p className="mt-5 text-sm text-slate-400">根据释义拼写英文</p><h1 className="mt-3 max-w-xl text-2xl font-bold leading-relaxed">{definitions[0] ?? "暂无释义"}</h1>{!revealed && getHintPattern(current.word.term) && <p className="mt-4 font-mono text-3xl tracking-[0.3em] text-indigo-500">{getHintPattern(current.word.term)}</p>}<input autoFocus className="mt-6 h-14 w-full max-w-md rounded-2xl border-2 border-slate-200 bg-transparent px-5 text-center text-2xl outline-none focus:border-indigo-500 dark:border-slate-700" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) void reveal(); }} disabled={revealed} placeholder="输入英文词条" /></> : <><button type="button" onClick={() => playWord(current)} className="grid size-24 place-items-center rounded-full bg-sky-100 text-sky-600 transition hover:scale-105 dark:bg-sky-950"><Headphones className="size-11" /></button><p className="mt-5 text-sm text-slate-400">点击播放，根据发音拼写</p><input autoFocus className="mt-6 h-14 w-full max-w-md rounded-2xl border-2 border-slate-200 bg-transparent px-5 text-center text-2xl outline-none focus:border-indigo-500 dark:border-slate-700" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) void reveal(); }} disabled={revealed} placeholder="输入听到的词条" /></>}

        {revealed && <div className="mt-8 w-full max-w-xl rounded-2xl bg-slate-50 p-5 text-left dark:bg-slate-800/60"><div className="flex items-start gap-3">{exactLocal === false ? <XCircle className="mt-0.5 size-5 shrink-0 text-rose-500" /> : <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-emerald-500" />}<div><p className="font-semibold">{current.word.term}</p>{definitions.map((definition) => <p key={definition} className="mt-1 text-sm text-slate-600 dark:text-slate-300">{definition}</p>)}{current.word.content.examples[0] && <p className="mt-3 border-t border-slate-200 pt-3 text-sm italic text-slate-500 dark:border-slate-700">{current.word.content.examples[0].sentence}</p>}</div></div></div>}
        {lastResult && <div className={`mt-4 flex items-center gap-2 text-sm font-medium ${lastResult.isCorrect ? "text-emerald-600" : "text-rose-600"}`}>{lastResult.isCorrect ? <CheckCircle2 className="size-4" /> : <XCircle className="size-4" />}{lastResult.isCorrect ? "已记录" : "已加入错词强化"}</div>}
        {error && <div className="mt-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-700 dark:bg-rose-950/30 dark:text-rose-300">{error}</div>}
      </div>
      {!revealed ? (current.questionType !== "EN_TO_ZH" ? <div className="grid grid-cols-[auto_auto_1fr] gap-2"><Button variant="outline" size="lg" onClick={() => void skip()} disabled={submitting}><Clock3 className="size-5" />稍后再学</Button><Button variant="outline" size="lg" onClick={() => void reveal()} disabled={submitting} className="border-rose-200 text-rose-600 hover:bg-rose-50 hover:border-rose-400 dark:border-rose-800 dark:text-rose-400 dark:hover:bg-rose-950"><XCircle className="size-5" />忘记</Button><Button size="lg" className="w-full" onClick={() => void reveal()} disabled={submitting || !userAnswer.trim()}><Sparkles className="size-5" />检查答案</Button></div> : <div className="grid grid-cols-[auto_1fr] gap-2"><Button variant="outline" size="lg" onClick={() => void skip()} disabled={submitting}><Clock3 className="size-5" />稍后再学</Button><Button size="lg" className="w-full" onClick={() => void reveal()} disabled={submitting}><Sparkles className="size-5" />显示答案</Button></div>) : <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">{(["AGAIN", "HARD", "GOOD", "EASY"] as ReviewRating[]).map((rating) => { const interval = intervals.find((item) => item.rating === rating); const labels = { AGAIN: "忘记", HARD: "模糊", GOOD: "认识", EASY: "很熟" } as const; return <button key={rating} disabled={submitting} onClick={() => void rate(rating)} className={`rounded-2xl border p-3 text-center transition hover:-translate-y-0.5 disabled:opacity-50 ${rating === "AGAIN" ? "border-rose-200 bg-rose-50 text-rose-700 dark:border-rose-900 dark:bg-rose-950/30" : rating === "HARD" ? "border-amber-200 bg-amber-50 text-amber-700 dark:border-amber-900 dark:bg-amber-950/30" : rating === "GOOD" ? "border-sky-200 bg-sky-50 text-sky-700 dark:border-sky-900 dark:bg-sky-950/30" : "border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-900 dark:bg-emerald-950/30"}`}><b className="block text-sm">{labels[rating]}</b><span className="mt-1 block text-[11px] opacity-70">{interval ? formatInterval(interval.scheduledDays) : "—"}</span></button>; })}</div>}
    </CardContent></Card>
  </div>;
}
function Pronunciation({ item }: { item: Item }) {
  const [selectedAccent, setSelectedAccent] = useState<"US" | "UK" | "GENERAL">("US");
  const [ttsTip, setTtsTip] = useState("");
  const current = item.word.content.pronunciations.find((p) => p.accent === selectedAccent);
  async function play() {
    setTtsTip("");
    try {
      const response = await fetch(`/api/tts?word=${encodeURIComponent(item.word.term)}&accent=${encodeURIComponent(selectedAccent)}`);
      if (response.ok) {
        const blob = await response.blob();
        const url = URL.createObjectURL(blob);
        const audio = new Audio(url); audio.playbackRate = 1; await audio.play();
      } else {
        setTtsTip("Edge TTS 发音失败，请检查网络。");
      }
    } catch {
      setTtsTip("Edge TTS 发音失败，请检查网络。");
    }
  }
  const accentLabel: Record<string, string> = { US: "美", UK: "英", GENERAL: "通用" };
  return <div className="mt-5">
    <div className="flex flex-wrap items-center gap-2">
      <div className="flex overflow-hidden rounded-lg border border-sky-200 dark:border-sky-800">
        {(["US", "UK", "GENERAL"] as const).map((accent) => <button key={accent} type="button" onClick={() => setSelectedAccent(accent)}
          className={`px-2 py-0.5 text-xs font-medium transition ${selectedAccent === accent ? "bg-sky-500 text-white" : "bg-sky-50 text-sky-600 hover:bg-sky-100 dark:bg-sky-950/50 dark:text-sky-300"}`}>
          {accentLabel[accent] ?? accent}
        </button>)}
      </div>
      <button type="button" onClick={play} className="inline-flex items-center gap-2 rounded-full bg-sky-50 px-4 py-2 text-sm text-sky-700 transition hover:bg-sky-100 dark:bg-sky-950/50 dark:text-sky-300">
        <Volume2 className="size-4" />{current?.phonetic || "播放发音"}
      </button>
    </div>
    {ttsTip && <p className="mt-2 text-xs text-amber-600 dark:text-amber-400">{ttsTip}</p>}
  </div>;
}
function formatInterval(days: number) { if (days < 1) return "今天"; if (days === 1) return "1 天"; if (days < 30) return `${Math.round(days)} 天`; if (days < 365) return `${Math.round(days / 30)} 月`; return `${(days / 365).toFixed(1)} 年`; }
