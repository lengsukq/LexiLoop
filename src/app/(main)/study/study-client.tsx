"use client";
import Link from "next/link";
import { errorMessage } from "@/lib/format";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { AlertCircle, ArrowLeft, CheckCircle2, ChevronDown, Clock3, Headphones, Home, Keyboard, Loader2, MessageSquareText, RotateCcw, Sparkles, Volume2, XCircle } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { playCachedTts, playEntryTts, preloadTtsBatch } from "@/lib/tts-client";
import { useActiveStopwatch } from "@/lib/use-active-stopwatch";
import type { DictionaryContent, QuestionType, ReviewRating, StudyMode } from "@/lib/types";
import { entryTypeLabel } from "@/lib/entry-type-label";
import { Badge, Button, Card, CardContent, Kbd, Progress, buttonClass } from "@/components/ui";

function clientId(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
  });
}

interface Item {
  itemId: number; position: number; taskType: string; questionType: QuestionType; status: string; skipReason: string | null;
  choices?: string[];
  choiceDefinitions?: Record<string, string>;
  word: { id: number; term: string; sourceLanguage: string; targetLanguage: string; entryType: string; content: DictionaryContent };
}
interface SessionData {
  resumed: boolean;
  resumeIndex: number;
  session: { id: number; sessionType: string; startedAt: string; completedAt: string | null; plannedCount: number; completedCount: number; correctCount: number; wrongCount: number; skippedCount: number; durationMs: number | null };
  items: Item[];
}
interface AnswerResult { isCorrect: boolean; rating: ReviewRating; expectedAnswer: string; nextDueAt: string | null; scheduledDays: number; masteryScore: number; masteryLevel: string; wrongWordActive: boolean; adaptiveFollowUp?: { questionType: QuestionType; position: number; repetition: number } | null; }
interface Interval { rating: ReviewRating; nextDueAt: string; scheduledDays: number; }

const MODES = new Set<StudyMode>(["DAILY", "NEW_WORDS", "DUE_REVIEW", "WRONG_WORDS", "LISTENING", "SPELLING", "SENTENCE_REVIEW", "AI_RECOMMENDED"]);
const MODE_LABELS: Record<StudyMode, string> = { DAILY: "今日学习", NEW_WORDS: "新词学习", DUE_REVIEW: "到期复习", WRONG_WORDS: "错词强化", LISTENING: "听力拼写", SPELLING: "中文拼写", SENTENCE_REVIEW: "句子复习", AI_RECOMMENDED: "AI 今日必做题" };

function targetDefinitions(item: Item): string[] {
  const target = item.word.content.definitions.filter((definition) => definition.language === item.word.targetLanguage);
  const definitions = (target.length ? target : item.word.content.definitions)
    .map((definition) => definition.text.trim())
    .filter(Boolean);
  if (definitions.length) return definitions;
  const translation = item.word.content.summary.translation?.trim();
  return translation ? [translation] : [];
}
async function playWord(item: Item): Promise<boolean> {
  return playEntryTts(item.word.term, item.word.entryType);
}
function getHintPattern(term: string): string | null {
  if (term.length <= 2 || /\s/.test(term)) return null;
  const firstLetter = term[0];
  const lastLetter = term[term.length - 1];
  // Long words use a compact (non-spaced) blank run so the hint fits the card width.
  const middleBlanks = term.length > 12
    ? "_".repeat(term.length - 2)
    : term.slice(1, -1).split("").map(() => "_").join(" ");
  return `${firstLetter} ${middleBlanks} ${lastLetter}`;
}
function normalizeSentenceAnswer(value: string): string {
  return value.normalize("NFKC").toLocaleLowerCase().replace(/[’‘]/g, "'").replace(/[\p{P}\p{S}]+/gu, " ").replace(/\s+/g, " ").trim();
}
function normalizeChoiceAnswer(value: string): string {
  return value.normalize("NFKC").toLocaleLowerCase().replace(/\s+/g, " ").trim();
}
function choiceOptionsDelayLabel(seconds: number): string {
  return seconds === 0 ? "正在显示选项…" : `${seconds} 秒后显示选项`;
}

const studyActionClass = "!h-12 !min-h-12 !px-3 !text-[14px] sm:!h-[54px] sm:!px-8 sm:!text-[17px]";

export function StudyClient() {
  const params = useSearchParams();
  const rawMode = params.get("mode") as StudyMode | null;
  const mode: StudyMode = rawMode && MODES.has(rawMode) ? rawMode : "DAILY";
  const started = useRef(false);
  const answerIdRef = useRef("");
  const questionDurationRef = useRef<number | null>(null);
  const autoPlayedRef = useRef("");
  const answerInputRef = useRef<HTMLInputElement>(null);
  const sentenceAnswerRef = useRef<HTMLTextAreaElement>(null);
  const [data, setData] = useState<SessionData | null>(null);
  const [index, setIndex] = useState(0);
  const [revealed, setRevealed] = useState(false);
  const [userAnswer, setUserAnswer] = useState("");
  const [intervals, setIntervals] = useState<Interval[]>([]);
  const [lastResult, setLastResult] = useState<AnswerResult | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [selectedChoice, setSelectedChoice] = useState<string | null>(null);
  const [choicesVisible, setChoicesVisible] = useState(false);
  const [error, setError] = useState("");
  const [choiceRevealDelaySeconds, setChoiceRevealDelaySeconds] = useState(2);
  const choiceRevealTimerRef = useRef<number | null>(null);
  const [autoContinue, setAutoContinue] = useState(mode === "DAILY");
  const autoContinueRef = useRef(mode === "DAILY");
  const [autoStopReason, setAutoStopReason] = useState<"USER" | "EXHAUSTED" | null>(null);

  useEffect(() => {
    let cancelled = false;
    void apiFetch<{ choiceRevealDelaySeconds?: number }>("/api/settings")
      .then((settings) => {
        if (!cancelled && typeof settings.choiceRevealDelaySeconds === "number") {
          setChoiceRevealDelaySeconds(Math.max(0, settings.choiceRevealDelaySeconds));
        }
      })
      .catch(() => {
        // Keep the two-second default if settings are temporarily unavailable.
      });
    return () => { cancelled = true; };
  }, []);

  const dismissKeyboard = useCallback(() => {
    answerInputRef.current?.blur();
    sentenceAnswerRef.current?.blur();
    const active = document.activeElement;
    if (active instanceof HTMLElement) active.blur();
  }, []);

  const applySession = useCallback((session: SessionData) => {
    dismissKeyboard();
    setData(session);
    setIndex(session.resumeIndex);
    setRevealed(false);
    setUserAnswer("");
    setIntervals([]);
    setLastResult(null);
    setSelectedChoice(null);
    setChoicesVisible(false);
  }, [dismissKeyboard]);

  const start = useCallback(async (forceNew = false) => {
    setError(""); setData(null); setIndex(0); setRevealed(false); setUserAnswer(""); setLastResult(null); setSelectedChoice(null); setChoicesVisible(false);
    try {
      const session = await apiFetch<SessionData>("/api/study/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode, resume: !forceNew, continuous: mode === "DAILY" && autoContinueRef.current }),
      });
      if (mode === "DAILY" && autoContinueRef.current && session.items.length === 0) {
        autoContinueRef.current = false;
        setAutoContinue(false);
        setAutoStopReason("EXHAUSTED");
      }
      applySession(session);
    } catch (reason) { setError(errorMessage(reason, "创建会话失败")); }
  }, [applySession, mode]);
  useEffect(() => { if (!started.current) { started.current = true; void start(); } }, [start]);

  const current = data?.items[index] ?? null;
  const { reset: resetQuestionTimer, capture: captureActiveQuestionDuration } = useActiveStopwatch(Boolean(current && !revealed && !submitting));
  useEffect(() => {
    if (!data) return;
    void preloadTtsBatch(data.items.slice(index, index + 5).map((item) => ({ text: item.word.term, accent: "US" })));
  }, [data, index]);

  const captureQuestionDuration = useCallback(() => {
    if (questionDurationRef.current === null) questionDurationRef.current = captureActiveQuestionDuration();
    return questionDurationRef.current;
  }, [captureActiveQuestionDuration]);

  useEffect(() => {
    if (current) {
      questionDurationRef.current = null;
      resetQuestionTimer();
      answerIdRef.current = clientId();
      const isChoiceQuestion = current.questionType === "EN_TO_ZH_CHOICE" || current.questionType === "ZH_TO_EN_CHOICE";
      const delayMs = Math.max(0, choiceRevealDelaySeconds) * 1000;
      choiceRevealTimerRef.current = window.setTimeout(() => {
        choiceRevealTimerRef.current = null;
        setChoicesVisible(true);
      }, isChoiceQuestion ? delayMs : 0);
    }
    return () => {
      if (choiceRevealTimerRef.current !== null) {
        window.clearTimeout(choiceRevealTimerRef.current);
        choiceRevealTimerRef.current = null;
      }
    };
  }, [choiceRevealDelaySeconds, current, resetQuestionTimer]);
  useEffect(() => {
    if (!current) return;
    if (current.word.entryType === "SENTENCE" && current.questionType === "ZH_TO_EN_SPELLING") return;
    if (current.questionType === "ZH_TO_EN_CHOICE") return;

    const playbackKey = `${data?.session.id ?? 0}:${current.itemId}`;
    if (autoPlayedRef.current === playbackKey) return;
    autoPlayedRef.current = playbackKey;

    const timer = window.setTimeout(() => {
      void playWord(current);
    }, 220);
    return () => window.clearTimeout(timer);
  }, [current, data?.session.id]);
  const complete = Boolean(data && (data.session.completedAt || data.resumeIndex >= data.items.length));
  const autoContinuationPending = Boolean(data && autoContinue && complete && data.items.length > 0);
  useEffect(() => {
    if (!autoContinuationPending) return;
    const timer = window.setTimeout(() => void start(true), 500);
    return () => window.clearTimeout(timer);
  }, [autoContinuationPending, start]);

  function stopAutoContinue() {
    autoContinueRef.current = false;
    setAutoContinue(false);
    setAutoStopReason("USER");
  }

  function resumeAutoContinue() {
    autoContinueRef.current = true;
    setAutoContinue(true);
    setAutoStopReason(null);
    void start(true);
  }

  const definitions = current ? targetDefinitions(current) : [];
  const definitionText = definitions.join("；");
  // A question without choices (legacy session items whose word has no
  // definition) cannot be answered; only "稍后再学" makes sense.
  const hasChoices = Boolean(current?.choices?.length);
  const exactLocal = current && current.questionType === "EN_TO_ZH_CHOICE"
    ? (selectedChoice ? selectedChoice === definitionText : null)
    : current && current.questionType === "ZH_TO_EN_CHOICE"
      ? (selectedChoice ? normalizeChoiceAnswer(selectedChoice) === normalizeChoiceAnswer(current.word.term) : null)
    : current && current.questionType !== "EN_TO_ZH"
      ? current.word.entryType === "SENTENCE"
        ? normalizeSentenceAnswer(userAnswer) === normalizeSentenceAnswer(current.word.term)
        : userAnswer.trim().toLocaleLowerCase() === current.word.term.trim().toLocaleLowerCase()
      : null;

  async function reloadSession(sessionId: number) {
    applySession(await apiFetch<SessionData>(`/api/study/sessions/${sessionId}`));
  }
  async function reveal() {
    if (!current) return;
    if (choiceRevealTimerRef.current !== null) {
      window.clearTimeout(choiceRevealTimerRef.current);
      choiceRevealTimerRef.current = null;
    }
    captureQuestionDuration();
    dismissKeyboard();
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
        userAnswer: current.questionType === "EN_TO_ZH_CHOICE" || current.questionType === "ZH_TO_EN_CHOICE" ? (selectedChoice ?? undefined) : (userAnswer || undefined),
        durationMs: captureQuestionDuration(),
      }) });
      setLastResult(result);
      await new Promise((resolve) => window.setTimeout(resolve, 650));
      if (result.adaptiveFollowUp) {
        // A follow-up item may have been inserted mid-session; reload to pick it up.
        await reloadSession(sessionId);
      } else {
        // No structural change to the session: advance locally instead of
        // re-fetching the whole session (which would cost extra round trips).
        setRevealed(false);
        setUserAnswer("");
        setLastResult(null);
        setSelectedChoice(null);
        setChoicesVisible(false);
        setData((prev) => {
          if (!prev) return prev;
          const isLast = index >= prev.items.length - 1;
          return {
            ...prev,
            session: {
              ...prev.session,
              completedCount: prev.session.completedCount + 1,
              correctCount: prev.session.correctCount + (result.isCorrect ? 1 : 0),
              wrongCount: prev.session.wrongCount + (result.isCorrect ? 0 : 1),
              completedAt: isLast ? new Date().toISOString() : prev.session.completedAt,
            },
            items: prev.items.map((item, itemIndex) => itemIndex === index ? { ...item, status: "ANSWERED" } : item),
          };
        });
        setIndex((value) => value + 1);
      }
    } catch (reason) { setError(errorMessage(reason, "提交答案失败")); }
    finally { setSubmitting(false); }
  }
  async function skip() {
    if (!current || !data) return;
    captureActiveQuestionDuration();
    dismissKeyboard();
    setSubmitting(true); setError("");
    try {
      const session = await apiFetch<SessionData>("/api/study/skip", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ studySessionId: data.session.id, studySessionItemId: current.itemId, reason: "LATER" }),
      });
      applySession(session);
    } catch (reason) { setError(errorMessage(reason, "跳过失败")); }
    finally { setSubmitting(false); }
  }

  // 桌面端全套键盘快捷键支持：1-4 评分、Space 翻转/检查、R 重播发音、S 稍后再学
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.repeat || submitting) return;
      const target = event.target as HTMLElement | null;
      const isInput = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement;

      // 重播发音快捷键 R
      if (!isInput && (event.key === "r" || event.key === "R") && current) {
        event.preventDefault();
        void playWord(current);
        return;
      }

      // 稍后再学快捷键 S
      if (!isInput && (event.key === "s" || event.key === "S") && current) {
        event.preventDefault();
        void skip();
        return;
      }

      if (!revealed) {
        // 未揭晓状态：Space 翻转/显示答案
        if (!isInput && event.key === " " && current) {
          event.preventDefault();
          void reveal();
          return;
        }

        // 选择题模式下数字键 1-4 快捷作答
        if (
          !isInput &&
          (current?.questionType === "EN_TO_ZH_CHOICE" || current?.questionType === "ZH_TO_EN_CHOICE") &&
          choicesVisible &&
          current.choices
        ) {
          const num = parseInt(event.key, 10);
          if (num >= 1 && num <= current.choices.length) {
            const choice = current.choices[num - 1];
            if (choice) {
              event.preventDefault();
              if (current.questionType === "ZH_TO_EN_CHOICE") {
                void playEntryTts(choice, choice === current.word.term ? current.word.entryType : "WORD");
              }
              captureQuestionDuration();
              setSelectedChoice(choice);
              setLastResult(null);
              void reveal();
            }
          }
        }
      } else {
        // 已揭晓状态：1 忘记、2 模糊、3 认识、4 很熟
        if (event.key === "1") { event.preventDefault(); void rate("AGAIN"); }
        else if (event.key === "2") { event.preventDefault(); void rate("HARD"); }
        else if (event.key === "3" || (!isInput && event.key === " ")) { event.preventDefault(); void rate("GOOD"); }
        else if (event.key === "4") { event.preventDefault(); void rate("EASY"); }
      }
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [choicesVisible, current, rate, reveal, revealed, skip, submitting]);

  if (!data && !error) return <div className="grid min-h-[75vh] place-items-center"><div className="animate-scale-in text-center"><Loader2 className="mx-auto size-10 animate-spin text-accent" /><p className="mt-3 text-[15px] text-quaternary-label">正在生成 {MODE_LABELS[mode]} 队列…</p></div></div>;
  if (error && !data) return <div className="mx-auto max-w-xl py-20 text-center"><AlertCircle className="mx-auto size-12 text-danger" /><h1 className="mt-4 text-xl font-bold">无法开始学习</h1><p className="mt-2 text-[15px] text-secondary-label">{error}</p><div className="mt-6 flex justify-center gap-3"><Button onClick={() => void start()}><RotateCcw className="size-4" />重试</Button><Link href="/" className={buttonClass("outline")}>返回首页</Link></div></div>;
  if (!data) return null;
  if (autoContinuationPending) return <div className="mx-auto max-w-2xl py-12"><Card><CardContent className="py-16 text-center"><span className="animate-scale-in mx-auto grid size-20 place-items-center rounded-full bg-accent/10 text-accent"><Loader2 className="size-10 animate-spin" /></span><h1 className="mt-5 text-2xl font-bold tracking-tight">正在准备下一批</h1><p className="mt-2 text-[15px] text-secondary-label">这一批已完成，马上继续循环学习。</p><div className="mt-7 flex flex-wrap justify-center gap-3"><Button variant="outline" onClick={stopAutoContinue}><XCircle className="size-4" />结束学习</Button><Link href="/" className={buttonClass("ghost")}><Home className="size-4" />返回今日</Link></div></CardContent></Card></div>;
  if (complete) return <div className="mx-auto max-w-2xl py-12"><Card><CardContent className="py-16 text-center"><span className="animate-scale-in mx-auto grid size-20 place-items-center rounded-full bg-success/12 text-success"><CheckCircle2 className="size-10" /></span><h1 className="mt-5 text-2xl font-bold tracking-tight">{autoStopReason === "USER" ? "无限学习已暂停" : data.items.length === 0 ? "暂时没有更多可学习词条" : "本轮学习完成"}</h1><p className="mt-2 text-[15px] text-secondary-label">已处理 {data.session.completedCount} 个任务，正确 {data.session.correctCount} 个，稍后再学 {data.session.skippedCount} 个。</p><div className="mt-7 flex flex-wrap justify-center gap-3">{mode === "DAILY" && autoStopReason === "USER" && data.items.length > 0 && <Button onClick={resumeAutoContinue}><RotateCcw className="size-4" />继续无限学习</Button>}<Button onClick={() => void start(true)}><RotateCcw className="size-4" />生成新一轮</Button><Link href="/" className={buttonClass("outline")}><Home className="size-4" />返回今日</Link></div></CardContent></Card></div>;
  if (!current) return null;

  const progress = data.session.plannedCount ? data.session.completedCount / data.session.plannedCount * 100 : 100;
  const activeMode = MODES.has(data.session.sessionType as StudyMode) ? data.session.sessionType as StudyMode : mode;
  return <div className="animate-fade-up mx-auto max-w-3xl space-y-3">
    <div className="flex flex-wrap items-center justify-between gap-2"><Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />退出</Link><div className="text-center"><div className="flex items-center justify-center gap-2"><p className="text-[15px] font-bold">{MODE_LABELS[activeMode]}</p>{data.resumed && <Badge tone="amber">继续上次</Badge>}</div><p className="text-xs text-tertiary-label">已处理 {data.session.completedCount} / {data.session.plannedCount}</p></div><Badge tone={current.taskType === "WRONG" ? "red" : current.taskType === "NEW" ? "purple" : "blue"}>{current.taskType}</Badge></div>
    <Progress value={progress} />
    <Card className="h-[calc(100dvh-7.25rem)] max-h-[720px] min-h-[260px] overflow-hidden sm:h-[calc(100dvh-8rem)] sm:min-h-[420px] lg:h-[calc(100dvh-9.5rem)]"><CardContent className="grid h-full min-h-0 grid-rows-[auto_minmax(0,1fr)_auto] px-4 py-3 sm:px-10 sm:py-4">
      <div className="flex items-center justify-between text-xs text-tertiary-label"><span>{entryTypeLabel(current.word.entryType)}</span><span>{current.word.sourceLanguage} → {current.word.targetLanguage}</span></div>
      <div className="min-h-0 overflow-y-auto overscroll-contain">
        <div className={`flex min-h-full w-full flex-col items-center px-1 text-center ${revealed ? "justify-start py-[clamp(0.5rem,2vh,1.25rem)]" : "justify-center py-[clamp(1rem,4vh,3rem)]"}`}>
        {current.questionType === "ZH_TO_EN_CHOICE" ? <>
          <p className="text-[13px] text-quaternary-label">根据释义选择单词</p>
          <div className="glass-inner mt-3 w-full max-w-xl rounded-[16px] border border-accent/10 bg-accent/[0.045] px-4 py-3 text-left shadow-[0_12px_36px_rgba(0,122,255,0.06)] sm:px-6 sm:py-4">
            <DefinitionBlock definitions={definitions} className="text-lg font-bold leading-snug sm:text-xl" />
          </div>
          {!revealed && hasChoices && <p className="mt-3 text-[13px] text-quaternary-label">{choicesVisible ? "点击候选单词即作答" : choiceOptionsDelayLabel(choiceRevealDelaySeconds)}</p>}
          {choicesVisible && hasChoices ? <div className={`grid w-full max-w-xl gap-2 ${revealed ? "mt-3" : "mt-5"}`}>
            {(current.choices ?? []).map((choice, cIdx) => {
              const isCorrect = normalizeChoiceAnswer(choice) === normalizeChoiceAnswer(current.word.term);
              const isSelected = choice === selectedChoice;
              const showState = revealed && (isCorrect || isSelected);
              const choiceDefinition = current.choiceDefinitions?.[choice];
              // After reveal, only keep the correct option and the user's pick so
              // the option list stays on screen without scrolling.
              if (revealed && !isCorrect && !isSelected) return null;
              return <button key={choice} type="button" disabled={revealed} onClick={() => {
                if (!revealed) {
                  void playEntryTts(choice, choice === current.word.term ? current.word.entryType : "WORD");
                  captureQuestionDuration();
                  setSelectedChoice(choice); setLastResult(null);
                  void reveal();
                }
              }} className={`ios-press rounded-[16px] border-[1.5px] px-4 py-2.5 text-left transition-all duration-200 ${showState ? (isCorrect ? "border-success bg-success/[0.08] text-success-deep shadow-[0_8px_24px_rgba(52,199,89,0.12)] dark:text-success" : "border-danger bg-danger/[0.08] text-danger-deep shadow-[0_8px_24px_rgba(255,59,48,0.12)] dark:text-danger") : isSelected ? "border-accent/55 bg-accent/[0.08] text-[#005ecb] shadow-[0_8px_28px_rgba(0,122,255,0.12)] dark:text-[#0a84ff]" : "glass-inner border-white/50 hover:border-accent/40 hover:shadow-[0_8px_32px_rgba(0,122,255,0.10)] dark:border-white/[0.08]"}`}>
                <span className="flex items-center justify-between gap-3"><span className="min-w-0 break-words text-[15px] font-semibold"><Kbd className="mr-2 hidden sm:inline-flex">{cIdx + 1}</Kbd>{choice}</span><Volume2 className="size-4 shrink-0 opacity-55" /></span>
                {revealed && <span className="mt-1.5 block text-[13px] font-normal leading-relaxed text-secondary-label">{choiceDefinition ?? "暂无释义"}</span>}
              </button>;
            })}
          </div> : !hasChoices ? <div className="glass-inner mt-5 flex w-full max-w-xl items-center justify-center gap-2 rounded-[16px] border border-dashed border-danger/20 px-4 py-4 text-sm text-secondary-label"><AlertCircle className="size-4 text-danger" />该词条暂无释义，可稍后再学</div> : <div className="glass-inner mt-5 flex w-full max-w-xl items-center justify-center gap-2 rounded-[16px] border border-dashed border-accent/20 px-4 py-4 text-sm text-secondary-label"><Clock3 className="size-4 text-accent" />先回忆释义，选项即将出现</div>}
        </> : current.questionType === "EN_TO_ZH_CHOICE" ? <>
          <p className="text-[13px] text-quaternary-label">选择正确的释义</p>
          <h1 className={`break-words font-bold tracking-tight ${revealed ? "mt-2 text-xl sm:text-2xl" : "mt-3 text-2xl sm:text-4xl lg:text-5xl"}`}>{current.word.term}</h1>
          {!revealed && <Pronunciation item={current} />}
          {choicesVisible && hasChoices ? <div className={`grid w-full max-w-xl gap-2 ${revealed ? "mt-3" : "mt-5"}`}>
            {(current.choices ?? []).map((choice, cIdx) => {
              const isCorrect = choice === definitionText;
              const isSelected = choice === selectedChoice;
              const showState = revealed && (isCorrect || isSelected);
              // After reveal, only keep the correct option and the user's pick.
              if (revealed && !isCorrect && !isSelected) return null;
              return <button key={choice} type="button" aria-pressed={isSelected} disabled={revealed} onClick={() => {
                captureQuestionDuration();
                setSelectedChoice(choice); setLastResult(null);
                void reveal();
              }} className={`ios-press break-words rounded-[16px] border-[1.5px] px-4 py-2.5 text-left text-[15px] font-medium transition-all duration-200 disabled:opacity-90 ${showState ? (isCorrect ? "border-success bg-success/[0.08] text-success-deep shadow-[0_8px_24px_rgba(52,199,89,0.12)] dark:text-success" : "border-danger bg-danger/[0.08] text-danger-deep shadow-[0_8px_24px_rgba(255,59,48,0.12)] dark:text-danger") : isSelected ? "border-accent/55 bg-accent/[0.08] text-[#005ecb] shadow-[0_8px_28px_rgba(0,122,255,0.12)] dark:text-[#0a84ff]" : "glass-inner border-white/50 hover:border-accent/40 hover:shadow-[0_8px_32px_rgba(0,122,255,0.10)] dark:border-white/[0.08]"}`}><Kbd className="mr-2 hidden sm:inline-flex">{cIdx + 1}</Kbd>{choice}</button>;
            })}
          </div> : !hasChoices ? <div className="glass-inner mt-5 flex w-full max-w-xl items-center justify-center gap-2 rounded-[16px] border border-dashed border-danger/20 px-4 py-4 text-sm text-secondary-label"><AlertCircle className="size-4 text-danger" />该词条暂无释义，可稍后再学</div> : <div className="glass-inner mt-5 flex w-full max-w-xl items-center justify-center gap-2 rounded-[16px] border border-dashed border-accent/20 px-4 py-4 text-sm text-secondary-label"><Clock3 className="size-4 text-accent" />先回忆单词含义，释义选项即将出现</div>}
        </> : current.questionType === "EN_TO_ZH" ? <>
          {!revealed && <p className="text-[13px] text-quaternary-label">{current.word.entryType === "SENTENCE" ? "理解句意、语法和关键表达" : "回忆它的含义"}</p>}
          {!revealed && <h1 className={`mt-3 break-words font-bold tracking-tight ${current.word.entryType === "SENTENCE" ? "max-w-2xl text-xl leading-snug sm:text-3xl" : "text-2xl sm:text-4xl lg:text-5xl"}`}>{current.word.term}</h1>}
          {!revealed && (current.word.entryType === "SENTENCE"
            ? <button type="button" onClick={() => void playWord(current)} className="ios-press mt-3 inline-flex items-center gap-2 rounded-full bg-accent/[0.08] px-4 py-2 text-sm font-semibold text-accent transition-all hover:bg-accent/[0.14] dark:text-[#0a84ff]"><Volume2 className="size-4" />朗读句子</button>
            : <Pronunciation item={current} />)}
        </> : current.questionType === "ZH_TO_EN_SPELLING" ? <>
          {revealed ? <div className="w-full max-w-xl">
            <p className="text-[13px] text-quaternary-label">{current.word.entryType === "SENTENCE" ? "根据中文还原完整英文句子" : "根据释义拼写英文"}</p>
            <div className="mt-1.5 space-y-1 text-lg font-bold leading-snug sm:text-xl"><DefinitionBlock definitions={definitions} /></div>
          </div> : <>
            <span className="grid size-12 place-items-center rounded-[16px] bg-warning/12 text-warning">{current.word.entryType === "SENTENCE" ? <MessageSquareText className="size-6" /> : <Keyboard className="size-6" />}</span>
            <p className="mt-3 text-[13px] text-quaternary-label">{current.word.entryType === "SENTENCE" ? "根据中文翻译还原完整英文句子" : "根据释义拼写英文"}</p>
            <div className="mt-2 max-w-xl text-xl font-bold leading-snug"><DefinitionBlock definitions={definitions} /></div>
            <button type="button" onClick={() => void playWord(current)} className="ios-press mt-3 inline-flex items-center gap-2 rounded-full bg-accent/[0.08] px-4 py-2 text-sm font-semibold text-accent transition-all hover:bg-accent/[0.14] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]">
              <Volume2 className="size-4" />{current.word.entryType === "SENTENCE" ? "听原句（提示）" : "重播发音"}
            </button>
            {current.word.entryType !== "SENTENCE" && getHintPattern(current.word.term) && <p className="mt-3 max-w-full break-all text-center font-mono text-lg tracking-[0.2em] text-accent sm:text-2xl sm:tracking-[0.3em]">{getHintPattern(current.word.term)}</p>}
            {current.word.entryType === "SENTENCE"
              ? <textarea ref={sentenceAnswerRef} autoFocus rows={4} autoCapitalize="sentences" autoCorrect="off" spellCheck={false} className="mt-3 min-h-24 w-full max-w-xl resize-none glass-inner rounded-[16px] border-[1.5px] border-white/50 px-4 py-3 text-left text-base leading-relaxed outline-none transition-all focus:border-accent/50 focus:shadow-[0_8px_32px_rgba(0,122,255,0.12),0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if ((event.metaKey || event.ctrlKey) && event.key === "Enter" && userAnswer.trim()) { event.preventDefault(); void reveal(); } }} placeholder="输入完整英文句子（Ctrl/⌘ + Enter 检查）" />
              : <input ref={answerInputRef} autoFocus enterKeyHint="done" autoCapitalize="none" autoCorrect="off" spellCheck={false} className="mt-3 h-12 w-full max-w-md glass-inner rounded-[16px] border-[1.5px] border-white/50 px-5 text-center text-lg outline-none transition-all focus:border-accent/50 focus:shadow-[0_8px_32px_rgba(0,122,255,0.12),0_0_0_4px_rgba(0,122,255,0.08)] sm:text-xl dark:border-white/[0.08]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) { event.preventDefault(); void reveal(); } }} placeholder="输入英文词条" />}
          </>}
        </> : <>
          {revealed ? <p className="text-[13px] text-quaternary-label">听力拼写答案</p> : <>
            <button type="button" onClick={() => void playWord(current)} className="ios-press grid size-16 place-items-center rounded-full bg-[#5ac8fa]/12 text-accent sm:size-20"><Headphones className="size-8 sm:size-9" /></button>
            <p className="mt-3 text-[13px] text-quaternary-label">已自动播放，也可点击上方按钮重播</p>
            <input ref={answerInputRef} autoFocus enterKeyHint="done" autoCapitalize="none" autoCorrect="off" spellCheck={false} className="mt-4 h-12 w-full max-w-md glass-inner rounded-[16px] border-[1.5px] border-white/50 px-5 text-center text-xl outline-none transition-all focus:border-accent/50 focus:shadow-[0_8px_32px_rgba(0,122,255,0.12),0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) { event.preventDefault(); void reveal(); } }} placeholder="输入听到的词条" />
          </>}
        </>}

        {revealed && <div className="animate-fade-up glass-inner mt-5 w-full max-w-xl rounded-[18px] p-4 text-left sm:p-5">
          <div className="flex items-start gap-3">
            {exactLocal === false ? <XCircle className="mt-1 size-5 shrink-0 text-danger" /> : <CheckCircle2 className="mt-1 size-5 shrink-0 text-success" />}
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className={`text-xs font-semibold ${exactLocal === false ? "text-danger" : exactLocal === true ? "text-success" : "text-accent"}`}>{exactLocal === false ? "正确答案" : exactLocal === true ? "回答正确" : "参考答案"}</p>
                  <p className="mt-1 break-words text-xl font-bold tracking-tight sm:text-2xl">{current.word.term}</p>
                </div>
                <button type="button" onClick={() => void playWord(current)} className="ios-press inline-flex shrink-0 items-center gap-2 rounded-full bg-accent/[0.08] px-3.5 py-2 text-sm font-semibold text-accent transition-all hover:bg-accent/[0.14] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]">
                  <Volume2 className="size-4" />播放
                </button>
              </div>
              <div className="mt-3 border-t border-black/[0.06] pt-3 dark:border-white/[0.06]">
                <DefinitionBlock definitions={definitions} className="mt-1 text-[14px] leading-relaxed text-secondary-label sm:text-[15px] dark:text-secondary-label" />
              </div>
              <div className="mt-3 space-y-3">
              {current.word.entryType === "SENTENCE" && (current.word.content.sentenceAnalysis.grammarNotes.length > 0 || current.word.content.sentenceAnalysis.keyExpressions.length > 0 || current.word.content.sentenceAnalysis.variations.length > 0) && <div className="space-y-3 rounded-[14px] bg-accent/[0.055] p-3.5">
                {current.word.content.sentenceAnalysis.grammarNotes.length > 0 && <div><p className="text-xs font-semibold text-accent">语法要点</p><ul className="mt-1.5 space-y-1 text-[13px] leading-relaxed text-secondary-label">{current.word.content.sentenceAnalysis.grammarNotes.map((note) => <li key={note}>• {note}</li>)}</ul></div>}
                {current.word.content.sentenceAnalysis.keyExpressions.length > 0 && <div><p className="text-xs font-semibold text-accent">关键表达</p><div className="mt-1.5 space-y-2">{current.word.content.sentenceAnalysis.keyExpressions.map((item) => <div key={item.expression}><p className="text-[14px] font-semibold">{item.expression}</p><ClampedText text={item.meaning + (item.note ? ` · ${item.note}` : "")} className="text-[13px] leading-relaxed text-secondary-label" /></div>)}</div></div>}
                {current.word.content.sentenceAnalysis.variations.length > 0 && <div><p className="text-xs font-semibold text-accent">替换句型</p><div className="mt-1.5 space-y-2">{current.word.content.sentenceAnalysis.variations.slice(0, 3).map((item) => <div key={item.sentence} className="rounded-[10px] bg-white/45 px-3 py-2 dark:bg-white/[0.04]"><ClampedText text={item.sentence} className="text-[13px] font-medium leading-relaxed" />{item.translation && <ClampedText text={item.translation} className="mt-0.5 text-xs text-quaternary-label" />}</div>)}</div></div>}
              </div>}
              {current.word.entryType !== "SENTENCE" && current.word.content.examples[0] && <div className="rounded-[12px] bg-black/[0.025] px-3 py-2.5 dark:bg-white/[0.035]"><div className="flex items-start justify-between gap-2"><p className="text-[14px] italic leading-relaxed text-quaternary-label sm:text-[15px]">{current.word.content.examples[0].sentence}</p><button type="button" aria-label="朗读例句" onClick={() => void playCachedTts(current.word.content.examples[0]!.sentence, "US", "sentence")} className="ios-press grid size-7 shrink-0 place-items-center rounded-full bg-accent/[0.08] text-accent transition hover:bg-accent/[0.14] dark:text-[#0a84ff]"><Volume2 className="size-3.5" /></button></div>{current.word.content.examples[0].translation && <p className="mt-1.5 text-[13px] leading-relaxed text-secondary-label sm:text-[14px] dark:text-secondary-label">{current.word.content.examples[0].translation}</p>}</div>}
              {current.word.content.learning.mnemonic && <div className="flex items-start gap-2 rounded-[14px] bg-warning/[0.08] p-3"><Sparkles className="mt-0.5 size-4 shrink-0 text-warning" /><p className="text-[13px] leading-relaxed text-warning-deep sm:text-[14px] dark:text-warning">{current.word.content.learning.mnemonic}</p></div>}
              </div>
            </div>
          </div>
        </div>}
        {lastResult && <div className={`mt-4 flex items-center gap-2 text-[15px] font-semibold ${lastResult.rating === "EASY" || lastResult.isCorrect ? "text-success" : "text-danger"}`}>{lastResult.rating === "EASY" || lastResult.isCorrect ? <CheckCircle2 className="size-4" /> : <XCircle className="size-4" />}{lastResult.rating === "EASY" ? "已掌握，近期不会再出现" : lastResult.isCorrect ? "已记录" : lastResult.adaptiveFollowUp ? "已加入错词强化，稍后会再次出现" : "已加入错词强化"}</div>}
        {error && <div className="mt-4 rounded-[14px] bg-danger/[0.08] p-3 text-[14px] text-danger-deep">{error}</div>}
        </div>
      </div>
      <div className="shrink-0 pt-1.5 sm:pt-3">
      {!revealed ? (current.questionType === "EN_TO_ZH_CHOICE" ? <div className="grid grid-cols-[auto_1fr] gap-1.5 sm:gap-2"><Button variant="outline" size="lg" className={studyActionClass} onClick={() => void skip()} disabled={submitting}><Clock3 className="size-5" />稍后再学<Kbd className="hidden sm:inline-flex ml-1">S</Kbd></Button><div className="self-center text-center text-[12px] text-tertiary-label sm:text-[13px]">{hasChoices ? (choicesVisible ? "点击上方选项或按 1-4 作答" : choiceOptionsDelayLabel(choiceRevealDelaySeconds)) : "该词条暂无释义，可稍后再学"}</div></div> : current.questionType === "ZH_TO_EN_CHOICE" ? <div className="grid grid-cols-[auto_1fr] gap-1.5 sm:gap-2"><Button variant="outline" size="lg" className={studyActionClass} onClick={() => void skip()} disabled={submitting}><Clock3 className="size-5" />稍后再学<Kbd className="hidden sm:inline-flex ml-1">S</Kbd></Button><div className="self-center text-center text-[12px] text-tertiary-label sm:text-[13px]">{hasChoices ? (choicesVisible ? "点击候选单词或按 1-4 作答" : choiceOptionsDelayLabel(choiceRevealDelaySeconds)) : "该词条暂无释义，可稍后再学"}</div></div> : current.questionType !== "EN_TO_ZH" ? <div className="flex flex-wrap gap-1.5 sm:gap-2"><Button variant="outline" size="lg" onClick={() => void skip()} disabled={submitting} className={`${studyActionClass} w-[calc(50%-3px)] sm:w-auto`}><Clock3 className="size-4 shrink-0" /><span>稍后再学</span><Kbd className="hidden sm:inline-flex ml-1">S</Kbd></Button><Button variant="outline" size="lg" onClick={() => void reveal()} disabled={submitting} className={`${studyActionClass} w-[calc(50%-3px)] border-danger/20 text-danger hover:bg-danger/[0.06] sm:w-auto`}><XCircle className="size-4 shrink-0" />忘记<Kbd className="hidden sm:inline-flex ml-1">1</Kbd></Button><Button size="lg" className={`${studyActionClass} w-full sm:flex-1`} onClick={() => void reveal()} disabled={submitting || !userAnswer.trim()}><Sparkles className="size-4 shrink-0" /><span>检查答案</span><Kbd className="hidden sm:inline-flex ml-1 bg-white/20 text-white border-white/30">Space</Kbd></Button></div> : <div className="grid grid-cols-[auto_1fr] gap-1.5 sm:gap-2"><Button variant="outline" size="lg" className={studyActionClass} onClick={() => void skip()} disabled={submitting}><Clock3 className="size-5" />稍后再学<Kbd className="hidden sm:inline-flex ml-1">S</Kbd></Button><Button size="lg" className={`${studyActionClass} w-full`} onClick={() => void reveal()} disabled={submitting}><Sparkles className="size-5" />显示答案<Kbd className="hidden sm:inline-flex ml-1 bg-white/20 text-white border-white/30">Space</Kbd></Button></div>) : <div className="border-t border-black/[0.06] pt-2 sm:pt-3 dark:border-white/[0.06]">
        {current.questionType === "ZH_TO_EN_CHOICE" && <p className="mb-1.5 text-center text-[11px] text-quaternary-label sm:mb-2 sm:text-xs">已按“{exactLocal === true ? "认识" : "忘记"}”记录，按数字键或点击熟悉度直接进入下一题</p>}
        <div className="grid grid-cols-2 gap-1.5 sm:grid-cols-4 sm:gap-2">{(["AGAIN", "HARD", "GOOD", "EASY"] as ReviewRating[]).map((rating, rIdx) => { const interval = intervals.find((item) => item.rating === rating); const labels = { AGAIN: "忘记", HARD: "模糊", GOOD: "认识", EASY: "很熟" } as const; const styles = { AGAIN: "glass-inner border-danger/25 text-danger-deep shadow-[0_6px_24px_rgba(255,59,48,0.10)] dark:text-danger", HARD: "glass-inner border-warning/25 text-warning-deep shadow-[0_6px_24px_rgba(255,149,0,0.10)] dark:text-warning", GOOD: "glass-inner border-accent/25 text-accent-deep shadow-[0_6px_24px_rgba(0,122,255,0.10)] dark:text-[#0a84ff]", EASY: "glass-inner border-success/25 text-success-deep shadow-[0_6px_24px_rgba(52,199,89,0.10)] dark:text-success" } as const; const shortcutKey = String(rIdx + 1); return <button key={rating} disabled={submitting} onClick={() => void rate(rating)} className={`ios-press min-h-10 rounded-[12px] border-[1.5px] px-1.5 py-1.5 text-center transition-all duration-200 disabled:opacity-40 sm:min-h-12 sm:rounded-[14px] sm:p-3 ${styles[rating]}`}><div className="flex items-center justify-center gap-1.5"><b className="text-[13px] sm:text-[15px]">{labels[rating]}</b><Kbd className="hidden sm:inline-flex text-[10px] px-1">{shortcutKey}</Kbd></div><span className="mt-0.5 block text-[10px] opacity-60 sm:mt-1 sm:text-[11px]">{interval ? formatInterval(interval.scheduledDays) : "—"}</span></button>; })}</div></div>}
      </div>
    </CardContent></Card>
  </div>;
}
function ClampedText({ text, lines = 2, className = "" }: { text: string; lines?: number; className?: string }) {
  const [expanded, setExpanded] = useState(false);
  const needsClamp = text.length > 40;
  if (!needsClamp) return <p className={className}>{text}</p>;
  return (
    <div className="w-full">
      <p className={`${className} ${expanded ? "" : `line-clamp-${lines}`}`}>{text}</p>
      <button type="button" onClick={() => setExpanded((value) => !value)} className="mt-1 inline-flex items-center gap-1 rounded-full bg-accent/[0.08] px-2 py-0.5 text-[11px] font-semibold text-accent transition hover:bg-accent/[0.14] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]">
        <ChevronDown className={`size-3 transition-transform duration-200 ${expanded ? "rotate-180" : ""}`} />
        {expanded ? "收起" : "查看全部"}
      </button>
    </div>
  );
}

function DefinitionBlock({ definitions, className = "" }: { definitions: string[]; className?: string }) {
  const [expanded, setExpanded] = useState(false);
  const needsClamp = definitions.some((definition) => definition.length > 40);
  const content = definitions.length > 0
    ? definitions.map((definition, definitionIndex) => <p key={`${definition}-${definitionIndex}`} className={className}>{definition}</p>)
    : <p className={className}>暂无释义</p>;
  if (!needsClamp) return <>{content}</>;
  return (
    <div className="w-full">
      <div className={expanded ? "" : "line-clamp-3"}>{content}</div>
      <button type="button" onClick={() => setExpanded((value) => !value)} className="mt-1.5 inline-flex items-center gap-1 rounded-full bg-accent/[0.08] px-2.5 py-1 text-[12px] font-semibold text-accent transition hover:bg-accent/[0.14] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]">
        <ChevronDown className={`size-3.5 transition-transform duration-200 ${expanded ? "rotate-180" : ""}`} />
        {expanded ? "收起" : "查看全部"}
      </button>
    </div>
  );
}

function Pronunciation({ item }: { item: Item }) {
  const [selectedAccent, setSelectedAccent] = useState<"US" | "UK">("US");
  const [ttsTip, setTtsTip] = useState("");
  const [playing, setPlaying] = useState(false);
  const current = item.word.content.pronunciations.find((p) => p.accent === selectedAccent);
  async function play() {
    setTtsTip("");
    setPlaying(true);
    try {
      const played = await playEntryTts(item.word.term, item.word.entryType, selectedAccent);
      if (!played) setTtsTip("发音播放失败，请检查浏览器自动播放权限或网络。");
    } finally {
      window.setTimeout(() => setPlaying(false), 900);
    }
  }
  const accentLabel: Record<string, string> = { US: "美", UK: "英" };
  return <div className="mt-3">
    <div className="flex flex-wrap items-center justify-center gap-2">
      <div className="flex overflow-hidden rounded-full border border-black/[0.08] bg-black/[0.03] dark:border-white/[0.08] dark:bg-white/[0.04]">
        {(["US", "UK"] as const).map((accent) => <button key={accent} type="button" onClick={() => setSelectedAccent(accent)}
          className={`inline-flex min-h-9 items-center px-4 text-xs font-semibold transition-all duration-200 ${selectedAccent === accent ? "bg-accent text-white shadow-[0_2px_8px_rgba(0,122,255,0.3)]" : "text-secondary-label hover:text-accent dark:text-secondary-label dark:hover:text-[#0a84ff]"}`}>
          {accentLabel[accent] ?? accent}
        </button>)}
      </div>
      <button type="button" onClick={play} className={`ios-press inline-flex items-center gap-2 rounded-full px-4 py-1.5 text-sm font-medium transition-all ${playing ? "bg-accent text-white shadow-[0_0_20px_rgba(0,122,255,0.4)] scale-105" : "bg-accent/[0.08] text-accent hover:bg-accent/[0.12] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]"}`}>
        <Volume2 className={`size-4 ${playing ? "animate-pulse" : ""}`} />{current?.phonetic || "播放发音"}<Kbd className="hidden sm:inline-flex ml-1 text-[10px]">R</Kbd>
      </button>
    </div>
    {ttsTip && <p className="mt-1.5 text-xs text-warning dark:text-warning">{ttsTip}</p>}
  </div>;
}
function formatInterval(days: number) { if (days < 1) return "今天"; if (days === 1) return "1 天"; if (days < 30) return `${Math.round(days)} 天`; if (days < 365) return `${Math.round(days / 30)} 月`; return `${(days / 365).toFixed(1)} 年`; }
