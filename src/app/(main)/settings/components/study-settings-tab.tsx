import { useRef, useState } from "react";
import { CheckCircle2, ChevronDown, ChevronRight, GripVertical, Loader2, PlugZap, Volume2 } from "lucide-react";
import type { AppSettings, InitializationProviderId } from "@/lib/types";
import { Button, Card, CardContent, CardHeader, CardTitle, Input, Select } from "@/components/ui";
import { NumberField, Toggle, type SettingsUpdater, type TestState } from "../settings-shared";

const PROVIDER_LABELS: Record<InitializationProviderId, string> = {
  "merriam-webster": "Merriam-Webster",
  "dictionaryapi.dev": "DictionaryAPI.dev",
  ecdict: "ECDICT 离线词典",
  ai: "AI 词条初始化",
  mymemory: "MyMemory 翻译",
  "tencent-translate": "腾讯翻译",
};

export function StudySettingsTab({
  settings,
  update,
  ttsState,
  ttsMessage,
  onTestTts,
  tencentTestState,
  tencentTestMessage,
  onTestTencentTranslate,
}: {
  settings: AppSettings;
  update: SettingsUpdater;
  ttsState: TestState;
  ttsMessage: string;
  onTestTts: () => Promise<void>;
  tencentTestState: TestState;
  tencentTestMessage: string;
  onTestTencentTranslate: () => Promise<void>;
}) {
  const [mwKeysExpanded, setMwKeysExpanded] = useState(false);
  const [tencentKeysExpanded, setTencentKeysExpanded] = useState(false);
  const dragIndex = useRef<number | null>(null);
  const [dragOverIndex, setDragOverIndex] = useState<number | null>(null);

  const providerOrder = settings.translationProviderOrder ?? [];

  function handleDragStart(index: number) {
    dragIndex.current = index;
  }

  function handleDragOver(event: React.DragEvent, index: number) {
    event.preventDefault();
    setDragOverIndex(index);
  }

  function handleDrop(index: number) {
    const from = dragIndex.current;
    setDragOverIndex(null);
    dragIndex.current = null;
    if (from === null || from === index) return;
    const reordered = [...providerOrder];
    const [moved] = reordered.splice(from, 1) as [InitializationProviderId];
    reordered.splice(index, 0, moved);
    update("translationProviderOrder", reordered);
  }

  function handleDragEnd() {
    dragIndex.current = null;
    setDragOverIndex(null);
  }

  return (
    <div className="space-y-5">
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

      <Card>
        <CardHeader><CardTitle>语音与词典</CardTitle></CardHeader>
        <CardContent className="space-y-6">
          <section>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[#6e6e73] dark:text-[#98989d]">发音设置</h3>
            <div className="flex flex-wrap gap-4">
              <label className="min-w-36 space-y-1.5">
                <span className="text-xs font-medium">默认口音</span>
                <Select className="w-full" value={settings.defaultAccent} onChange={(event) => update("defaultAccent", event.target.value as AppSettings["defaultAccent"])}>
                  <option value="US">美音</option><option value="UK">英音</option><option value="GENERAL">通用</option>
                </Select>
              </label>
              <label className="min-w-28 space-y-1.5">
                <span className="text-xs font-medium">播放速度</span>
                <Select className="w-full" value={settings.playbackSpeed} onChange={(event) => update("playbackSpeed", Number(event.target.value))}>
                  <option value={0.75}>0.75x</option><option value={1}>1.0x</option><option value={1.25}>1.25x</option><option value={1.5}>1.5x</option>
                </Select>
              </label>
              <div className="flex items-end pb-1"><Toggle label="自动播放发音" checked={settings.autoPlayPronunciation} onChange={(value) => update("autoPlayPronunciation", value)} /></div>
            </div>
          </section>

          <hr className="border-black/[0.06] dark:border-white/[0.08]" />

          <section>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[#6e6e73] dark:text-[#98989d]">数据来源与执行顺序</h3>
            <p className="mb-3 text-xs text-[#aeaeb2]">拖动调整翻译/词典查询优先级，排在上方的来源会先被执行。</p>
            <div className="space-y-1.5">
              {providerOrder.map((id, index) => (
                <div
                  key={id}
                  draggable
                  onDragStart={() => handleDragStart(index)}
                  onDragOver={(event) => handleDragOver(event, index)}
                  onDrop={() => handleDrop(index)}
                  onDragEnd={handleDragEnd}
                  className={`flex cursor-grab items-center gap-3 rounded-[12px] border px-3 py-2.5 transition-all active:cursor-grabbing ${
                    dragOverIndex === index
                      ? "border-[#007aff]/40 bg-[#007aff]/[0.06]"
                      : "border-black/[0.06] bg-white/[0.6] dark:border-white/[0.08] dark:bg-white/[0.04]"
                  }`}
                >
                  <GripVertical className="size-4 shrink-0 text-[#aeaeb2]" />
                  <span className="flex size-5 shrink-0 items-center justify-center rounded-full bg-[#007aff]/[0.08] text-[10px] font-bold text-[#007aff]">{index + 1}</span>
                  <span className="text-sm font-medium">{PROVIDER_LABELS[id] ?? id}</span>
                </div>
              ))}
            </div>
          </section>

          <hr className="border-black/[0.06] dark:border-white/[0.08]" />

          <section>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[#6e6e73] dark:text-[#98989d]">在线词典来源</h3>
            <div className="flex flex-wrap gap-x-6 gap-y-2">
              <Toggle label="DictionaryAPI.dev" checked={settings.dictionaryApiEnabled} onChange={(value) => update("dictionaryApiEnabled", value)} />
              <Toggle label="MyMemory 翻译" checked={settings.myMemoryEnabled} onChange={(value) => update("myMemoryEnabled", value)} />
              <Toggle label="Merriam-Webster 词典" checked={settings.merriamWebsterEnabled} onChange={(value) => update("merriamWebsterEnabled", value)} />
            </div>
          </section>

          <section>
            <button type="button" onClick={() => setMwKeysExpanded((expanded) => !expanded)} className="flex items-center gap-1.5 text-sm font-medium text-[#6e6e73] transition-colors hover:text-[#1c1c1e] dark:text-[#98989d] dark:hover:text-white">
              {mwKeysExpanded ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
              Merriam-Webster API 密钥 <span className="text-xs font-normal text-[#aeaeb2]">（可选）</span>
            </button>
            {mwKeysExpanded && (
              <div className="mt-3 grid gap-3 sm:grid-cols-2">
                <label className="space-y-1.5"><span className="text-xs font-medium">Collegiate Dictionary Key</span><Input type="password" autoComplete="off" value={settings.merriamWebsterDictionaryKey} onChange={(event) => update("merriamWebsterDictionaryKey", event.target.value)} placeholder="输入词典 API Key" /></label>
                <label className="space-y-1.5"><span className="text-xs font-medium">Collegiate Thesaurus Key</span><Input type="password" autoComplete="off" value={settings.merriamWebsterThesaurusKey} onChange={(event) => update("merriamWebsterThesaurusKey", event.target.value)} placeholder="输入同义词词典 API Key" /></label>
              </div>
            )}
          </section>

          <hr className="border-black/[0.06] dark:border-white/[0.08]" />

          <section>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[#6e6e73] dark:text-[#98989d]">腾讯翻译</h3>
            <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
              <Toggle label="启用腾讯翻译" checked={settings.tencentTranslateEnabled} onChange={(value) => update("tencentTranslateEnabled", value)} />
              <Button variant="outline" size="sm" onClick={() => void onTestTencentTranslate()} disabled={tencentTestState === "testing" || !settings.tencentTranslateSecretId || !settings.tencentTranslateSecretKey}>
                {tencentTestState === "testing" ? <Loader2 className="size-4 animate-spin" /> : <PlugZap className="size-4" />}测试连接
              </Button>
              <span className="text-xs text-[#aeaeb2]">腾讯云机器翻译提供 500 万字符/月免费额度</span>
            </div>
            {tencentTestState !== "idle" && tencentTestMessage && (
              <p className={`mt-2 text-xs ${tencentTestState === "success" ? "text-[#34c759]" : "text-[#ff3b30]"}`}>{tencentTestMessage}</p>
            )}
            <button type="button" onClick={() => setTencentKeysExpanded((expanded) => !expanded)} className="mt-3 flex items-center gap-1.5 text-sm font-medium text-[#6e6e73] transition-colors hover:text-[#1c1c1e] dark:text-[#98989d] dark:hover:text-white">
              {tencentKeysExpanded ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
              腾讯翻译 API 密钥
            </button>
            {tencentKeysExpanded && (
              <div className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                <label className="space-y-1.5"><span className="text-xs font-medium">SecretId</span><Input type="password" autoComplete="off" value={settings.tencentTranslateSecretId} onChange={(event) => update("tencentTranslateSecretId", event.target.value)} placeholder="输入腾讯云 SecretId" /></label>
                <label className="space-y-1.5"><span className="text-xs font-medium">SecretKey</span><Input type="password" autoComplete="off" value={settings.tencentTranslateSecretKey} onChange={(event) => update("tencentTranslateSecretKey", event.target.value)} placeholder="输入腾讯云 SecretKey" /></label>
                <label className="space-y-1.5"><span className="text-xs font-medium">ProjectId</span><Input type="number" min={0} value={settings.tencentTranslateProjectId} onChange={(event) => update("tencentTranslateProjectId", Math.max(0, Number(event.target.value) || 0))} placeholder="0" /></label>
              </div>
            )}
          </section>

          <hr className="border-black/[0.06] dark:border-white/[0.08]" />

          <section>
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wider text-[#6e6e73] dark:text-[#98989d]">语音合成 (TTS)</h3>
            <p className="mb-3 text-sm text-[#6e6e73] dark:text-[#98989d]">发音功能使用 <strong>Microsoft Edge TTS</strong>，无需配置 API Key 或模型。</p>
            <div className="flex flex-wrap items-center gap-3">
              <div className="flex items-center gap-2 rounded-[14px] border border-[#34c759]/15 bg-[#34c759]/[0.08] px-4 py-2 text-sm text-[#248a3d] dark:text-[#30d158]"><CheckCircle2 className="size-4" />免费 - 无需额外配置</div>
              <div className="flex items-center gap-2 rounded-[14px] border border-[#007aff]/15 bg-[#007aff]/[0.08] px-4 py-2 text-sm text-[#007aff] dark:text-[#0a84ff]"><Volume2 className="size-4" />支持美音 / 英音</div>
            </div>
            <div className="mt-3 flex items-center gap-3">
              <Button variant="outline" size="sm" onClick={() => void onTestTts()} disabled={ttsState === "testing"}>
                {ttsState === "testing" ? <Loader2 className="size-4 animate-spin" /> : <Volume2 className="size-4" />}试听发音
              </Button>
              {ttsState !== "idle" && <span className={`text-xs ${ttsState === "success" ? "text-[#34c759]" : "text-[#ff3b30]"}`}>{ttsMessage}</span>}
            </div>
          </section>
        </CardContent>
      </Card>
    </div>
  );
}
