"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { errorMessage } from "@/lib/format";
import { apiFetch } from "@/lib/client-api";
import { playCachedTts, preloadTtsBatch } from "@/lib/tts-client";
import { useActiveStopwatch } from "@/lib/use-active-stopwatch";
import { useGameCountdown } from "@/lib/use-game-countdown";
import { useGameScoring } from "@/lib/use-game-scoring";
import type { SummaryItem } from "@/components/game-summary";
import type {
  PhoneticAccent,
  PhoneticAnswerState,
  PhoneticGameItem,
  PhoneticGameResult,
  PhoneticGameSession,
  PhoneticPhase,
} from "./types";
import { correctChoice } from "./choice";

const CORRECT_FEEDBACK_MS = 1_050;
const WRONG_FEEDBACK_MS = 520;

export function usePhoneticGame() {
  const [accent, setAccent] = useState<PhoneticAccent>("US");
  const [phase, setPhase] = useState<PhoneticPhase>("setup");
  const [session, setSession] = useState<PhoneticGameSession | null>(null);
  const [index, setIndex] = useState(0);
  const [wrongChoice, setWrongChoice] = useState<string | null>(null);
  const [correctFeedback, setCorrectFeedback] = useState(false);
  const [audioError, setAudioError] = useState("");
  const [error, setError] = useState("");
  const [result, setResult] = useState<PhoneticGameResult | null>(null);
  const [summaryItems, setSummaryItems] = useState<SummaryItem[]>([]);

  const {
    combo, mistakeCount,
    incrementCombo, recordMistake,
    reset: resetScoring, getMaxCombo, getMistakeCount, hasMistake,
  } = useGameScoring();

  const sessionRef = useRef<PhoneticGameSession | null>(null);
  const answersRef = useRef<Map<number, PhoneticAnswerState>>(new Map());
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
          mistakeCount: getMistakeCount(),
          maxCombo: getMaxCombo(),
        }),
      });
      setResult(saved);
      setPhase("result");
    } catch (reason) {
      setError(errorMessage(reason, "保存音标训练结果失败"));
      setPhase("save-error");
      finishingRef.current = false;
      lockedRef.current = false;
    }
  }, [getMaxCombo, getMistakeCount]);

  const advance = useCallback((item: PhoneticGameItem, solved: boolean) => {
    answersRef.current.set(item.itemId, {
      itemId: item.itemId,
      wordId: item.wordId,
      solved,
      hadMistake: hasMistake(item.itemId) || !solved,
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
  }, [captureItemDuration, finish, hasMistake, index]);

  const { remainingMs, start: startCountdown } = useGameCountdown(phase === "playing" && Boolean(session), () => void finish());

  const choose = useCallback((choice: string) => {
    const item = sessionRef.current?.items[index];
    if (!item || lockedRef.current || wrongChoice || correctFeedback) return;
    if (choice !== correctChoice(item)) {
      recordMistake(item.itemId);
      setWrongChoice(choice);
      if (item.challengeType === "SOUND_TO_PHONETIC") void playCurrent();
      window.setTimeout(() => setWrongChoice(null), WRONG_FEEDBACK_MS);
      return;
    }

    lockedRef.current = true;
    incrementCombo();
    setCorrectFeedback(true);
    void playCurrent();
    advance(item, true);
  }, [advance, correctFeedback, incrementCombo, index, playCurrent, recordMistake, wrongChoice]);

  const skip = useCallback(() => {
    const item = sessionRef.current?.items[index];
    if (!item || lockedRef.current) return;
    lockedRef.current = true;
    recordMistake(item.itemId);
    advance(item, false);
  }, [advance, index, recordMistake]);

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
      finishingRef.current = false;
      lockedRef.current = false;
      autoPlayedRef.current = null;
      resetScoring();
      startCountdown(created.durationSeconds * 1000);
      setSession(created);
      setIndex(0);
      setWrongChoice(null);
      setCorrectFeedback(false);
      setAudioError("");
      setSummaryItems([]);
      setPhase("playing");
    } catch (reason) {
      setError(errorMessage(reason, "创建音标训练失败"));
      setPhase("setup");
    }
  }, [accent, resetScoring, startCountdown]);

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
