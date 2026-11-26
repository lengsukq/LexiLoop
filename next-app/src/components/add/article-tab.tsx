"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { AlertCircle, ArrowRight, CheckCircle2, FileText, Loader2, Sparkles, Wand2, BookOpen, Layers, MessageSquareText, RefreshCw } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { entryTypeLabel } from "@/lib/entry-type-label";
import { errorMessage } from "@/lib/format";
import { MAX_ARTICLE_CHARS, MIN_ARTICLE_CHARS, ARTICLE_MAX_SEGMENTS, ARTICLE_SEGMENTS_PER_BATCH_MAX, ARTICLE_SEGMENT_CONCURRENCY, ARTICLE_SEGMENT_PREVIEW_CHARS } from "@/lib/config";
import type { AppSettings, ArticleCandidate, ArticleImportPreview, ExamTarget, ImportMode } from "@/lib/types";
import { EXAM_TARGETS } from "@/lib/types";
import { Alert, Badge, Button, Card, CardContent, CardHeader, CardTitle, buttonClass, toast } from "@/components/ui";
import { articleCandidateKey as candidateKey, initialSelectionKeys, mergeArticlePreviews } from "@/modules/article-import/candidates";
import { segmentArticleParagraphs, batchesForSegments } from "@/modules/article-import/extract";

interface CommitResult {
  batchId: number;
  createdWords: number;
  existingWords: number;
  queuedInitializations: number;
}

interface SegmentPlanResponse {
  segments: Array<{ id: string; index: number; charCount: number; preview: string }>;
  totalSegments: number;
  totalChars: number;
  suggestedBatches: number;
  batches: Array<{ batchIndex: number; segmentIds: string[]; charCount: number }>;
}

type SegmentStatus = "idle" | "loading" | "success" | "error";
interface SegmentState {
  id: string;
  index: number;
  text: string;
  charCount: number;
  previewText: string;
  status: SegmentStatus;
  preview?: ArticleImportPreview | null;
  error?: string | null;
}

const SAMPLE_ARTICLE =
  "The rapid advancement of artificial intelligence has profoundly reshaped how we acquire knowledge. While conventional rote memorization emphasizes repetition, contemporary cognitive science suggests that contextual learning—encountering vocabulary within authentic discourse—yields more durable retention. Nevertheless, learners often feel overwhelmed when faced with an entire article replete with unfamiliar terminology. An intelligent system that discerns which words merit attention, based on the learner's existing lexicon, can transform a daunting passage into a curated learning experience.";

const EXAM_LABEL: Record<ExamTarget, string> = { CET4: "CET-4", CET6: "CET-6", KY: "考研", IELTS: "雅思", TOEFL: "托福" };

function keyLabel(et: string): string {
  return entryTypeLabel(et);
}
function keyTone(et: string): "slate" | "blue" | "purple" {
  return et === "PHRASE" ? "blue" : et === "SENTENCE" ? "purple" : "slate";
}

function mergePreviews(previews: ArticleImportPreview[]): ArticleImportPreview | null {
  // 共用 candidates.ts 的合并（含 aiError 按 token 去重），避免增量/重试/服务端三处漂移。
  return mergeArticlePreviews(previews);
}

export default function ArticleTab({ onImported }: { onImported?: () => void }) {
  const [articleText, setArticleText] = useState("");
  const [preview, setPreview] = useState<ArticleImportPreview | null>(null);
  const [mergedPreview, setMergedPreview] = useState<ArticleImportPreview | null>(null);
  const [finalToken, setFinalToken] = useState<string | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [mode, setMode] = useState<ImportMode>("FILL_MISSING");
  const [reset, setReset] = useState(false);
  const [step, setStep] = useState<"input" | "analyzing" | "preview" | "committing" | "success">("input");
  const [error, setError] = useState("");
  const [result, setResult] = useState<CommitResult | null>(null);
  const [filter, setFilter] = useState<"all" | "WORD" | "PHRASE" | "SENTENCE">("all");
  const [showRecommendedOnly, setShowRecommendedOnly] = useState(false);
  const [examTargets, setExamTargets] = useState<ExamTarget[]>([]);
  const [examTargetsLoaded, setExamTargetsLoaded] = useState(false);
  const [segmentsPerBatch, setSegmentsPerBatch] = useState(1);
  const [segmentPlan, setSegmentPlan] = useState<SegmentPlanResponse | null>(null);
  const [segments, setSegments] = useState<SegmentState[]>([]);
  const [useSegmented, setUseSegmented] = useState(false);
  const [batchProgress, setBatchProgress] = useState<{ done: number; total: number; failed: number } | null>(null);

  const charCount = articleText.length;
  const canAnalyze = charCount >= MIN_ARTICLE_CHARS && charCount <= MAX_ARTICLE_CHARS;

  const localPlan = useMemo(() => {
    if (!articleText || articleText.trim().length < MIN_ARTICLE_CHARS) return null;
    try {
      const segs = segmentArticleParagraphs(articleText, { maxSegments: ARTICLE_MAX_SEGMENTS });
      if (segs.length === 0) return null;
      const perBatch = Math.max(1, Math.min(ARTICLE_SEGMENTS_PER_BATCH_MAX, segmentsPerBatch));
      const batches = batchesForSegments(segs, perBatch);
      return {
        segments: segs.map((s) => ({ id: s.id, index: s.index, charCount: s.charCount, preview: s.text.slice(0, ARTICLE_SEGMENT_PREVIEW_CHARS) })),
        totalSegments: segs.length,
        totalChars: articleText.length,
        batches,
        rawSegments: segs,
      };
    } catch {
      return null;
    }
  }, [articleText, segmentsPerBatch]);

  useEffect(() => {
    if (!localPlan) {
      setSegmentPlan(null);
      return;
    }
    setSegmentPlan({
      segments: localPlan.segments,
      totalSegments: localPlan.totalSegments,
      totalChars: localPlan.totalChars,
      suggestedBatches: Math.ceil(localPlan.totalSegments / 2),
      batches: localPlan.batches,
    });
  }, [localPlan]);

  const totalBatches = segmentPlan?.batches.length ?? 0;

  useEffect(() => {
    let cancelled = false;
    apiFetch<AppSettings>("/api/settings")
      .then((s) => {
        if (cancelled) return;
        setExamTargets(s.examTargets ?? []);
        setExamTargetsLoaded(true);
      })
      .catch(() => {
        if (!cancelled) setExamTargetsLoaded(true);
      });
    return () => { cancelled = true; };
  }, []);

  function toggleExamTarget(target: ExamTarget) {
    setExamTargets((prev) => (prev.includes(target) ? prev.filter((t) => t !== target) : [...prev, target]));
  }

  const displayPreview = mergedPreview ?? preview;

  const grouped = useMemo(() => {
    if (!displayPreview) return { words: [] as ArticleCandidate[], phrases: [] as ArticleCandidate[], sentences: [] as ArticleCandidate[] };
    const words = displayPreview.candidates.filter((c) => (c.entryType ?? "WORD") === "WORD");
    const phrases = displayPreview.candidates.filter((c) => c.entryType === "PHRASE");
    const sentences = displayPreview.candidates.filter((c) => c.entryType === "SENTENCE");
    return { words, phrases, sentences };
  }, [displayPreview]);

  const candidateCount = displayPreview?.candidates.filter((c) => c.status === "CANDIDATE").length ?? 0;
  const recommendedKeys = useMemo(() => {
    if (!displayPreview) return new Set<string>();
    if (displayPreview.recommendedKeys?.length) return new Set(displayPreview.recommendedKeys.map((k) => k.toLowerCase()));
    return new Set(displayPreview.recommendedTerms.map((t) => t.toLowerCase()));
  }, [displayPreview]);

  const visibleCandidates = useMemo(() => {
    if (!displayPreview) return [] as ArticleCandidate[];
    let list = displayPreview.candidates;
    if (filter !== "all") list = list.filter((c) => (c.entryType ?? "WORD") === filter);
    if (showRecommendedOnly && displayPreview.aiApplied) {
      list = list.filter((c) => c.status === "KNOWN" || recommendedKeys.has(candidateKey(c).toLowerCase()) || recommendedKeys.has(c.normalizedTerm.toLowerCase()));
    }
    return list;
  }, [displayPreview, filter, showRecommendedOnly, recommendedKeys]);

  // 依赖必须是 segments 本身：若直接在渲染期 filter 出新数组，useMemo 每次渲染都会
  // 重新合并出新对象，与下方 effect（已移除）形成无限重渲染循环，卡死整页。
  const successSegments = useMemo(() => segments.filter((s) => s.status === "success" && s.preview), [segments]);
  const mergedFromSegments = useMemo(() => {
    if (!useSegmented || successSegments.length === 0) return null;
    return mergePreviews(successSegments.map((s) => s.preview!));
  }, [useSegmented, successSegments]);

  const effectivePreview = mergedFromSegments ?? displayPreview;

  function applyPreviewSelection(data: ArticleImportPreview) {
    const aiCandidateKeys = initialSelectionKeys(data);
    setSelected((prev) => {
      if (prev.size === 0) return aiCandidateKeys;
      const next = new Set(prev);
      for (const k of aiCandidateKeys) next.add(k);
      return next;
    });
  }

  async function analyzeSingle() {
    if (!canAnalyze) {
      setError(`文章至少需要 ${MIN_ARTICLE_CHARS} 个字符，且不能超过 ${MAX_ARTICLE_CHARS} 字符。`);
      return;
    }
    setError("");
    setStep("analyzing");
    setUseSegmented(false);
    setSegments([]);
    setMergedPreview(null);
    setFinalToken(null);
    try {
      const data = await apiFetch<ArticleImportPreview>("/api/article-import/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ articleText, examTargets: examTargets.length ? examTargets : undefined }),
      });
      setPreview(data);
      setFinalToken(data.previewToken);
      setSelected(initialSelectionKeys(data));
      const phraseOrSentenceCount = data.candidates.filter((c) => c.entryType === "PHRASE" || c.entryType === "SENTENCE").length;
      setShowRecommendedOnly(Boolean(data.aiApplied && phraseOrSentenceCount === 0 && data.recommendedTerms.length > 0 && data.recommendedTerms.length < data.candidates.filter((c) => c.status === "CANDIDATE").length));
      setStep("preview");
      const phraseCount = data.candidates.filter((c) => c.entryType === "PHRASE").length;
      const sentenceCount = data.candidates.filter((c) => c.entryType === "SENTENCE").length;
      toast.success(`已提取 ${data.articleStats.uniqueCount} 去重词${phraseCount ? ` · 短语 ${phraseCount}` : ""}${sentenceCount ? ` · 句子 ${sentenceCount}` : ""}，AI 已筛选`, "分析完成");
    } catch (reason) {
      setStep("input");
      setError(errorMessage(reason, "分析文章失败"));
    }
  }

  async function analyzeSegmented() {
    const plan = localPlan;
    if (!plan || !canAnalyze) {
      setError(`文章至少需要 ${MIN_ARTICLE_CHARS} 个字符。`);
      return;
    }
    setError("");
    setPreview(null);
    setMergedPreview(null);
    setFinalToken(null);
    setSelected(new Set());
    setFilter("all");
    setShowRecommendedOnly(false);
    const segs: SegmentState[] = plan.rawSegments.map((s) => ({
      id: s.id,
      index: s.index,
      text: s.text,
      charCount: s.charCount,
      previewText: s.text.slice(0, ARTICLE_SEGMENT_PREVIEW_CHARS),
      status: "idle" as SegmentStatus,
      preview: null,
      error: null,
    }));
    setSegments(segs);
    setUseSegmented(true);
    setStep("analyzing");
    const perBatch = Math.max(1, Math.min(ARTICLE_SEGMENTS_PER_BATCH_MAX, segmentsPerBatch));
    const batches = batchesForSegments(plan.rawSegments, perBatch);
    setBatchProgress({ done: 0, total: batches.length, failed: 0 });

    // helper to fetch one batch
    const fetchBatch = async (batch: { batchIndex: number; segmentIds: string[] }, batchSegs: SegmentState[]) => {
      const combinedText = batchSegs.map((s) => s.text).join("\n\n");
      const data = await apiFetch<ArticleImportPreview>("/api/article-import/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ articleText: combinedText, examTargets: examTargets.length ? examTargets : undefined }),
      });
      return data;
    };

    // concurrency 3
    const concurrency = ARTICLE_SEGMENT_CONCURRENCY;
    let nextBatchIdx = 0;
    let done = 0;
    let failed = 0;
    const batchResults = new Map<number, ArticleImportPreview>();
    const batchErrors = new Map<number, string>();

    const getNext = () => {
      if (nextBatchIdx >= batches.length) return null;
      const b = batches[nextBatchIdx]!;
      nextBatchIdx += 1;
      return b;
    };

    const runWorker = async () => {
      while (true) {
        const batch = getNext();
        if (!batch) return;
        const batchSegs = segs.filter((s) => batch.segmentIds.includes(s.id));
        setSegments((prev) => prev.map((s) => (batch.segmentIds.includes(s.id) ? { ...s, status: "loading" as SegmentStatus, error: null } : s)));
        try {
          const data = await fetchBatch(batch, batchSegs);
          batchResults.set(batch.batchIndex, data);
          // mark segments in this batch as success (share same preview per batch slice: we attribute whole batch preview)
          setSegments((prev) => prev.map((s) => (batch.segmentIds.includes(s.id) ? { ...s, status: "success" as SegmentStatus, preview: data, error: null } : s)));
          done += 1;
          setBatchProgress({ done, total: batches.length, failed });
          // incremental merge: update mergedPreview immediately so table shows as soon as any batch succeeds
          const previews = Array.from(batchResults.values());
          const merged = mergePreviews(previews);
          if (merged) {
            setMergedPreview(merged);
            // auto-select incrementally
            applyPreviewSelection(merged);
            if (previews.length === 1) {
              setPreview(merged);
            }
          }
        } catch (reason) {
          const msg = errorMessage(reason, "分析失败");
          batchErrors.set(batch.batchIndex, msg);
          setSegments((prev) => prev.map((s) => (batch.segmentIds.includes(s.id) ? { ...s, status: "error" as SegmentStatus, error: msg } : s)));
          failed += 1;
          setBatchProgress({ done, total: batches.length, failed });
        }
      }
    };

    const workers = Array.from({ length: Math.min(concurrency, batches.length) }, () => runWorker());
    await Promise.all(workers);

    if (batchResults.size === 0) {
      setStep("input");
      setError(batchErrors.values().next().value ?? "所有段落均分析失败，请重试。");
      return;
    }
    const previews = Array.from(batchResults.values());
    // try server merge to get a single commit token
    try {
      const tokens = previews.map((p) => p.previewToken);
      const mergedServer = await apiFetch<ArticleImportPreview>("/api/article-import/merge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ tokens }),
      });
      setPreview(mergedServer);
      setMergedPreview(mergedServer);
      setFinalToken(mergedServer.previewToken);
      applyPreviewSelection(mergedServer);
      setStep("preview");
      toast.success(`分 ${batches.length} 批完成 · 成功 ${batchResults.size} 批 · 已合并 ${mergedServer.candidates.filter((c) => c.status === "CANDIDATE").length} 个待学`, "分析完成");
    } catch {
      // fallback: use client-merged preview; commit will fail without merged token so we keep first token as fallback
      const merged = mergePreviews(previews);
      if (merged) {
        setPreview(merged);
        setMergedPreview(merged);
        setFinalToken(merged.previewToken);
        applyPreviewSelection(merged);
      }
      setStep("preview");
      if (failed > 0) toast.success(`已完成 ${batchResults.size}/${batches.length} 批，${failed} 批失败可重试`, "部分完成");
      else toast.success("分析完成", "已完成");
    }
  }

  async function retryBatch(batchIndex: number) {
    const plan = localPlan;
    if (!plan) return;
    const batch = plan.batches.find((b) => b.batchIndex === batchIndex);
    if (!batch) return;
    const batchSegs = segments.filter((s) => batch.segmentIds.includes(s.id));
    if (batchSegs.length === 0) return;
    setSegments((prev) => prev.map((s) => (batch.segmentIds.includes(s.id) ? { ...s, status: "loading" as SegmentStatus, error: null } : s)));
    setError("");
    try {
      const combinedText = batchSegs.map((s) => s.text).join("\n\n");
      const data = await apiFetch<ArticleImportPreview>("/api/article-import/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ articleText: combinedText, examTargets: examTargets.length ? examTargets : undefined }),
      });
      setSegments((prev) => prev.map((s) => (batch.segmentIds.includes(s.id) ? { ...s, status: "success" as SegmentStatus, preview: data, error: null } : s)));
      // re-merge all success previews + new one (segments state is stale in this closure, so take
      // other batches' previews from state and add the just-fetched one manually)
      const otherSuccess = segments.filter((s) => s.status === "success" && s.preview && !batch.segmentIds.includes(s.id)).map((s) => s.preview!);
      const dedupTokens = new Map<string, ArticleImportPreview>();
      for (const p of [...otherSuccess, data]) dedupTokens.set(p.previewToken, p);
      const merged = mergePreviews(Array.from(dedupTokens.values()));
      if (merged) {
        setMergedPreview(merged);
        setPreview(merged);
        applyPreviewSelection(merged);
      }
      // update batch progress
      setBatchProgress((prev) => (prev ? { ...prev, failed: Math.max(0, prev.failed - 1), done: prev.done + 1 } : prev));
      // try server merge again
      try {
        const tokens = Array.from(dedupTokens.values()).map((p) => p.previewToken);
        const mergedServer = await apiFetch<ArticleImportPreview>("/api/article-import/merge", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ tokens }),
        });
        setPreview(mergedServer);
        setMergedPreview(mergedServer);
        setFinalToken(mergedServer.previewToken);
        applyPreviewSelection(mergedServer);
        toast.success("该批已重试成功并重新合并", "已更新");
      } catch {
        // keep client merged
        if (merged) setFinalToken(merged.previewToken);
      }
    } catch (reason) {
      const msg = errorMessage(reason, "重试失败");
      setSegments((prev) => prev.map((s) => (batch.segmentIds.includes(s.id) ? { ...s, status: "error" as SegmentStatus, error: msg } : s)));
      setError(msg);
    }
  }

  async function retryFailedBatches() {
    const failedBatchIndices = new Set<number>();
    for (const s of segments) if (s.status === "error") {
      const b = localPlan?.batches.find((batch) => batch.segmentIds.includes(s.id));
      if (b) failedBatchIndices.add(b.batchIndex);
    }
    for (const idx of failedBatchIndices) await retryBatch(idx);
  }

  /** AI 回退的批次：请求成功但 aiError 非空（AI 筛选失败，降级为本地结果）。 */
  function aiFallbackBatchIndices(): number[] {
    const indices = new Set<number>();
    for (const s of segments) {
      if (s.status !== "success" || !s.preview?.aiError) continue;
      const b = localPlan?.batches.find((batch) => batch.segmentIds.includes(s.id));
      if (b) indices.add(b.batchIndex);
    }
    return [...indices];
  }

  async function retryAiFallbackBatches() {
    for (const idx of aiFallbackBatchIndices()) await retryBatch(idx);
  }

  function toggleKey(key: string) {
    const k = key.toLowerCase();
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(k)) next.delete(k);
      else next.add(k);
      return next;
    });
  }

  function selectAllVisible() {
    const src = effectivePreview;
    if (!src) return;
    const keys = visibleCandidates.filter((c) => c.status === "CANDIDATE").map((c) => candidateKey(c).toLowerCase());
    setSelected((prev) => {
      const next = new Set(prev);
      for (const k of keys) next.add(k);
      return next;
    });
  }

  function selectRecommended() {
    const src = effectivePreview;
    if (!src) return;
    const keys = src.recommendedKeys?.length ? src.recommendedKeys.map((k) => k.toLowerCase()) : [];
    if (keys.length) {
      setSelected(new Set(keys));
      return;
    }
    setSelected(new Set(src.recommendedTerms.map((term) => `WORD\u0000${term.toLowerCase()}`)));
  }

  function clearSelection() {
    setSelected(new Set());
  }

  async function commit() {
    const token = finalToken ?? preview?.previewToken ?? mergedPreview?.previewToken;
    if (!token) return;
    if (selected.size === 0) {
      setError("请至少选择一个词条再导入。");
      return;
    }
    setStep("committing");
    setError("");
    try {
      const data = await apiFetch<CommitResult>("/api/article-import/commit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          previewToken: token,
          selectedKeys: [...selected],
          mode,
          resetLearningProgress: reset,
        }),
      });
      setResult(data);
      setStep("success");
      onImported?.();
      toast.success(`成功导入 ${data.createdWords} 个新词条！`, "导入完成");
    } catch (reason) {
      setStep("preview");
      setError(errorMessage(reason, "提交导入失败"));
    }
  }

  function restart() {
    setStep("input");
    setPreview(null);
    setMergedPreview(null);
    setFinalToken(null);
    setResult(null);
    setError("");
    setSelected(new Set());
    setShowRecommendedOnly(false);
    setFilter("all");
    setSegments([]);
    setUseSegmented(false);
    setBatchProgress(null);
  }

  function ImportStrategyCard() {
    return (
      <Card>
        <CardHeader>
          <CardTitle>导入策略</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid gap-3 lg:grid-cols-3">
            {[
              { value: "FILL_MISSING", title: "智能补充", description: "新增词条，并给已有词条补充缺失的释义、发音和例句。" },
              { value: "SKIP_EXISTING", title: "仅新增", description: "已有词条完全跳过，不创建初始化任务。" },
              { value: "FORCE_DICTIONARY_REFRESH", title: "强制刷新", description: "重新查询已有词条的词典内容，但保留学习进度。" },
            ].map((item) => (
              <label key={item.value} className={`cursor-pointer rounded-[18px] border p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm transition ${mode === item.value ? "border-accent/40 bg-accent/[0.06] ring-2 ring-accent/15" : "border-white/50 bg-white/40 hover:border-white/70 dark:border-white/[0.08] dark:bg-white/[0.04]"}`}>
                <input className="sr-only" type="radio" name="article-mode" checked={mode === item.value} onChange={() => setMode(item.value as ImportMode)} />
                <b className="text-sm">{item.title}</b>
                <p className="mt-1 text-xs leading-5 text-secondary-label">{item.description}</p>
              </label>
            ))}
          </div>
          <label className="flex items-start gap-3 rounded-[18px] border border-danger/20 bg-danger/[0.05] p-4 text-sm shadow-[0_4px_16px_rgba(255,59,48,0.04)] backdrop-blur-sm">
            <input type="checkbox" className="mt-1 accent-danger" checked={reset} onChange={(event) => setReset(event.target.checked)} />
            <span>
              <b className="text-danger-deep">重置本次已有词条的学习进度</b>
              <span className="mt-1 block text-xs text-danger/70">删除复习卡、复习日志和错词状态，词典内容不会删除。</span>
            </span>
          </label>
          {error && <Alert tone="danger" icon={<AlertCircle className="size-4" />}>{error}</Alert>}
          <div className="flex justify-end">
            <Button size="lg" onClick={() => void commit()} disabled={selected.size === 0 || !effectivePreview}>
              确认导入 {selected.size} 个
              <ArrowRight className="size-5" />
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (step === "analyzing") {
    const hasSegmented = useSegmented && segments.length > 0;
    return (
      <div className="space-y-4">
        <Card>
          <CardContent className="py-10 text-center">
            <Loader2 className="mx-auto size-9 animate-spin text-accent" />
            <p className="mt-3 text-sm font-medium text-label">
              {hasSegmented ? `正在分批分析… ${batchProgress ? `${batchProgress.done}/${batchProgress.total} 批完成` : ""}` : "正在分析文章并匹配你的词汇量…"}
            </p>
            <p className="mt-1 text-xs text-secondary-label">
              {hasSegmented ? `每批 ${segmentsPerBatch} 段 · 已解析的批次会立即展示在下方` : "本地分词去重后，AI 会按你的水平筛选值得学的词/短语/句子"}
            </p>
            {hasSegmented && batchProgress && batchProgress.failed > 0 && (
              <p className="mt-2 text-xs text-danger">{batchProgress.failed} 批失败，可在下方单独重试</p>
            )}
          </CardContent>
        </Card>
        {hasSegmented && segments.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between">
                <span>分段进度 · {segments.filter((s) => s.status === "success").length}/{segments.length} 段完成</span>
                {segments.some((s) => s.status === "error") && (
                  <Button variant="outline" size="sm" onClick={() => void retryFailedBatches()}>
                    <RefreshCw className="size-4" />
                    重试失败段
                  </Button>
                )}
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {(() => {
                const batches = localPlan?.batches ?? [];
                return batches.map((batch) => {
                  const batchSegs = segments.filter((s) => batch.segmentIds.includes(s.id));
                  const statuses = batchSegs.map((s) => s.status);
                  const isLoading = statuses.includes("loading");
                  const isError = batchSegs.some((s) => s.status === "error");
                  const isSuccess = batchSegs.every((s) => s.status === "success");
                  return (
                    <div key={batch.batchIndex} className={`flex items-center justify-between gap-3 rounded-[14px] border p-3 text-sm ${isError ? "border-danger/30 bg-danger/[0.04]" : isSuccess ? "border-success/20 bg-success/[0.04]" : "border-black/[0.06] bg-white/60 dark:border-white/[0.08] dark:bg-white/[0.04]"}`}>
                      <div className="min-w-0 flex-1">
                        <p className="font-medium">
                          第 {batch.batchIndex + 1} 批 · {batchSegs.length} 段 · {batch.charCount} 字符
                        </p>
                        <p className="mt-0.5 truncate text-xs text-secondary-label">
                          {batchSegs.map((s) => s.previewText).join(" ｜ ").slice(0, ARTICLE_SEGMENT_PREVIEW_CHARS)}
                        </p>
                        {isError && batchSegs.find((s) => s.error) && (
                          <p className="mt-1 text-xs text-danger">{batchSegs.find((s) => s.error)?.error}</p>
                        )}
                      </div>
                      <div className="shrink-0">
                        {isLoading && <Loader2 className="size-5 animate-spin text-accent" />}
                        {isSuccess && <CheckCircle2 className="size-5 text-success" />}
                        {isError && (
                          <Button variant="outline" size="sm" onClick={() => void retryBatch(batch.batchIndex)}>
                            重试
                          </Button>
                        )}
                        {!isLoading && !isSuccess && !isError && <span className="text-xs text-tertiary-label">等待中</span>}
                      </div>
                    </div>
                  );
                });
              })()}
            </CardContent>
          </Card>
        )}
        {hasSegmented && effectivePreview && (
          <div className="space-y-5">
            <ImportStrategyCard />
            <Card>
              <CardHeader>
                <div className="flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <CardTitle className="flex items-center gap-2">
                      <FileText className="size-5 text-accent" />
                      {effectivePreview.filename} · 已就绪 {successSegments.length} 批
                    </CardTitle>
                    <p className="mt-1 text-sm text-secondary-label">已解析的批次已合并展示，可先勾选并导入；剩余批次完成后会自动追加</p>
                  </div>
                </div>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
                  <Metric label="全文词数" value={effectivePreview.articleStats.wordCount} />
                  <Metric label="去重词数" value={effectivePreview.articleStats.uniqueCount} />
                  <Metric label="待学候选" value={candidateCount} tone="green" />
                  <Metric label="已掌握" value={effectivePreview.articleStats.knownCount} tone="blue" />
                  <Metric label="短语/句子" value={(effectivePreview.articleStats.phraseCount ?? grouped.phrases.length) + (effectivePreview.articleStats.sentenceCount ?? grouped.sentences.length)} tone="purple" />
                </div>
              </CardContent>
            </Card>
            <CandidateTables />
          </div>
        )}
      </div>
    );
  }

  if (step === "committing") {
    return (
      <Card>
        <CardContent className="py-20 text-center">
          <Loader2 className="mx-auto size-12 animate-spin text-accent" />
          <h2 className="mt-5 text-xl font-semibold">正在写入词库</h2>
          <p className="mt-2 text-sm text-secondary-label">创建初始化任务并应用导入策略，请勿重复提交。</p>
        </CardContent>
      </Card>
    );
  }

  if (step === "success" && result) {
    return (
      <Card>
        <CardContent className="py-16 text-center">
          <span className="mx-auto grid size-20 place-items-center rounded-full bg-success/12 text-success shadow-[0_8px_32px_rgba(52,199,89,0.15)]">
            <CheckCircle2 className="size-10" />
          </span>
          <h2 className="mt-5 text-2xl font-bold">导入完成</h2>
          <p className="mt-2 text-sm text-secondary-label">
            新增 {result.createdWords} 个，识别已有 {result.existingWords} 个，新增初始化任务 {result.queuedInitializations} 个。
          </p>
          <div className="mt-7 flex flex-wrap justify-center gap-3">
            <Link href="/initialize" className={buttonClass("primary")}>
              <Loader2 className="size-4" />
              查看初始化
            </Link>
            <Link href="/words" className={buttonClass("outline")}>
              打开单词本
            </Link>
            <Button variant="ghost" onClick={restart}>
              继续导入
            </Button>
          </div>
        </CardContent>
      </Card>
    );
  }

  function CandidateTables() {
    return (
      <Card>
        <CardHeader>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <CardTitle>候选 · 已选 {selected.size} / {candidateCount}</CardTitle>
            <div className="flex flex-wrap items-center gap-2">
              <div className="flex overflow-hidden rounded-full border border-black/[0.08] bg-black/[0.04] dark:border-white/[0.08] dark:bg-white/[0.06]">
                {(["all", "WORD", "PHRASE", "SENTENCE"] as const).map((v) => (
                  <button key={v} type="button" onClick={() => setFilter(v)} className={`px-3 py-1.5 text-xs font-semibold transition ${filter === v ? "bg-white text-label shadow-sm dark:bg-white/[0.12]" : "text-secondary-label"}`}>
                    {v === "all" ? "全部" : keyLabel(v)}
                  </button>
                ))}
              </div>
              {displayPreview?.aiApplied && (displayPreview?.recommendedTerms.length ?? 0) > 0 && (
                <label className="flex items-center gap-1.5 text-xs text-secondary-label">
                  <input type="checkbox" checked={showRecommendedOnly} onChange={(event) => setShowRecommendedOnly(event.target.checked)} className="accent-accent" />
                  仅看 AI 推荐
                </label>
              )}
              <Button variant="outline" size="sm" onClick={selectRecommended} disabled={!displayPreview?.aiApplied || (displayPreview?.recommendedTerms.length ?? 0) === 0}>
                选推荐
              </Button>
              <Button variant="outline" size="sm" onClick={selectAllVisible}>
                全选当前
              </Button>
              <Button variant="ghost" size="sm" onClick={clearSelection}>
                清空
              </Button>
            </div>
          </div>
        </CardHeader>
        <CardContent className="space-y-6">
          {(filter === "all" || filter === "WORD") && grouped.words.length > 0 && (
            <div>
              <p className="mb-2 flex items-center gap-2 text-xs font-semibold text-secondary-label"><BookOpen className="size-3.5" />单词 · {grouped.words.filter((c) => c.status === "CANDIDATE").length} 待学</p>
              <div className="max-h-80 overflow-auto glass-inner rounded-xl">
                <table className="w-full min-w-[640px] text-left text-sm">
                  <thead className="sticky top-0 bg-white/60 text-xs text-secondary-label backdrop-blur-xl dark:bg-white/[0.06]">
                    <tr>
                      <th className="w-10 p-3">
                        <input type="checkbox" className="accent-accent" checked={grouped.words.filter((c) => c.status === "CANDIDATE" && selected.has(candidateKey(c).toLowerCase())).length === grouped.words.filter((c) => c.status === "CANDIDATE").length && grouped.words.some((c) => c.status === "CANDIDATE")} onChange={() => {
                          const cands = grouped.words.filter((c) => c.status === "CANDIDATE");
                          const all = cands.every((c) => selected.has(candidateKey(c).toLowerCase()));
                          if (all) {
                            setSelected((prev) => {
                              const next = new Set(prev);
                              for (const c of cands) next.delete(candidateKey(c).toLowerCase());
                              return next;
                            });
                          } else {
                            setSelected((prev) => {
                              const next = new Set(prev);
                              for (const c of cands) next.add(candidateKey(c).toLowerCase());
                              return next;
                            });
                          }
                        }} />
                      </th>
                      <th className="p-3">单词</th>
                      <th className="p-3">出现</th>
                      <th className="p-3">难度</th>
                      <th className="p-3">推荐理由</th>
                      <th className="p-3">状态</th>
                    </tr>
                  </thead>
                  <tbody>
                    {grouped.words.filter((c) => filter === "all" || c.entryType === filter || (!c.entryType && filter === "WORD")).filter((c) => !showRecommendedOnly || c.status === "KNOWN" || recommendedKeys.has(candidateKey(c).toLowerCase()) || recommendedKeys.has(c.normalizedTerm.toLowerCase())).map((candidate) => {
                      const isKnown = candidate.status === "KNOWN";
                      const key = candidateKey(candidate).toLowerCase();
                      const isChecked = selected.has(key) || selected.has(candidate.normalizedTerm.toLowerCase());
                      if (filter === "WORD" && visibleCandidates.length && !visibleCandidates.includes(candidate)) return null;
                      return (
                        <tr key={key} className="border-t border-black/[0.04] dark:border-white/[0.06]">
                          <td className="p-3">
                            <input type="checkbox" className="accent-accent" disabled={isKnown} checked={isKnown ? false : isChecked} onChange={() => toggleKey(key)} />
                          </td>
                          <td className="p-3 font-medium">
                            <span className={isKnown ? "text-tertiary-label line-through" : ""}>{candidate.term}</span>
                            {candidate.cefrLevel && <span className="ml-2 text-xs text-tertiary-label">{candidate.cefrLevel}</span>}
                          </td>
                          <td className="p-3 text-secondary-label">×{candidate.occurrences}</td>
                          <td className="p-3">
                            {candidate.difficulty ? <Badge tone={candidate.difficulty >= 4 ? "red" : candidate.difficulty >= 3 ? "amber" : "blue"}>{candidate.difficulty}/5</Badge> : <span className="text-xs text-tertiary-label">—</span>}
                          </td>
                          <td className="max-w-[220px] p-3 text-xs text-secondary-label">{candidate.aiReason || (isKnown ? "已在词库" : "—")}</td>
                          <td className="p-3">{isKnown ? <Badge tone="blue">已掌握</Badge> : <Badge tone={isChecked ? "green" : "slate"}>{isChecked ? "待导入" : "未选"}</Badge>}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
          {(filter === "all" || filter === "PHRASE") && grouped.phrases.length > 0 && (
            <div>
              <p className="mb-2 flex items-center gap-2 text-xs font-semibold text-secondary-label"><Layers className="size-3.5" />短语 · {grouped.phrases.filter((c) => c.status === "CANDIDATE").length} 待学（AI 精选固定搭配）</p>
              <div className="grid gap-2">
                {grouped.phrases.filter((c) => visibleCandidates.includes(c)).map((c) => {
                  const key = candidateKey(c).toLowerCase();
                  const isKnown = c.status === "KNOWN";
                  const isChecked = selected.has(key);
                  const card = c.aiCard;
                  return (
                    <label key={key} className={`flex cursor-pointer gap-3 rounded-[16px] border p-3.5 text-left transition ${isChecked ? "border-accent/30 bg-accent/[0.06] shadow-sm" : "border-black/[0.06] bg-white/60 hover:border-black/[0.12] dark:border-white/[0.08] dark:bg-white/[0.04]"}`}>
                      <input type="checkbox" className="mt-1 accent-accent" disabled={isKnown} checked={isChecked} onChange={() => toggleKey(key)} />
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-1.5">
                          <b className="text-[14px]">{c.term}</b>
                          <Badge tone={keyTone(c.entryType ?? "PHRASE")}>{keyLabel(c.entryType ?? "PHRASE")}</Badge>
                          {isKnown ? <Badge tone="blue">已掌握</Badge> : isChecked ? <Badge tone="green">已选</Badge> : <Badge tone="slate">未选</Badge>}
                          {c.difficulty && <Badge tone={c.difficulty >= 4 ? "red" : c.difficulty >= 3 ? "amber" : "blue"}>{c.difficulty}/5</Badge>}
                        </div>
                        {c.aiReason && <p className="mt-1 text-xs text-secondary-label">{c.aiReason}</p>}
                        {card && (
                          <div className="mt-2 space-y-1.5 rounded-[12px] bg-black/[0.03] p-2.5 dark:bg-white/[0.04]">
                            <p className="text-xs"><span className="font-semibold text-accent">直译：</span>{card.literalTranslation}</p>
                            <p className="text-xs"><span className="font-semibold text-success">意译：</span>{card.freeTranslation}</p>
                            {card.keyVocab?.length > 0 && <p className="text-[11px] leading-relaxed text-secondary-label"><span className="font-semibold">重点词汇：</span>{card.keyVocab.map((k) => `${k.term}${k.pos ? ` ${k.pos}.` : ""} ${k.meaning}`).join("； ")}</p>}
                            {(card.grammarPattern || (card.grammarNotes?.length ?? 0) > 0) && <p className="text-[11px] leading-relaxed text-secondary-label"><span className="font-semibold">语法：</span>{[card.grammarPattern, ...(card.grammarNotes ?? [])].filter(Boolean).join("； ")}</p>}
                            {card.nuance && <p className="text-[11px] leading-relaxed text-warning-dark">辨析：{card.nuance}</p>}
                          </div>
                        )}
                      </div>
                    </label>
                  );
                })}
                {grouped.phrases.filter((c) => visibleCandidates.includes(c)).length === 0 && <p className="text-center text-xs text-tertiary-label">当前筛选无短语。</p>}
              </div>
            </div>
          )}
          {(filter === "all" || filter === "SENTENCE") && grouped.sentences.length > 0 && (
            <div>
              <p className="mb-2 flex items-center gap-2 text-xs font-semibold text-secondary-label"><MessageSquareText className="size-3.5" />句子 · {grouped.sentences.filter((c) => c.status === "CANDIDATE").length} 待学（AI 句法卡片）</p>
              <div className="grid gap-3">
                {grouped.sentences.filter((c) => visibleCandidates.includes(c)).map((c) => {
                  const key = candidateKey(c).toLowerCase();
                  const isKnown = c.status === "KNOWN";
                  const isChecked = selected.has(key);
                  const card = c.aiCard;
                  return (
                    <label key={key} className={`flex cursor-pointer gap-3 rounded-[16px] border p-3.5 text-left transition ${isChecked ? "border-purple/30 bg-purple/[0.06] shadow-sm" : "border-black/[0.06] bg-white/60 hover:border-black/[0.12] dark:border-white/[0.08] dark:bg-white/[0.04]"}`}>
                      <input type="checkbox" className="mt-1 accent-purple" disabled={isKnown} checked={isChecked} onChange={() => toggleKey(key)} />
                      <div className="min-w-0 flex-1">
                        <p className="text-[13.5px] font-medium leading-relaxed">{c.term}</p>
                        <div className="mt-1.5 flex flex-wrap gap-1.5">
                          <Badge tone="purple">句子</Badge>
                          {isKnown ? <Badge tone="blue">已掌握</Badge> : isChecked ? <Badge tone="green">已选</Badge> : <Badge tone="slate">未选</Badge>}
                        </div>
                        {card ? (
                          <div className="mt-2 space-y-1.5 rounded-[12px] bg-black/[0.03] p-2.5 dark:bg-white/[0.04]">
                            <p className="text-xs"><span className="font-semibold text-accent">直译：</span>{card.literalTranslation}</p>
                            <p className="text-xs"><span className="font-semibold text-success">意译：</span>{card.freeTranslation}</p>
                            {card.keyVocab?.length > 0 && <p className="text-[11px] leading-relaxed text-secondary-label"><span className="font-semibold">重点词汇：</span>{card.keyVocab.map((k) => `${k.term}${k.pos ? ` ${k.pos}.` : ""} ${k.meaning}`).join("； ")}</p>}
                            {(card.grammarPattern || (card.grammarNotes?.length ?? 0) > 0) && <p className="text-[11px] leading-relaxed text-secondary-label"><span className="font-semibold">语法：</span>{[card.grammarPattern, ...(card.grammarNotes ?? [])].filter(Boolean).join("； ")}</p>}
                            {card.nuance && <p className="text-[11px] leading-relaxed text-tertiary-label">注：{card.nuance}</p>}
                          </div>
                        ) : (
                          <p className="mt-1 text-xs text-tertiary-label">本地切句（配置 AI 后可获直译/语法/意译卡片）</p>
                        )}
                      </div>
                    </label>
                  );
                })}
                {grouped.sentences.filter((c) => visibleCandidates.includes(c)).length === 0 && <p className="text-center text-xs text-tertiary-label">当前筛选无句子。</p>}
              </div>
            </div>
          )}
          {visibleCandidates.length === 0 && <p className="text-center text-sm text-secondary-label">当前筛选无候选。</p>}
          <p className="text-xs text-tertiary-label">已根据词库与类型去重；AI 推荐含短语与句子固定搭配，已自动勾选，可手动增删。</p>
        </CardContent>
      </Card>
    );
  }

  if (step === "preview" && effectivePreview) {
    return (
      <div className="space-y-5">
        <ImportStrategyCard />
        {useSegmented && segments.length > 0 && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center justify-between text-sm">
                <span>分段 · {segments.filter((s) => s.status === "success").length}/{segments.length} 段成功{segments.some((s) => s.status === "error") ? ` · ${segments.filter((s) => s.status === "error").length} 段失败` : ""}{aiFallbackBatchIndices().length > 0 ? ` · ${aiFallbackBatchIndices().length} 批 AI 回退` : ""}</span>
                <div className="flex gap-2">
                  {aiFallbackBatchIndices().length > 0 && (
                    <Button variant="outline" size="sm" onClick={() => void retryAiFallbackBatches()}>
                      <Sparkles className="size-4" />
                      重试 AI 回退
                    </Button>
                  )}
                  {segments.some((s) => s.status === "error") && (
                    <Button variant="outline" size="sm" onClick={() => void retryFailedBatches()}>
                      <RefreshCw className="size-4" />
                      重试失败
                    </Button>
                  )}
                </div>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-2">
              {(localPlan?.batches ?? []).map((batch) => {
                const batchSegs = segments.filter((s) => batch.segmentIds.includes(s.id));
                const isLoading = batchSegs.some((s) => s.status === "loading");
                const isError = batchSegs.some((s) => s.status === "error");
                const isSuccess = batchSegs.length > 0 && batchSegs.every((s) => s.status === "success");
                const hasAiFallback = isSuccess && batchSegs.some((s) => s.preview?.aiError);
                return (
                  <div key={batch.batchIndex} className={`flex items-center justify-between gap-3 rounded-[14px] border p-3 ${isError ? "border-danger/30 bg-danger/[0.04]" : isSuccess ? "border-success/20 bg-success/[0.04]" : "border-black/[0.06] bg-white/60 dark:border-white/[0.08] dark:bg-white/[0.04]"}`}>
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium">第 {batch.batchIndex + 1} 批 · {batchSegs.length} 段 · {batch.charCount} 字符{hasAiFallback ? " · AI 回退" : ""}</p>
                      <p className="mt-0.5 truncate text-xs text-secondary-label">{batchSegs.map((s) => s.previewText).join(" ｜ ").slice(0, ARTICLE_SEGMENT_PREVIEW_CHARS)}</p>
                      {isError && <p className="mt-1 text-xs text-danger">{batchSegs.find((s) => s.error)?.error}</p>}
                      {hasAiFallback && <p className="mt-1 truncate text-xs text-warning">{batchSegs.find((s) => s.preview?.aiError)?.preview?.aiError}</p>}
                    </div>
                    <div className="shrink-0">
                      {isLoading && <Loader2 className="size-5 animate-spin text-accent" />}
                      {isSuccess && !hasAiFallback && <CheckCircle2 className="size-5 text-success" />}
                      {hasAiFallback && (
                        <Button variant="outline" size="sm" onClick={() => void retryBatch(batch.batchIndex)}>
                          <Sparkles className="size-4" />
                          重试 AI
                        </Button>
                      )}
                      {isError && <Button variant="outline" size="sm" onClick={() => void retryBatch(batch.batchIndex)}>重试</Button>}
                    </div>
                  </div>
                );
              })}
            </CardContent>
          </Card>
        )}
        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <CardTitle className="flex items-center gap-2">
                  <FileText className="size-5 text-accent" />
                  {effectivePreview.filename}
                </CardTitle>
                <p className="mt-1 text-sm text-secondary-label">预览在 {new Date(effectivePreview.expiresAt).toLocaleTimeString("zh-CN")} 前有效{useSegmented ? ` · 共 ${segments.length} 段分 ${localPlan?.batches.length ?? 0} 批` : ""}</p>
              </div>
              <Button variant="ghost" onClick={restart}>
                重新粘贴
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
              <Metric label="全文词数" value={effectivePreview.articleStats.wordCount} />
              <Metric label="去重词数" value={effectivePreview.articleStats.uniqueCount} />
              <Metric label="待学候选" value={candidateCount} tone="green" />
              <Metric label="已掌握" value={effectivePreview.articleStats.knownCount} tone="blue" />
              <Metric label="短语/句子" value={(effectivePreview.articleStats.phraseCount ?? grouped.phrases.length) + (effectivePreview.articleStats.sentenceCount ?? grouped.sentences.length)} tone="purple" />
            </div>
            <div className="mt-4 flex flex-wrap items-center gap-2">
              {effectivePreview.aiApplied ? (
                <Badge tone="purple" className="gap-1">
                  <Sparkles className="size-3" />
                  AI 已筛选 · 推荐 {effectivePreview.recommendedTerms.length} 词{grouped.phrases.length ? ` · 短语 ${grouped.phrases.length}` : ""}{grouped.sentences.length ? ` · 句子 ${grouped.sentences.length}` : ""}
                </Badge>
              ) : (
                <Badge tone="amber">未启用 AI · 展示单词与本地切句</Badge>
              )}
              <Badge tone="slate">{effectivePreview.articleStats.charCount} 字符</Badge>
            </div>
            {effectivePreview.aiError && (
              <Alert tone="info" icon={<AlertCircle className="size-4" />} className="mt-4">
                <div className="flex flex-wrap items-center gap-2">
                  <span>{effectivePreview.aiError} 已回退为展示单词与本地切句，你仍可手动勾选。</span>
                  {useSegmented && aiFallbackBatchIndices().length > 0 ? (
                    <Button variant="outline" size="sm" onClick={() => void retryAiFallbackBatches()}>
                      <Sparkles className="size-4" />
                      重试 AI 回退
                    </Button>
                  ) : !useSegmented ? (
                    <Button variant="outline" size="sm" onClick={() => void analyzeSingle()}>
                      <Sparkles className="size-4" />
                      重试 AI 筛选
                    </Button>
                  ) : null}
                </div>
              </Alert>
            )}
            {!effectivePreview.aiApplied && !effectivePreview.aiError && (
              <Alert tone="info" icon={<Wand2 className="size-4" />} className="mt-4">
                到“设置 → 模型服务 → AI”配置 LLM，可获得按你词汇量智能筛选的短语与句子卡片。
              </Alert>
            )}
          </CardContent>
        </Card>
        <CandidateTables />
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Wand2 className="size-5 text-accent" />
            粘贴英文文章
          </CardTitle>
          <p className="mt-1 text-sm text-secondary-label">AI 会结合你的词库与考试目标，自动挑出值得学的单词、短语与句子。未配置 AI 也可按生词与本地切句导入。</p>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <p className="mb-2 text-xs font-medium text-secondary-label">考试目标 · 可多选，不选为自适应（支持跨档如四级 + 托福）</p>
            <div className="flex flex-wrap gap-2">
              {EXAM_TARGETS.map((target) => {
                const active = examTargets.includes(target);
                return (
                  <button
                    key={target}
                    type="button"
                    onClick={() => toggleExamTarget(target)}
                    className={`rounded-full border px-3 py-1.5 text-xs font-semibold transition ${active ? "border-accent bg-accent text-white shadow-sm" : "border-black/10 bg-white text-secondary-label hover:border-accent/30 dark:border-white/10 dark:bg-white/[0.06]"}`}
                  >
                    {EXAM_LABEL[target]}
                  </button>
                );
              })}
              {examTargets.length > 0 && (
                <button type="button" onClick={() => setExamTargets([])} className="rounded-full border border-black/10 px-3 py-1.5 text-xs text-tertiary-label hover:text-secondary-label dark:border-white/10">
                  清空
                </button>
              )}
            </div>
            {!examTargetsLoaded && <p className="mt-1.5 text-xs text-tertiary-label">正在读取设置…</p>}
            {examTargetsLoaded && examTargets.length === 0 && <p className="mt-1.5 text-xs text-tertiary-label">当前：自适应（按已掌握词库）</p>}
          </div>

          <div className="relative">
            <textarea
              value={articleText}
              onChange={(event) => setArticleText(event.target.value)}
              placeholder={SAMPLE_ARTICLE}
              maxLength={MAX_ARTICLE_CHARS}
              className="glass-inner min-h-64 w-full rounded-[18px] p-4 text-[15px] leading-6 outline-none placeholder:text-tertiary-label focus:border-accent/20 dark:placeholder:text-[#636366]"
              rows={10}
            />
            <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-xs">
              <span className={charCount < MIN_ARTICLE_CHARS ? "text-warning" : charCount > MAX_ARTICLE_CHARS ? "text-danger" : "text-tertiary-label"}>
                {charCount} / {MAX_ARTICLE_CHARS} 字符 · 至少 {MIN_ARTICLE_CHARS} 字符
              </span>
              <div className="flex gap-2">
                <Button variant="ghost" size="sm" onClick={() => setArticleText(SAMPLE_ARTICLE)}>
                  填入示例
                </Button>
                <Button variant="outline" size="sm" onClick={() => setArticleText("")} disabled={!articleText}>
                  清空
                </Button>
              </div>
            </div>
          </div>
          {segmentPlan && segmentPlan.totalSegments > 1 && (
            <div className="rounded-[16px] border border-black/[0.06] bg-white/60 p-4 dark:border-white/[0.08] dark:bg-white/[0.04]">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="text-sm font-semibold">智能分段预览</p>
                  <p className="mt-0.5 text-xs text-secondary-label">
                    按换行智能识别为 {segmentPlan.totalSegments} 段 · 共 {segmentPlan.totalChars} 字符 · 将分 {totalBatches} 次请求{totalBatches > 1 ? `（每批 ${segmentsPerBatch} 段）` : ""}
                  </p>
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {segmentPlan.segments.slice(0, 6).map((seg) => (
                      <span key={seg.id} className="rounded-full bg-black/[0.06] px-2.5 py-1 text-[11px] text-secondary-label dark:bg-white/[0.08]">
                        {seg.id} · {seg.charCount}字 · {seg.preview.slice(0, ARTICLE_SEGMENT_PREVIEW_CHARS)}…
                      </span>
                    ))}
                    {segmentPlan.totalSegments > 6 && <span className="px-2 py-1 text-xs text-tertiary-label">+{segmentPlan.totalSegments - 6} 段</span>}
                  </div>
                  <p className="mt-2 text-[11px] text-tertiary-label">批次在下方滑条调节，1 段一批最稳、10 段一批最快；已解析的批次会立即展示候选</p>
                </div>
                <div className="flex items-center gap-3">
                  <div className="text-right">
                    <p className="text-xs font-medium text-secondary-label">每批段数</p>
                    <p className="text-[11px] text-tertiary-label">{segmentsPerBatch} 段 / 批 · 共 {totalBatches} 批</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <input type="range" min={1} max={ARTICLE_SEGMENTS_PER_BATCH_MAX} value={segmentsPerBatch} onChange={(e) => setSegmentsPerBatch(Math.max(1, Math.min(ARTICLE_SEGMENTS_PER_BATCH_MAX, Number(e.target.value))))} className="h-2 w-28 accent-accent" />
                    <span className="w-8 text-center text-sm font-semibold">{segmentsPerBatch}</span>
                  </div>
                </div>
              </div>
              <div className="mt-3 flex flex-wrap gap-1">
                {segmentPlan.batches.map((b) => (
                  <span key={b.batchIndex} className="rounded-full border border-black/[0.08] bg-white px-2.5 py-1 text-xs dark:border-white/[0.08] dark:bg-white/[0.06]">
                    第 {b.batchIndex + 1} 批：{b.segmentIds.join(" + ")} · {b.charCount}字
                  </span>
                ))}
              </div>
            </div>
          )}
          {segmentPlan && segmentPlan.totalSegments <= 1 && charCount >= MIN_ARTICLE_CHARS && (
            <p className="text-xs text-tertiary-label">当前为单段，将一次性请求；如需分段请用空行分隔段落</p>
          )}
          {error && <Alert tone="danger" icon={<AlertCircle className="size-4" />}>{error}</Alert>}
          <div className="flex flex-wrap justify-end gap-2">
            {segmentPlan && segmentPlan.totalSegments > 1 ? (
              <>
                <Button variant="outline" onClick={() => void analyzeSingle()} disabled={!canAnalyze}>
                  单次请求（{charCount} 字）
                </Button>
                <Button size="lg" onClick={() => void analyzeSegmented()} disabled={!canAnalyze}>
                  <Sparkles className="size-4" />
                  分 {totalBatches} 批分析
                </Button>
              </>
            ) : (
              <Button size="lg" onClick={() => void analyzeSingle()} disabled={!canAnalyze}>
                <Sparkles className="size-4" />
                智能分析
              </Button>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

function Metric({ label, value, tone = "slate" }: { label: string; value: number; tone?: "slate" | "green" | "blue" | "amber" | "red" | "purple" }) {
  const colors = { slate: "text-label", green: "text-success", blue: "text-accent", amber: "text-warning", red: "text-danger", purple: "text-purple" } as const;
  return (
    <div className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]">
      <p className={`text-2xl font-bold ${colors[tone]}`}>{value}</p>
      <p className="text-xs text-secondary-label">{label}</p>
    </div>
  );
}
