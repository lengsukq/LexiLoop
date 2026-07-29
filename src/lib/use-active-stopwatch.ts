"use client";

import { useCallback, useEffect, useRef } from "react";

export const ACTIVE_IDLE_TIMEOUT_MS = 45_000;

/**
 * Tracks foreground interaction time instead of wall-clock time.
 * Time pauses when the page is hidden, the window loses focus, or no supported
 * user interaction is observed for the idle timeout.
 */
export function useActiveStopwatch(enabled: boolean, idleTimeoutMs = ACTIVE_IDLE_TIMEOUT_MS) {
  const enabledRef = useRef(enabled);
  const accumulatedMsRef = useRef(0);
  const activeSinceRef = useRef<number | null>(null);
  const lastActivityAtRef = useRef(0);
  const idleTimerRef = useRef<number | null>(null);

  const clearIdleTimer = useCallback(() => {
    if (idleTimerRef.current !== null) {
      window.clearTimeout(idleTimerRef.current);
      idleTimerRef.current = null;
    }
  }, []);

  const stopActiveSegment = useCallback((now = Date.now()) => {
    const activeSince = activeSinceRef.current;
    if (activeSince === null) return;
    const idleCutoff = lastActivityAtRef.current > 0
      ? lastActivityAtRef.current + idleTimeoutMs
      : now;
    const activeUntil = Math.max(activeSince, Math.min(now, idleCutoff));
    accumulatedMsRef.current += activeUntil - activeSince;
    activeSinceRef.current = null;
    clearIdleTimer();
  }, [clearIdleTimer, idleTimeoutMs]);

  const scheduleIdlePause = useCallback(() => {
    clearIdleTimer();
    const delay = Math.max(0, lastActivityAtRef.current + idleTimeoutMs - Date.now());
    idleTimerRef.current = window.setTimeout(() => stopActiveSegment(Date.now()), delay);
  }, [clearIdleTimer, idleTimeoutMs, stopActiveSegment]);

  const resume = useCallback(() => {
    if (!enabledRef.current || document.visibilityState !== "visible" || !document.hasFocus()) return;
    const now = Date.now();
    lastActivityAtRef.current = now;
    if (activeSinceRef.current === null) activeSinceRef.current = now;
    scheduleIdlePause();
  }, [scheduleIdlePause]);

  const pause = useCallback(() => {
    stopActiveSegment(Date.now());
  }, [stopActiveSegment]);

  const reset = useCallback(() => {
    accumulatedMsRef.current = 0;
    activeSinceRef.current = null;
    lastActivityAtRef.current = 0;
    clearIdleTimer();
    resume();
  }, [clearIdleTimer, resume]);

  const elapsedMs = useCallback(() => {
    const activeSince = activeSinceRef.current;
    if (activeSince === null) return Math.max(0, Math.round(accumulatedMsRef.current));
    const now = Date.now();
    const activeUntil = Math.max(activeSince, Math.min(now, lastActivityAtRef.current + idleTimeoutMs));
    return Math.max(0, Math.round(accumulatedMsRef.current + activeUntil - activeSince));
  }, [idleTimeoutMs]);

  const capture = useCallback(() => {
    stopActiveSegment(Date.now());
    return Math.max(0, Math.round(accumulatedMsRef.current));
  }, [stopActiveSegment]);

  useEffect(() => {
    enabledRef.current = enabled;
    if (enabled) resume();
    else pause();
  }, [enabled, pause, resume]);

  useEffect(() => {
    const activity = () => resume();
    const visibility = () => {
      if (document.visibilityState === "visible") resume();
      else pause();
    };

    window.addEventListener("focus", resume);
    window.addEventListener("blur", pause);
    window.addEventListener("pointerdown", activity, { passive: true });
    window.addEventListener("keydown", activity);
    window.addEventListener("touchstart", activity, { passive: true });
    window.addEventListener("wheel", activity, { passive: true });
    window.addEventListener("scroll", activity, { passive: true, capture: true });
    document.addEventListener("visibilitychange", visibility);

    return () => {
      window.removeEventListener("focus", resume);
      window.removeEventListener("blur", pause);
      window.removeEventListener("pointerdown", activity);
      window.removeEventListener("keydown", activity);
      window.removeEventListener("touchstart", activity);
      window.removeEventListener("wheel", activity);
      window.removeEventListener("scroll", activity, true);
      document.removeEventListener("visibilitychange", visibility);
      pause();
    };
  }, [pause, resume]);

  return { reset, pause, resume, elapsedMs, capture };
}
