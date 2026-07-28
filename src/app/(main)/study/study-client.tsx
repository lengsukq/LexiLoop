"use client";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { AlertCircle, ArrowLeft, CheckCircle2, Clock3, Headphones, Home, Keyboard, Loader2, RotateCcw, Sparkles, Volume2, XCircle } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import type { DictionaryContent, QuestionType, ReviewRating, StudyMode } from "@/lib/types";
import { Badge, Button, Card, CardContent, Progress, buttonClass } from "@/components/ui";

function clientId(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

interface Item {
  itemId: number; position: number; taskType: string; questionType: QuestionType; status: string; skipReason: string | null;
  choices?: string[];
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
  const [selectedChoice, setSelectedChoice] = useState<string | null>(null);
  const [error, setError] = useState("");

  const applySession = useCallback((session: SessionData) => {
    setData(session);
    setIndex(session.resumeIndex);
    setRevealed(false);
    setUserAnswer("");
    setIntervals([]);
    setLastResult(null);
    setSelectedChoice(null);
  }, []);

  const start = useCallback(async (forceNew = false) => {
    setError(""); setData(null); setIndex(0); setRevealed(false); setUserAnswer(""); setLastResult(null); setSelectedChoice(null);
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
      answerIdRef.current = clientId();
    }
  }, [current]);
  const complete = Boolean(data && (data.session.completedAt || data.resumeIndex >= data.items.length));
  const definitions = current ? targetDefinitions(current) : [];
  const exactLocal = current && current.questionType === "EN_TO_ZH_CHOICE"
    ? (selectedChoice ? selectedChoice === definitions[0] : null)
    : current && current.questionType !== "EN_TO_ZH" ? userAnswer.trim().toLocaleLowerCase() === current.word.term.trim().toLocaleLowerCase() : null;

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
        clientAnswerId: answerIdRef.current || clientId(), wordId: current.word.id, studySessionId: sessionId,
        studySessionItemId: current.itemId, rating, questionType: current.questionType,
        userAnswer: current.questionType === "EN_TO_ZH_CHOICE" ? (selectedChoice ?? undefined) : (userAnswer || undefined),
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

  if (!data && !error) return <div className="grid min-h-[75vh] place-items-center"><div className="animate-scale-in text-center"><Loader2 className="mx-auto size-10 animate-spin text-[#007aff]" /><p className="mt-3 text-[15px] text-[#8e8e93]">正在生成 {MODE_LABELS[mode]} 队列…</p></div></div>;
  if (error && !data) return <div className="mx-auto max-w-xl py-20 text-center"><AlertCircle className="mx-auto size-12 text-[#ff3b30]" /><h1 className="mt-4 text-xl font-bold">无法开始学习</h1><p className="mt-2 text-[15px] text-[#6e6e73]">{error}</p><div className="mt-6 flex justify-center gap-3"><Button onClick={() => void start()}><RotateCcw className="size-4" />重试</Button><Link href="/" className={buttonClass("outline")}>返回首页</Link></div></div>;
  if (!data) return null;
  if (complete) return <div className="mx-auto max-w-2xl py-12"><Card><CardContent className="py-16 text-center"><span className="animate-scale-in mx-auto grid size-20 place-items-center rounded-full bg-[#34c759]/12 text-[#34c759]"><CheckCircle2 className="size-10" /></span><h1 className="mt-5 text-2xl font-bold tracking-tight">本轮学习完成</h1><p className="mt-2 text-[15px] text-[#6e6e73]">已处理 {data.session.completedCount} 个任务，正确 {data.session.correctCount} 个，稍后再学 {data.session.skippedCount} 个。</p><div className="mt-7 flex flex-wrap justify-center gap-3"><Button onClick={() => void start(true)}><RotateCcw className="size-4" />生成新一轮</Button><Link href="/" className={buttonClass("outline")}><Home className="size-4" />返回今日</Link></div></CardContent></Card></div>;
  if (!current) return null;

  const progress = data.session.plannedCount ? data.session.completedCount / data.session.plannedCount * 100 : 100;
  const activeMode = MODES.has(data.session.sessionType as StudyMode) ? data.session.sessionType as StudyMode : mode;
  return <div className="animate-fade-up mx-auto max-w-3xl space-y-5">
    <div className="flex flex-wrap items-center justify-between gap-2"><Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />退出</Link><div className="text-center"><div className="flex items-center justify-center gap-2"><p className="text-[15px] font-bold">{MODE_LABELS[activeMode]}</p>{data.resumed && <Badge tone="amber">继续上次</Badge>}</div><p className="text-xs text-[#aeaeb2]">已处理 {data.session.completedCount} / {data.session.plannedCount}</p></div><Badge tone={current.taskType === "WRONG" ? "red" : current.taskType === "NEW" ? "purple" : "blue"}>{current.taskType}</Badge></div>
    <Progress value={progress} />
    <Card className="min-h-[520px]"><CardContent className="flex min-h-[520px] flex-col px-6 py-8 sm:px-10">
      <div className="flex items-center justify-between text-xs text-[#aeaeb2]"><span>{current.word.entryType === "WORD" ? "单词" : "短语"}</span><span>{current.word.sourceLanguage} → {current.word.targetLanguage}</span></div>
      <div className="flex flex-1 flex-col items-center justify-center text-center">
        {current.questionType === "EN_TO_ZH_CHOICE" ? <><p className="text-[13px] text-[#8e8e93]">选择正确的释义</p><h1 className="mt-4 break-words text-4xl font-bold tracking-tight sm:text-5xl lg:text-6xl">{current.word.term}</h1><Pronunciation item={current} /><div className="mt-8 grid w-full max-w-xl gap-3">{(current.choices ?? []).map((choice) => { const isCorrect = choice === definitions[0]; const isSelected = choice === selectedChoice; const showState = revealed && (isCorrect || isSelected); return <button key={choice} type="button" disabled={revealed} onClick={() => { setSelectedChoice(choice); setRevealed(true); setLastResult(null); void apiFetch<Interval[]>("/api/reviews/preview", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ wordId: current.word.id }) }).then(setIntervals).catch(() => setIntervals([])); }} className={`ios-press glass-inner rounded-[16px] border-[1.5px] px-5 py-4 text-left text-[15px] font-medium transition-all duration-200 disabled:opacity-90 ${showState ? (isCorrect ? "border-[#34c759] bg-[#34c759]/[0.08] text-[#248a3d] shadow-[0_8px_24px_rgba(52,199,89,0.12)] dark:text-[#30d158]" : "border-[#ff3b30] bg-[#ff3b30]/[0.08] text-[#d70015] shadow-[0_8px_24px_rgba(255,59,48,0.12)] dark:text-[#ff453a]") : "border-white/50 hover:border-[#007aff]/40 hover:shadow-[0_8px_32px_rgba(0,122,255,0.10)] dark:border-white/[0.08]"}`}>{choice}</button>; })}</div></> : current.questionType === "EN_TO_ZH" ? <><p className="text-[13px] text-[#8e8e93]">回忆它的含义</p><h1 className="mt-4 break-words text-4xl font-bold tracking-tight sm:text-5xl lg:text-6xl">{current.word.term}</h1><Pronunciation item={current} /></> : current.questionType === "ZH_TO_EN_SPELLING" ? <><span className="grid size-14 place-items-center rounded-[16px] bg-[#ff9500]/12 text-[#ff9500]"><Keyboard className="size-7" /></span><p className="mt-5 text-[13px] text-[#8e8e93]">根据释义拼写英文</p><h1 className="mt-3 max-w-xl text-2xl font-bold leading-relaxed">{definitions[0] ?? "暂无释义"}</h1>{!revealed && getHintPattern(current.word.term) && <p className="mt-4 font-mono text-3xl tracking-[0.3em] text-[#007aff]">{getHintPattern(current.word.term)}</p>}<input autoFocus className="mt-6 h-14 w-full max-w-md glass-inner rounded-[16px] border-[1.5px] border-white/50 px-5 text-center text-2xl outline-none transition-all focus:border-[#007aff]/50 focus:shadow-[0_8px_32px_rgba(0,122,255,0.12),0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) void reveal(); }} disabled={revealed} placeholder="输入英文词条" /></> : <><button type="button" onClick={() => playWord(current)} className="ios-press grid size-24 place-items-center rounded-full bg-[#5ac8fa]/12 text-[#007aff]"><Headphones className="size-11" /></button><p className="mt-5 text-[13px] text-[#8e8e93]">点击播放，根据发音拼写</p><input autoFocus className="mt-6 h-14 w-full max-w-md glass-inner rounded-[16px] border-[1.5px] border-white/50 px-5 text-center text-2xl outline-none transition-all focus:border-[#007aff]/50 focus:shadow-[0_8px_32px_rgba(0,122,255,0.12),0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) void reveal(); }} disabled={revealed} placeholder="输入听到的词条" /></>}

        {revealed && <div className="animate-fade-up glass-inner mt-8 w-full max-w-xl rounded-[18px] p-5 text-left"><div className="flex items-start gap-3">{exactLocal === false ? <XCircle className="mt-0.5 size-5 shrink-0 text-[#ff3b30]" /> : <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-[#34c759]" />}<div><p className="font-bold">{current.word.term}</p>{definitions.map((definition) => <p key={definition} className="mt-1 text-[15px] text-[#6e6e73] dark:text-[#98989d]">{definition}</p>)}{current.word.content.examples[0] && <p className="mt-3 border-t border-black/[0.06] pt-3 text-[15px] italic text-[#8e8e93] dark:border-white/[0.06]">{current.word.content.examples[0].sentence}</p>}{current.word.content.learning.mnemonic && <div className="mt-3 flex items-start gap-2 rounded-[14px] bg-[#ff9500]/[0.08] p-3"><Sparkles className="mt-0.5 size-4 shrink-0 text-[#ff9500]" /><p className="text-[14px] leading-relaxed text-[#c93400] dark:text-[#ff9f0a]">{current.word.content.learning.mnemonic}</p></div>}</div></div></div>}
        {lastResult && <div className={`mt-4 flex items-center gap-2 text-[15px] font-semibold ${lastResult.isCorrect ? "text-[#34c759]" : "text-[#ff3b30]"}`}>{lastResult.isCorrect ? <CheckCircle2 className="size-4" /> : <XCircle className="size-4" />}{lastResult.isCorrect ? "已记录" : "已加入错词强化"}</div>}
        {error && <div className="mt-4 rounded-[14px] bg-[#ff3b30]/[0.08] p-3 text-[14px] text-[#d70015] dark:text-[#ff453a]">{error}</div>}
      </div>
      {!revealed ? (current.questionType === "EN_TO_ZH_CHOICE" ? <div className="flex flex-col gap-2 sm:grid sm:grid-cols-[auto_1fr]"><Button variant="outline" size="lg" onClick={() => void skip()} disabled={submitting}><Clock3 className="size-5" />稍后再学</Button><div className="self-center text-center text-[13px] text-[#aeaeb2]">点击上方选项作答</div></div> : current.questionType !== "EN_TO_ZH" ? <div className="flex flex-col gap-2 sm:grid sm:grid-cols-[auto_auto_1fr]"><Button variant="outline" size="lg" onClick={() => void skip()} disabled={submitting} className="w-full sm:w-auto"><Clock3 className="size-5" />稍后再学</Button><Button variant="outline" size="lg" onClick={() => void reveal()} disabled={submitting} className="w-full border-[#ff3b30]/20 text-[#ff3b30] hover:bg-[#ff3b30]/[0.06] sm:w-auto"><XCircle className="size-5" />忘记</Button><Button size="lg" className="w-full" onClick={() => void reveal()} disabled={submitting || !userAnswer.trim()}><Sparkles className="size-5" />检查答案</Button></div> : <div className="flex flex-col gap-2 sm:grid sm:grid-cols-[auto_1fr]"><Button variant="outline" size="lg" onClick={() => void skip()} disabled={submitting}><Clock3 className="size-5" />稍后再学</Button><Button size="lg" className="w-full" onClick={() => void reveal()} disabled={submitting}><Sparkles className="size-5" />显示答案</Button></div>) : <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">{(["AGAIN", "HARD", "GOOD", "EASY"] as ReviewRating[]).map((rating) => { const interval = intervals.find((item) => item.rating === rating); const labels = { AGAIN: "忘记", HARD: "模糊", GOOD: "认识", EASY: "很熟" } as const; const styles = { AGAIN: "glass-inner border-[#ff3b30]/25 text-[#d70015] shadow-[0_6px_24px_rgba(255,59,48,0.10)] dark:text-[#ff453a]", HARD: "glass-inner border-[#ff9500]/25 text-[#c93400] shadow-[0_6px_24px_rgba(255,149,0,0.10)] dark:text-[#ff9f0a]", GOOD: "glass-inner border-[#007aff]/25 text-[#0040dd] shadow-[0_6px_24px_rgba(0,122,255,0.10)] dark:text-[#0a84ff]", EASY: "glass-inner border-[#34c759]/25 text-[#248a3d] shadow-[0_6px_24px_rgba(52,199,89,0.10)] dark:text-[#30d158]" } as const; return <button key={rating} disabled={submitting} onClick={() => void rate(rating)} className={`ios-press rounded-[16px] border-[1.5px] p-3.5 text-center transition-all duration-200 disabled:opacity-40 ${styles[rating]}`}><b className="block text-[15px]">{labels[rating]}</b><span className="mt-1 block text-[11px] opacity-60">{interval ? formatInterval(interval.scheduledDays) : "—"}</span></button>; })}</div>}
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
    <div className="flex flex-wrap items-center justify-center gap-2">
      <div className="flex overflow-hidden rounded-full border border-black/[0.08] bg-black/[0.03] dark:border-white/[0.08] dark:bg-white/[0.04]">
        {(["US", "UK", "GENERAL"] as const).map((accent) => <button key={accent} type="button" onClick={() => setSelectedAccent(accent)}
          className={`px-3 py-1 text-xs font-semibold transition-all duration-200 ${selectedAccent === accent ? "bg-[#007aff] text-white shadow-[0_2px_8px_rgba(0,122,255,0.3)]" : "text-[#6e6e73] hover:text-[#007aff] dark:text-[#98989d] dark:hover:text-[#0a84ff]"}`}>
          {accentLabel[accent] ?? accent}
        </button>)}
      </div>
      <button type="button" onClick={play} className="ios-press inline-flex items-center gap-2 rounded-full bg-[#007aff]/[0.08] px-4 py-2 text-sm font-medium text-[#007aff] transition-all hover:bg-[#007aff]/[0.12] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]">
        <Volume2 className="size-4" />{current?.phonetic || "播放发音"}
      </button>
    </div>
    {ttsTip && <p className="mt-2 text-xs text-[#ff9500] dark:text-[#ff9f0a]">{ttsTip}</p>}
  </div>;
}
function formatInterval(days: number) { if (days < 1) return "今天"; if (days === 1) return "1 天"; if (days < 30) return `${Math.round(days)} 天`; if (days < 365) return `${Math.round(days / 30)} 月`; return `${(days / 365).toFixed(1)} 年`; }
