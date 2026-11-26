"use client";

import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Shared countdown timer for practice games.
 *
 * Call `start(durationMs)` when a session begins. While `active` is true the
 * remaining time ticks down every `tickMs` and `onExpire` fires once at zero.
 * `pause`/`resume` freeze the deadline (used by WORD_BUILDER's reveal flow);
 * games that do not pause simply never call them.
 */
export function useGameCountdown(active: boolean, onExpire: () => void, tickMs = 200) {
  const [remainingMs, setRemainingMs] = useState(0);
  const deadlineRef = useRef(0);
  const pausedRef = useRef(false);
  const pausedAtRef = useRef(0);
  const onExpireRef = useRef(onExpire);

  useEffect(() => {
    onExpireRef.current = onExpire;
  }, [onExpire]);

  const start = useCallback((durationMs: number) => {
    deadlineRef.current = Date.now() + durationMs;
    pausedRef.current = false;
    pausedAtRef.current = 0;
    setRemainingMs(durationMs);
  }, []);

  const pause = useCallback(() => {
    pausedAtRef.current = Date.now();
    pausedRef.current = true;
  }, []);

  const resume = useCallback(() => {
    deadlineRef.current += Date.now() - pausedAtRef.current;
    pausedRef.current = false;
  }, []);

  useEffect(() => {
    if (!active) return;
    const tick = () => {
      if (pausedRef.current) return;
      const next = Math.max(0, deadlineRef.current - Date.now());
      setRemainingMs(next);
      if (next <= 0) onExpireRef.current();
    };
    tick();
    const timer = window.setInterval(tick, tickMs);
    return () => window.clearInterval(timer);
  }, [active, tickMs]);

  return { remainingMs, start, pause, resume };
}
