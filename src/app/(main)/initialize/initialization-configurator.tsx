"use client";

import { useEffect, useMemo, useState, type Dispatch, type SetStateAction } from "react";
import {
  ArrowDown, ArrowUp, BookOpen, CheckCircle2, ChevronDown, Database, ListChecks,
  Loader2, LockKeyhole, Search, Sparkles, Volume2,
} from "lucide-react";
import type { InitializationField, InitializationProviderId, ProviderStrategy } from "@/lib/types";
import { apiFetch } from "@/lib/client-api";
import { Badge, Button } from "@/components/ui";

interface ProviderOption {
  id: InitializationProviderId;
  label: string;
  available: boolean;
  enabled: boolean;
  reason: string | null;
  capabilities: InitializationField[];
}
interface OptionsData { providers: ProviderOption[]; }
interface PreviewData {
  scope: "ALL" | "SELECTED";
  requestedWords: number;
  existingWords: number;
  selectedWords: number;
  skippedExisting: number;
  requestedFields: InitializationField[];
  requestedProviders: InitializationProviderId[];
  providerStrategy: ProviderStrategy;
  mode: "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE";
  sample: Array<{ id: number; term: string }>;
}
interface WordSearchData {
  items: Array<{ id: number; term: string; definition: string | null; hasPronunciation: boolean }>;
}

const FIELD_LABELS: Record<InitializationField, string> = {
  definitions: "释义",
  "pronunciations.phonetic": "音标",
  "pronunciations.audio": "真人音频",
  examples: "例句",
  phrases: "搭配与短语",
  forms: "词形变化",
  synonyms: "近义词",
  antonyms: "反义词",
  wordFamily: "同根词",
  confusedWords: "易混词",
  roots: "词根",
  affixes: "词缀",
  tags: "标签",
  summary: "概要",
  learning: "助记与学习提示",
  sentenceAnalysis: "句子分析",
};

const FIELD_GROUPS: Array<{ label: string; fields: InitializationField[] }> = [
  { label: "基础信息", fields: ["definitions", "pronunciations.phonetic", "pronunciations.audio", "forms"] },
  { label: "学习内容", fields: ["examples", "phrases", "synonyms", "antonyms", "wordFamily", "confusedWords"] },
  { label: "扩展内容", fields: ["roots", "affixes", "tags", "summary", "learning", "sentenceAnalysis"] },
];

const YOUDAO_FIELDS: InitializationField[] = [
  "definitions", "pronunciations.phonetic", "examples", "phrases", "forms", "summary",
];

type SourceMode = "GENERAL" | "YOUDAO_ONLY";

const PRESETS: Array<{ id: string; label: string; description: string; icon: typeof Volume2; fields: InitializationField[]; sourceMode?: SourceMode }> = [
  {
    id: "phonetic",
    label: "仅补音标",
    description: "适合新配置词典后补齐音标",
    icon: Volume2,
    fields: ["pronunciations.phonetic"],
  },
  {
    id: "basic",
    label: "基础词典信息",
    description: "释义、音标、音频和词形",
    icon: BookOpen,
    fields: ["definitions", "pronunciations.phonetic", "pronunciations.audio", "forms"],
  },
  {
    id: "full",
    label: "完整初始化",
    description: "生成完整学习内容",
    icon: Sparkles,
    fields: FIELD_GROUPS.flatMap((group) => group.fields),
  },
  {
    id: "youdao",
    label: "有道词典",
    description: "仅使用有道词典的权威内容",
    icon: Database,
    fields: YOUDAO_FIELDS,
    sourceMode: "YOUDAO_ONLY",
  },
];

const PROVIDER_PRIORITY: InitializationProviderId[] = ["merriam-webster", "dictionaryapi.dev", "ai", "youdao", "mymemory", "tencent-translate"];

function sameFields(left: InitializationField[], right: InitializationField[]) {
  return left.length === right.length && left.every((field) => right.includes(field));
}

export function InitializationConfigurator({
  selectedWordIds,
  setSelectedWordIds,
  onQueued,
  requestedScope,
}: {
  selectedWordIds: Set<number>;
  setSelectedWordIds: Dispatch<SetStateAction<Set<number>>>;
  onQueued: () => Promise<void> | void;
  requestedScope?: "ALL" | "SELECTED";
}) {
  const [options, setOptions] = useState<OptionsData | null>(null);
  const [requestedFields, setRequestedFields] = useState<InitializationField[]>(["pronunciations.phonetic"]);
  const [requestedProviders, setRequestedProviders] = useState<InitializationProviderId[]>([]);
  const [providerStrategy, setProviderStrategy] = useState<ProviderStrategy>("PRIORITY_FALLBACK");
  const [sourceMode, setSourceMode] = useState<SourceMode>("GENERAL");
  const [mode, setMode] = useState<"FILL_MISSING_FIELDS" | "FORCE_OVERWRITE">("FILL_MISSING_FIELDS");
  const [scope, setScope] = useState<"ALL" | "SELECTED">(requestedScope ?? "ALL");
  const [wordQuery, setWordQuery] = useState("");
  const [wordResults, setWordResults] = useState<WordSearchData["items"]>([]);
  const [busy, setBusy] = useState<"options" | "words" | "preview" | "queue" | "">("options");
  const [preview, setPreview] = useState<PreviewData | null>(null);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  const activePreset = useMemo(
    () => PRESETS.find((preset) => (preset.sourceMode ?? "GENERAL") === sourceMode && sameFields(requestedFields, preset.fields)),
    [requestedFields, sourceMode],
  );
  const providerMap = useMemo(
    () => new Map(options?.providers.map((provider) => [provider.id, provider]) ?? []),
    [options],
  );

  useEffect(() => {
    let cancelled = false;
    void apiFetch<OptionsData>("/api/initialization/options")
      .then((value) => {
        if (cancelled) return;
        setOptions(value);
        setRequestedProviders(PROVIDER_PRIORITY.filter((id) => value.providers.some((provider) =>
          provider.id === id && provider.available && provider.capabilities.includes("pronunciations.phonetic"))));
        setError("");
      })
      .catch((reason) => { if (!cancelled) setError(reason instanceof Error ? reason.message : "加载初始化来源失败"); })
      .finally(() => { if (!cancelled) setBusy(""); });
    return () => { cancelled = true; };
  }, []);

  function invalidatePreview() {
    setPreview(null);
    setMessage("");
  }

  function eligibleProviders(fields: InitializationField[]): InitializationProviderId[] {
    return PROVIDER_PRIORITY.filter((id) => options?.providers.some((provider) =>
      provider.id === id && provider.available && fields.some((field) => provider.capabilities.includes(field))));
  }

  function applyFields(fields: InitializationField[], nextSourceMode = sourceMode) {
    const nextFields = [...new Set(fields)];
    setRequestedFields(nextFields);
    if (nextSourceMode === "YOUDAO_ONLY") {
      setRequestedProviders(["youdao"]);
      setProviderStrategy("PRIORITY_FALLBACK");
    } else if (options) {
      const eligible = eligibleProviders(nextFields);
      setRequestedProviders((current) => {
        const retained = current.filter((id) => eligible.includes(id));
        return [...retained, ...eligible.filter((id) => !retained.includes(id))];
      });
    }
    invalidatePreview();
  }

  function toggleField(field: InitializationField) {
    applyFields(requestedFields.includes(field)
      ? requestedFields.filter((item) => item !== field)
      : [...requestedFields, field]);
  }

  function toggleProvider(provider: ProviderOption) {
    if (sourceMode === "YOUDAO_ONLY") return;
    if (!provider.available || !requestedFields.some((field) => provider.capabilities.includes(field))) return;
    setRequestedProviders((current) => current.includes(provider.id)
      ? current.filter((id) => id !== provider.id)
      : [...current, provider.id]);
    invalidatePreview();
  }

  function moveProvider(id: InitializationProviderId, offset: -1 | 1) {
    if (sourceMode === "YOUDAO_ONLY") return;
    setRequestedProviders((current) => {
      const index = current.indexOf(id);
      const target = index + offset;
      if (index < 0 || target < 0 || target >= current.length) return current;
      const next = [...current];
      [next[index], next[target]] = [next[target]!, next[index]!];
      return next;
    });
    invalidatePreview();
  }

  function applyPreset(preset: (typeof PRESETS)[number]) {
    const nextSourceMode = preset.sourceMode ?? "GENERAL";
    setSourceMode(nextSourceMode);
    applyFields(preset.fields, nextSourceMode);
  }

  function switchToGeneralSources() {
    setSourceMode("GENERAL");
    setRequestedProviders(eligibleProviders(requestedFields));
    setProviderStrategy("PRIORITY_FALLBACK");
    invalidatePreview();
  }

  async function searchWords() {
    setBusy("words");
    setError("");
    try {
      const params = new URLSearchParams({ q: wordQuery.trim(), limit: "20", sort: "term", order: "asc" });
      const result = await apiFetch<WordSearchData>(`/api/words?${params}`);
      setWordResults(result.items);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "搜索词条失败");
    } finally {
      setBusy("");
    }
  }

  function toggleWord(id: number) {
    setSelectedWordIds((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
    invalidatePreview();
  }

  function requestBody() {
    if (!requestedFields.length) throw new Error("请至少选择一个初始化字段。");
    if (!requestedProviders.length) throw new Error("请至少选择一个可用数据来源。");
    if (scope === "SELECTED" && !selectedWordIds.size) throw new Error("请先选择需要初始化的词条。");
    return {
      mode,
      onlyMissing: mode === "FILL_MISSING_FIELDS",
      requestedFields,
      requestedProviders,
      providerStrategy,
      ...(scope === "SELECTED" ? { wordIds: [...selectedWordIds] } : {}),
    };
  }

  async function calculatePreview() {
    setBusy("preview");
    setError("");
    setMessage("");
    try {
      setPreview(await apiFetch<PreviewData>("/api/initialization/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(requestBody()),
      }));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "计算初始化范围失败");
    } finally {
      setBusy("");
    }
  }

  async function createJobs() {
    if (mode === "FORCE_OVERWRITE" && !window.confirm("将只刷新本次选中的字段，其他内容保持不变。确定继续吗？")) return;
    setBusy("queue");
    setError("");
    setMessage("");
    try {
      const result = await apiFetch<PreviewData & { createdJobs: number; updatedJobs: number }>("/api/initialization/bulk", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(requestBody()),
      });
      setPreview(result);
      setMessage(`已创建 ${result.createdJobs} 个任务，合并 ${result.updatedJobs} 个现有任务。`);
      await onQueued();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "创建初始化任务失败");
    } finally {
      setBusy("");
    }
  }

  return <div id="initialization-configurator" className="space-y-5">
    <div className="flex items-center justify-between gap-3">
      <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">先选择常用方案，需要时再展开高级设置。</p>
      <Badge tone="blue">{activePreset?.label ?? `自定义 ${requestedFields.length} 项`}</Badge>
    </div>

    <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_320px]">
        <div className="min-w-0 space-y-5">
          <section>
            <div className="mb-3 flex items-center justify-between">
              <h3 className="text-sm font-semibold">选择初始化方案</h3>
              <span className="text-xs text-[#aeaeb2]">{requestedFields.length} 个字段</span>
            </div>
            <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-4">
              {PRESETS.map((preset) => {
                const selected = (preset.sourceMode ?? "GENERAL") === sourceMode && sameFields(requestedFields, preset.fields);
                const unavailable = preset.sourceMode === "YOUDAO_ONLY" && (options === null || !providerMap.get("youdao")?.available);
                return <button
                  key={preset.id}
                  type="button"
                  onClick={() => applyPreset(preset)}
                  disabled={unavailable}
                  className={`ios-press rounded-[16px] border p-3 text-left transition ${selected
                    ? "border-[#007aff]/30 bg-[#007aff]/[0.08] shadow-[0_6px_18px_rgba(0,122,255,0.08)]"
                    : "border-black/[0.06] bg-black/[0.02] hover:bg-black/[0.04] dark:border-white/[0.08] dark:bg-white/[0.03]"} ${unavailable ? "cursor-not-allowed opacity-50" : ""}`}
                >
                  <div className="flex items-center justify-between">
                    <span className={`grid size-9 place-items-center rounded-[12px] ${selected ? "bg-[#007aff] text-white" : "bg-black/[0.05] text-[#6e6e73] dark:bg-white/[0.07] dark:text-[#98989d]"}`}><preset.icon className="size-4" /></span>
                    {selected && <CheckCircle2 className="size-4 text-[#007aff]" />}
                  </div>
                  <b className="mt-3 block text-sm">{preset.label}</b>
                  <span className="mt-1 block text-xs leading-relaxed text-[#8e8e93]">{unavailable ? (options === null ? "正在检查有道词典状态…" : providerMap.get("youdao")?.reason ?? "有道词典当前不可用") : preset.description}</span>
                </button>;
              })}
            </div>
          </section>

          <section className="grid gap-3 sm:grid-cols-2">
            <div>
              <p className="mb-2 text-sm font-semibold">词条范围</p>
              <div className="grid grid-cols-2 rounded-[14px] bg-black/[0.04] p-1 dark:bg-white/[0.05]">
                <button type="button" onClick={() => { setScope("ALL"); invalidatePreview(); }} className={`rounded-[11px] px-3 py-2 text-sm font-medium transition ${scope === "ALL" ? "bg-white shadow-sm dark:bg-white/[0.12]" : "text-[#8e8e93]"}`}>全部词条</button>
                <button type="button" onClick={() => { setScope("SELECTED"); invalidatePreview(); }} className={`rounded-[11px] px-3 py-2 text-sm font-medium transition ${scope === "SELECTED" ? "bg-white shadow-sm dark:bg-white/[0.12]" : "text-[#8e8e93]"}`}>手动选择 {selectedWordIds.size ? `(${selectedWordIds.size})` : ""}</button>
              </div>
            </div>
            <div>
              <p className="mb-2 text-sm font-semibold">写入方式</p>
              <div className="grid grid-cols-2 rounded-[14px] bg-black/[0.04] p-1 dark:bg-white/[0.05]">
                <button type="button" onClick={() => { setMode("FILL_MISSING_FIELDS"); invalidatePreview(); }} className={`rounded-[11px] px-3 py-2 text-sm font-medium transition ${mode === "FILL_MISSING_FIELDS" ? "bg-white shadow-sm dark:bg-white/[0.12]" : "text-[#8e8e93]"}`}>仅补缺失</button>
                <button type="button" onClick={() => { setMode("FORCE_OVERWRITE"); invalidatePreview(); }} className={`rounded-[11px] px-3 py-2 text-sm font-medium transition ${mode === "FORCE_OVERWRITE" ? "bg-white shadow-sm dark:bg-white/[0.12]" : "text-[#8e8e93]"}`}>刷新所选</button>
              </div>
            </div>
          </section>

          {scope === "SELECTED" && <section className="rounded-[16px] border border-black/[0.06] p-3 dark:border-white/[0.08]">
            <div className="flex items-center justify-between gap-3">
              <div><p className="text-sm font-semibold">选择词条</p><p className="mt-0.5 text-xs text-[#8e8e93]">也可以直接使用下方任务记录中已勾选的词条。</p></div>
              {selectedWordIds.size > 0 && <button type="button" className="text-xs text-[#ff3b30]" onClick={() => { setSelectedWordIds(new Set()); invalidatePreview(); }}>清空 {selectedWordIds.size} 项</button>}
            </div>
            <div className="mt-3 flex gap-2">
              <input value={wordQuery} onChange={(event) => setWordQuery(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") void searchWords(); }} placeholder="搜索单词或短语" className="h-10 min-w-0 flex-1 rounded-[12px] border border-black/[0.07] bg-white/60 px-3 text-sm outline-none focus:border-[#007aff]/40 dark:border-white/[0.08] dark:bg-white/[0.04]" />
              <Button variant="outline" size="sm" onClick={() => void searchWords()} disabled={busy === "words"}>{busy === "words" ? <Loader2 className="size-4 animate-spin" /> : <Search className="size-4" />}搜索</Button>
            </div>
            {wordResults.length > 0 && <div className="mt-3 grid max-h-52 gap-2 overflow-y-auto sm:grid-cols-2">
              {wordResults.map((word) => <label key={word.id} className="flex cursor-pointer items-start gap-2 rounded-[12px] bg-black/[0.025] p-2.5 text-sm dark:bg-white/[0.035]">
                <input className="mt-1" type="checkbox" checked={selectedWordIds.has(word.id)} onChange={() => toggleWord(word.id)} />
                <span className="min-w-0"><b className="block truncate">{word.term}</b><span className="block truncate text-xs text-[#8e8e93]">{word.definition ?? "暂无释义"}</span></span>
              </label>)}
            </div>}
          </section>}

          <details className="group rounded-[16px] border border-black/[0.06] dark:border-white/[0.08]">
            <summary className="flex cursor-pointer list-none items-center justify-between p-4">
              <div className="flex items-center gap-3"><span className="grid size-9 place-items-center rounded-[12px] bg-[#5856d6]/10 text-[#5856d6]"><ListChecks className="size-4" /></span><div><p className="text-sm font-semibold">自定义内容字段</p><p className="text-xs text-[#8e8e93]">当前已选：{requestedFields.map((field) => FIELD_LABELS[field]).join("、") || "无"}</p></div></div>
              <ChevronDown className="size-4 text-[#8e8e93] transition group-open:rotate-180" />
            </summary>
            <div className="border-t border-black/[0.05] p-4 dark:border-white/[0.07]">
              <div className="grid gap-4 md:grid-cols-3">{FIELD_GROUPS.map((group) => <div key={group.label}><p className="mb-2 text-xs font-semibold text-[#8e8e93]">{group.label}</p><div className="space-y-2">{group.fields.map((field) => <label key={field} className="flex cursor-pointer items-center gap-2 text-sm"><input type="checkbox" checked={requestedFields.includes(field)} onChange={() => toggleField(field)} />{FIELD_LABELS[field]}</label>)}</div></div>)}</div>
            </div>
          </details>

          <details className="group rounded-[16px] border border-black/[0.06] dark:border-white/[0.08]">
            <summary className="flex cursor-pointer list-none items-center justify-between p-4">
              <div className="flex min-w-0 items-center gap-3"><span className="grid size-9 shrink-0 place-items-center rounded-[12px] bg-[#007aff]/10 text-[#007aff]"><Database className="size-4" /></span><div className="min-w-0"><p className="text-sm font-semibold">数据来源与执行策略</p><p className="truncate text-xs text-[#8e8e93]">{requestedProviders.map((id) => providerMap.get(id)?.label ?? id).join(" → ") || "尚未选择来源"}</p></div></div>
              <ChevronDown className="size-4 shrink-0 text-[#8e8e93] transition group-open:rotate-180" />
            </summary>
            <div className="space-y-4 border-t border-black/[0.05] p-4 dark:border-white/[0.07]">
              {sourceMode === "YOUDAO_ONLY" ? <div className="rounded-[14px] border border-[#007aff]/15 bg-[#007aff]/[0.06] p-3">
                <div className="flex items-start gap-3">
                  <span className="grid size-9 shrink-0 place-items-center rounded-[12px] bg-[#007aff]/10 text-[#007aff]"><LockKeyhole className="size-4" /></span>
                  <div className="min-w-0 flex-1"><p className="text-sm font-semibold">已锁定为有道词典</p><p className="mt-1 text-xs leading-relaxed text-[#6e6e73] dark:text-[#98989d]">本次任务只会请求有道词典，不会调用其他词典、翻译服务或 AI。</p></div>
                </div>
                <button type="button" onClick={switchToGeneralSources} className="mt-3 text-xs font-semibold text-[#007aff] dark:text-[#0a84ff]">切换为自定义来源</button>
              </div> : busy === "options" ? <div className="flex items-center gap-2 text-sm text-[#8e8e93]"><Loader2 className="size-4 animate-spin" />加载来源状态…</div> : <div className="space-y-2">{options?.providers.map((provider) => {
                const compatible = requestedFields.some((field) => provider.capabilities.includes(field));
                const selectedIndex = requestedProviders.indexOf(provider.id);
                const selectable = provider.available && compatible;
                return <div key={provider.id} className={`flex items-center gap-3 rounded-[14px] border p-3 ${selectedIndex >= 0 ? "border-[#007aff]/20 bg-[#007aff]/[0.05]" : "border-black/[0.05] dark:border-white/[0.07]"}`}>
                  <input type="checkbox" checked={selectedIndex >= 0} disabled={!selectable} onChange={() => toggleProvider(provider)} />
                  <div className="min-w-0 flex-1"><div className="flex flex-wrap items-center gap-2"><b className="text-sm">{provider.label}</b>{selectedIndex >= 0 && <Badge tone="blue">{selectedIndex + 1}</Badge>}{!provider.available && <Badge tone="amber">不可用</Badge>}</div><p className="mt-1 text-xs text-[#8e8e93]">{provider.reason ?? (compatible ? provider.capabilities.filter((field) => requestedFields.includes(field)).map((field) => FIELD_LABELS[field]).join("、") : "不支持当前字段")}</p></div>
                  {selectedIndex >= 0 && <div className="flex gap-1"><button type="button" aria-label="提高优先级" disabled={selectedIndex === 0} onClick={() => moveProvider(provider.id, -1)} className="grid size-8 place-items-center rounded-[10px] hover:bg-black/[0.05] disabled:opacity-30 dark:hover:bg-white/[0.06]"><ArrowUp className="size-4" /></button><button type="button" aria-label="降低优先级" disabled={selectedIndex === requestedProviders.length - 1} onClick={() => moveProvider(provider.id, 1)} className="grid size-8 place-items-center rounded-[10px] hover:bg-black/[0.05] disabled:opacity-30 dark:hover:bg-white/[0.06]"><ArrowDown className="size-4" /></button></div>}
                </div>;
              })}</div>}
              {sourceMode === "GENERAL" && <div className="grid gap-2 sm:grid-cols-2">
                <label className={`cursor-pointer rounded-[14px] border p-3 text-sm ${providerStrategy === "PRIORITY_FALLBACK" ? "border-[#007aff]/25 bg-[#007aff]/[0.05]" : "border-black/[0.05] dark:border-white/[0.07]"}`}><input className="mr-2" type="radio" checked={providerStrategy === "PRIORITY_FALLBACK"} onChange={() => { setProviderStrategy("PRIORITY_FALLBACK"); invalidatePreview(); }} />按优先级回退<p className="ml-5 mt-1 text-xs text-[#8e8e93]">满足字段后停止请求后续来源。</p></label>
                <label className={`cursor-pointer rounded-[14px] border p-3 text-sm ${providerStrategy === "PARALLEL_MERGE" ? "border-[#007aff]/25 bg-[#007aff]/[0.05]" : "border-black/[0.05] dark:border-white/[0.07]"}`}><input className="mr-2" type="radio" checked={providerStrategy === "PARALLEL_MERGE"} onChange={() => { setProviderStrategy("PARALLEL_MERGE"); invalidatePreview(); }} />全部查询并合并<p className="ml-5 mt-1 text-xs text-[#8e8e93]">适合例句、近义词等汇总内容。</p></label>
              </div>}
            </div>
          </details>
        </div>

        <aside className="xl:sticky xl:top-5 xl:self-start">
          <div className="rounded-[20px] border border-black/[0.06] bg-black/[0.02] p-4 dark:border-white/[0.08] dark:bg-white/[0.035]">
            <div className="flex items-center gap-2"><Database className="size-4 text-[#007aff]" /><h3 className="text-sm font-semibold">任务摘要</h3></div>
            <div className="mt-4 space-y-3 text-sm">
              <SummaryRow label="内容" value={activePreset?.label ?? `自定义 ${requestedFields.length} 项`} />
              <SummaryRow label="范围" value={scope === "ALL" ? "全部词条" : `已选 ${selectedWordIds.size} 个`} />
              <SummaryRow label="写入" value={mode === "FILL_MISSING_FIELDS" ? "仅补充缺失" : "刷新所选字段"} />
              <SummaryRow label="来源" value={sourceMode === "YOUDAO_ONLY" ? "有道词典（仅此来源）" : `${requestedProviders.length} 个`} />
              <SummaryRow label="策略" value={sourceMode === "YOUDAO_ONLY" ? "严格仅有道" : providerStrategy === "PRIORITY_FALLBACK" ? "按优先级回退" : "全部查询并合并"} />
            </div>

            <div className="mt-4 rounded-[14px] bg-white/70 p-3 dark:bg-black/20">
              {preview ? <>
                <div className="grid grid-cols-3 gap-2 text-center">
                  <Metric label="范围" value={preview.existingWords} />
                  <Metric label="处理" value={preview.selectedWords} highlight />
                  <Metric label="跳过" value={preview.skippedExisting} />
                </div>
                {preview.sample.length > 0 && <p className="mt-3 line-clamp-2 text-xs leading-relaxed text-[#8e8e93]">示例：{preview.sample.map((item) => item.term).join("、")}</p>}
              </> : <p className="text-center text-xs leading-relaxed text-[#8e8e93]">点击“预览”查看将处理多少个词条。</p>}
            </div>

            {error && <div className="mt-3 rounded-[12px] border border-[#ff3b30]/15 bg-[#ff3b30]/[0.06] p-3 text-xs leading-relaxed text-[#d70015] dark:text-[#ff453a]">{error}</div>}
            {message && <div className="mt-3 flex items-start gap-2 rounded-[12px] border border-[#34c759]/15 bg-[#34c759]/[0.06] p-3 text-xs leading-relaxed text-[#248a3d] dark:text-[#30d158]"><CheckCircle2 className="mt-0.5 size-4 shrink-0" />{message}</div>}

            <div className="mt-4 grid gap-2">
              <Button variant="outline" onClick={() => void calculatePreview()} disabled={Boolean(busy)}>{busy === "preview" ? <Loader2 className="size-4 animate-spin" /> : <Database className="size-4" />}预览任务</Button>
              <Button onClick={() => void createJobs()} disabled={Boolean(busy)}>{busy === "queue" ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}创建任务</Button>
            </div>
          </div>
        </aside>
      </div>
  </div>;
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return <div className="flex items-start justify-between gap-3"><span className="text-[#8e8e93]">{label}</span><b className="max-w-[190px] text-right font-medium">{value}</b></div>;
}

function Metric({ label, value, highlight = false }: { label: string; value: number; highlight?: boolean }) {
  return <div><b className={`block text-xl ${highlight ? "text-[#007aff]" : ""}`}>{value}</b><span className="text-[11px] text-[#8e8e93]">{label}</span></div>;
}
