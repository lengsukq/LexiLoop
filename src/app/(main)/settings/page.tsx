"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  AlertCircle, CheckCircle2, ChevronDown, ChevronRight, Download, HardDrive, Loader2, Plus, RefreshCw,
  Save, Trash2, Upload, Volume2, X, Zap,
} from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import type { AppSettings, LlmPurposeId, LlmProviderConfig } from "@/lib/types";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Input, PageHeader, Select } from "@/components/ui";

const PURPOSE_META: Array<{ id: LlmPurposeId; label: string; desc: string }> = [
  { id: "IMPORT_ENRICHMENT", label: "AI 词条初始化", desc: "为导入词条生成完整、结构化的学习内容" },
  { id: "STUDY_PLAN", label: "生成学习计划", desc: "根据学习进度生成每日计划" },
  { id: "SUGGESTION", label: "生成建议", desc: "在学习中提供智能建议" },
];

const SETTINGS_TABS = [
  { id: "study" as const, label: "学习计划" },
  { id: "ai" as const, label: "AI 模型" },
  { id: "data" as const, label: "数据管理" },
];

function configuredModels(provider: LlmProviderConfig): string[] {
  return [...new Set([...(provider.models ?? []), provider.defaultModel ?? ""].filter(Boolean))];
}

function parseModels(value: string): string[] {
  return [...new Set(value.split(/[\n,]/).map((model) => model.trim()).filter(Boolean))];
}

interface EcdictStatus { installed: boolean; enabled: boolean; fileSize: number; path: string; downloadUrl: string; }
interface ModelPickerState { providerIndex: number; models: string[]; selected: string[]; }
function bytes(value: number) { if (!value) return "0 B"; const units = ["B", "KB", "MB", "GB"]; const index = Math.min(units.length - 1, Math.floor(Math.log(value) / Math.log(1024))); return `${(value / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`; }

function NumberField({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (value: number) => void }) {
  return <label className="space-y-1.5"><span className="text-sm font-medium leading-none">{label}</span>
    <Input type="number" min={min} max={max} value={value} onChange={(event) => onChange(Math.max(min, Math.min(max, Number(event.target.value) || 0)))} />
  </label>;
}

function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange: (value: boolean) => void }) {
  return <label className="flex items-center gap-2 text-sm font-medium leading-none"><span>{label}</span>
    <input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} className="size-4 accent-[#007aff]" />
  </label>;
}

export default function SettingsPage() {
  const [activeTab, setActiveTab] = useState<"study" | "ai" | "data">("study");
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [ecdict, setEcdict] = useState<EcdictStatus | null>(null);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState("");
  const ecdictInput = useRef<HTMLInputElement>(null);
  const restoreInput = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    try {
      const [values, status] = await Promise.all([
        apiFetch<AppSettings>("/api/settings"),
        apiFetch<EcdictStatus>("/api/settings/ecdict"),
      ]);
      setSettings(values);
      setEcdict(status);
      setError("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "加载失败");
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  function update<K extends keyof AppSettings>(key: K, value: AppSettings[K]) {
    setSettings((current) => current ? { ...current, [key]: value } : current);
  }

  async function save() {
    if (!settings) return;
    setBusy("save");
    setMessage("");
    try {
      setSettings(await apiFetch<AppSettings>("/api/settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(settings),
      }));
      setMessage("学习设置已保存。新会话和内置后台引擎会使用最新配置。");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "保存失败");
    } finally {
      setBusy("");
    }
  }

  async function ecdictAction(action: "download" | "enable" | "disable" | "remove") {
    setBusy(action);
    setError("");
    setMessage("");
    try {
      setEcdict(await apiFetch<EcdictStatus>("/api/settings/ecdict", {
        method: action === "remove" ? "DELETE" : "POST",
        headers: action === "remove" ? undefined : { "Content-Type": "application/json" },
        body: action === "remove" ? undefined : JSON.stringify({ action }),
      }));
      setMessage(action === "download" ? "ECDICT 已下载并启用。" : action === "remove" ? "ECDICT 已移除。" : "ECDICT 状态已更新。");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "操作失败");
    } finally {
      setBusy("");
    }
  }

  async function uploadEcdict(file?: File) {
    if (!file) return;
    setBusy("upload-ecdict");
    try {
      const form = new FormData();
      form.append("file", file);
      setEcdict(await apiFetch<EcdictStatus>("/api/settings/ecdict", { method: "PUT", body: form }));
      setMessage("ECDICT 文件校验通过并已启用。");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "上传失败");
    } finally {
      setBusy("");
      if (ecdictInput.current) ecdictInput.current.value = "";
    }
  }

  async function restore(file?: File) {
    if (!file || !window.confirm("恢复会替换当前全部 LexiLoop 数据。已确认有可用备份吗？")) return;
    setBusy("restore");
    try {
      const form = new FormData();
      form.append("file", file);
      const result = await apiFetch<{ message: string }>("/api/backups/restore", { method: "POST", body: form });
      setMessage(result.message);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "恢复失败");
    } finally {
      setBusy("");
      if (restoreInput.current) restoreInput.current.value = "";
    }
  }

  const [ttsTestState, setTtsTestState] = useState<"idle" | "testing" | "success" | "error">("idle");
  const [ttsTestMessage, setTtsTestMessage] = useState("");
  const [providerTest, setProviderTest] = useState<Record<number, { state: "idle" | "testing" | "success" | "error"; message: string }>>({});
  const [providerTestModel, setProviderTestModel] = useState<Record<number, string>>({});
  const [providerModels, setProviderModels] = useState<Record<number, { state: "idle" | "loading" | "success" | "error"; message: string }>>({});
  const [modelPicker, setModelPicker] = useState<ModelPickerState | null>(null);
  const [modelFilter, setModelFilter] = useState("");
  const [mwKeysExpanded, setMwKeysExpanded] = useState(false);

  async function testTts() {
    if (!settings) return;
    setTtsTestState("testing");
    setTtsTestMessage("");
    try {
      const response = await fetch("/api/tts?word=LexiLoop&accent=US");
      if (response.ok) {
        const blob = await response.blob();
        const url = URL.createObjectURL(blob);
        const audio = new Audio(url);
        audio.playbackRate = 1;
        await audio.play();
        setTtsTestState("success");
        setTtsTestMessage("播放正常");
      } else {
        const body = await response.json().catch(() => ({ error: "未知错误" }));
        setTtsTestState("error");
        setTtsTestMessage(body.error || "测试失败");
      }
    } catch {
      setTtsTestState("error");
      setTtsTestMessage("网络请求失败");
    }
  }

  async function testProvider(index: number) {
    if (!settings) return;
    const provider = settings.llmConfig.providers[index];
    if (!provider) return;
    const model = providerTestModel[index] || provider.defaultModel || provider.models?.[0] || "";
    if (!model) { setProviderTest((t) => ({ ...t, [index]: { state: "error", message: "请先通过 Models 接口获取模型，或手动添加一个模型" } })); return; }
    setProviderTest((t) => ({ ...t, [index]: { state: "testing", message: "" } }));
    try {
      const result = await apiFetch<{ model: string; durationMs: number; responsePreview: string }>("/api/settings/test-provider", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ apiType: provider.apiType, baseUrl: provider.baseUrl, apiKey: provider.apiKey, model }),
      });
      setProviderTest((t) => ({ ...t, [index]: { state: "success", message: `${result.model} 响应正常（${result.durationMs}ms）` } }));
    } catch (reason) {
      setProviderTest((t) => ({ ...t, [index]: { state: "error", message: reason instanceof Error ? reason.message : "连接失败" } }));
    }
  }

  function updatePurpose(purposeId: LlmPurposeId, field: string, value: unknown) {
    setSettings((current) => {
      if (!current) return null;
      return {
        ...current,
        llmConfig: {
          ...current.llmConfig,
          purposes: {
          ...current.llmConfig.purposes,
          [purposeId]: { ...current.llmConfig.purposes[purposeId], [field]: value },
        },
      },
      };
    });
  }

  function addProvider() {
    setSettings((current) => {
      if (!current) return null;
      const id = `provider-${Date.now()}`;
      const newProvider: LlmProviderConfig = { id, name: "", apiType: "openai", baseUrl: "", apiKey: "", models: [], defaultModel: "" };
      return {
        ...current,
        llmConfig: {
          ...current.llmConfig,
          providers: [...current.llmConfig.providers, newProvider],
        },
      };
    });
  }

  function updateProviderField(index: number, field: keyof LlmProviderConfig, value: string) {
    setSettings((current) => {
      if (!current) return null;
      const providers = current.llmConfig.providers.map((p, i) =>
        i === index ? { ...p, [field]: value } : p
      );
      return { ...current, llmConfig: { ...current.llmConfig, providers } };
    });
  }

  function updateProviderModels(index: number, value: string) {
    const models = parseModels(value);
    setSettings((current) => {
      if (!current) return null;
      const providers = current.llmConfig.providers.map((provider, providerIndex) => {
        if (providerIndex !== index) return provider;
        const defaultModel = models.includes(provider.defaultModel ?? "") ? provider.defaultModel : (models[0] ?? "");
        return { ...provider, models, defaultModel };
      });
      return { ...current, llmConfig: { ...current.llmConfig, providers } };
    });
  }

  async function fetchProviderModels(index: number) {
    if (!settings) return;
    const provider = settings.llmConfig.providers[index];
    if (!provider) return;
    if (!provider.baseUrl.trim() || !provider.apiKey.trim()) {
      setProviderModels((current) => ({ ...current, [index]: { state: "error", message: "请先填写接口地址和 API Key" } }));
      return;
    }
    setProviderModels((current) => ({ ...current, [index]: { state: "loading", message: "" } }));
    try {
      const result = await apiFetch<{ models: string[] }>("/api/settings/models", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ apiType: provider.apiType, baseUrl: provider.baseUrl, apiKey: provider.apiKey }),
      });
      const existing = new Set(provider.models ?? []);
      setModelPicker({ providerIndex: index, models: result.models, selected: result.models.filter((model) => !existing.has(model)) });
      setModelFilter("");
      setProviderModels((current) => ({ ...current, [index]: { state: "success", message: `已读取 ${result.models.length} 个模型，请选择后加入。` } }));
    } catch (reason) {
      setProviderModels((current) => ({ ...current, [index]: { state: "error", message: reason instanceof Error ? reason.message : "读取模型失败" } }));
    }
  }

  function toggleModelPickerItem(model: string) {
    setModelPicker((current) => {
      if (!current) return current;
      return current.selected.includes(model)
        ? { ...current, selected: current.selected.filter((item) => item !== model) }
        : { ...current, selected: [...current.selected, model] };
    });
  }

  function applyModelPickerSelection() {
    if (!modelPicker) return;
    setSettings((current) => {
      if (!current) return current;
      const provider = current.llmConfig.providers[modelPicker.providerIndex];
      if (!provider) return current;
      const models = [...new Set([...(provider.models ?? []), ...modelPicker.selected])];
      const providers = current.llmConfig.providers.map((item, index) => index === modelPicker.providerIndex
        ? { ...item, models, defaultModel: item.defaultModel || models[0] || "" }
        : item);
      return { ...current, llmConfig: { ...current.llmConfig, providers } };
    });
    setProviderModels((current) => ({ ...current, [modelPicker.providerIndex]: { state: "success", message: `已加入 ${modelPicker.selected.length} 个模型，请保存设置。` } }));
    setModelPicker(null);
  }

  function removeProvider(index: number) {
    setSettings((current) => {
      if (!current) return null;
      const removed = current.llmConfig.providers[index];
      if (!removed) return current;
      const providers = current.llmConfig.providers.filter((_, i) => i !== index);
      const purposes = { ...current.llmConfig.purposes };
      for (const key of Object.keys(purposes) as LlmPurposeId[]) {
        if (purposes[key].providerId === removed.id) {
          purposes[key] = { ...purposes[key], enabled: false, providerId: "" };
        }
      }
      return { ...current, llmConfig: { ...current.llmConfig, providers, purposes } };
    });
  }

  const pickerProvider = modelPicker && settings ? settings.llmConfig.providers[modelPicker.providerIndex] : null;
  const pickerExisting = new Set(pickerProvider?.models ?? []);
  const pickerModels = modelPicker?.models.filter((model) => model.toLocaleLowerCase().includes(modelFilter.trim().toLocaleLowerCase())) ?? [];
  const pickerSelectableModels = modelPicker?.models.filter((model) => !pickerExisting.has(model)) ?? [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="设置与数据"
        description="调整每日学习计划、词典来源，并管理完整备份。"
        action={<div className="flex gap-2">
          <Button variant="outline" onClick={() => void load()}><RefreshCw className="size-4" />刷新</Button>
          <Button onClick={() => void save()} disabled={busy === "save"}>
            {busy === "save" ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}保存
          </Button>
        </div>}
      />

      {error && (
        <div className="flex items-center gap-2 rounded-[18px] border border-[#ff3b30]/15 bg-[#ff3b30]/[0.08] p-4 text-sm text-[#d70015] shadow-[0_8px_32px_rgba(255,59,48,0.08)] backdrop-blur-xl dark:text-[#ff453a]">
          <AlertCircle className="size-4 shrink-0" />{error}
        </div>
      )}
      {message && (
        <div className="flex items-center gap-2 rounded-[18px] border border-[#34c759]/15 bg-[#34c759]/[0.08] p-4 text-sm text-[#248a3d] shadow-[0_8px_32px_rgba(52,199,89,0.08)] backdrop-blur-xl dark:text-[#30d158]">
          <CheckCircle2 className="size-4 shrink-0" />{message}
        </div>
      )}

      {!settings && <div className="grid min-h-64 place-items-center"><Loader2 className="size-8 animate-spin text-[#007aff]" /></div>}

      {settings && (
        <>
          {/* Tab navigation */}
          <div className="flex gap-1 rounded-2xl bg-white/50 p-1 shadow-[0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-2xl dark:bg-white/[0.06]">
            {SETTINGS_TABS.map((tab) => (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`flex-1 rounded-xl px-4 py-2.5 text-sm font-semibold transition-all ${
                  activeTab === tab.id
                    ? "bg-white text-[#1c1c1e] shadow-[0_2px_8px_rgba(0,0,0,0.08)] dark:bg-white/[0.12] dark:text-white"
                    : "text-[#6e6e73] hover:text-[#1c1c1e] dark:text-[#98989d] dark:hover:text-white"
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {/* Tab: 学习计划 */}
          {activeTab === "study" && (
            <div className="space-y-5">
              {/* 每日学习计划 */}
              <Card>
                <CardHeader><CardTitle>每日学习计划</CardTitle></CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
                    <NumberField label="每日新词" value={settings.dailyNewWords} min={0} max={100} onChange={(value) => update("dailyNewWords", value)} />
                    <NumberField label="每日错词上限" value={settings.dailyWrongWordLimit} min={0} max={100} onChange={(value) => update("dailyWrongWordLimit", value)} />
                    <NumberField label="到期复习上限" value={settings.dailyDueReviewLimit} min={1} max={500} onChange={(value) => update("dailyDueReviewLimit", value)} />
                    <label className="space-y-1.5">
                      <span className="text-sm font-medium leading-none">目标记忆率</span>
                      <Select className="w-full" value={settings.targetRetentionRate} onChange={(event) => update("targetRetentionRate", Number(event.target.value))}>
                        <option value={0.85}>85% - 更轻松</option>
                        <option value={0.9}>90% - 推荐</option>
                        <option value={0.93}>93% - 更密集</option>
                        <option value={0.95}>95% - 高强度</option>
                      </Select>
                    </label>
                    <NumberField label="初始化并行数" value={settings.backgroundConcurrency} min={1} max={10} onChange={(value) => update("backgroundConcurrency", value)} />
                    <div className="space-y-1.5">
                      <NumberField label="AI 失败重试次数" value={settings.aiRetryCount} min={0} max={5} onChange={(value) => update("aiRetryCount", value)} />
                      <p className="text-xs leading-tight text-[#aeaeb2]">默认 1 次：每个 AI 任务最多尝试 2 次。</p>
                    </div>
                  </div>
                </CardContent>
              </Card>

              {/* 语音与词典 (合并: 发音 + 词典来源 + MW密钥 + TTS) */}
              <Card>
                <CardHeader><CardTitle>语音与词典</CardTitle></CardHeader>
                <CardContent className="space-y-6">
                  {/* -- 发音设置 -- */}
                  <div>
                    <h3 className="mb-3 text-sm font-semibold text-[#6e6e73] dark:text-[#98989d] uppercase tracking-wider">发音设置</h3>
                    <div className="flex flex-wrap gap-4">
                      <label className="space-y-1.5 min-w-36">
                        <span className="text-xs font-medium">默认口音</span>
                        <Select className="w-full" value={settings.defaultAccent} onChange={(event) => update("defaultAccent", event.target.value as AppSettings["defaultAccent"])}>
                          <option value="US">美音</option>
                          <option value="UK">英音</option>
                          <option value="GENERAL">通用</option>
                        </Select>
                      </label>
                      <label className="space-y-1.5 min-w-28">
                        <span className="text-xs font-medium">播放速度</span>
                        <Select className="w-full" value={settings.playbackSpeed} onChange={(event) => update("playbackSpeed", Number(event.target.value))}>
                          <option value={0.75}>0.75x</option>
                          <option value={1}>1.0x</option>
                          <option value={1.25}>1.25x</option>
                          <option value={1.5}>1.5x</option>
                        </Select>
                      </label>
                      <div className="flex items-end pb-1">
                        <Toggle label="自动播放发音" checked={settings.autoPlayPronunciation} onChange={(value) => update("autoPlayPronunciation", value)} />
                      </div>
                    </div>
                  </div>

                  <hr className="border-black/[0.06] dark:border-white/[0.08]" />

                  {/* -- 在线词典来源 -- */}
                  <div>
                    <h3 className="mb-3 text-sm font-semibold text-[#6e6e73] dark:text-[#98989d] uppercase tracking-wider">在线词典来源</h3>
                    <div className="flex flex-wrap gap-x-6 gap-y-2">
                      <Toggle label="DictionaryAPI.dev" checked={settings.dictionaryApiEnabled} onChange={(value) => update("dictionaryApiEnabled", value)} />
                      <Toggle label="MyMemory 翻译" checked={settings.myMemoryEnabled} onChange={(value) => update("myMemoryEnabled", value)} />
                      <Toggle label="Merriam-Webster 词典" checked={settings.merriamWebsterEnabled} onChange={(value) => update("merriamWebsterEnabled", value)} />
                    </div>
                  </div>

                  {/* -- Merriam-Webster API 密钥 (可折叠) -- */}
                  <div>
                    <button
                      type="button"
                      onClick={() => setMwKeysExpanded(!mwKeysExpanded)}
                      className="flex items-center gap-1.5 text-sm font-medium text-[#6e6e73] hover:text-[#1c1c1e] dark:text-[#98989d] dark:hover:text-white transition-colors"
                    >
                      {mwKeysExpanded ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
                      Merriam-Webster API 密钥
                      <span className="text-xs text-[#aeaeb2] font-normal">（可选）</span>
                    </button>
                    {mwKeysExpanded && (
                      <div className="mt-3 grid gap-3 sm:grid-cols-2">
                        <label className="space-y-1.5">
                          <span className="text-xs font-medium">Collegiate Dictionary Key</span>
                          <Input type="password" autoComplete="off" value={settings.merriamWebsterDictionaryKey} onChange={(event) => update("merriamWebsterDictionaryKey", event.target.value)} placeholder="输入词典 API Key" />
                        </label>
                        <label className="space-y-1.5">
                          <span className="text-xs font-medium">Collegiate Thesaurus Key</span>
                          <Input type="password" autoComplete="off" value={settings.merriamWebsterThesaurusKey} onChange={(event) => update("merriamWebsterThesaurusKey", event.target.value)} placeholder="输入同义词词典 API Key" />
                        </label>
                      </div>
                    )}
                  </div>

                  <hr className="border-black/[0.06] dark:border-white/[0.08]" />

                  {/* -- 语音合成 TTS -- */}
                  <div>
                    <h3 className="mb-3 text-sm font-semibold text-[#6e6e73] dark:text-[#98989d] uppercase tracking-wider">语音合成 (TTS)</h3>
                    <p className="mb-3 text-sm text-[#6e6e73] dark:text-[#98989d]">
                      发音功能已内置使用 <strong>Microsoft Edge TTS</strong>，完全免费，无需配置 API Key 或模型。
                    </p>
                    <div className="flex flex-wrap items-center gap-3">
                      <div className="flex items-center gap-2 rounded-[14px] border border-[#34c759]/15 bg-[#34c759]/[0.08] px-4 py-2 text-sm text-[#248a3d] shadow-[0_4px_12px_rgba(52,199,89,0.06)] backdrop-blur-sm dark:text-[#30d158]">
                        <CheckCircle2 className="size-4" />免费 - 无需额外配置
                      </div>
                      <div className="flex items-center gap-2 rounded-[14px] border border-[#007aff]/15 bg-[#007aff]/[0.08] px-4 py-2 text-sm text-[#007aff] shadow-[0_4px_12px_rgba(0,122,255,0.06)] backdrop-blur-sm dark:text-[#0a84ff]">
                        <Volume2 className="size-4" />支持美音 / 英音
                      </div>
                    </div>
                    <div className="mt-3 flex items-center gap-3">
                      <Button variant="outline" size="sm" onClick={() => void testTts()} disabled={ttsTestState === "testing"}>
                        {ttsTestState === "testing" ? <Loader2 className="size-4 animate-spin" /> : <Volume2 className="size-4" />}试听发音
                      </Button>
                      {ttsTestState !== "idle" && (
                        <span className={`text-xs ${ttsTestState === "success" ? "text-[#34c759]" : "text-[#ff3b30]"}`}>{ttsTestMessage}</span>
                      )}
                    </div>
                  </div>
                </CardContent>
              </Card>
            </div>
          )}

          {/* Tab: AI 模型 */}
          {activeTab === "ai" && (
            <Card>
              <CardHeader><CardTitle>大模型配置</CardTitle></CardHeader>
              <CardContent className="space-y-5">
                <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">
                  配置 AI 大模型生成完整词汇学习内容，包括分词义释义、例句、搭配、词形、同根词、近反义词、易混词和记忆提示。Edge TTS 仍独立负责发音。
                </p>

                {/* Provider management section */}
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <h3 className="text-sm font-semibold text-[#6e6e73] dark:text-[#98989d] uppercase tracking-wider">Provider 管理</h3>
                    <Button variant="outline" size="sm" onClick={addProvider}>
                      <Plus className="size-4" />添加 Provider
                    </Button>
                  </div>
                  {settings.llmConfig.providers.length === 0 && (
                    <p className="text-xs text-[#aeaeb2]">暂无配置，请添加一个 Provider。</p>
                  )}
                  {settings.llmConfig.providers.map((provider, index) => (
                    <div key={provider.id} className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_8px_32px_rgba(0,0,0,0.04)] backdrop-blur-xl dark:border-white/[0.08] dark:bg-white/[0.04]">
                      <div className="flex items-start justify-between gap-2">
                        <div className="flex-1 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                          <label className="space-y-1.5">
                            <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">名称</span>
                            <Input
                              value={provider.name}
                              onChange={(e) => updateProviderField(index, "name", e.target.value)}
                              placeholder="例如: 我的 OpenAI"
                            />
                          </label>
                          <label className="space-y-1.5">
                            <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">API 类型</span>
                            <Select
                              className="w-full"
                              value={provider.apiType}
                              onChange={(e) => updateProviderField(index, "apiType", e.target.value)}
                            >
                              <option value="openai">OpenAI 兼容</option>
                              <option value="anthropic">Anthropic</option>
                            </Select>
                          </label>
                          <label className="space-y-1.5">
                            <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">接口地址</span>
                            <Input
                              value={provider.baseUrl}
                              onChange={(e) => updateProviderField(index, "baseUrl", e.target.value)}
                              placeholder={provider.apiType === "openai" ? "https://api.openai.com/v1" : "https://api.anthropic.com/v1"}
                            />
                          </label>
                          <label className="space-y-1.5">
                            <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">API Key</span>
                            <Input
                              value={provider.apiKey}
                              onChange={(e) => updateProviderField(index, "apiKey", e.target.value)}
                              placeholder="sk-..."
                              type="password"
                            />
                          </label>
                        </div>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="text-[#ff3b30] shrink-0"
                          onClick={() => removeProvider(index)}
                        >
                          <Trash2 className="size-4" />
                        </Button>
                      </div>
                      <label className="mt-3 block space-y-1.5">
                        <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">可保存模型</span>
                        <Input
                          value={(provider.models ?? []).join(", ")}
                          onChange={(event) => updateProviderModels(index, event.target.value)}
                          placeholder="从 Models 接口获取，或手动输入（用逗号分隔）"
                        />
                        <div className="flex flex-wrap items-center gap-2">
                          <Button variant="outline" size="sm" type="button" onClick={() => void fetchProviderModels(index)} disabled={providerModels[index]?.state === "loading"}>
                            {providerModels[index]?.state === "loading" ? <Loader2 className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />}从 Models 接口获取
                          </Button>
                          <span className="text-xs text-[#aeaeb2]">读取 {provider.baseUrl.trim() ? "当前接口的" : "当前 Provider 的"} `/models` 并加入清单。</span>
                          {providerModels[index]?.state === "success" && <span className="text-xs text-[#34c759]">{providerModels[index].message}</span>}
                          {providerModels[index]?.state === "error" && <span className="text-xs text-[#ff3b30]">{providerModels[index].message}</span>}
                        </div>
                      </label>
                      <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-black/[0.06] pt-3 dark:border-white/[0.08]">
                        <Select
                          className="h-8 w-56 text-xs"
                          value={providerTestModel[index] ?? provider.defaultModel ?? ""}
                          onChange={(event) => {
                            const model = event.target.value;
                            setProviderTestModel((current) => ({ ...current, [index]: model }));
                            updateProviderField(index, "defaultModel", model);
                          }}
                        >
                          <option value="">选择已保存的模型</option>
                          {configuredModels(provider).map((model) => <option key={model} value={model}>{model}</option>)}
                        </Select>
                        <Button
                          variant="outline"
                          size="sm"
                          onClick={() => void testProvider(index)}
                          disabled={providerTest[index]?.state === "testing"}
                        >
                          {providerTest[index]?.state === "testing" ? <Loader2 className="size-3.5 animate-spin" /> : <Zap className="size-3.5" />}测试连接
                        </Button>
                        {providerTest[index]?.state === "success" && (
                          <span className="text-xs text-[#34c759]">{providerTest[index].message}</span>
                        )}
                        {providerTest[index]?.state === "error" && (
                          <span className="text-xs text-[#ff3b30]">{providerTest[index].message}</span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>

                {/* Purpose binding section */}
                <div className="space-y-4">
                  <h3 className="text-sm font-semibold text-[#6e6e73] dark:text-[#98989d] uppercase tracking-wider">用途绑定</h3>
                  {PURPOSE_META.map((purpose) => {
                    const config = settings.llmConfig.purposes[purpose.id];
                    const provider = settings.llmConfig.providers.find((p) => p.id === config.providerId);
                    const models = provider ? configuredModels(provider) : [];
                    const retryProvider = settings.llmConfig.providers.find((p) => p.id === config.retryProviderId) ?? provider;
                    const retryModels = retryProvider ? configuredModels(retryProvider) : [];
                    const reserved = purpose.id === "STUDY_PLAN" || purpose.id === "SUGGESTION";
                    return (
                      <div key={purpose.id} className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_8px_32px_rgba(0,0,0,0.04)] backdrop-blur-xl dark:border-white/[0.08] dark:bg-white/[0.04]">
                        <div className="flex items-center justify-between gap-3">
                          <div className="min-w-0 flex-1">
                            <p className="text-sm font-medium">{purpose.label}</p>
                            <p className="text-xs text-[#aeaeb2]">{purpose.desc}{reserved ? " · 功能预留，当前版本不会调用模型" : ""}</p>
                          </div>
                          <label className="flex shrink-0 items-center gap-2 text-sm">
                            <span className="text-[#6e6e73] dark:text-[#98989d]">{reserved ? "预留" : config.enabled ? "已启用" : "已禁用"}</span>
                            <input
                              type="checkbox"
                              checked={reserved ? false : config.enabled}
                              onChange={(event) => updatePurpose(purpose.id, "enabled", event.target.checked)}
                              disabled={reserved}
                              className="size-4 accent-[#007aff]"
                            />
                          </label>
                        </div>
                        {!reserved && config.enabled && (
                          <div className="mt-4 space-y-4">
                            <div className="flex flex-wrap items-end gap-3">
                              <label className="space-y-1.5 min-w-[10rem] flex-1">
                                <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">提供商</span>
                                <Select
                                  className="w-full"
                                  value={config.providerId}
                                  onChange={(event) => {
                                    const selectedProvider = settings.llmConfig.providers.find((p) => p.id === event.target.value);
                                    updatePurpose(purpose.id, "providerId", event.target.value);
                                    if (selectedProvider) {
                                      const defaultModel = selectedProvider.defaultModel || selectedProvider.models?.[0] || "";
                                      updatePurpose(purpose.id, "model", defaultModel);
                                    }
                                  }}
                                >
                                  {settings.llmConfig.providers.length === 0 && (
                                    <option value="">-- 请先添加 Provider --</option>
                                  )}
                                  {settings.llmConfig.providers.map((p) => (
                                    <option key={p.id} value={p.id}>{p.name || p.id}</option>
                                  ))}
                                </Select>
                              </label>
                              <label className="space-y-1.5 min-w-[12rem] flex-[2]">
                                <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">模型</span>
                                <Input
                                  value={config.model}
                                  onChange={(event) => updatePurpose(purpose.id, "model", event.target.value)}
                                  list={`models-${purpose.id}-${provider?.id ?? "none"}`}
                                  placeholder={models.length > 0 ? "选择或输入模型名称" : "输入模型名称"}
                                />
                                <datalist id={`models-${purpose.id}-${provider?.id ?? "none"}`}>
                                  {models.map((model) => <option key={model} value={model} />)}
                                </datalist>
                              </label>
                              {purpose.id === "IMPORT_ENRICHMENT" && (
                                <>
                                  <label className="space-y-1.5 w-20">
                                    <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">温度</span>
                                    <Input
                                      type="number"
                                      min={0}
                                      max={1}
                                      step={0.1}
                                      value={config.temperature ?? 0.2}
                                      onChange={(event) => updatePurpose(purpose.id, "temperature", Number(event.target.value))}
                                    />
                                  </label>
                                  <label className="space-y-1.5 w-24">
                                    <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">输出 Token</span>
                                    <Input
                                      type="number"
                                      min={500}
                                      max={200000}
                                      step={100}
                                      value={config.maxOutputTokens ?? 200000}
                                      onChange={(event) => updatePurpose(purpose.id, "maxOutputTokens", Number(event.target.value))}
                                    />
                                  </label>
                                  <label className="space-y-1.5 w-20">
                                    <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">超时(秒)</span>
                                    <Input
                                      type="number"
                                      min={5}
                                      max={300}
                                      value={(config.timeoutMs ?? 180000) / 1000}
                                      onChange={(event) => updatePurpose(purpose.id, "timeoutMs", Number(event.target.value) * 1000)}
                                    />
                                  </label>
                                </>
                              )}
                            </div>
                            <div className="rounded-2xl border border-[#ff9f0a]/15 bg-[#ff9f0a]/[0.055] p-3.5 shadow-[0_6px_18px_rgba(255,159,10,0.05)] dark:border-[#ff9f0a]/20 dark:bg-[#ff9f0a]/[0.08]">
                              <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                                <div className="flex items-start gap-2.5"><RefreshCw className="mt-0.5 size-4 shrink-0 text-[#d97706] dark:text-[#ff9f0a]" /><div><p className="text-sm font-medium">失败重试策略</p><p className="mt-0.5 text-xs leading-5 text-[#8e6a35] dark:text-[#d6ad70]">第 2 次及之后的自动重试可切换到另一家 Provider；留空则继续使用主模型。</p></div></div>
                                <Badge tone="amber">自动切换</Badge>
                              </div>
                              <div className="mt-3 grid gap-3 sm:grid-cols-2">
                                <label className="space-y-1.5"><span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">重试 Provider</span>
                                  <Select className="w-full" value={config.retryProviderId ?? ""} onChange={(event) => {
                                    const retryProviderId = event.target.value;
                                    const selectedProvider = settings.llmConfig.providers.find((item) => item.id === retryProviderId) ?? provider;
                                    updatePurpose(purpose.id, "retryProviderId", retryProviderId);
                                    updatePurpose(purpose.id, "retryModel", selectedProvider?.defaultModel || selectedProvider?.models?.[0] || "");
                                  }}>
                                    <option value="">与主 Provider 相同</option>
                                    {settings.llmConfig.providers.filter((item) => item.id !== config.providerId).map((item) => <option key={item.id} value={item.id}>{item.name || item.id}</option>)}
                                  </Select>
                                </label>
                                <label className="space-y-1.5"><span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">重试模型</span>
                                  <Select className="w-full" value={config.retryModel ?? ""} onChange={(event) => updatePurpose(purpose.id, "retryModel", event.target.value)} disabled={!retryProvider}>
                                    <option value="">{retryProvider === provider ? "与主模型相同" : "选择重试模型"}</option>
                                    {retryModels.map((model) => <option key={model} value={model}>{model}</option>)}
                                  </Select>
                                </label>
                              </div>
                            </div>
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
              </CardContent>
            </Card>
          )}

          {/* Tab: 数据管理 */}
          {activeTab === "data" && (
            <div className="space-y-5">
              {/* 备份与还原 */}
              <Card>
                <CardHeader><CardTitle>备份与还原</CardTitle></CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">将学习数据导出为 SQLite 或 JSON 格式进行备份。</p>
                  <div className="flex flex-wrap gap-2">
                    <a href="/api/backups/sqlite" download className="inline-flex items-center gap-2 rounded-[14px] border border-white/50 bg-white/50 px-4 py-2 text-sm font-medium shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-xl transition hover:bg-white/70 hover:shadow-[0_8px_24px_rgba(0,0,0,0.06)] dark:border-white/[0.08] dark:bg-white/[0.05] dark:hover:bg-white/[0.08]"><HardDrive className="size-4" />下载 SQLite 备份</a>
                    <a href="/api/backups/json" download className="inline-flex items-center gap-2 rounded-[14px] border border-white/50 bg-white/50 px-4 py-2 text-sm font-medium shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-xl transition hover:bg-white/70 hover:shadow-[0_8px_24px_rgba(0,0,0,0.06)] dark:border-white/[0.08] dark:bg-white/[0.05] dark:hover:bg-white/[0.08]"><Download className="size-4" />下载 JSON 备份</a>
                  </div>
                  <hr className="border-black/[0.06] dark:border-white/[0.08]" />
                  <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">从备份文件恢复。恢复操作将覆盖全部现有数据。</p>
                  <label className="cursor-pointer">
                    <span className="inline-flex cursor-pointer items-center gap-2 rounded-[14px] border border-white/50 bg-white/50 px-4 py-2 text-sm font-medium shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-xl transition hover:bg-white/70 hover:shadow-[0_8px_24px_rgba(0,0,0,0.06)] dark:border-white/[0.08] dark:bg-white/[0.05] dark:hover:bg-white/[0.08]" onClick={() => restoreInput.current?.click()}>
                      <Upload className="size-4" />上传备份文件并恢复
                    </span>
                    <input ref={restoreInput} type="file" accept=".sqlite,.json" className="hidden" onChange={(event) => void restore(event.target.files?.[0])} />
                  </label>
                </CardContent>
              </Card>

              {/* ECDICT 词典 */}
              <Card>
                <CardHeader><CardTitle>ECDICT 词典</CardTitle></CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">ECDICT 提供大规模离线英汉词典数据，用词形、词源和真人发音补充 AI 生成内容。</p>
                  {!ecdict ? (
                    <div className="flex items-center gap-2 text-sm text-[#aeaeb2]"><Loader2 className="size-4 animate-spin" />加载中...</div>
                  ) : ecdict.installed ? (
                    <div className="space-y-3">
                      <div className="flex items-center gap-3">
                        <Badge className="text-[#34c759] border-[#34c759]/30" tone="green">{ecdict.enabled ? "已启用" : "已禁用"}</Badge>
                        <span className="text-xs text-[#aeaeb2]">{bytes(ecdict.fileSize)}</span>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        {ecdict.enabled
                          ? <Button variant="outline" size="sm" onClick={() => void ecdictAction("disable")} disabled={busy === "disable"}>停用</Button>
                          : <Button variant="outline" size="sm" onClick={() => void ecdictAction("enable")} disabled={busy === "enable"}>启用</Button>
                        }
                        <Button variant="outline" size="sm" onClick={() => void ecdictAction("remove")} disabled={busy === "remove"} className="text-[#ff3b30]">
                          {busy === "remove" ? <Loader2 className="size-4 animate-spin" /> : <Trash2 className="size-4" />}移除
                        </Button>
                      </div>
                    </div>
                  ) : (
                    <div className="space-y-3">
                      <p className="text-xs text-[#aeaeb2]">尚未安装 ECDICT 词典（~700MB）</p>
                      <div className="flex flex-wrap gap-2">
                        <Button variant="outline" size="sm" onClick={() => void ecdictAction("download")} disabled={busy === "download"}>
                          {busy === "download" ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}下载并启用
                        </Button>
                        <label className="cursor-pointer">
                          <span className="inline-flex cursor-pointer items-center gap-2 rounded-[14px] border border-white/50 bg-white/50 px-4 py-2 text-sm font-medium shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-xl transition hover:bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.05] dark:hover:bg-white/[0.08]" onClick={() => ecdictInput.current?.click()}>
                            <Upload className="size-4" />上传自定义文件
                          </span>
                          <input ref={ecdictInput} type="file" accept=".sqlite,.mdb" className="hidden" onChange={(event) => void uploadEcdict(event.target.files?.[0])} />
                        </label>
                      </div>
                    </div>
                  )}
                </CardContent>
              </Card>
            </div>
          )}

        </>
      )}

      {modelPicker && pickerProvider && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <button type="button" aria-label="关闭模型选择" className="absolute inset-0 bg-[#101522]/35 backdrop-blur-sm" onClick={() => setModelPicker(null)} />
          <Card className="relative z-10 flex max-h-[min(720px,calc(100vh-2rem))] w-full max-w-2xl flex-col overflow-hidden border-white/70 shadow-[0_32px_90px_rgba(15,23,42,0.28)] dark:border-white/[0.12]">
            <CardHeader className="shrink-0 border-b border-black/[0.06] dark:border-white/[0.08]">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <CardTitle>选择要加入的模型</CardTitle>
                  <p className="mt-1 text-sm text-[#6e6e73] dark:text-[#98989d]">来自 {pickerProvider.name || pickerProvider.id} 的 Models 接口；已存在的模型会保留。</p>
                </div>
                <Button variant="ghost" size="sm" onClick={() => setModelPicker(null)} aria-label="关闭"><X className="size-4" /></Button>
              </div>
              <div className="mt-4 flex flex-wrap items-center gap-2">
                <Input className="min-w-48 flex-1" value={modelFilter} onChange={(event) => setModelFilter(event.target.value)} placeholder="筛选模型名称…" autoFocus />
                <Button variant="outline" size="sm" type="button" onClick={() => setModelPicker((current) => current ? { ...current, selected: pickerSelectableModels } : current)}>全选新增</Button>
                <Button variant="ghost" size="sm" type="button" onClick={() => setModelPicker((current) => current ? { ...current, selected: [] } : current)}>清空</Button>
              </div>
            </CardHeader>
            <div className="min-h-0 flex-1 overflow-y-auto p-3 sm:p-4">
              {pickerModels.length ? <div className="grid gap-2 sm:grid-cols-2">
                {pickerModels.map((model) => {
                  const exists = pickerExisting.has(model);
                  const checked = exists || modelPicker.selected.includes(model);
                  return <label key={model} className={`flex min-w-0 cursor-pointer items-center gap-3 rounded-xl border px-3 py-2.5 text-sm transition ${checked ? "border-[#007aff]/30 bg-[#007aff]/[0.07]" : "border-black/[0.06] bg-white/40 hover:border-[#007aff]/20 hover:bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.04]"} ${exists ? "cursor-default opacity-65" : ""}`}>
                    <input type="checkbox" checked={checked} disabled={exists} onChange={() => toggleModelPickerItem(model)} className="size-4 shrink-0 accent-[#007aff]" />
                    <span className="min-w-0 flex-1 truncate font-medium" title={model}>{model}</span>
                    {exists && <span className="shrink-0 text-[11px] text-[#8e8e93]">已存在</span>}
                  </label>;
                })}
              </div> : <p className="py-12 text-center text-sm text-[#8e8e93]">没有匹配的模型。</p>}
            </div>
            <div className="flex shrink-0 items-center justify-between gap-3 border-t border-black/[0.06] bg-white/45 px-4 py-3 backdrop-blur-sm dark:border-white/[0.08] dark:bg-white/[0.04]">
              <span className="text-sm text-[#6e6e73] dark:text-[#98989d]">已选择 {modelPicker.selected.length} 个新增模型</span>
              <div className="flex gap-2"><Button variant="ghost" onClick={() => setModelPicker(null)}>取消</Button><Button onClick={applyModelPickerSelection} disabled={!modelPicker.selected.length}>加入 {modelPicker.selected.length} 个</Button></div>
            </div>
          </Card>
        </div>
      )}
    </div>
  );
}
