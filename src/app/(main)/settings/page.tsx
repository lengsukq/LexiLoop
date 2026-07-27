"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { AlertCircle, CheckCircle2, Database, Download, HardDrive, Loader2, Plus, RefreshCw, Save, Trash2, Upload, Volume2, X, Zap } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import type { AppSettings, LlmPurposeId, LlmProviderConfig } from "@/lib/types";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Input, PageHeader, Select } from "@/components/ui";

const PURPOSE_META: Array<{ id: LlmPurposeId; label: string; desc: string }> = [
  { id: "IMPORT_ENRICHMENT", label: "AI 词条初始化", desc: "为导入词条生成完整、结构化的学习内容" },
  { id: "STUDY_PLAN", label: "生成学习计划", desc: "根据学习进度生成每日计划" },
  { id: "SUGGESTION", label: "生成建议", desc: "在学习中提供智能建议" },
];

const API_TYPE_SUGGESTED_MODELS: Record<string, Partial<Record<LlmPurposeId, string[]>>> = {
  openai: {
    TTS: ["tts-1", "tts-1-hd"],
    IMPORT_ENRICHMENT: ["gpt-4o-mini", "gpt-4o"],
    STUDY_PLAN: ["gpt-4o-mini", "gpt-4o"],
    SUGGESTION: ["gpt-4o-mini", "gpt-4o"],
  },
  anthropic: {
    IMPORT_ENRICHMENT: ["claude-3-5-haiku", "claude-3-5-sonnet"],
    STUDY_PLAN: ["claude-3-5-haiku", "claude-3-5-sonnet"],
    SUGGESTION: ["claude-3-5-haiku", "claude-3-5-sonnet"],
  },
  "opencode-zen": {
    IMPORT_ENRICHMENT: ["deepseek-v4-flash-free", "mimo-v2.5-free"],
    STUDY_PLAN: ["deepseek-v4-flash-free", "mimo-v2.5-free"],
    SUGGESTION: ["mimo-v2.5-free", "deepseek-v4-flash-free"],
  },
};

function suggestedModels(apiType: string, purposeId: LlmPurposeId): string[] {
  return API_TYPE_SUGGESTED_MODELS[apiType]?.[purposeId] ?? [];
}

interface EcdictStatus { installed: boolean; enabled: boolean; fileSize: number; path: string; downloadUrl: string; }
function bytes(value: number) { if (!value) return "0 B"; const units = ["B", "KB", "MB", "GB"]; const index = Math.min(units.length - 1, Math.floor(Math.log(value) / Math.log(1024))); return `${(value / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`; }

function NumberField({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (value: number) => void }) {
  return <label className="space-y-2"><span className="text-sm font-medium">{label}</span>
    <Input type="number" min={min} max={max} value={value} onChange={(event) => onChange(Math.max(min, Math.min(max, Number(event.target.value) || 0)))} />
  </label>;
}

function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange: (value: boolean) => void }) {
  return <label className="flex items-center gap-2 text-sm font-medium"><span>{label}</span>
    <input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} className="size-4 accent-[#007aff]" />
  </label>;
}

export default function SettingsPage() {
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
    const model = providerTestModel[index] || suggestedModels(provider.apiType, "IMPORT_ENRICHMENT")[0] || "";
    if (!model) { setProviderTest((t) => ({ ...t, [index]: { state: "error", message: "请输入要测试的模型名称" } })); return; }
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
      const newProvider: LlmProviderConfig = { id, name: "", apiType: "openai", baseUrl: "", apiKey: "" };
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

  return (
    <div className="space-y-6">
      <PageHeader
        title="设置与数据"
        description="调整每日学习计划、词典来源，并管理完整备份。"
        action={<Button variant="outline" onClick={() => void load()}><RefreshCw className="size-4" />刷新</Button>}
      />
      {error && (
        <div className="flex items-center gap-2 rounded-[18px] border border-[#ff3b30]/15 bg-[#ff3b30]/[0.08] p-4 text-sm text-[#d70015] shadow-[0_8px_32px_rgba(255,59,48,0.08)] backdrop-blur-xl dark:text-[#ff453a]">
          <AlertCircle className="size-4" />{error}
        </div>
      )}
      {message && (
        <div className="flex items-center gap-2 rounded-[18px] border border-[#34c759]/15 bg-[#34c759]/[0.08] p-4 text-sm text-[#248a3d] shadow-[0_8px_32px_rgba(52,199,89,0.08)] backdrop-blur-xl dark:text-[#30d158]">
          <CheckCircle2 className="size-4" />{message}
        </div>
      )}
    {!settings && <div className="grid min-h-64 place-items-center"><Loader2 className="size-8 animate-spin text-[#007aff]" /></div>}
      {settings && (
        <>
          <Card>
            <CardHeader><CardTitle>每日学习计划</CardTitle></CardHeader>
            <CardContent className="grid gap-5 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-5">
              <NumberField label="每日新词" value={settings.dailyNewWords} min={0} max={100} onChange={(value) => update("dailyNewWords", value)} />
              <NumberField label="每日错词上限" value={settings.dailyWrongWordLimit} min={0} max={100} onChange={(value) => update("dailyWrongWordLimit", value)} />
              <NumberField label="到期复习上限" value={settings.dailyDueReviewLimit} min={1} max={500} onChange={(value) => update("dailyDueReviewLimit", value)} />
              <label className="space-y-2">
                <span className="text-sm font-medium">目标记忆率</span>
                <Select className="w-full" value={settings.targetRetentionRate} onChange={(event) => update("targetRetentionRate", Number(event.target.value))}>
                  <option value={0.85}>85% - 更轻松</option>
                  <option value={0.9}>90% - 推荐</option>
                  <option value={0.93}>93% - 更密集</option>
                  <option value={0.95}>95% - 高强度</option>
                </Select>
              </label>
              <NumberField label="初始化并行数" value={settings.backgroundConcurrency} min={1} max={10} onChange={(value) => update("backgroundConcurrency", value)} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle>发音与词典来源</CardTitle></CardHeader>
            <CardContent className="grid gap-5 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4">
              <label className="space-y-2">
                <span className="text-sm font-medium">默认口音</span>
                <Select className="w-full" value={settings.defaultAccent} onChange={(event) => update("defaultAccent", event.target.value as AppSettings["defaultAccent"])}>
                  <option value="US">美音</option>
                  <option value="UK">英音</option>
                  <option value="GENERAL">通用</option>
                </Select>
              </label>
              <label className="space-y-2">
                <span className="text-sm font-medium">播放速度</span>
                <Select className="w-full" value={settings.playbackSpeed} onChange={(event) => update("playbackSpeed", Number(event.target.value))}>
                  <option value={0.75}>0.75x</option>
                  <option value={1}>1.0x</option>
                  <option value={1.25}>1.25x</option>
                  <option value={1.5}>1.5x</option>
                </Select>
              </label>
              <Toggle label="自动播放发音" checked={settings.autoPlayPronunciation} onChange={(value) => update("autoPlayPronunciation", value)} />
              <Toggle label="DictionaryAPI.dev" checked={settings.dictionaryApiEnabled} onChange={(value) => update("dictionaryApiEnabled", value)} />
              <Toggle label="MyMemory 翻译" checked={settings.myMemoryEnabled} onChange={(value) => update("myMemoryEnabled", value)} />
            </CardContent>
          </Card>

          <Card>
            <CardHeader><CardTitle>语音合成 (TTS)</CardTitle></CardHeader>
            <CardContent className="space-y-4">
              <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">发音功能已内置使用 <strong>Microsoft Edge TTS</strong>，完全免费，无需配置 API Key 或模型。</p>
              <div className="flex flex-wrap items-center gap-3">
                <div className="flex items-center gap-2 rounded-[14px] border border-[#34c759]/15 bg-[#34c759]/[0.08] px-4 py-2 text-sm text-[#248a3d] shadow-[0_4px_12px_rgba(52,199,89,0.06)] backdrop-blur-sm dark:text-[#30d158]">
                  <CheckCircle2 className="size-4" />免费 - 无需额外配置
                </div>
                <div className="flex items-center gap-2 rounded-[14px] border border-[#007aff]/15 bg-[#007aff]/[0.08] px-4 py-2 text-sm text-[#007aff] shadow-[0_4px_12px_rgba(0,122,255,0.06)] backdrop-blur-sm dark:text-[#0a84ff]">
                  <Volume2 className="size-4" />支持美音 / 英音
                </div>
              </div>
              <div className="flex items-center gap-3">
                <Button variant="outline" size="sm" onClick={() => void testTts()} disabled={ttsTestState === "testing"}>
                  {ttsTestState === "testing" ? <Loader2 className="size-4 animate-spin" /> : <Volume2 className="size-4" />}试听发音
                </Button>
                {ttsTestState !== "idle" && (
                  <span className={`text-xs ${ttsTestState === "success" ? "text-[#34c759]" : "text-[#ff3b30]"}`}>{ttsTestMessage}</span>
                )}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>大模型配置</CardTitle>
            </CardHeader>
            <CardContent className="space-y-5">
              <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">
                配置 AI 大模型生成完整词汇学习内容，包括分词义释义、例句、搭配、词形、同根词、近反义词、易混词和记忆提示。Edge TTS 仍独立负责发音。
              </p>

              {/* Provider management section */}
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-medium">Provider 管理</h3>
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
                    <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-black/[0.06] pt-3 dark:border-white/[0.08]">
                      <Input
                        className="w-56 h-8 text-xs"
                        placeholder="测试模型，如 gpt-4o-mini"
                        value={providerTestModel[index] ?? ""}
                        onChange={(e) => setProviderTestModel((m) => ({ ...m, [index]: e.target.value }))}
                      />
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
                {PURPOSE_META.map((purpose) => {
                  const config = settings.llmConfig.purposes[purpose.id];
                  const provider = settings.llmConfig.providers.find((p) => p.id === config.providerId);
                  const models = provider ? suggestedModels(provider.apiType, purpose.id) : [];
                  return (
                    <div key={purpose.id} className="rounded-[18px] border border-white/50 bg-white/40 p-4 shadow-[0_8px_32px_rgba(0,0,0,0.04)] backdrop-blur-xl dark:border-white/[0.08] dark:bg-white/[0.04]">
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <p className="text-sm font-medium">{purpose.label}</p>
                          <p className="text-xs text-[#aeaeb2]">{purpose.desc}</p>
                        </div>
                        <label className="flex items-center gap-2 text-sm">
                          <span className="text-[#6e6e73] dark:text-[#98989d]">{config.enabled ? "已启用" : "已禁用"}</span>
                          <input
                            type="checkbox"
                            checked={config.enabled}
                            onChange={(event) => updatePurpose(purpose.id, "enabled", event.target.checked)}
                            className="size-4 accent-[#007aff]"
                          />
                        </label>
                      </div>
                      {config.enabled && (
                        <div className="mt-3 flex flex-wrap items-end gap-3">
                          <label className="space-y-1.5 flex-1 min-w-40">
                            <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">提供商</span>
                            <Select
                              className="w-full"
                              value={config.providerId}
                              onChange={(event) => {
                                const selectedProvider = settings.llmConfig.providers.find((p) => p.id === event.target.value);
                                updatePurpose(purpose.id, "providerId", event.target.value);
                                if (selectedProvider) {
                                  const newModels = suggestedModels(selectedProvider.apiType, purpose.id);
                                  if (newModels.length > 0) {
                                    updatePurpose(purpose.id, "model", newModels[0]);
                                  }
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
                          <label className="space-y-1.5 flex-[2] min-w-48">
                            <span className="text-xs font-medium text-[#6e6e73] dark:text-[#98989d]">模型</span>
                            <Input
                              value={config.model}
                              onChange={(event) => updatePurpose(purpose.id, "model", event.target.value)}
                              placeholder={models.length > 0 ? `推荐: ${models.join("、")}` : "输入模型名称"}
                            />
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
                              <label className="space-y-1.5 w-24">
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
                      )}
                    </div>
                  );
                })}
              </div>
            </CardContent>
          </Card>

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

          <div className="flex justify-end gap-3">
            <Button onClick={() => void save()} disabled={busy === "save"}>
              {busy === "save" ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}保存设置
            </Button>
          </div>
        </>
      )}
    </div>
  );
}
