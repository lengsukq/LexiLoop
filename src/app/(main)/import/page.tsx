"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { AlertCircle, ArrowRight, CheckCircle2, FileText, History, Loader2, RotateCcw, Undo2, Upload } from "lucide-react";
import { apiFetch, formatDate } from "@/lib/client-api";
import type { ImportMode, ImportPreview } from "@/lib/types";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, PageHeader, Progress, buttonClass } from "@/components/ui";

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
      setPreview(await apiFetch<ImportPreview>("/api/imports/preview", { method: "POST", body: form }));
    } catch (reason) { setStep("upload"); setError(reason instanceof Error ? reason.message : "生成预览失败"); }
  }
  async function commit() {
    if (!preview) return;
    setStep("committing"); setError("");
    try {
      const data = await apiFetch<CommitResult>("/api/imports/commit", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ previewToken: preview.previewToken, mode, resetLearningProgress: reset }) });
      setResult(data); setStep("success"); await loadHistory();
    } catch (reason) { setStep("preview"); setError(reason instanceof Error ? reason.message : "提交导入失败"); }
  }
  function restart() { setStep("upload"); setPreview(null); setResult(null); setError(""); if (inputRef.current) inputRef.current.value = ""; }
  async function rollback(batch: ImportBatch) {
    if (!batch.rollback.canRollback || !window.confirm(`确定撤销“${batch.filename}”吗？仅会删除该批次新建且尚未学习的词条。`)) return;
    setRollbackBusy(batch.id); setError(""); setHistoryMessage("");
    try {
      const result = await apiFetch<{ deletedWords: number }>(`/api/imports/${batch.id}/rollback`, { method: "POST" });
      setHistoryMessage(`已撤销批次 #${batch.id}，删除 ${result.deletedWords} 个未学习词条。`);
      await loadHistory();
    } catch (reason) { setError(reason instanceof Error ? reason.message : "撤销导入失败"); }
    finally { setRollbackBusy(null); }
  }

  return <div className="space-y-6"><PageHeader title="导入 EasyDict CSV" description="解析、去重和预览后再写入词库。只初始化你实际导入的词条。" />
    {error && step !== "preview" && <ErrorBox message={error} />}
    {step === "upload" && <Card><CardContent className="pt-5"><button type="button" onClick={() => inputRef.current?.click()} onDragOver={(event) => { event.preventDefault(); setDragging(true); }} onDragLeave={() => setDragging(false)} onDrop={(event) => { event.preventDefault(); setDragging(false); void selectFile(event.dataTransfer.files[0]); }} className={`flex min-h-80 w-full flex-col items-center justify-center rounded-2xl border-2 border-dashed p-8 text-center transition ${dragging ? "border-indigo-500 bg-indigo-50 dark:bg-indigo-950/30" : "border-slate-300 hover:border-indigo-400 hover:bg-slate-50 dark:border-slate-700 dark:hover:bg-slate-800/50"}`}><span className="grid size-16 place-items-center rounded-3xl bg-indigo-100 text-indigo-600 dark:bg-indigo-950"><Upload className="size-8" /></span><h2 className="mt-5 text-lg font-semibold">拖拽 CSV 到这里，或点击选择</h2><p className="mt-2 text-sm text-slate-500">需要包含 queryText、queryFromLanguage、queryToLanguage；支持 timestamp。最大 10MB / 20,000 行。</p><span className="mt-5 rounded-full bg-slate-100 px-4 py-2 text-xs text-slate-500 dark:bg-slate-800">UTF-8 · EasyDict Favorites CSV</span></button><input ref={inputRef} type="file" accept=".csv,text/csv" hidden onChange={(event) => void selectFile(event.target.files?.[0])} /></CardContent></Card>}

    {step === "preview" && !preview && <Card><CardContent className="grid min-h-72 place-items-center"><div className="text-center"><Loader2 className="mx-auto size-9 animate-spin text-indigo-500" /><p className="mt-3 text-sm text-slate-500">正在解析 CSV 并检查已有词条…</p></div></CardContent></Card>}

    {step === "preview" && preview && <div className="space-y-5">
      <Card><CardHeader><div className="flex flex-wrap items-center justify-between gap-3"><div><CardTitle className="flex items-center gap-2"><FileText className="size-5 text-indigo-500" />{preview.filename}</CardTitle><p className="mt-1 text-sm text-slate-500">预览在 {new Date(preview.expiresAt).toLocaleTimeString("zh-CN")} 前有效</p></div><Button variant="ghost" onClick={restart}><RotateCcw className="size-4" />重新选择</Button></div></CardHeader><CardContent><div className="grid grid-cols-2 gap-3 sm:grid-cols-5"><Metric label="总行数" value={preview.totalRows} /><Metric label="新增" value={preview.newRows} tone="green" /><Metric label="已存在" value={preview.existingRows} tone="blue" /><Metric label="重复" value={preview.duplicateRows} tone="amber" /><Metric label="无效" value={preview.invalidRows} tone="red" /></div><div className="mt-5 flex flex-wrap gap-2">{Object.entries(preview.languages).map(([language, count]) => <Badge key={language} tone="blue">{language} · {count}</Badge>)}{Object.entries(preview.entryTypes).map(([type, count]) => <Badge key={type}>{type === "WORD" ? "单词" : "短语"} · {count}</Badge>)}</div></CardContent></Card>
      <Card><CardHeader><CardTitle>词条预览</CardTitle></CardHeader><CardContent><div className="max-h-96 overflow-auto rounded-xl border border-slate-200 dark:border-slate-800"><table className="w-full min-w-[680px] text-left text-sm"><thead className="sticky top-0 bg-slate-50 text-xs text-slate-500 dark:bg-slate-900"><tr><th className="p-3">行</th><th className="p-3">词条</th><th className="p-3">语言</th><th className="p-3">类型</th><th className="p-3">状态</th><th className="p-3">说明</th></tr></thead><tbody>{preview.rows.slice(0, 200).map((row) => <tr key={row.rowNumber} className="border-t border-slate-100 dark:border-slate-800"><td className="p-3 text-slate-400">{row.rowNumber}</td><td className="p-3 font-medium">{row.term || "—"}</td><td className="p-3 text-slate-500">{row.sourceLanguage} → {row.targetLanguage}</td><td className="p-3">{row.entryType === "WORD" ? "单词" : "短语"}</td><td className="p-3"><RowStatus status={row.status} /></td><td className="max-w-xs p-3 text-xs text-slate-400">{row.errors.join("；") || "—"}</td></tr>)}</tbody></table></div>{preview.rows.length > 200 && <p className="mt-2 text-xs text-slate-400">仅显示前 200 行，提交时会处理全部 {preview.rows.length} 行。</p>}</CardContent></Card>
      <Card><CardHeader><CardTitle>导入策略</CardTitle></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 lg:grid-cols-3">{[
        { value: "FILL_MISSING", title: "智能补充", description: "新增词条，并给已有词条补充缺失的释义、发音和例句。" },
        { value: "SKIP_EXISTING", title: "仅新增", description: "已有词条完全跳过，不创建初始化任务。" },
        { value: "FORCE_DICTIONARY_REFRESH", title: "强制刷新", description: "重新查询已有词条的词典内容，但保留学习进度。" },
      ].map((item) => <label key={item.value} className={`cursor-pointer rounded-2xl border p-4 transition ${mode === item.value ? "border-indigo-500 bg-indigo-50 ring-2 ring-indigo-100 dark:bg-indigo-950/30 dark:ring-indigo-950" : "border-slate-200 hover:border-slate-300 dark:border-slate-700"}`}><input className="sr-only" type="radio" name="mode" checked={mode === item.value} onChange={() => setMode(item.value as ImportMode)} /><b className="text-sm">{item.title}</b><p className="mt-1 text-xs leading-5 text-slate-500">{item.description}</p></label>)}</div><label className="flex items-start gap-3 rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm dark:border-rose-900 dark:bg-rose-950/20"><input type="checkbox" className="mt-1" checked={reset} onChange={(event) => setReset(event.target.checked)} /><span><b className="text-rose-700 dark:text-rose-300">重置本次已有词条的学习进度</b><span className="mt-1 block text-xs text-rose-600/80 dark:text-rose-300/70">删除复习卡、复习日志和错词状态，词典内容不会删除。</span></span></label>{error && <ErrorBox message={error} />}<div className="flex justify-end"><Button size="lg" onClick={() => void commit()} disabled={preview.validRows === 0}>确认导入<ArrowRight className="size-5" /></Button></div></CardContent></Card>
    </div>}

    {step === "committing" && <Card><CardContent className="py-20 text-center"><Loader2 className="mx-auto size-12 animate-spin text-indigo-500" /><h2 className="mt-5 text-xl font-semibold">正在写入词库</h2><p className="mt-2 text-sm text-slate-500">创建初始化任务并应用导入策略，请勿重复提交。</p><Progress value={75} className="mx-auto mt-6 max-w-md" /></CardContent></Card>}

    {step === "success" && result && <Card><CardContent className="py-16 text-center"><span className="mx-auto grid size-20 place-items-center rounded-full bg-emerald-100 text-emerald-600 dark:bg-emerald-950"><CheckCircle2 className="size-10" /></span><h2 className="mt-5 text-2xl font-bold">导入完成</h2><p className="mt-2 text-sm text-slate-500">新增 {result.createdWords} 个，识别已有 {result.existingWords} 个，新增初始化任务 {result.queuedInitializations} 个。</p><div className="mt-7 flex flex-wrap justify-center gap-3"><Link href="/initialize" className={buttonClass("primary")}><Loader2 className="size-4" />查看初始化</Link><Link href="/words" className={buttonClass("outline")}>打开单词本</Link><Button variant="ghost" onClick={restart}>继续导入</Button></div></CardContent></Card>}

    <Card><CardHeader><CardTitle className="flex items-center gap-2"><History className="size-5 text-indigo-500" />最近导入</CardTitle></CardHeader><CardContent className="space-y-3">{historyMessage && <div className="rounded-xl bg-emerald-50 p-3 text-sm text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300">{historyMessage}</div>}{history.length ? history.map((batch) => <div key={batch.id} className="flex flex-col gap-3 rounded-2xl border border-slate-200 p-4 sm:flex-row sm:items-center sm:justify-between dark:border-slate-700"><div className="min-w-0"><div className="flex flex-wrap items-center gap-2"><b className="truncate text-sm">{batch.filename}</b><BatchStatus status={batch.status} /><span className="text-xs text-slate-400">#{batch.id}</span></div><p className="mt-1 text-xs text-slate-500">{formatDate(batch.createdAt)} · 新增 {batch.createdWords} · 已有 {batch.existingWords} · 初始化 {batch.queuedInitializations}</p>{!batch.rollback.canRollback && batch.status === "COMMITTED" && <p className="mt-1 text-xs text-amber-600">{batch.rollback.reason}</p>}</div><Button variant="outline" size="sm" disabled={!batch.rollback.canRollback || rollbackBusy !== null} onClick={() => void rollback(batch)}>{rollbackBusy === batch.id ? <Loader2 className="size-4 animate-spin" /> : <Undo2 className="size-4" />}撤销</Button></div>) : <p className="py-6 text-center text-sm text-slate-500">暂无导入历史。</p>}</CardContent></Card>
  </div>;
}
function Metric({ label, value, tone = "slate" }: { label: string; value: number; tone?: "slate" | "green" | "blue" | "amber" | "red" }) { const colors = { slate: "text-slate-900 dark:text-white", green: "text-emerald-600", blue: "text-sky-600", amber: "text-amber-600", red: "text-rose-600" }; return <div className="rounded-2xl bg-slate-50 p-4 dark:bg-slate-800/60"><p className={`text-2xl font-bold ${colors[tone]}`}>{value}</p><p className="text-xs text-slate-500">{label}</p></div>; }
function RowStatus({ status }: { status: string }) { const values: Record<string, [string, "green" | "blue" | "amber" | "red"]> = { NEW: ["新增", "green"], EXISTING: ["已存在", "blue"], DUPLICATE: ["重复", "amber"], INVALID: ["无效", "red"] }; const value = values[status] ?? [status, "blue"]; return <Badge tone={value[1]}>{value[0]}</Badge>; }
function ErrorBox({ message }: { message: string }) { return <div className="mt-4 flex items-start gap-2 rounded-xl bg-rose-50 p-3 text-sm text-rose-700 dark:bg-rose-950/30 dark:text-rose-300"><AlertCircle className="mt-0.5 size-4 shrink-0" />{message}</div>; }

function BatchStatus({ status }: { status: string }) { const map: Record<string, [string, "green" | "amber" | "red" | "slate"]> = { COMMITTED: ["已提交", "green"], ROLLED_BACK: ["已撤销", "slate"], FAILED: ["失败", "red"], PENDING: ["处理中", "amber"] }; const value = map[status] ?? [status, "slate"]; return <Badge tone={value[1]}>{value[0]}</Badge>; }
