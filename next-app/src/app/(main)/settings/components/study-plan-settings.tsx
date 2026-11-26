import type { AppSettings } from "@/lib/types";
import { Card, CardContent, CardHeader, CardTitle, Select } from "@/components/ui";
import { NumberField, type SettingsUpdater } from "../settings-shared";

export function StudyPlanSettings({ settings, update }: { settings: AppSettings; update: SettingsUpdater }) {
  return (
<Card>
  <CardHeader><CardTitle>每日学习计划</CardTitle></CardHeader>
  <CardContent>
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
      <NumberField label="每日新词" value={settings.dailyNewWords} min={0} max={100} onChange={(value) => update("dailyNewWords", value)} />
      <NumberField label="每日错词上限" value={settings.dailyWrongWordLimit} min={0} max={100} onChange={(value) => update("dailyWrongWordLimit", value)} />
      <NumberField label="到期复习上限" value={settings.dailyDueReviewLimit} min={1} max={500} onChange={(value) => update("dailyDueReviewLimit", value)} />
      <div className="space-y-1.5">
        <NumberField label="选择题选项延迟（秒）" value={settings.choiceRevealDelaySeconds} min={0} max={60} onChange={(value) => update("choiceRevealDelaySeconds", value)} />
        <p className="text-xs leading-tight text-tertiary-label">两种选择题均适用；0 秒立即显示，默认 2 秒。</p>
      </div>
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
        <p className="text-xs leading-tight text-tertiary-label">默认 1 次：每个 AI 任务最多尝试 2 次。</p>
      </div>
    </div>
  </CardContent>
</Card>
  );
}
