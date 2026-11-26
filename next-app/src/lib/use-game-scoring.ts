"use client";

import { useCallback, useRef, useState } from "react";

/**
 * Shared combo / mistake tracking for practice games.
 *
 * - `incrementCombo` bumps the combo and records the running max.
 * - `recordMistake(...ids)` flags the items, bumps the mistake counter and
 *   resets the combo (the common "wrong answer" path).
 * - `flagMistakeItems(...ids)` + `resetCombo()` flag items without bumping the
 *   counter (WORD_BUILDER's advanceFailed path, which must not count a mistake).
 * Ref-backed getters expose the latest values to the async finish flow.
 */
export function useGameScoring() {
  const [combo, setCombo] = useState(0);
  const [mistakeCount, setMistakeCount] = useState(0);
  const comboRef = useRef(0);
  const maxComboRef = useRef(0);
  const mistakeCountRef = useRef(0);
  const mistakeItemsRef = useRef<Set<number>>(new Set());

  const incrementCombo = useCallback(() => {
    const next = comboRef.current + 1;
    comboRef.current = next;
    maxComboRef.current = Math.max(maxComboRef.current, next);
    setCombo(next);
  }, []);

  const resetCombo = useCallback(() => {
    comboRef.current = 0;
    setCombo(0);
  }, []);

  const flagMistakeItems = useCallback((...itemIds: number[]) => {
    for (const id of itemIds) mistakeItemsRef.current.add(id);
  }, []);

  const bumpMistakeCount = useCallback(() => {
    mistakeCountRef.current += 1;
    setMistakeCount(mistakeCountRef.current);
  }, []);

  const recordMistake = useCallback((...itemIds: number[]) => {
    flagMistakeItems(...itemIds);
    bumpMistakeCount();
    resetCombo();
  }, [flagMistakeItems, bumpMistakeCount, resetCombo]);

  const reset = useCallback(() => {
    comboRef.current = 0;
    maxComboRef.current = 0;
    mistakeCountRef.current = 0;
    mistakeItemsRef.current = new Set();
    setCombo(0);
    setMistakeCount(0);
  }, []);

  const getMaxCombo = useCallback(() => maxComboRef.current, []);
  const getMistakeCount = useCallback(() => mistakeCountRef.current, []);
  const hasMistake = useCallback((itemId: number) => mistakeItemsRef.current.has(itemId), []);

  return {
    combo,
    mistakeCount,
    incrementCombo,
    resetCombo,
    flagMistakeItems,
    bumpMistakeCount,
    recordMistake,
    reset,
    getMaxCombo,
    getMistakeCount,
    hasMistake,
  };
}
