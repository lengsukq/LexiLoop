"use client";

import { levenshteinDistance, normalizeSentenceAnswer } from "@/modules/reviews/answer-evaluation";

type DiffSegment = { text: string; type: "equal" | "diff" };

function diffCharsSegments(expected: string, actual: string): { expected: DiffSegment[]; actual: DiffSegment[] } {
  const m = expected.length;
  const n = actual.length;
  if (!m || !n) {
    return {
      expected: [{ text: expected, type: expected === actual ? "equal" : "diff" }],
      actual: [{ text: actual, type: expected === actual ? "equal" : "diff" }],
    };
  }
  // Build LCS table
  const dp: number[][] = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
  for (let i = m - 1; i >= 0; i--) {
    for (let j = n - 1; j >= 0; j--) {
      dp[i]![j] = expected[i] === actual[j] ? dp[i + 1]![j + 1]! + 1 : Math.max(dp[i + 1]![j]!, dp[i]![j + 1]!);
    }
  }
  const expectedSegs: DiffSegment[] = [];
  const actualSegs: DiffSegment[] = [];
  let i = 0;
  let j = 0;
  let curE = "";
  let curAType: DiffSegment["type"] = "equal";
  let curA = "";
  let curBType: DiffSegment["type"] = "equal";
  const flushE = (type: DiffSegment["type"]) => {
    if (curE) {
      expectedSegs.push({ text: curE, type });
      curE = "";
    }
  };
  const flushA = (type: DiffSegment["type"]) => {
    if (curA) {
      actualSegs.push({ text: curA, type });
      curA = "";
    }
  };
  // We'll walk and emit char by char grouped by type
  // Simpler: emit per-char segments
  const expChars: Array<{ ch: string; type: DiffSegment["type"] }> = [];
  const actChars: Array<{ ch: string; type: DiffSegment["type"] }> = [];
  while (i < m || j < n) {
    if (i < m && j < n && expected[i] === actual[j]) {
      expChars.push({ ch: expected[i]!, type: "equal" });
      actChars.push({ ch: actual[j]!, type: "equal" });
      i++; j++;
    } else if (j >= n || (i < m && j < n && dp[i + 1]![j]! >= dp[i]![j + 1]!)) {
      expChars.push({ ch: expected[i]!, type: "diff" });
      i++;
    } else {
      actChars.push({ ch: actual[j]!, type: "diff" });
      j++;
    }
  }
  // Group consecutive same-type chars
  for (const c of expChars) {
    if (curAType !== c.type && curE) {
      flushE(curAType);
      curAType = c.type;
    } else if (!curE) curAType = c.type;
    curE += c.ch;
  }
  flushE(curAType);
  for (const c of actChars) {
    if (curBType !== c.type && curA) {
      flushA(curBType);
      curBType = c.type;
    } else if (!curA) curBType = c.type;
    curA += c.ch;
  }
  flushA(curBType);
  return { expected: expectedSegs.length ? expectedSegs : [{ text: expected, type: "equal" }], actual: actualSegs.length ? actualSegs : [{ text: actual, type: "equal" }] };
}

function SegmentLine({ segments, diffClass }: { segments: DiffSegment[]; diffClass: string }) {
  return (
    <span className="break-words">
      {segments.map((seg, idx) => (
        <span
          key={`${idx}-${seg.text}`}
          className={seg.type === "diff" ? diffClass : undefined}
        >
          {seg.text}
        </span>
      ))}
    </span>
  );
}

export function TermDiff({ expected, actual }: { expected: string; actual: string }) {
  const normalizedExpected = expected.trim();
  const normalizedActual = actual.trim();
  if (!normalizedActual) return null;
  if (normalizedExpected.toLocaleLowerCase() === normalizedActual.toLocaleLowerCase()) return null;
  const { expected: expSegs, actual: actSegs } = diffCharsSegments(normalizedExpected, normalizedActual);
  return (
    <div className="mt-2 space-y-1 rounded-[10px] border border-black/[0.06] bg-black/[0.02] px-3 py-2 dark:border-white/[0.06] dark:bg-white/[0.04]">
      <div className="text-xs">
        <span className="font-semibold text-tertiary-label">你的输入：</span>
        <SegmentLine segments={actSegs} diffClass="bg-danger/15 text-danger-deep underline decoration-danger/40 underline-offset-2 dark:text-danger" />
      </div>
      <div className="text-xs">
        <span className="font-semibold text-tertiary-label">正确答案：</span>
        <SegmentLine segments={expSegs} diffClass="bg-success/15 text-success-deep underline decoration-success/40 underline-offset-2 dark:text-success" />
      </div>
    </div>
  );
}

export function SentenceDiff({ expected, actual }: { expected: string; actual: string }) {
  const normExpected = normalizeSentenceAnswer(expected);
  const normActual = normalizeSentenceAnswer(actual);
  if (!normActual) return null;
  if (normExpected === normActual) {
    // Still show if raw differs only by punctuation/case?
    if (expected.trim() === actual.trim()) return null;
  }
  const expWords = normExpected.split(" ");
  const actWords = normActual.split(" ");
  const dist = levenshteinDistance(normExpected, normActual);
  if (dist === 0) return null;
  // Word-level diff via LCS
  const m = expWords.length;
  const n = actWords.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
  for (let i = m - 1; i >= 0; i--) {
    for (let j = n - 1; j >= 0; j--) {
      dp[i]![j] = expWords[i] === actWords[j] ? dp[i + 1]![j + 1]! + 1 : Math.max(dp[i + 1]![j]!, dp[i]![j + 1]!);
    }
  }
  const wordDiff: Array<{ word: string; type: "equal" | "missing" | "extra" }> = [];
  let ii = 0;
  let jj = 0;
  while (ii < m || jj < n) {
    if (ii < m && jj < n && expWords[ii] === actWords[jj]) {
      wordDiff.push({ word: actWords[jj]!, type: "equal" });
      ii++; jj++;
    } else if (jj >= n || (ii < m && jj < n && dp[ii + 1]![jj]! >= dp[ii]![jj + 1]!)) {
      wordDiff.push({ word: expWords[ii]!, type: "missing" });
      ii++;
    } else {
      wordDiff.push({ word: actWords[jj]!, type: "extra" });
      jj++;
    }
  }
  return (
    <div className="mt-2 rounded-[10px] border border-black/[0.06] bg-black/[0.02] px-3 py-2 dark:border-white/[0.06] dark:bg-white/[0.04]">
      <p className="text-[11px] font-semibold text-tertiary-label">逐词对比（红=多/错词，绿=漏词）</p>
      <p className="mt-1 flex flex-wrap gap-1 text-xs leading-relaxed">
        {wordDiff.map((w, idx) => (
          <span
            key={`${idx}-${w.word}`}
            className={
              w.type === "equal"
                ? "text-secondary-label"
                : w.type === "extra"
                  ? "rounded bg-danger/15 px-1 text-danger-deep dark:text-danger"
                  : "rounded bg-success/15 px-1 text-success-deep line-through decoration-success/50 dark:text-success"
            }
          >
            {w.word}
          </span>
        ))}
      </p>
      <p className="mt-2 text-[11px] text-quaternary-label">编辑距离 {dist} · 参考：{expected}</p>
    </div>
  );
}
