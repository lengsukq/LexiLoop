"use client";
import Link from "next/link";
import { errorMessage } from "@/lib/format";
import { useSearchParams } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { AlertCircle, ArrowLeft, CheckCircle2, ChevronDown, Clock3, Eye, Headphones, Home, Keyboard, Lightbulb, Loader2, MessageSquareText, RotateCcw, Sparkles, Volume2, XCircle } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { playCachedTts, playEntryTts, preloadTtsBatch } from "@/lib/tts-client";
import { useActiveStopwatch } from "@/lib/use-active-stopwatch";
import type { AffixItem, DictionaryContent, QuestionType, RelatedWordItem, ReviewRating, RootItem, StudyMode } from "@/lib/types";
import { entryTypeLabel } from "@/lib/entry-type-label";
import { Badge, Button, Card, CardContent, Kbd, Progress, buttonClass } from "@/components/ui";
import { SentenceDiff, TermDiff } from "@/components/answer-diff";

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
  cloze?: { sentence: string; translation: string | null; blankedSentence: string } | null;
  letters?: Array<{ id: string; value: string }>;
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
  const middleBlanks = term.length > 12
    ? "_".repeat(term.length - 2)
    : term.slice(1, -1).split("").map(() => "_").join(" ");
  return `${firstLetter} ${middleBlanks} ${lastLetter}`;
}
function getProgressiveHint(term: string, level: number): string | null {
  if (term.length <= 2 || /\s/.test(term)) return null;
  if (level <= 0) return getHintPattern(term);
  const revealCount = Math.min(term.length - 2, level + 1);
  const revealed = term.slice(1, 1 + revealCount);
  const remaining = term.length - 2 - revealCount;
  const blanks = remaining <= 0 ? "" : term.length > 12 ? "_".repeat(remaining) : Array(remaining).fill("_").join(" ");
  const sep = term.length > 12 ? "" : " ";
  const middle = revealed.split("").join(sep) + (remaining > 0 ? sep + blanks : "");
  return `${term[0]} ${middle} ${term[term.length - 1]}`;
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
  const [choiceRevealProgress, setChoiceRevealProgress] = useState(0);
  const choiceProgressTimerRef = useRef<number | null>(null);
  const [aiGenerating, setAiGenerating] = useState(false);
  const [error, setError] = useState("");
  const [choiceRevealDelaySeconds, setChoiceRevealDelaySeconds] = useState(2);
  const choiceRevealDelaySecondsRef = useRef(2);
  const choiceRevealTimerRef = useRef<number | null>(null);
  const [hintLevel, setHintLevel] = useState(0);
  const [usedHint, setUsedHint] = useState(false);
  const [revealSections, setRevealSections] = useState({ mnemonic: true, roots: false, grammar: false, example: false });
  const [builtLetterIds, setBuiltLetterIds] = useState<string[]>([]);
  const [autoContinue, setAutoContinue] = useState(mode === "DAILY");
  const autoContinueRef = useRef(mode === "DAILY");
  const [autoStopReason, setAutoStopReason] = useState<"USER" | "EXHAUSTED" | null>(null);

  useEffect(() => {
    let cancelled = false;
    void apiFetch<{ choiceRevealDelaySeconds?: number }>("/api/settings")
      .then((settings) => {
        if (!cancelled && typeof settings.choiceRevealDelaySeconds === "number") {
          const delay = Math.max(0, settings.choiceRevealDelaySeconds);
          choiceRevealDelaySecondsRef.current = delay;
          setChoiceRevealDelaySeconds(delay);
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

  function clearChoiceRevealTimers() {
    if (choiceRevealTimerRef.current !== null) {
      window.clearTimeout(choiceRevealTimerRef.current);
      choiceRevealTimerRef.current = null;
    }
    if (choiceProgressTimerRef.current !== null) {
      window.clearInterval(choiceProgressTimerRef.current);
      choiceProgressTimerRef.current = null;
    }
  }

  const current = data?.items[index] ?? null;
  const { reset: resetQuestionTimer, capture: captureActiveQuestionDuration } = useActiveStopwatch(Boolean(current && !revealed && !submitting));

  // Runs on every question transition (event handler, not an effect): resets
  // per-question state, restarts the stopwatch, and arms the choice delay.
  const beginQuestion = useCallback((questionType: QuestionType | null) => {
    questionDurationRef.current = null;
    resetQuestionTimer();
    answerIdRef.current = clientId();
    clearChoiceRevealTimers();
    setHintLevel(0);
    setUsedHint(false);
    setRevealSections({ mnemonic: true, roots: false, grammar: false, example: false });
    setBuiltLetterIds([]);
    if (!questionType) return;
    const isChoiceQuestion = questionType === "EN_TO_ZH_CHOICE" || questionType === "ZH_TO_EN_CHOICE" || questionType === "LISTENING_CHOICE";
    const delayMs = Math.max(0, choiceRevealDelaySecondsRef.current) * 1000;
    if (isChoiceQuestion && delayMs > 0) {
      setChoicesVisible(false);
      setChoiceRevealProgress(0);
      const startedAt = Date.now();
      choiceProgressTimerRef.current = window.setInterval(() => {
        const elapsed = Date.now() - startedAt;
        setChoiceRevealProgress(Math.min(1, elapsed / delayMs));
      }, 80);
      choiceRevealTimerRef.current = window.setTimeout(() => {
        choiceRevealTimerRef.current = null;
        clearChoiceRevealTimers();
        setChoiceRevealProgress(1);
        setChoicesVisible(true);
      }, delayMs) as unknown as number;
    } else {
      setChoicesVisible(true);
      setChoiceRevealProgress(1);
    }
  }, [resetQuestionTimer]);

  const applySession = useCallback((session: SessionData) => {
    dismissKeyboard();
    beginQuestion(session.items[session.resumeIndex]?.questionType ?? null);
    setData(session);
    setIndex(session.resumeIndex);
    setRevealed(false);
    setUserAnswer("");
    setIntervals([]);
    setLastResult(null);
    setSelectedChoice(null);
  }, [beginQuestion, dismissKeyboard]);

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
  useEffect(() => {
    if (!data) return;
    void preloadTtsBatch(data.items.slice(index, index + 5).map((item) => ({ text: item.word.term, accent: "US" })));
  }, [data, index]);

  const captureQuestionDuration = useCallback(() => {
    if (questionDurationRef.current === null) questionDurationRef.current = captureActiveQuestionDuration();
    return questionDurationRef.current;
  }, [captureActiveQuestionDuration]);

  // Timers are armed per question in beginQuestion; this only cleans up on unmount.
  useEffect(() => () => {
    if (choiceRevealTimerRef.current !== null) {
      window.clearTimeout(choiceRevealTimerRef.current);
      choiceRevealTimerRef.current = null;
    }
    if (choiceProgressTimerRef.current !== null) {
      window.clearInterval(choiceProgressTimerRef.current);
      choiceProgressTimerRef.current = null;
    }
  }, []);
  useEffect(() => {
    if (!current) return;
    if (revealed) return;
    if (
      current.questionType === "ZH_TO_EN_CHOICE" ||
      current.questionType === "LISTENING_CHOICE" ||
      current.questionType === "EN_TO_ZH_CHOICE"
    ) return;

    const playbackKey = `q:${data?.session.id ?? 0}:${current.itemId}`;
    if (autoPlayedRef.current === playbackKey) return;
    autoPlayedRef.current = playbackKey;

    const timer = window.setTimeout(() => {
      void playWord(current);
    }, 220);
    return () => window.clearTimeout(timer);
  }, [current, data?.session.id, revealed]);

  const revealedPlayedRef = useRef("");
  useEffect(() => {
    if (!current || !revealed) return;
    const playbackKey = `r:${data?.session.id ?? 0}:${current.itemId}`;
    if (revealedPlayedRef.current === playbackKey) return;
    revealedPlayedRef.current = playbackKey;

    const timer = window.setTimeout(() => {
      void playWord(current);
    }, 280);
    return () => window.clearTimeout(timer);
  }, [current, data?.session.id, revealed]);
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
    : current && (current.questionType === "ZH_TO_EN_CHOICE" || current.questionType === "LISTENING_CHOICE")
      ? (selectedChoice ? normalizeChoiceAnswer(selectedChoice) === normalizeChoiceAnswer(current.word.term) : null)
    : current && current.questionType === "CLOZE_SENTENCE"
      ? (userAnswer.trim() ? userAnswer.trim().toLocaleLowerCase() === current.word.term.trim().toLocaleLowerCase() : null)
    : current && current.questionType === "LETTER_BANK"
      ? (builtLetterIds.length ? builtLetterIds.map((id) => current.letters?.find((l) => l.id === id)?.value ?? "").join("").toLocaleLowerCase() === current.word.term.toLocaleLowerCase() : null)
    : current && current.questionType !== "EN_TO_ZH"
      ? current.word.entryType === "SENTENCE"
        ? normalizeSentenceAnswer(userAnswer) === normalizeSentenceAnswer(current.word.term)
        : userAnswer.trim().toLocaleLowerCase() === current.word.term.trim().toLocaleLowerCase()
      : null;

  const reloadSession = useCallback(async (sessionId: number) => {
    applySession(await apiFetch<SessionData>(`/api/study/sessions/${sessionId}`));
  }, [applySession]);

  const revealChoiceNow = useCallback(() => {
    if (choiceRevealTimerRef.current !== null) {
      window.clearTimeout(choiceRevealTimerRef.current);
      choiceRevealTimerRef.current = null;
    }
    if (choiceProgressTimerRef.current !== null) {
      window.clearInterval(choiceProgressTimerRef.current);
      choiceProgressTimerRef.current = null;
    }
    setChoiceRevealProgress(1);
    setChoicesVisible(true);
  }, []);

  const reveal = useCallback(async () => {
    if (!current) return;
    if (choiceRevealTimerRef.current !== null) {
      window.clearTimeout(choiceRevealTimerRef.current);
      choiceRevealTimerRef.current = null;
    }
    if (choiceProgressTimerRef.current !== null) {
      window.clearInterval(choiceProgressTimerRef.current);
      choiceProgressTimerRef.current = null;
    }
    setChoiceRevealProgress(1);
    captureQuestionDuration();
    dismissKeyboard();
    setRevealed(true); setLastResult(null);
    try { setIntervals(await apiFetch<Interval[]>("/api/reviews/preview", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ wordId: current.word.id }) })); }
    catch { setIntervals([]); }
  }, [captureQuestionDuration, current, dismissKeyboard]);

  async function generateAiMnemonicForCurrent() {
    if (!current) return;
    setAiGenerating(true);
    setError("");
    try {
      const res = await apiFetch<{
        success: boolean;
        mnemonic: string;
        learning: DictionaryContent["learning"];
        roots?: RootItem[];
        affixes?: AffixItem[];
        confusedWords?: RelatedWordItem[];
      }>(`/api/words/${current.word.id}/mnemonic`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sync: true }),
      });

      setData((prev) => {
        if (!prev) return prev;
        return {
          ...prev,
          items: prev.items.map((item, itemIdx) => {
            if (itemIdx !== index) return item;
            return {
              ...item,
              word: {
                ...item.word,
                content: {
                  ...item.word.content,
                  learning: res.learning,
                  roots: res.roots?.length ? res.roots : item.word.content.roots,
                  affixes: res.affixes?.length ? res.affixes : item.word.content.affixes,
                  confusedWords: res.confusedWords?.length ? res.confusedWords : item.word.content.confusedWords,
                },
              },
            };
          }),
        };
      });
    } catch {
      setError("AI 助记生成失败，请稍后重试。");
    } finally {
      setAiGenerating(false);
    }
  }

  const rate = useCallback(async (rating: ReviewRating) => {
    if (!current || !data) return;
    const effectiveRating: ReviewRating = usedHint && (current.questionType === "ZH_TO_EN_SPELLING" || current.questionType === "LISTENING_SPELLING") && exactLocal === false && (rating === "GOOD" || rating === "EASY") ? "HARD" : rating;
    const sessionId = data.session.id;
    setSubmitting(true); setError("");
    try {
      const result = await apiFetch<AnswerResult>("/api/study/answer", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({
        clientAnswerId: answerIdRef.current || clientId(), wordId: current.word.id, studySessionId: sessionId,
        studySessionItemId: current.itemId, rating: effectiveRating, questionType: current.questionType,
        userAnswer: (() => {
          if (current.questionType === "EN_TO_ZH_CHOICE" || current.questionType === "ZH_TO_EN_CHOICE" || current.questionType === "LISTENING_CHOICE") return selectedChoice ?? undefined;
          if (current.questionType === "LETTER_BANK") return builtLetterIds.map((id) => current.letters?.find((l) => l.id === id)?.value ?? "").join("") || undefined;
          return userAnswer || undefined;
        })(),
        durationMs: captureQuestionDuration(),
      }) });
      setLastResult(result);
      await new Promise((resolve) => window.setTimeout(resolve, 320));
      if (result.adaptiveFollowUp) {
        // A follow-up item may have been inserted mid-session; reload to pick it up.
        await reloadSession(sessionId);
      } else {
        // No structural change to the session: advance locally instead of
        // re-fetching the whole session (which would cost extra round trips).
        const nextQuestionType = data.items[index + 1]?.questionType ?? null;
        beginQuestion(nextQuestionType);
        setRevealed(false);
        setUserAnswer("");
        setLastResult(null);
        setSelectedChoice(null);
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
  }, [beginQuestion, builtLetterIds, captureQuestionDuration, current, data, exactLocal, index, reloadSession, selectedChoice, usedHint, userAnswer]);

  const skip = useCallback(async () => {
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
  }, [applySession, captureActiveQuestionDuration, current, data, dismissKeyboard]);

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
        if (
          !isInput &&
          (current?.questionType === "EN_TO_ZH_CHOICE" || current?.questionType === "ZH_TO_EN_CHOICE" || current?.questionType === "LISTENING_CHOICE") &&
          !choicesVisible
        ) {
          if (event.key === " " || event.key === "Enter") {
            event.preventDefault();
            revealChoiceNow();
            return;
          }
        }
        // 未揭晓状态：Space 翻转/显示答案
        if (!isInput && event.key === " " && current) {
          if (current.questionType === "EN_TO_ZH_CHOICE" || current.questionType === "ZH_TO_EN_CHOICE" || current.questionType === "LISTENING_CHOICE") {
            if (!choicesVisible) {
              event.preventDefault();
              revealChoiceNow();
              return;
            }
          }
          event.preventDefault();
          void reveal();
          return;
        }

        // 选择题模式下数字键 1-4 快捷作答
        if (
          !isInput &&
          (current?.questionType === "EN_TO_ZH_CHOICE" || current?.questionType === "ZH_TO_EN_CHOICE" || current?.questionType === "LISTENING_CHOICE") &&
          choicesVisible &&
          current.choices
        ) {
          const num = parseInt(event.key, 10);
          if (num >= 1 && num <= current.choices.length) {
            const choice = current.choices[num - 1];
            if (choice) {
              event.preventDefault();
              if (current.questionType === "ZH_TO_EN_CHOICE" || current.questionType === "LISTENING_CHOICE") {
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
  }, [captureQuestionDuration, choicesVisible, current, rate, reveal, revealChoiceNow, revealed, skip, submitting]);

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
    <Card className="h-[calc(100dvh-7.25rem)] max-h-[720px] min-h-[260px] overflow-hidden rounded-[24px] sm:h-[calc(100dvh-8rem)] sm:min-h-[420px] lg:h-[calc(100dvh-9.5rem)]"><CardContent className="grid h-full min-h-0 grid-rows-[auto_minmax(0,1fr)_auto] px-4 py-3 sm:px-8 sm:py-4">
      <div className="flex items-center justify-between text-xs text-tertiary-label"><span>{entryTypeLabel(current.word.entryType)}</span><span>{current.word.sourceLanguage} → {current.word.targetLanguage}</span></div>
      <div className="min-h-0 overflow-y-auto overscroll-contain">
        <div className={`flex min-h-full w-full flex-col items-center px-1 text-center ${revealed ? "justify-start py-[clamp(0.5rem,2vh,1.25rem)]" : "justify-center py-[clamp(1rem,4vh,3rem)]"}`}>
        {current.questionType === "CLOZE_SENTENCE" ? <>
          {revealed ? <div className="w-full max-w-xl">
            <p className="text-[12.5px] font-medium text-quaternary-label">补全句子中的单词</p>
            <div className="mt-1.5 rounded-[12px] bg-accent/[0.04] px-3 py-2 text-left text-sm leading-relaxed sm:text-[15px]">{current.cloze?.blankedSentence ?? "____"}</div>
            {current.cloze?.translation && <p className="mt-1.5 text-xs text-secondary-label">{current.cloze.translation}</p>}
            <div className="mt-2 space-y-1 text-base font-bold leading-snug"><DefinitionBlock definitions={definitions} /></div>
          </div> : <>
            <p className="text-[12.5px] font-medium text-quaternary-label">根据释义补全句子</p>
            <div className="mt-2 w-full max-w-xl rounded-[12px] bg-accent/[0.04] px-3 py-2 text-left text-sm leading-relaxed sm:text-[15px]">{current.cloze?.blankedSentence ?? "____"}</div>
            {current.cloze?.translation && <p className="mt-1.5 text-xs text-secondary-label">{current.cloze.translation}</p>}
            <div className="mt-2 text-sm font-bold leading-snug"><DefinitionBlock definitions={definitions} /></div>
            <button type="button" onClick={() => void playWord(current)} className="ios-press mt-2.5 inline-flex items-center gap-2 rounded-full bg-accent/[0.08] px-3.5 py-1.5 text-xs font-semibold text-accent hover:bg-accent/[0.14] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]"><Volume2 className="size-3.5" />重播发音</button>
            {current.word.entryType !== "SENTENCE" && getHintPattern(current.word.term) && <p className="mt-2.5 max-w-full break-all text-center font-mono text-base tracking-[0.2em] text-accent sm:text-xl sm:tracking-[0.25em]">{getProgressiveHint(current.word.term, hintLevel) ?? getHintPattern(current.word.term)}</p>}
            {current.word.entryType !== "SENTENCE" && (() => {
              const usPh = current.word.content.pronunciations.find((pr) => pr.accent === "US")?.phonetic || null;
              const ukPh = current.word.content.pronunciations.find((pr) => pr.accent === "UK")?.phonetic || null;
              const ph = usPh || ukPh;
              if (!ph) return null;
              const accent = usPh ? "US" : "UK";
              return <p className="font-mono text-xs tracking-wide text-tertiary-label">/{ph}/ <span className="ml-1 rounded-full bg-black/[0.04] px-1.5 py-0.5 text-[10px] font-semibold text-secondary-label dark:bg-white/[0.08]">{accent === "US" ? "美" : "英"}</span></p>;
            })()}
            <div className="mt-2.5 flex w-full max-w-md justify-center gap-2">
              <button type="button" onClick={() => { setHintLevel((v) => v + 1); setUsedHint(true); }} disabled={hintLevel >= current.word.term.length - 2} className="ios-press inline-flex items-center gap-1.5 rounded-full border border-accent/20 bg-accent/[0.06] px-3 py-1 text-xs font-semibold text-accent hover:bg-accent/[0.12] disabled:opacity-40 dark:text-[#0a84ff]"><Lightbulb className="size-3.5" />提示</button>
            </div>
            <input ref={answerInputRef} autoFocus enterKeyHint="done" autoCapitalize="none" autoCorrect="off" spellCheck={false} className="mt-2.5 h-11 w-full max-w-md rounded-[14px] border border-black/[0.08] bg-white/70 px-4 text-center text-base outline-none transition-all focus:border-accent focus:bg-white focus:shadow-[0_4px_16px_rgba(0,122,255,0.08)] sm:text-lg dark:border-white/[0.09] dark:bg-white/[0.05]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) { event.preventDefault(); void reveal(); } }} placeholder="输入单词补全句子" />
          </>}
        </> : current.questionType === "LETTER_BANK" ? <>
          {revealed ? <div className="w-full max-w-xl">
            <p className="text-[12.5px] font-medium text-quaternary-label">拼出单词</p>
            <div className="mt-1.5 space-y-1 text-base font-bold leading-snug"><DefinitionBlock definitions={definitions} /></div>
          </div> : <>
            <p className="text-[12.5px] font-medium text-quaternary-label">根据释义拼出单词（点选字母）</p>
            <div className="mt-1.5 max-w-xl text-base font-bold leading-snug"><DefinitionBlock definitions={definitions} /></div>
            <button type="button" onClick={() => void playWord(current)} className="ios-press mt-2.5 inline-flex items-center gap-2 rounded-full bg-accent/[0.08] px-3.5 py-1.5 text-xs font-semibold text-accent hover:bg-accent/[0.14] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]"><Volume2 className="size-3.5" />重播发音</button>
            {(() => {
              const usPh = current.word.content.pronunciations.find((pr) => pr.accent === "US")?.phonetic || null;
              const ukPh = current.word.content.pronunciations.find((pr) => pr.accent === "UK")?.phonetic || null;
              const ph = usPh || ukPh;
              if (!ph) return null;
              const accent = usPh ? "US" : "UK";
              return <p className="mt-1 font-mono text-xs tracking-wide text-tertiary-label">/{ph}/ <span className="ml-1 rounded-full bg-black/[0.04] px-1.5 py-0.5 text-[10px] font-semibold text-secondary-label dark:bg-white/[0.08]">{accent === "US" ? "美" : "英"}</span></p>;
            })()}
            <div className="mt-3 flex min-h-12 w-full max-w-md flex-wrap items-center justify-center gap-1.5 rounded-[14px] border-2 border-dashed border-accent/20 bg-accent/[0.04] px-3 py-2">
              {builtLetterIds.length ? builtLetterIds.map((id) => {
                const tile = current.letters?.find((l) => l.id === id);
                return <button key={id} type="button" onClick={() => setBuiltLetterIds((ids) => ids.filter((v) => v !== id))} className="ios-press grid size-9 place-items-center rounded-[10px] bg-accent text-sm font-bold uppercase text-white shadow">{tile?.value ?? ""}</button>;
              }) : <span className="text-xs text-tertiary-label">点按字母拼写</span>}
            </div>
            <div className="mt-3 flex max-w-md flex-wrap justify-center gap-1.5">
              {(current.letters ?? []).map((letter) => {
                const used = builtLetterIds.includes(letter.id);
                return <button key={letter.id} type="button" disabled={used} onClick={() => { if (!used) setBuiltLetterIds((ids) => [...ids, letter.id]); }} className={`ios-press grid size-9 place-items-center rounded-[10px] border text-sm font-bold uppercase shadow-sm ${used ? "opacity-25 border-black/5 bg-black/5 dark:bg-white/5" : "border-black/[0.06] bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.06]"}`}>{letter.value}</button>;
              })}
            </div>
            <div className="mt-3 flex gap-2">
              <Button variant="outline" size="sm" onClick={() => setBuiltLetterIds([])} disabled={!builtLetterIds.length}>清空</Button>
              <Button size="sm" onClick={() => void reveal()} disabled={!builtLetterIds.length}>检查答案</Button>
            </div>
          </>}
        </> : current.questionType === "LISTENING_CHOICE" ? <>
          <p className="text-[12.5px] font-medium text-quaternary-label">听发音选择单词</p>
          <button type="button" onClick={() => void playWord(current)} className="ios-press mt-3 grid size-14 place-items-center rounded-full bg-[#5ac8fa]/10 text-accent sm:size-16"><Headphones className="size-7 sm:size-8" /></button>
          <p className="mt-2 text-xs text-quaternary-label">已自动播放，可点击重播</p>
          {!revealed && hasChoices && <p className="mt-2.5 text-xs text-quaternary-label">{choicesVisible ? "点击候选单词或按 1-4 作答" : choiceOptionsDelayLabel(choiceRevealDelaySeconds)}</p>}
          {!revealed && !choicesVisible && hasChoices && <div className="mt-3 w-full max-w-xl space-y-2"><div className="h-1 overflow-hidden rounded-full bg-black/[0.06] dark:bg-white/[0.08]"><div className="h-full rounded-full bg-accent transition-all duration-100" style={{ width: `${Math.round(choiceRevealProgress * 100)}%` }} /></div><button type="button" onClick={revealChoiceNow} className="ios-press inline-flex items-center gap-1.5 rounded-full border border-accent/20 bg-accent/[0.06] px-3 py-1 text-xs font-semibold text-accent hover:bg-accent/[0.12] dark:text-[#0a84ff]"><Eye className="size-3.5" />立即显示选项<Kbd className="hidden sm:inline-flex ml-1 text-[10px]">Space</Kbd></button></div>}
          {choicesVisible && hasChoices ? <div className={`grid w-full max-w-xl gap-2 ${revealed ? "mt-2.5" : "mt-4"}`}>
            {(current.choices ?? []).map((choice, cIdx) => {
              const isCorrect = normalizeChoiceAnswer(choice) === normalizeChoiceAnswer(current.word.term);
              const isSelected = choice === selectedChoice;
              const choiceDefinition = current.choiceDefinitions?.[choice];
              const revealedStyle = revealed
                ? isCorrect ? "border-success/40 bg-success/[0.08] text-success-deep shadow-xs dark:text-success" : isSelected ? "border-danger/40 bg-danger/[0.08] text-danger-deep shadow-xs dark:text-danger" : "border-black/[0.06] bg-black/[0.015] text-tertiary-label opacity-75 dark:border-white/[0.06] dark:bg-white/[0.03]"
                : isSelected ? "border-accent/60 bg-accent/[0.08] text-accent font-semibold shadow-xs" : "border-black/[0.08] bg-white/70 hover:bg-white hover:border-accent/40 dark:border-white/[0.09] dark:bg-white/[0.05] dark:hover:bg-white/[0.09]";
              return <button key={choice} type="button" disabled={revealed} onClick={() => { if (!revealed) { void playEntryTts(choice, choice === current.word.term ? current.word.entryType : "WORD"); captureQuestionDuration(); setSelectedChoice(choice); setLastResult(null); void reveal(); } }} className={`ios-press rounded-[14px] border px-3.5 py-2.5 text-left transition-all duration-200 ${revealedStyle}`}><span className="flex items-center justify-between gap-3"><span className="min-w-0 break-words text-[14.5px] font-medium"><Kbd className="mr-2 hidden sm:inline-flex">{cIdx + 1}</Kbd>{choice}</span>{revealed ? (isCorrect ? <CheckCircle2 className="size-4 shrink-0 text-success" /> : isSelected ? <XCircle className="size-4 shrink-0 text-danger" /> : null) : <Volume2 className="size-4 shrink-0 opacity-50" />}</span>{revealed && <span className="mt-1 block text-xs font-normal leading-relaxed text-secondary-label">{choiceDefinition ?? "暂无释义"}</span>}</button>;
            })}
          </div> : !hasChoices ? <div className="glass-inner mt-4 flex w-full max-w-xl items-center justify-center gap-2 rounded-[14px] border border-dashed border-danger/20 px-4 py-3 text-xs text-secondary-label"><AlertCircle className="size-4 text-danger" />该词条暂无释义，可稍后再学</div> : null}
        </> : current.questionType === "ZH_TO_EN_CHOICE" ? <>
          <p className="text-[12.5px] font-medium text-quaternary-label">根据释义选择单词</p>
          <div className="glass-inner mt-2.5 w-full max-w-xl rounded-[16px] border border-accent/15 bg-accent/[0.04] px-4 py-3 text-left shadow-[0_4px_16px_rgba(0,122,255,0.04)] sm:px-6 sm:py-3.5">
            <DefinitionBlock definitions={definitions} className="text-base font-bold leading-snug sm:text-lg" />
          </div>
          {!revealed && hasChoices && <p className="mt-2.5 text-xs text-quaternary-label">{choicesVisible ? "点击候选单词即作答" : choiceOptionsDelayLabel(choiceRevealDelaySeconds)}</p>}
          {!revealed && !choicesVisible && hasChoices && <div className="mt-3 w-full max-w-xl space-y-2"><div className="h-1 overflow-hidden rounded-full bg-black/[0.06] dark:bg-white/[0.08]"><div className="h-full rounded-full bg-accent transition-all duration-100" style={{ width: `${Math.round(choiceRevealProgress * 100)}%` }} /></div><button type="button" onClick={revealChoiceNow} className="ios-press inline-flex items-center gap-1.5 rounded-full border border-accent/20 bg-accent/[0.06] px-3 py-1 text-xs font-semibold text-accent hover:bg-accent/[0.12] dark:text-[#0a84ff]"><Eye className="size-3.5" />立即显示选项<Kbd className="hidden sm:inline-flex ml-1 text-[10px]">Space</Kbd></button></div>}
          {choicesVisible && hasChoices ? <div className={`grid w-full max-w-xl gap-2 ${revealed ? "mt-2.5" : "mt-4"}`}>
            {(current.choices ?? []).map((choice, cIdx) => {
              const isCorrect = normalizeChoiceAnswer(choice) === normalizeChoiceAnswer(current.word.term);
              const isSelected = choice === selectedChoice;
              const choiceDefinition = current.choiceDefinitions?.[choice];
              const revealedStyle = revealed
                ? isCorrect
                  ? "border-success/40 bg-success/[0.08] text-success-deep shadow-xs dark:text-success"
                  : isSelected
                    ? "border-danger/40 bg-danger/[0.08] text-danger-deep shadow-xs dark:text-danger"
                    : "border-black/[0.06] bg-black/[0.015] text-tertiary-label opacity-75 dark:border-white/[0.06] dark:bg-white/[0.03]"
                : isSelected
                  ? "border-accent/60 bg-accent/[0.08] text-accent font-semibold shadow-xs"
                  : "border-black/[0.08] bg-white/70 hover:bg-white hover:border-accent/40 dark:border-white/[0.09] dark:bg-white/[0.05] dark:hover:bg-white/[0.09]";
              return <button key={choice} type="button" disabled={revealed} onClick={() => {
                if (!revealed) {
                  void playEntryTts(choice, choice === current.word.term ? current.word.entryType : "WORD");
                  captureQuestionDuration();
                  setSelectedChoice(choice); setLastResult(null);
                  void reveal();
                }
              }} className={`ios-press rounded-[14px] border px-3.5 py-2.5 text-left transition-all duration-200 ${revealedStyle}`}>
                <span className="flex items-center justify-between gap-3"><span className="min-w-0 break-words text-[14.5px] font-medium"><Kbd className="mr-2 hidden sm:inline-flex">{cIdx + 1}</Kbd>{choice}</span>{revealed ? (isCorrect ? <CheckCircle2 className="size-4 shrink-0 text-success" /> : isSelected ? <XCircle className="size-4 shrink-0 text-danger" /> : null) : <Volume2 className="size-4 shrink-0 opacity-50" />}</span>
                {revealed && <span className="mt-1 block text-xs font-normal leading-relaxed text-secondary-label">{choiceDefinition ?? "暂无释义"}</span>}
              </button>;
            })}
          </div> : !hasChoices ? <div className="glass-inner mt-4 flex w-full max-w-xl items-center justify-center gap-2 rounded-[14px] border border-dashed border-danger/20 px-4 py-3 text-xs text-secondary-label"><AlertCircle className="size-4 text-danger" />该词条暂无释义，可稍后再学</div> : null}
        </> : current.questionType === "EN_TO_ZH_CHOICE" ? <>
          <p className="text-[12.5px] font-medium text-quaternary-label">选择正确的释义</p>
          <h1 className={`break-words font-bold tracking-tight ${revealed ? "mt-1.5 text-xl sm:text-2xl" : "mt-2.5 text-2xl sm:text-4xl lg:text-5xl"}`}>{current.word.term}</h1>
          {!revealed && <Pronunciation item={current} />}
          {!revealed && hasChoices && <p className="mt-2 text-xs text-quaternary-label">{choicesVisible ? "点击释义作答或按 1-4" : choiceOptionsDelayLabel(choiceRevealDelaySeconds)}</p>}
          {!revealed && !choicesVisible && hasChoices && <div className="mt-3 w-full max-w-xl space-y-2"><div className="h-1 overflow-hidden rounded-full bg-black/[0.06] dark:bg-white/[0.08]"><div className="h-full rounded-full bg-accent transition-all duration-100" style={{ width: `${Math.round(choiceRevealProgress * 100)}%` }} /></div><button type="button" onClick={revealChoiceNow} className="ios-press inline-flex items-center gap-1.5 rounded-full border border-accent/20 bg-accent/[0.06] px-3 py-1 text-xs font-semibold text-accent hover:bg-accent/[0.12] dark:text-[#0a84ff]"><Eye className="size-3.5" />立即显示选项<Kbd className="hidden sm:inline-flex ml-1 text-[10px]">Space</Kbd></button></div>}
          {choicesVisible && hasChoices ? <div className={`grid w-full max-w-xl gap-2 ${revealed ? "mt-2.5" : "mt-4"}`}>
            {(current.choices ?? []).map((choice, cIdx) => {
              const isCorrect = choice === definitionText;
              const isSelected = choice === selectedChoice;
              const revealedStyle = revealed
                ? isCorrect
                  ? "border-success/40 bg-success/[0.08] text-success-deep shadow-xs dark:text-success"
                  : isSelected
                    ? "border-danger/40 bg-danger/[0.08] text-danger-deep shadow-xs dark:text-danger"
                    : "border-black/[0.06] bg-black/[0.015] text-tertiary-label opacity-70 dark:border-white/[0.06] dark:bg-white/[0.03]"
                : isSelected
                  ? "border-accent/60 bg-accent/[0.08] text-accent font-semibold shadow-xs"
                  : "border-black/[0.08] bg-white/70 hover:bg-white hover:border-accent/40 dark:border-white/[0.09] dark:bg-white/[0.05] dark:hover:bg-white/[0.09]";
              return <button key={choice} type="button" aria-pressed={isSelected} disabled={revealed} onClick={() => {
                captureQuestionDuration();
                setSelectedChoice(choice); setLastResult(null);
                void reveal();
              }} className={`ios-press break-words rounded-[14px] border px-3.5 py-2.5 text-left text-[14.5px] font-medium transition-all duration-200 ${revealedStyle}`}><span className="flex items-center justify-between gap-2"><span className="flex-1"><Kbd className="mr-2 hidden sm:inline-flex">{cIdx + 1}</Kbd>{choice}</span>{revealed && (isCorrect ? <CheckCircle2 className="size-4 shrink-0 text-success" /> : isSelected ? <XCircle className="size-4 shrink-0 text-danger" /> : null)}</span></button>;
            })}
          </div> : !hasChoices ? <div className="glass-inner mt-4 flex w-full max-w-xl items-center justify-center gap-2 rounded-[14px] border border-dashed border-danger/20 px-4 py-3 text-xs text-secondary-label"><AlertCircle className="size-4 text-danger" />该词条暂无释义，可稍后再学</div> : null}
        </> : current.questionType === "EN_TO_ZH" ? <>
          {revealed && <p className="mt-2 text-center text-[11px] text-quaternary-label">诚实自评更有助于记忆 · 回忆不起来请选“忘记”</p>}
          {!revealed && <p className="text-[12.5px] font-medium text-quaternary-label">{current.word.entryType === "SENTENCE" ? "理解句意、语法和关键表达" : "回忆它的含义"}</p>}
          {!revealed && <h1 className={`mt-2.5 break-words font-bold tracking-tight ${current.word.entryType === "SENTENCE" ? "max-w-2xl text-xl leading-snug sm:text-3xl" : "text-2xl sm:text-4xl lg:text-5xl"}`}>{current.word.term}</h1>}
          {!revealed && (current.word.entryType === "SENTENCE"
            ? <button type="button" onClick={() => void playWord(current)} className="ios-press mt-2.5 inline-flex items-center gap-2 rounded-full bg-accent/[0.08] px-3.5 py-1.5 text-xs font-semibold text-accent transition-all hover:bg-accent/[0.14] dark:text-[#0a84ff]"><Volume2 className="size-3.5" />朗读句子</button>
            : <Pronunciation item={current} />)}
        </> : current.questionType === "ZH_TO_EN_SPELLING" ? <>
          {revealed ? <div className="w-full max-w-xl">
            <p className="text-[12.5px] font-medium text-quaternary-label">{current.word.entryType === "SENTENCE" ? "根据中文还原完整英文句子" : "根据释义拼写英文"}</p>
            <div className="mt-1.5 space-y-1 text-base font-bold leading-snug sm:text-lg"><DefinitionBlock definitions={definitions} /></div>
          </div> : <>
            <span className="grid size-11 place-items-center rounded-[14px] bg-warning/10 text-warning">{current.word.entryType === "SENTENCE" ? <MessageSquareText className="size-5.5" /> : <Keyboard className="size-5.5" />}</span>
            <p className="mt-2.5 text-[12.5px] font-medium text-quaternary-label">{current.word.entryType === "SENTENCE" ? "根据中文翻译还原完整英文句子" : "根据释义拼写英文"}</p>
            <div className="mt-1.5 max-w-xl text-lg font-bold leading-snug"><DefinitionBlock definitions={definitions} /></div>
            <button type="button" onClick={() => void playWord(current)} className="ios-press mt-2.5 inline-flex items-center gap-2 rounded-full bg-accent/[0.08] px-3.5 py-1.5 text-xs font-semibold text-accent transition-all hover:bg-accent/[0.14] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]">
              <Volume2 className="size-3.5" />{current.word.entryType === "SENTENCE" ? "听原句（提示）" : "重播发音"}
            </button>
            {current.word.entryType !== "SENTENCE" && getHintPattern(current.word.term) && (
              <div className="mt-2.5 flex w-full max-w-md flex-col items-center gap-2">
                <p className="max-w-full break-all text-center font-mono text-base tracking-[0.2em] text-accent sm:text-xl sm:tracking-[0.25em]">{getProgressiveHint(current.word.term, hintLevel) ?? getHintPattern(current.word.term)}</p>
                {(() => {
                  const usPh = current.word.content.pronunciations.find((pr) => pr.accent === "US")?.phonetic || null;
                  const ukPh = current.word.content.pronunciations.find((pr) => pr.accent === "UK")?.phonetic || null;
                  const ph = usPh || ukPh;
                  if (!ph) return null;
                  const accent = usPh ? "US" : "UK";
                  return <p className="font-mono text-xs tracking-wide text-tertiary-label">/{ph}/ <span className="ml-1 rounded-full bg-black/[0.04] px-1.5 py-0.5 text-[10px] font-semibold text-secondary-label dark:bg-white/[0.08]">{accent === "US" ? "美" : "英"}</span></p>;
                })()}
                <div className="flex flex-wrap items-center justify-center gap-2">
                  <button type="button" onClick={() => { setHintLevel((v) => v + 1); setUsedHint(true); }} disabled={hintLevel >= current.word.term.length - 2} className="ios-press inline-flex items-center gap-1.5 rounded-full border border-accent/20 bg-accent/[0.06] px-3 py-1 text-xs font-semibold text-accent hover:bg-accent/[0.12] disabled:opacity-40 dark:text-[#0a84ff]"><Lightbulb className="size-3.5" />提示 {hintLevel > 0 ? `(${hintLevel})` : ""}</button>
                </div>
                {usedHint && <p className="text-[11px] text-quaternary-label">已使用提示，本题将按“模糊”记录</p>}
              </div>
            )}
            {current.word.entryType === "SENTENCE"
              ? <textarea ref={sentenceAnswerRef} autoFocus rows={3} autoCapitalize="sentences" autoCorrect="off" spellCheck={false} className="mt-2.5 min-h-20 w-full max-w-xl resize-none rounded-[14px] border border-black/[0.08] bg-white/70 px-3.5 py-2.5 text-left text-[14.5px] leading-relaxed outline-none transition-all focus:border-accent focus:bg-white focus:shadow-[0_4px_16px_rgba(0,122,255,0.08)] dark:border-white/[0.09] dark:bg-white/[0.05]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if ((event.metaKey || event.ctrlKey) && event.key === "Enter" && userAnswer.trim()) { event.preventDefault(); void reveal(); } }} placeholder="输入完整英文句子（Ctrl/⌘ + Enter 检查）" />
              : <input ref={answerInputRef} autoFocus enterKeyHint="done" autoCapitalize="none" autoCorrect="off" spellCheck={false} className="mt-2.5 h-11 w-full max-w-md rounded-[14px] border border-black/[0.08] bg-white/70 px-4 text-center text-base outline-none transition-all focus:border-accent focus:bg-white focus:shadow-[0_4px_16px_rgba(0,122,255,0.08)] sm:text-lg dark:border-white/[0.09] dark:bg-white/[0.05]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) { event.preventDefault(); void reveal(); } }} placeholder="输入英文词条" />}
          </>}
        </> : <>
          {revealed ? <p className="text-[12.5px] font-medium text-quaternary-label">听力拼写答案</p> : <>
            <button type="button" onClick={() => void playWord(current)} className="ios-press grid size-14 place-items-center rounded-full bg-[#5ac8fa]/10 text-accent sm:size-16"><Headphones className="size-7 sm:size-8" /></button>
            <p className="mt-2.5 text-[12.5px] text-quaternary-label">已自动播放，也可点击上方按钮重播</p>
            <input ref={answerInputRef} autoFocus enterKeyHint="done" autoCapitalize="none" autoCorrect="off" spellCheck={false} className="mt-3 h-11 w-full max-w-md rounded-[14px] border border-black/[0.08] bg-white/70 px-4 text-center text-lg outline-none transition-all focus:border-accent focus:bg-white focus:shadow-[0_4px_16px_rgba(0,122,255,0.08)] dark:border-white/[0.09] dark:bg-white/[0.05]" value={userAnswer} onChange={(event) => setUserAnswer(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && userAnswer.trim()) { event.preventDefault(); void reveal(); } }} placeholder="输入听到的词条" />
          </>}
        </>}

        {revealed && <div className="animate-fade-up glass-inner mt-4 w-full max-w-xl rounded-[18px] p-3.5 text-left sm:p-4.5">
          <div className="flex items-start gap-3">
            {exactLocal === false ? <XCircle className="mt-0.5 size-4.5 shrink-0 text-danger" /> : <CheckCircle2 className="mt-0.5 size-4.5 shrink-0 text-success" />}
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <p className={`text-[11px] font-semibold tracking-tight ${exactLocal === false ? "text-danger" : exactLocal === true ? "text-success" : "text-accent"}`}>{exactLocal === false ? "正确答案" : exactLocal === true ? "回答正确" : "参考答案"}</p>
                  <p className="mt-0.5 break-words text-lg font-bold tracking-tight sm:text-xl">{current.word.term}</p>
                  {(() => {
                    const usPh = current.word.content.pronunciations.find((pr) => pr.accent === "US")?.phonetic || null;
                    const ukPh = current.word.content.pronunciations.find((pr) => pr.accent === "UK")?.phonetic || null;
                    const ph = usPh || ukPh;
                    const accent = usPh ? "US" : ukPh ? "UK" : null;
                    if (!ph) return null;
                    return <p className="mt-1 font-mono text-xs tracking-wide text-tertiary-label">/{ph}/ <span className="ml-1 rounded-full bg-black/[0.04] px-1.5 py-0.5 text-[10px] font-semibold text-secondary-label dark:bg-white/[0.08]">{accent === "US" ? "美" : "英"}</span></p>;
                  })()}
                </div>
                <button type="button" onClick={() => void playWord(current)} className="ios-press inline-flex shrink-0 items-center gap-1.5 rounded-full bg-accent/[0.08] px-3 py-1 text-xs font-semibold text-accent transition-all hover:bg-accent/[0.14] dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff]">
                  <Volume2 className="size-3.5" />播放
                </button>
              </div>
              <div className="mt-2.5 border-t border-black/[0.05] pt-2.5 dark:border-white/[0.06]">
                <DefinitionBlock definitions={definitions} className="text-[13.5px] leading-relaxed text-secondary-label" />
              </div>

              {/* 错选提示 */}
              {selectedChoice && exactLocal === false && (
                <div className="mt-2 rounded-[10px] border border-danger/20 bg-danger/[0.05] p-2 text-left text-xs">
                  <span className="font-semibold text-danger">❌ 你的选择：</span>
                  <span className="text-secondary-label font-medium">
                    {selectedChoice} {current.choiceDefinitions?.[selectedChoice] ? `(${current.choiceDefinitions[selectedChoice]})` : ""}
                  </span>
                </div>
              )}

              {(current.questionType === "ZH_TO_EN_SPELLING" || current.questionType === "LISTENING_SPELLING" || current.questionType === "CLOZE_SENTENCE" || current.questionType === "LETTER_BANK") && exactLocal === false && (
                current.word.entryType === "SENTENCE"
                  ? <SentenceDiff expected={current.word.term} actual={(current.questionType === "LETTER_BANK" ? builtLetterIds.map((id) => current.letters?.find((l) => l.id === id)?.value ?? "").join("") : userAnswer)} />
                  : <TermDiff expected={current.word.term} actual={(current.questionType === "LETTER_BANK" ? builtLetterIds.map((id) => current.letters?.find((l) => l.id === id)?.value ?? "").join("") : userAnswer)} />
              )}
              {usedHint && (current.questionType === "ZH_TO_EN_SPELLING" || current.questionType === "LISTENING_SPELLING") && !revealed && null}
              {usedHint && revealed && (current.questionType === "ZH_TO_EN_SPELLING" || current.questionType === "LISTENING_SPELLING") && exactLocal !== true && (
                <p className="mt-2 text-xs text-warning-deep">已使用提示，建议选择“模糊”</p>
              )}

              <div className="mt-2.5 space-y-2">
              {(current.word.content.roots.length > 0 || current.word.content.affixes.length > 0) && (
                <div className="rounded-[10px] bg-accent/[0.04] p-2.5">
                  <button type="button" onClick={() => setRevealSections((s) => ({ ...s, roots: !s.roots }))} className="flex w-full items-center justify-between text-left">
                    <span className="text-[10.5px] font-bold uppercase tracking-wider text-accent-deep">🧩 构词拆解</span>
                    <ChevronDown className={`size-3.5 text-accent transition-transform ${revealSections.roots ? "rotate-180" : ""}`} />
                  </button>
                  {revealSections.roots && <div className="mt-1 flex flex-wrap gap-1">
                    {current.word.content.roots.map((root) => (
                      <span key={root.root} className="rounded-md bg-white/70 px-1.5 py-0.5 text-[11px] font-medium text-label dark:bg-white/[0.08]">
                        <span className="font-mono text-accent">词根 {root.root}</span>: {root.meaning}
                      </span>
                    ))}
                    {current.word.content.affixes.map((affix) => (
                      <span key={`${affix.type}-${affix.value}`} className="rounded-md bg-white/70 px-1.5 py-0.5 text-[11px] font-medium text-label dark:bg-white/[0.08]">
                        <span className="font-mono text-purple">{affix.type === "PREFIX" ? "前缀" : "后缀"} {affix.value}</span>: {affix.meaning}
                      </span>
                    ))}
                  </div>}
                </div>
              )}

              {/* 易混词 */}
              {current.word.content.confusedWords.length > 0 && (
                <div className="rounded-[10px] bg-black/[0.02] px-2.5 py-1.5 text-xs text-secondary-label dark:bg-white/[0.03]">
                  <span className="font-semibold text-warning-deep">⚠️ 易混词：</span>
                  {current.word.content.confusedWords.map((cw) => cw.word).join("、")}
                </div>
              )}

              {current.word.content.learning.mnemonic ? (
                <div className="rounded-[12px] bg-warning/[0.06] p-2.5">
                  <button type="button" onClick={() => setRevealSections((s) => ({ ...s, mnemonic: !s.mnemonic }))} className="flex w-full items-center justify-between text-left">
                    <span className="flex items-center gap-1.5 text-[10.5px] font-bold text-warning-deep"><Sparkles className="size-3.5 text-warning" />趣味助记</span>
                    <span className="flex items-center gap-2"><span className="text-[11px] text-quaternary-label">{revealSections.mnemonic ? "收起" : "展开"}</span><ChevronDown className={`size-3.5 text-warning transition-transform ${revealSections.mnemonic ? "rotate-180" : ""}`} /></span>
                  </button>
                  {revealSections.mnemonic && <div className="mt-1.5 flex items-start justify-between gap-2">
                    <p className="text-[12.5px] leading-relaxed text-label">{current.word.content.learning.mnemonic}</p>
                    <button type="button" onClick={() => void generateAiMnemonicForCurrent()} disabled={aiGenerating} className="ios-press shrink-0 rounded-full bg-warning/12 px-2 py-0.5 text-[10.5px] font-semibold text-warning-deep hover:bg-warning/20 disabled:opacity-50">{aiGenerating ? <Loader2 className="size-3 animate-spin" /> : "换一个"}</button>
                  </div>}
                </div>
              ) : current.word.entryType !== "SENTENCE" ? (
                <div className="flex items-center justify-between gap-2 rounded-[12px] border border-dashed border-warning/25 bg-warning/[0.03] p-2.5">
                  <div className="flex items-center gap-1.5">
                    <Sparkles className="size-3.5 text-warning" />
                    <p className="text-xs text-secondary-label">该单词暂无趣味助记</p>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => void generateAiMnemonicForCurrent()}
                    disabled={aiGenerating}
                    className="h-6.5 text-[11px] border-warning/30 text-warning-deep hover:bg-warning/10"
                  >
                    {aiGenerating ? <Loader2 className="size-3 animate-spin" /> : <Sparkles className="size-3" />}
                    {aiGenerating ? "AI 创作中…" : "✨ AI 巧记"}
                  </Button>
                </div>
              ) : null}

              {current.word.entryType === "SENTENCE" && (current.word.content.sentenceAnalysis.grammarNotes.length > 0 || current.word.content.sentenceAnalysis.keyExpressions.length > 0 || current.word.content.sentenceAnalysis.variations.length > 0) && <div className="rounded-[12px] bg-accent/[0.045] p-3">
                <button type="button" onClick={() => setRevealSections((s) => ({ ...s, grammar: !s.grammar }))} className="flex w-full items-center justify-between text-left">
                  <span className="text-xs font-semibold text-accent">句型与表达 {revealSections.grammar ? "" : `· ${current.word.content.sentenceAnalysis.grammarNotes.length + current.word.content.sentenceAnalysis.keyExpressions.length + current.word.content.sentenceAnalysis.variations.length} 项`}</span>
                  <ChevronDown className={`size-3.5 text-accent transition-transform ${revealSections.grammar ? "rotate-180" : ""}`} />
                </button>
                {revealSections.grammar && <div className="mt-2 space-y-2.5">
                  {current.word.content.sentenceAnalysis.grammarNotes.length > 0 && <div><p className="text-xs font-semibold text-accent">语法要点</p><ul className="mt-1 space-y-0.5 text-xs leading-relaxed text-secondary-label">{current.word.content.sentenceAnalysis.grammarNotes.map((note) => <li key={note}>• {note}</li>)}</ul></div>}
                  {current.word.content.sentenceAnalysis.keyExpressions.length > 0 && <div><p className="text-xs font-semibold text-accent">关键表达</p><div className="mt-1 space-y-1.5">{current.word.content.sentenceAnalysis.keyExpressions.map((item) => <div key={item.expression}><p className="text-[13px] font-semibold">{item.expression}</p><ClampedText text={item.meaning + (item.note ? ` · ${item.note}` : "")} className="text-xs leading-relaxed text-secondary-label" /></div>)}</div></div>}
                  {current.word.content.sentenceAnalysis.variations.length > 0 && <div><p className="text-xs font-semibold text-accent">替换句型</p><div className="mt-1 space-y-1.5">{current.word.content.sentenceAnalysis.variations.slice(0, 3).map((item) => <div key={item.sentence} className="rounded-[8px] bg-white/50 px-2.5 py-1.5 dark:bg-white/[0.04]"><ClampedText text={item.sentence} className="text-xs font-medium leading-relaxed" />{item.translation && <ClampedText text={item.translation} className="mt-0.5 text-[11px] text-quaternary-label" />}</div>)}</div></div>}
                </div>}
              </div>}
              {current.word.entryType !== "SENTENCE" && current.word.content.examples[0] && <div className="rounded-[10px] bg-black/[0.02] px-3 py-2 dark:bg-white/[0.03]">
                <button type="button" onClick={() => setRevealSections((s) => ({ ...s, example: !s.example }))} className="flex w-full items-center justify-between text-left">
                  <span className="text-[11px] font-semibold text-tertiary-label">例句</span>
                  <ChevronDown className={`size-3.5 text-tertiary-label transition-transform ${revealSections.example ? "rotate-180" : ""}`} />
                </button>
                {revealSections.example ? <><div className="mt-1.5 flex items-start justify-between gap-2"><p className="text-[13.5px] italic leading-relaxed text-quaternary-label">{current.word.content.examples[0].sentence}</p><button type="button" aria-label="朗读例句" onClick={() => void playCachedTts(current.word.content.examples[0]!.sentence, "US", "sentence")} className="ios-press grid size-6 shrink-0 place-items-center rounded-full bg-accent/[0.08] text-accent transition hover:bg-accent/[0.14] dark:text-[#0a84ff]"><Volume2 className="size-3" /></button></div>{current.word.content.examples[0].translation && <p className="mt-1 text-xs leading-relaxed text-secondary-label">{current.word.content.examples[0].translation}</p>}</> : <p className="mt-1 line-clamp-1 text-[12px] italic text-quaternary-label">{current.word.content.examples[0].sentence}</p>}
              </div>}
              </div>
            </div>
          </div>
        </div>}
        {lastResult && <div className={`mt-3 flex items-center gap-1.5 text-[14px] font-semibold ${lastResult.rating === "EASY" || lastResult.isCorrect ? "text-success" : "text-danger"}`}>{lastResult.rating === "EASY" || lastResult.isCorrect ? <CheckCircle2 className="size-4" /> : <XCircle className="size-4" />}{lastResult.rating === "EASY" ? "已掌握，近期不会再出现" : lastResult.isCorrect ? "已记录" : lastResult.adaptiveFollowUp ? "已加入错词强化，稍后会再次出现" : "已加入错词强化"}</div>}
        {error && <div className="mt-3 rounded-[12px] bg-danger/[0.06] p-2.5 text-xs text-danger-deep">{error}</div>}
        </div>
      </div>
      <div className="shrink-0 pt-1.5 sm:pt-2.5">
      {!revealed ? (current.questionType === "EN_TO_ZH_CHOICE" || current.questionType === "LISTENING_CHOICE" ? <div className="grid grid-cols-[auto_1fr] gap-1.5 sm:gap-2"><Button variant="outline" size="lg" className={studyActionClass} onClick={() => void skip()} disabled={submitting}><Clock3 className="size-4.5" />稍后再学<Kbd className="hidden sm:inline-flex ml-1">S</Kbd></Button><div className="self-center text-center text-xs text-tertiary-label">{hasChoices ? (choicesVisible ? "点击上方选项或按 1-4 作答" : choiceOptionsDelayLabel(choiceRevealDelaySeconds)) : "该词条暂无释义，可稍后再学"}</div></div> : current.questionType === "ZH_TO_EN_CHOICE" ? <div className="grid grid-cols-[auto_1fr] gap-1.5 sm:gap-2"><Button variant="outline" size="lg" className={studyActionClass} onClick={() => void skip()} disabled={submitting}><Clock3 className="size-4.5" />稍后再学<Kbd className="hidden sm:inline-flex ml-1">S</Kbd></Button><div className="self-center text-center text-xs text-tertiary-label">{hasChoices ? (choicesVisible ? "点击候选单词或按 1-4 作答" : choiceOptionsDelayLabel(choiceRevealDelaySeconds)) : "该词条暂无释义，可稍后再学"}</div></div> : current.questionType === "CLOZE_SENTENCE" || current.questionType === "LETTER_BANK" || current.questionType === "ZH_TO_EN_SPELLING" || current.questionType === "LISTENING_SPELLING" ? <div className="flex flex-wrap gap-1.5 sm:gap-2"><Button variant="outline" size="lg" onClick={() => void skip()} disabled={submitting} className={`${studyActionClass} w-[calc(50%-3px)] sm:w-auto`}><Clock3 className="size-4 shrink-0" /><span>稍后再学</span><Kbd className="hidden sm:inline-flex ml-1">S</Kbd></Button><Button variant="outline" size="lg" onClick={() => void reveal()} disabled={submitting} className={`${studyActionClass} w-[calc(50%-3px)] border-danger/20 text-danger hover:bg-danger/[0.06] sm:w-auto`}><XCircle className="size-4 shrink-0" />忘记<Kbd className="hidden sm:inline-flex ml-1">1</Kbd></Button><Button size="lg" className={`${studyActionClass} w-full sm:flex-1`} onClick={() => void reveal()} disabled={submitting || (current.questionType === "LETTER_BANK" ? !builtLetterIds.length : !userAnswer.trim())}><Sparkles className="size-4 shrink-0" /><span>检查答案</span><Kbd className="hidden sm:inline-flex ml-1 bg-white/20 text-white border-white/30">Space</Kbd></Button></div> : <div className="grid grid-cols-[auto_1fr] gap-1.5 sm:gap-2"><Button variant="outline" size="lg" className={studyActionClass} onClick={() => void skip()} disabled={submitting}><Clock3 className="size-4.5" />稍后再学<Kbd className="hidden sm:inline-flex ml-1">S</Kbd></Button><Button size="lg" className={`${studyActionClass} w-full`} onClick={() => void reveal()} disabled={submitting}><Sparkles className="size-4.5" />显示答案<Kbd className="hidden sm:inline-flex ml-1 bg-white/20 text-white border-white/30">Space</Kbd></Button></div>) : <div className="border-t border-black/[0.05] pt-2 sm:pt-2.5 dark:border-white/[0.06]">
        {(current.questionType === "ZH_TO_EN_CHOICE" || current.questionType === "LISTENING_CHOICE" || current.questionType === "EN_TO_ZH_CHOICE") && <p className="mb-1.5 text-center text-[11px] text-quaternary-label sm:mb-2 sm:text-xs">已按“{exactLocal === true ? "认识" : "忘记"}”记录，按数字键或点击熟悉度直接进入下一题</p>}
        <div className="grid grid-cols-2 gap-1.5 sm:grid-cols-4 sm:gap-2">{(["AGAIN", "HARD", "GOOD", "EASY"] as ReviewRating[]).map((rating, rIdx) => { const interval = intervals.find((item) => item.rating === rating); const labels = { AGAIN: "忘记", HARD: "模糊", GOOD: "认识", EASY: "很熟" } as const; const styles = { AGAIN: "border border-danger/20 bg-danger/[0.04] text-danger-deep hover:bg-danger/[0.08] dark:text-danger", HARD: "border border-warning/20 bg-warning/[0.04] text-warning-deep hover:bg-warning/[0.08] dark:text-warning", GOOD: "border border-accent/20 bg-accent/[0.04] text-accent-deep hover:bg-accent/[0.08] dark:text-[#0a84ff]", EASY: "border border-success/20 bg-success/[0.04] text-success-deep hover:bg-success/[0.08] dark:text-success" } as const; const shortcutKey = String(rIdx + 1); return <button key={rating} disabled={submitting} onClick={() => void rate(rating)} className={`ios-press min-h-9.5 rounded-[12px] px-1.5 py-1.5 text-center transition-all duration-150 disabled:opacity-40 sm:min-h-11 sm:rounded-[13px] sm:p-2.5 ${styles[rating]}`}><div className="flex items-center justify-center gap-1.5"><b className="text-[13px] sm:text-[14px]">{labels[rating]}</b><Kbd className="hidden sm:inline-flex text-[9px] px-1">{shortcutKey}</Kbd></div><span className="mt-0.5 block text-[10px] opacity-65 sm:text-[10.5px] num-tabular">{interval ? formatInterval(interval.scheduledDays) : "—"}</span></button>; })}</div></div>}
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
