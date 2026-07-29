"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { apiFetch } from "@/lib/client-api";
import { playCachedTts, preloadTtsBatch } from "@/lib/tts-client";
import { useActiveStopwatch } from "@/lib/use-active-stopwatch";
import type { SummaryItem } from "@/components/game-summary";
import type {
  PhoneticAccent,
  PhoneticAnswerState,
  PhoneticGameItem,
  PhoneticGameResult,
  PhoneticGameSession,
  PhoneticPhase,
} from "./types";

const CORRECT_FEEDBACK_MS = 1_050;
const WRONG_FEEDBACK_MS = 520;

function expectedChoice(item: PhoneticGameItem): string {
  return item.challengeType === "PHONETIC_TO_WORD" ? item.term : item.phonetic;
}

export function usePhoneticGame() {
  const [accent, setAccent] = useState<PhoneticAccent>("US");
  const [phase, setPhase] = useState<PhoneticPhase>("setup");
  const [session, setSession] = useState<PhoneticGameSession | null>(null);
  const [index, setIndex] = useState(0);
  const [remainingMs, setRemainingMs] = useState(0);
  const [combo, setCombo] = useState(0);
  const [mistakeCount, setMistakeCount] = useState(0);
  const [wrongChoice, setWrongChoice] = useState<string | null>(null);
  const [correctFeedback, setCorrectFeedback] = useState(false);
  const [audioError, setAudioError] = useState("");
  const [error, setError] = useState("");
  const [result, setResult] = useState<PhoneticGameResult | null>(null);
  const [summaryItems, setSummaryItems] = useState<SummaryItem[]>([]);

  const sessionRef = useRef<PhoneticGameSession | null>(null);
  const answersRef = useRef<Map<number, PhoneticAnswerState>>(new Map());
  const mistakeItemsRef = useRef<Set<number>>(new Set());
  const mistakeCountRef = useRef(0);
  const comboRef = useRef(0);
  const maxComboRef = useRef(0);
  const remainingMsRef = useRef(0);
  const deadlineRef = useRef(0);
  const finishingRef = useRef(false);
  const lockedRef = useRef(false);
  const autoPlayedRef = useRef<number | null>(null);

  const current = session?.items[index] ?? null;
  const { reset: resetItemTimer, capture: captureItemDuration } = useActiveStopwatch(Boolean(phase === "playing" && current && !correctFeedback));
  useEffect(() => {
    if (phase !== "playing" || !session) return;
    void preloadTtsBatch(session.items.slice(index, index + 5).map((item) => ({ text: item.term, accent: session.accent })));
  }, [index, phase, session]);

  const playCurrent = useCallback(async () => {
    const item = sessionRef.current?.items[index];
    if (!item) return;
    setAudioError("");
    const played = await playCachedTts(item.term, sessionRef.current?.accent ?? accent);
    if (!played) setAudioError("发音加载失败，请检查网络后重试。");
  }, [accent, index]);

  const finish = useCallback(async () => {
    const activeSession = sessionRef.current;
    if (!activeSession || finishingRef.current) return;
    finishingRef.current = true;
    lockedRef.current = true;
    setPhase("saving");
    setError("");
    const answers = activeSession.items.map((item) => answersRef.current.get(item.itemId) ?? {
      itemId: item.itemId,
      wordId: item.wordId,
      solved: false,
      hadMistake: true,
      durationMs: 0,
    });
    const elapsedMs = answers.reduce((sum, answer) => sum + answer.durationMs, 0);
    setSummaryItems(activeSession.items.map((item) => {
      const answer = answersRef.current.get(item.itemId);
      const solved = answer?.solved ?? false;
      const hadMistake = answer?.hadMistake ?? true;
      return {
        term: item.term,
        definition: item.definition,
        phonetic: item.phonetic,
        status: solved ? (hadMistake ? "recovered" : "correct") : "missed",
      } satisfies SummaryItem;
    }));

    try {
      const saved = await apiFetch<PhoneticGameResult>(`/api/phonetics/sessions/${activeSession.sessionId}/complete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          answers,
          elapsedMs,
          mistakeCount: mistakeCountRef.current,
          maxCombo: maxComboRef.current,
        }),
      });
      setResult(saved);
      setPhase("result");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "保存音标训练结果失败");
      setPhase("save-error");
      finishingRef.current = false;
      lockedRef.current = false;
    }
  }, []);

  const advance = useCallback((item: PhoneticGameItem, solved: boolean) => {
    answersRef.current.set(item.itemId, {
      itemId: item.itemId,
      wordId: item.wordId,
      solved,
      hadMistake: mistakeItemsRef.current.has(item.itemId) || !solved,
      durationMs: captureItemDuration(),
    });
    const activeSession = sessionRef.current;
    if (!activeSession || index >= activeSession.items.length - 1) {
      window.setTimeout(() => void finish(), solved ? CORRECT_FEEDBACK_MS : 260);
      return;
    }
    window.setTimeout(() => {
      setWrongChoice(null);
      setCorrectFeedback(false);
      setAudioError("");
      lockedRef.current = false;
      setIndex((value) => value + 1);
    }, solved ? CORRECT_FEEDBACK_MS : 260);
  }, [captureItemDuration, finish, index]);

  const markMistake = useCallback((item: PhoneticGameItem) => {
    mistakeItemsRef.current.add(item.itemId);
    mistakeCountRef.current += 1;
    comboRef.current = 0;
    setMistakeCount(mistakeCountRef.current);
    setCombo(0);
  }, []);

  const choose = useCallback((choice: string) => {
    const item = sessionRef.current?.items[index];
    if (!item || lockedRef.current || wrongChoice || correctFeedback) return;
    if (choice !== expectedChoice(item)) {
      markMistake(item);
      setWrongChoice(choice);
      if (item.challengeType === "SOUND_TO_PHONETIC") void playCurrent();
      window.setTimeout(() => setWrongChoice(null), WRONG_FEEDBACK_MS);
      return;
    }

    lockedRef.current = true;
    const nextCombo = comboRef.current + 1;
    comboRef.current = nextCombo;
    maxComboRef.current = Math.max(maxComboRef.current, nextCombo);
    setCombo(nextCombo);
    setCorrectFeedback(true);
    void playCurrent();
    advance(item, true);
  }, [advance, correctFeedback, index, markMistake, playCurrent, wrongChoice]);

  const skip = useCallback(() => {
    const item = sessionRef.current?.items[index];
    if (!item || lockedRef.current) return;
    lockedRef.current = true;
    markMistake(item);
    advance(item, false);
  }, [advance, index, markMistake]);

  const start = useCallback(async () => {
    setPhase("loading");
    setError("");
    setResult(null);
    try {
      const created = await apiFetch<PhoneticGameSession>("/api/phonetics/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ accent }),
      });
      sessionRef.current = created;
      answersRef.current = new Map();
      mistakeItemsRef.current = new Set();
      mistakeCountRef.current = 0;
      comboRef.current = 0;
      maxComboRef.current = 0;
      remainingMsRef.current = created.durationSeconds * 1000;
      deadlineRef.current = Date.now() + created.durationSeconds * 1000;
      finishingRef.current = false;
      lockedRef.current = false;
      autoPlayedRef.current = null;
      setSession(created);
      setIndex(0);
      setRemainingMs(created.durationSeconds * 1000);
      setCombo(0);
      setMistakeCount(0);
      setWrongChoice(null);
      setCorrectFeedback(false);
      setAudioError("");
      setSummaryItems([]);
      setPhase("playing");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "创建音标训练失败");
      setPhase("setup");
    }
  }, [accent]);

  useEffect(() => {
    if (phase !== "playing" || !session) return;
    const tick = () => {
      const next = Math.max(0, deadlineRef.current - Date.now());
      remainingMsRef.current = next;
      setRemainingMs(next);
      if (next <= 0) void finish();
    };
    tick();
    const timer = window.setInterval(tick, 200);
    return () => window.clearInterval(timer);
  }, [finish, phase, session]);

  useEffect(() => {
    if (!current) return;
    resetItemTimer();
    if (current.challengeType !== "SOUND_TO_PHONETIC" || autoPlayedRef.current === current.itemId) return;
    autoPlayedRef.current = current.itemId;
    const timer = window.setTimeout(() => void playCurrent(), 180);
    return () => window.clearTimeout(timer);
  }, [current, playCurrent, resetItemTimer]);

  const exit = useCallback(() => {
    sessionRef.current = null;
    setSession(null);
    setResult(null);
    setPhase("setup");
    setError("");
  }, []);

  return {
    accent,
    setAccent,
    phase,
    session,
    current,
    index,
    remainingMs,
    combo,
    mistakeCount,
    wrongChoice,
    correctFeedback,
    audioError,
    error,
    result,
    summaryItems,
    start,
    finish,
    choose,
    skip,
    playCurrent,
    exit,
  };
}
