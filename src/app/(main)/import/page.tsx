"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { errorMessage } from "@/lib/format";
import Link from "next/link";
import { AlertCircle, ArrowRight, CheckCircle2, FileText, History, Loader2, RotateCcw, Undo2, Upload } from "lucide-react";
import { apiFetch, formatDate } from "@/lib/client-api";
import type { ImportMode, ImportPreview } from "@/lib/types";
import { Alert, Badge, Button, Card, CardContent, CardHeader, CardTitle, PageHeader, Progress, Segmented, buttonClass, toast } from "@/components/ui";
import { entryTypeLabel } from "@/lib/entry-type-label";
import ArticleImportTab from "./article-import-tab";

type Step = "upload" | "preview" | "committing" | "success";
interface CommitResult { batchId: number; createdWords: number; existingWords: number; queuedInitializations: number; }
interface ImportBatch {
  id: number; filename: string; importMode: string; resetLearningProgress: boolean;
  totalRows: number; createdWords: number; existingWords: number; queuedInitializations: number;
  status: string; createdAt: string; completedAt: string | null; rolledBackAt: string | null;
  rollback: { canRollback: boolean; reason: string | null };
}

export default function ImportPage() {
  const inputRef = useRef<HTMLInputElement>(null);
  const [activeTab, setActiveTab] = useState<"csv" | "article">("csv");
  const [step, setStep] = useState<Step>("upload");
  const [preview, setPreview] = useState<ImportPreview | null>(null);
  const [result, setResult] = useState<CommitResult | null>(null);
  const [mode, setMode] = useState<ImportMode>("FILL_MISSING");
  const [reset, setReset] = useState(false);
  const [error, setError] = useState("");
  const [dragging, setDragging] = useState(false);
  const [history, setHistory] = useState<ImportBatch[]>([]);
  const [rollbackBusy, setRollbackBusy] = useState<number | null>(null);
  const [historyMessage, setHistoryMessage] = useState("");

  const loadHistory = useCallback(async () => {
    try { setHistory(await apiFetch<ImportBatch[]>("/api/imports?limit=20")); }
    catch { setHistory([]); }
  }, []);
  useEffect(() => { const timer = window.setTimeout(() => void loadHistory(), 0); return () => window.clearTimeout(timer); }, [loadHistory]);

  async function selectFile(file?: File) {
    if (!file) return;
    setError(""); setPreview(null); setStep("preview");
    try {
      const form = new FormData(); form.append("file", file);
      const data = await apiFetch<ImportPreview>("/api/imports/preview", { method: "POST", body: form });
      setPreview(data);
      toast.success(`已解析 ${data.totalRows} 行 CSV 记录`, "文件上传成功");
    } catch (reason) { setStep("upload"); setError(errorMessage(reason, "生成预览失败")); }
  }
  async function commit() {
    if (!preview) return;
    setStep("committing"); setError("");
    try {
      const data = await apiFetch<CommitResult>("/api/imports/commit", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ previewToken: preview.previewToken, mode, resetLearningProgress: reset }) });
      setResult(data); setStep("success"); await loadHistory();
      toast.success(`成功导入 ${data.createdWords} 个新词条！`, "导入完成");
    } catch (reason) { setStep("preview"); setError(errorMessage(reason, "提交导入失败")); }
  }
  function restart() { setStep("upload"); setPreview(null); setResult(null); setError(""); if (inputRef.current) inputRef.current.value = ""; }
  async function rollback(batch: ImportBatch) {
    if (!batch.rollback.canRollback || !window.confirm(`确定撤销“${batch.filename}”吗？仅会删除该批次新建且尚未学习的词条。`)) return;
    setRollbackBusy(batch.id); setError(""); setHistoryMessage("");
    try {
      const result = await apiFetch<{ deletedWords: number }>(`/api/imports/${batch.id}/rollback`, { method: "POST" });
      const msg = `已撤销批次 #${batch.id}，删除 ${result.deletedWords} 个未学习词条。`;
      setHistoryMessage(msg);
      toast.success(msg, "撤销成功");
      await loadHistory();
    } catch (reason) { setError(errorMessage(reason, "撤销导入失败")); }
    finally { setRollbackBusy(null); }
  }

  const stepsList: Array<{ key: Step; label: string }> = [
    { key: "upload", label: "1. 上传 CSV" },
    { key: "preview", label: "2. 数据校验与策略" },
    { key: "committing", label: "3. 写入词库" },
    { key: "success", label: "4. 导入完成" },
  ];

  return <div className="space-y-6"><PageHeader title="导入" description="CSV 批量导入或粘贴英文文章智能导词，预览后再写入词库。" />
    <Segmented options={[{ value: "csv", label: "CSV 文件" }, { value: "article", label: "粘贴文章" }]} value={activeTab} onChange={setActiveTab} />
    {activeTab === "article" ? <ArticleImportTab onImported={() => void loadHistory()} /> : <>
      <div className="flex items-center justify-between gap-1 overflow-x-auto rounded-[16px] border border-white/50 bg-white/40 p-2 text-xs backdrop-blur-sm dark:border-white/[0.08] dark:bg-white/[0.04]">
        {stepsList.map((s, idx) => {
          const isActive = s.key === step || (step === "preview" && s.key === "upload") || (step === "committing" && (s.key === "upload" || s.key === "preview")) || (step === "success");
          const isCurrent = s.key === step;
          return (
            <div key={s.key} className={`flex items-center gap-1.5 px-3 py-1.5 rounded-xl font-medium transition ${isCurrent ? "bg-accent text-white shadow-[0_2px_8px_rgba(0,122,255,0.3)]" : isActive ? "text-accent font-semibold" : "text-tertiary-label"}`}>
              <span>{s.label}</span>
              {idx < stepsList.length - 1 && <span className="opacity-30">/</span>}
            </div>
          );
        })}
      </div>
      {error && step !== "preview" && <ErrorBox message={error} />}
      {step === "upload" && <Card><CardContent className="pt-5"><button type="button" onClick={() => inputRef.current?.click()} onDragOver={(event) => { event.preventDefault(); setDragging(true); }} onDragLeave={() => setDragging(false)} onDrop={(event) => { event.preventDefault(); setDragging(false); void selectFile(event.dataTransfer.files[0]); }} className={`glass-inner flex min-h-80 w-full flex-col items-center justify-center rounded-2xl border-2 border-dashed p-8 text-center transition ${dragging ? "border-accent bg-accent/[0.06] shadow-[0_12px_40px_rgba(0,122,255,0.12)]" : "border-white/60 hover:border-accent/40 hover:shadow-[0_12px_40px_rgba(0,122,255,0.08)] dark:border-white/[0.1]"}`}><span className="grid size-16 place-items-center rounded-3xl bg-accent/12 text-accent shadow-[0_8px_24px_rgba(0,122,255,0.12)]"><Upload className="size-8" /></span><h2 className="mt-5 text-lg font-semibold">拖拽 CSV 到这里，或点击选择</h2><p className="mt-2 text-sm text-secondary-label">需要包含 queryText、queryFromLanguage、queryToLanguage；支持 timestamp。最大 10MB / 20,000 行。</p><span className="mt-5 glass-inner rounded-full px-4 py-2 text-xs text-secondary-label">UTF-8 · EasyDict Favorites CSV</span></button><input ref={inputRef} type="file" accept=".csv,text/csv" hidden onChange={(event) => void selectFile(event.target.files?.[0])} /></CardContent></Card>}

      {step === "preview" && !preview && <Card><CardContent className="grid min-h-72 place-items-center"><div className="text-center"><Loader2 className="mx-auto size-9 animate-spin text-accent" /><p className="mt-3 text-sm text-secondary-label">正在解析 CSV 并检查已有词条…</p></div></CardContent></Card>}

      {step === "preview" && preview && <div className="space-y-5">
        <Card><CardHeader><div className="flex flex-wrap items-center justify-between gap-3"><div><CardTitle className="flex items-center gap-2"><FileText className="size-5 text-accent" />{preview.filename}</CardTitle><p className="mt-1 text-sm text-secondary-label">预览在 {new Date(preview.expiresAt).toLocaleTimeString("zh-CN")} 前有效</p></div><Button variant="ghost" onClick={restart}><RotateCcw className="size-4" />重新选择</Button></div></CardHeader><CardContent><div className="grid grid-cols-2 gap-3 sm:grid-cols-5"><Metric label="总行数" value={preview.totalRows} /><Metric label="新增" value={preview.newRows} tone="green" /><Metric label="已存在" value={preview.existingRows} tone="blue" /><Metric label="重复" value={preview.duplicateRows} tone="amber" /><Metric label="无效" value={preview.invalidRows} tone="red" /></div><div className="mt-5 flex flex-wrap gap-2">{Object.entries(preview.languages).map(([language, count]) => <Badge key={language} tone="blue">{language} · {count}</Badge>)}{Object.entries(preview.entryTypes).map(([type, count]) => <Badge key={type}>{entryTypeLabel(type)} · {count}</Badge>)}</div></CardContent></Card>
        <Card><CardHeader><CardTitle>词条预览</CardTitle></CardHeader><CardContent><div className="max-h-96 overflow-auto glass-inner rounded-xl"><table className="w-full min-w-[680px] text-left text-sm"><thead className="sticky top-0 bg-white/60 text-xs text-secondary-label backdrop-blur-xl dark:bg-white/[0.06] dark:text-secondary-label"><tr><th className="p-3">行</th><th className="p-3">词条</th><th className="p-3">语言</th><th className="p-3">类型</th><th className="p-3">状态</th><th className="p-3">说明</th></tr></thead><tbody>{preview.rows.slice(0, 200).map((row) => <tr key={row.rowNumber} className="border-t border-black/[0.04] dark:border-white/[0.06]"><td className="p-3 text-tertiary-label">{row.rowNumber}</td><td className="p-3 font-medium">{row.term || "—"}</td><td className="p-3 text-secondary-label">{row.sourceLanguage} → {row.targetLanguage}</td><td className="p-3">{entryTypeLabel(row.entryType)}</td><td className="p-3"><RowStatus status={row.status} /></td><td className="max-w-xs p-3 text-xs text-tertiary-label">{row.errors.join("；") || "—"}</td></tr>)}</tbody></table></div>{preview.rows.length > 200 && <p className="mt-2 text-xs text-tertiary-label">仅显示前 200 行，提交时会处理全部 {preview.rows.length} 行。</p>}</CardContent></Card>
        <Card><CardHeader><CardTitle>导入策略</CardTitle></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 lg:grid-cols-3">{[
          { value: "FILL_MISSING", title: "智能补充", description: "新增词条，并给已有词条补充缺失的释义、发音和例句。" },
          { value: "SKIP_EXISTING", title: "仅新增", description: "已有词条完全跳过，不创建初始化任务。" },
          { value: "FORCE_DICTIONARY_REFRESH", title: "强制刷新", description: "重新查询已有词条的词典内容，但保留学习进度。" },
        ].map((item) => <label key={item.value} className={`cursor-pointer rounded-[18px] border p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm transition ${mode === item.value ? "border-accent/40 bg-accent/[0.06] ring-2 ring-accent/15" : "border-white/50 bg-white/40 hover:border-white/70 dark:border-white/[0.08] dark:bg-white/[0.04]"}`}><input className="sr-only" type="radio" name="mode" checked={mode === item.value} onChange={() => setMode(item.value as ImportMode)} /><b className="text-sm">{item.title}</b><p className="mt-1 text-xs leading-5 text-secondary-label">{item.description}</p></label>)}</div><label className="flex items-start gap-3 rounded-[18px] border border-danger/20 bg-danger/[0.05] p-4 text-sm shadow-[0_4px_16px_rgba(255,59,48,0.04)] backdrop-blur-sm"><input type="checkbox" className="mt-1 accent-danger" checked={reset} onChange={(event) => setReset(event.target.checked)} /><span><b className="text-danger-deep">重置本次已有词条的学习进度</b><span className="mt-1 block text-xs text-danger/70">删除复习卡、复习日志和错词状态，词典内容不会删除。</span></span></label>{error && <ErrorBox message={error} />}<div className="flex justify-end"><Button size="lg" onClick={() => void commit()} disabled={preview.validRows === 0}>确认导入<ArrowRight className="size-5" /></Button></div></CardContent></Card>
      </div>}

      {step === "committing" && <Card><CardContent className="py-20 text-center"><Loader2 className="mx-auto size-12 animate-spin text-accent" /><h2 className="mt-5 text-xl font-semibold">正在写入词库</h2><p className="mt-2 text-sm text-secondary-label">创建初始化任务并应用导入策略，请勿重复提交。</p><Progress value={0} indeterminate className="mx-auto mt-6 max-w-md" /></CardContent></Card>}

      {step === "success" && result && <Card><CardContent className="py-16 text-center"><span className="mx-auto grid size-20 place-items-center rounded-full bg-success/12 text-success shadow-[0_8px_32px_rgba(52,199,89,0.15)]"><CheckCircle2 className="size-10" /></span><h2 className="mt-5 text-2xl font-bold">导入完成</h2><p className="mt-2 text-sm text-secondary-label">新增 {result.createdWords} 个，识别已有 {result.existingWords} 个，新增初始化任务 {result.queuedInitializations} 个。</p><div className="mt-7 flex flex-wrap justify-center gap-3"><Link href="/initialize" className={buttonClass("primary")}><Loader2 className="size-4" />查看初始化</Link><Link href="/words" className={buttonClass("outline")}>打开单词本</Link><Button variant="ghost" onClick={restart}>继续导入</Button></div></CardContent></Card>}
    </>}

    <Card><CardHeader><CardTitle className="flex items-center gap-2"><History className="size-5 text-accent" />最近导入</CardTitle></CardHeader><CardContent className="space-y-3">{historyMessage && <div className="rounded-[16px] border border-success/10 bg-success/[0.06] p-3 text-sm text-success-deep shadow-[0_4px_12px_rgba(52,199,89,0.04)] backdrop-blur-sm dark:text-success">{historyMessage}</div>}{history.length ? history.map((batch) => <div key={batch.id} className="flex flex-col gap-3 rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_8px_32px_rgba(0,0,0,0.04)] backdrop-blur-xl sm:flex-row sm:items-center sm:justify-between dark:border-white/[0.08] dark:bg-white/[0.04]"><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><b className="truncate text-sm">{batch.filename}</b><BatchStatus status={batch.status} /><span className="text-xs text-tertiary-label">#{batch.id}</span></div><p className="mt-1 text-xs text-secondary-label">{formatDate(batch.createdAt)} · 新增 {batch.createdWords} · 已有 {batch.existingWords} · 初始化 {batch.queuedInitializations}</p>{!batch.rollback.canRollback && batch.status === "COMMITTED" && <p className="mt-1 text-xs text-warning">{batch.rollback.reason}</p>}</div><Button variant="outline" size="sm" disabled={!batch.rollback.canRollback || rollbackBusy !== null} onClick={() => void rollback(batch)}>{rollbackBusy === batch.id ? <Loader2 className="size-4 animate-spin" /> : <Undo2 className="size-4" />}撤销</Button></div>) : <p className="py-6 text-center text-sm text-secondary-label">暂无导入历史。</p>}</CardContent></Card>
  </div>;
}
function Metric({ label, value, tone = "slate" }: { label: string; value: number; tone?: "slate" | "green" | "blue" | "amber" | "red" }) { const colors = { slate: "text-label", green: "text-success", blue: "text-accent", amber: "text-warning", red: "text-danger" }; return <div className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><p className={`text-2xl font-bold ${colors[tone]}`}>{value}</p><p className="text-xs text-secondary-label">{label}</p></div>; }
function RowStatus({ status }: { status: string }) { const values: Record<string, [string, "green" | "blue" | "amber" | "red"]> = { NEW: ["新增", "green"], EXISTING: ["已存在", "blue"], DUPLICATE: ["重复", "amber"], INVALID: ["无效", "red"] }; const value = values[status] ?? [status, "blue"]; return <Badge tone={value[1]}>{value[0]}</Badge>; }
function ErrorBox({ message }: { message: string }) { return <Alert className="mt-4" icon={<AlertCircle className="size-4" />}>{message}</Alert>; }

function BatchStatus({ status }: { status: string }) { const map: Record<string, [string, "green" | "amber" | "red" | "slate"]> = { COMMITTED: ["已提交", "green"], ROLLED_BACK: ["已撤销", "slate"], FAILED: ["失败", "red"], PENDING: ["处理中", "amber"] }; const value = map[status] ?? [status, "slate"]; return <Badge tone={value[1]}>{value[0]}</Badge>; }
