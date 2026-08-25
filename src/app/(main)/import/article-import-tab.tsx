"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { AlertCircle, ArrowRight, CheckCircle2, FileText, Loader2, Sparkles, Wand2 } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { errorMessage } from "@/lib/format";
import { MAX_ARTICLE_CHARS, MIN_ARTICLE_CHARS } from "@/lib/config";
import type { ArticleImportPreview, ImportMode } from "@/lib/types";
import { Alert, Badge, Button, Card, CardContent, CardHeader, CardTitle, buttonClass, toast } from "@/components/ui";

interface CommitResult {
  batchId: number;
  createdWords: number;
  existingWords: number;
  queuedInitializations: number;
}

const SAMPLE_ARTICLE =
  "The rapid advancement of artificial intelligence has profoundly reshaped how we acquire knowledge. While conventional rote memorization emphasizes repetition, contemporary cognitive science suggests that contextual learning—encountering vocabulary within authentic discourse—yields more durable retention. Nevertheless, learners often feel overwhelmed when faced with an entire article replete with unfamiliar terminology. An intelligent system that discerns which words merit attention, based on the learner's existing lexicon, can transform a daunting passage into a curated learning experience.";

export default function ArticleImportTab({ onImported }: { onImported?: () => void }) {
  const [articleText, setArticleText] = useState("");
  const [preview, setPreview] = useState<ArticleImportPreview | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [mode, setMode] = useState<ImportMode>("FILL_MISSING");
  const [reset, setReset] = useState(false);
  const [step, setStep] = useState<"input" | "analyzing" | "preview" | "committing" | "success">("input");
  const [error, setError] = useState("");
  const [result, setResult] = useState<CommitResult | null>(null);
  const [showRecommendedOnly, setShowRecommendedOnly] = useState(false);

  const charCount = articleText.length;
  const canAnalyze = charCount >= MIN_ARTICLE_CHARS && charCount <= MAX_ARTICLE_CHARS;

  const visibleCandidates = useMemo(() => {
    if (!preview) return [];
    if (!showRecommendedOnly || !preview.aiApplied) return preview.candidates;
    const recommendedSet = new Set(preview.recommendedTerms.map((term) => term.toLowerCase()));
    return preview.candidates.filter((candidate) => recommendedSet.has(candidate.normalizedTerm.toLowerCase()) || candidate.status === "KNOWN");
  }, [preview, showRecommendedOnly]);

  const candidateCount = preview?.candidates.filter((candidate) => candidate.status === "CANDIDATE").length ?? 0;

  async function analyze() {
    if (!canAnalyze) {
      setError(`文章至少需要 ${MIN_ARTICLE_CHARS} 个字符，且不能超过 ${MAX_ARTICLE_CHARS} 字符。`);
      return;
    }
    setError("");
    setStep("analyzing");
    try {
      const data = await apiFetch<ArticleImportPreview>("/api/article-import/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ articleText }),
      });
      setPreview(data);
      setSelected(new Set(data.recommendedTerms.map((term) => term.toLowerCase())));
      setShowRecommendedOnly(data.aiApplied && data.recommendedTerms.length > 0 && data.recommendedTerms.length < candidateCount);
      setStep("preview");
      toast.success(`已提取 ${data.articleStats.uniqueCount} 个去重词，AI 推荐 ${data.recommendedTerms.length} 个`, "分析完成");
    } catch (reason) {
      setStep("input");
      setError(errorMessage(reason, "分析文章失败"));
    }
  }

  function toggleTerm(normalizedTerm: string) {
    const key = normalizedTerm.toLowerCase();
    setSelected((previous) => {
      const next = new Set(previous);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }

  function selectAllVisible() {
    const candidates = visibleCandidates.filter((candidate) => candidate.status === "CANDIDATE");
    setSelected(new Set(candidates.map((candidate) => candidate.normalizedTerm.toLowerCase())));
  }

  function selectRecommended() {
    if (!preview) return;
    setSelected(new Set(preview.recommendedTerms.map((term) => term.toLowerCase())));
  }

  function clearSelection() {
    setSelected(new Set());
  }

  async function commit() {
    if (!preview) return;
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
          previewToken: preview.previewToken,
          selectedTerms: [...selected],
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
    setResult(null);
    setError("");
    setSelected(new Set());
    setShowRecommendedOnly(false);
  }

  if (step === "analyzing") {
    return (
      <Card>
        <CardContent className="grid min-h-72 place-items-center">
          <div className="text-center">
            <Loader2 className="mx-auto size-9 animate-spin text-accent" />
            <p className="mt-3 text-sm font-medium text-label">正在分析文章并匹配你的词汇量…</p>
            <p className="mt-1 text-xs text-secondary-label">本地分词去重后，AI 会按你的水平筛选值得学的词</p>
          </div>
        </CardContent>
      </Card>
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

  if (step === "preview" && preview) {
    return (
      <div className="space-y-5">
        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <CardTitle className="flex items-center gap-2">
                  <FileText className="size-5 text-accent" />
                  {preview.filename}
                </CardTitle>
                <p className="mt-1 text-sm text-secondary-label">预览在 {new Date(preview.expiresAt).toLocaleTimeString("zh-CN")} 前有效</p>
              </div>
              <Button variant="ghost" onClick={restart}>
                重新粘贴
              </Button>
            </div>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Metric label="全文词数" value={preview.articleStats.wordCount} />
              <Metric label="去重词数" value={preview.articleStats.uniqueCount} />
              <Metric label="待学候选" value={candidateCount} tone="green" />
              <Metric label="已掌握" value={preview.articleStats.knownCount} tone="blue" />
            </div>
            <div className="mt-4 flex flex-wrap items-center gap-2">
              {preview.aiApplied ? (
                <Badge tone="purple" className="gap-1">
                  <Sparkles className="size-3" />
                  AI 已筛选 · 推荐 {preview.recommendedTerms.length} 个
                </Badge>
              ) : (
                <Badge tone="amber">未启用 AI · 展示全部生词</Badge>
              )}
              <Badge tone="slate">{preview.articleStats.charCount} 字符</Badge>
            </div>
            {preview.aiError && (
              <Alert tone="info" icon={<AlertCircle className="size-4" />} className="mt-4">
                {preview.aiError} 已回退为展示全部生词，你仍可手动勾选。
              </Alert>
            )}
            {!preview.aiApplied && !preview.aiError && (
              <Alert tone="info" icon={<Wand2 className="size-4" />} className="mt-4">
                到“设置 → 模型服务 → IMPORT_ENRICHMENT”配置 LLM，可获得按你词汇量智能筛选的效果。
              </Alert>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <CardTitle>候选词 · 已选 {selected.size} / {candidateCount}</CardTitle>
              <div className="flex flex-wrap items-center gap-2">
                {preview.aiApplied && preview.recommendedTerms.length > 0 && (
                  <label className="flex items-center gap-1.5 text-xs text-secondary-label">
                    <input type="checkbox" checked={showRecommendedOnly} onChange={(event) => setShowRecommendedOnly(event.target.checked)} className="accent-accent" />
                    仅看 AI 推荐
                  </label>
                )}
                <Button variant="outline" size="sm" onClick={selectRecommended} disabled={!preview.aiApplied || preview.recommendedTerms.length === 0}>
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
          <CardContent>
            <div className="max-h-96 overflow-auto glass-inner rounded-xl">
              <table className="w-full min-w-[640px] text-left text-sm">
                <thead className="sticky top-0 bg-white/60 text-xs text-secondary-label backdrop-blur-xl dark:bg-white/[0.06]">
                  <tr>
                    <th className="w-10 p-3">
                      <input type="checkbox" className="accent-accent" checked={visibleCandidates.filter((candidate) => candidate.status === "CANDIDATE" && selected.has(candidate.normalizedTerm.toLowerCase())).length === visibleCandidates.filter((candidate) => candidate.status === "CANDIDATE").length && visibleCandidates.some((candidate) => candidate.status === "CANDIDATE")} onChange={() => {
                        const candidates = visibleCandidates.filter((candidate) => candidate.status === "CANDIDATE");
                        const allSelected = candidates.every((candidate) => selected.has(candidate.normalizedTerm.toLowerCase()));
                        if (allSelected) clearSelection();
                        else setSelected(new Set(candidates.map((candidate) => candidate.normalizedTerm.toLowerCase())));
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
                  {visibleCandidates.map((candidate) => {
                    const isKnown = candidate.status === "KNOWN";
                    const isChecked = selected.has(candidate.normalizedTerm.toLowerCase());
                    return (
                      <tr key={candidate.normalizedTerm} className="border-t border-black/[0.04] dark:border-white/[0.06]">
                        <td className="p-3">
                          <input type="checkbox" className="accent-accent" disabled={isKnown} checked={isKnown ? false : isChecked} onChange={() => toggleTerm(candidate.normalizedTerm)} />
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
            {visibleCandidates.length === 0 && <p className="mt-3 text-center text-sm text-secondary-label">当前筛选无候选词。</p>}
            <p className="mt-2 text-xs text-tertiary-label">已根据你的词库自动标记“已掌握”；AI 推荐仅作参考，可手动增删。</p>
          </CardContent>
        </Card>

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
              <Button size="lg" onClick={() => void commit()} disabled={selected.size === 0}>
                确认导入 {selected.size} 个
                <ArrowRight className="size-5" />
              </Button>
            </div>
          </CardContent>
        </Card>
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
          <p className="mt-1 text-sm text-secondary-label">AI 会结合你的词库与词汇水平，自动挑出值得学的单词。未配置 AI 也可直接按生词导入。</p>
        </CardHeader>
        <CardContent className="space-y-4">
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
          {error && <Alert tone="danger" icon={<AlertCircle className="size-4" />}>{error}</Alert>}
          <div className="flex justify-end">
            <Button size="lg" onClick={() => void analyze()} disabled={!canAnalyze}>
              <Sparkles className="size-4" />
              智能分析
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

function Metric({ label, value, tone = "slate" }: { label: string; value: number; tone?: "slate" | "green" | "blue" | "amber" | "red" }) {
  const colors = { slate: "text-label", green: "text-success", blue: "text-accent", amber: "text-warning", red: "text-danger" };
  return (
    <div className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]">
      <p className={`text-2xl font-bold ${colors[tone]}`}>{value}</p>
      <p className="text-xs text-secondary-label">{label}</p>
    </div>
  );
}
