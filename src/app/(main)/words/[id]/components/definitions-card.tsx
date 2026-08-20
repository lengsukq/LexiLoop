import { ChevronDown, Loader2, Save, Sparkles } from "lucide-react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { WordDetail } from "../word-detail-types";

type Definition = WordDetail["content"]["definitions"][number];

export function DefinitionsCard({
  word,
  manualDefinition,
  saving,
  translationBusy,
  translationMessage,
  onManualDefinitionChange,
  onSave,
  onTranslate,
}: {
  word: WordDetail;
  manualDefinition: string;
  saving: boolean;
  translationBusy: boolean;
  translationMessage: string;
  onManualDefinitionChange: (value: string) => void;
  onSave: () => Promise<void>;
  onTranslate: () => Promise<void>;
}) {
  const targetDefinitions = word.content.definitions.filter((definition) =>
    definition.language === word.targetLanguage,
  );
  const sourceDefinitions = word.content.definitions.filter((definition) =>
    definition.language !== word.targetLanguage,
  );
  const needsTranslation = word.sourceLanguage !== word.targetLanguage
    && sourceDefinitions.length > targetDefinitions.length;
  const summaryTranslation = word.content.summary.translation?.trim() ?? "";

  return <Card>
    <CardHeader className="flex-row items-start justify-between gap-3">
      <div>
        <CardTitle>中文释义</CardTitle>
        {needsTranslation && <p className="mt-1 text-xs text-quaternary-label">词典原文尚未全部翻译成目标语言</p>}
      </div>
      {needsTranslation && <Button variant="outline" size="sm" onClick={() => void onTranslate()} disabled={translationBusy}>
        {translationBusy ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}
        补全中文释义
      </Button>}
    </CardHeader>
    <CardContent>
      {targetDefinitions.length > 0
        ? <DefinitionList definitions={targetDefinitions} />
        : summaryTranslation
          ? <div className="rounded-[16px] border border-success/15 bg-success/[0.07] p-4 shadow-[0_4px_16px_rgba(52,199,89,0.04)]">
              <div className="flex flex-wrap gap-2"><Badge tone="green">中文概览</Badge></div>
              <p className="mt-2 break-words text-[16px] font-medium leading-7">{summaryTranslation}</p>
              <p className="mt-2 text-xs text-secondary-label">这是词条概览；点击“补全中文释义”可逐条翻译下面的英文原文。</p>
            </div>
          : <div className="rounded-[16px] border border-warning/15 bg-warning/[0.07] p-4 text-sm text-[#8a3b00] dark:text-warning">
              暂无中文释义。可以补全翻译，或直接填写手动释义继续学习。
            </div>}

      {translationMessage && <p className={`mt-3 text-xs ${translationMessage.startsWith("已") ? "text-success-deep" : "text-danger-deep"}`}>{translationMessage}</p>}

      {sourceDefinitions.length > 0 && <details className="group mt-4 rounded-[16px] border border-black/[0.05] bg-black/[0.018] dark:border-white/[0.07] dark:bg-white/[0.025]">
        <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3 text-sm font-medium text-secondary-label [&::-webkit-details-marker]:hidden dark:text-secondary-label">
          <span>查看英文原文（{sourceDefinitions.length} 条）</span>
          <ChevronDown className="size-4 transition-transform group-open:rotate-180" />
        </summary>
        <div className="space-y-3 border-t border-black/[0.05] p-3 dark:border-white/[0.07]">
          <DefinitionList definitions={sourceDefinitions} compact />
        </div>
      </details>}

      <div className="mt-5 border-t border-black/[0.06] pt-5 dark:border-white/[0.08]">
        <label className="text-sm font-medium">手动中文释义</label>
        <textarea className="mt-2 min-h-24 w-full rounded-[14px] border border-black/[0.06] bg-white/60 p-3 text-sm shadow-[inset_0_1px_3px_rgba(0,0,0,0.03)] outline-none backdrop-blur-sm transition focus:border-accent/40 focus:shadow-[0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08] dark:bg-white/[0.04]" value={manualDefinition} onChange={(event) => onManualDefinitionChange(event.target.value)} placeholder="例如：参与者；参加者。保存后即使 AI 服务暂时失败，该词也可以进入学习。" />
        <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
          <p className="text-xs text-tertiary-label">AI 强制刷新时不会覆盖你的手动释义。</p>
          <Button variant="outline" onClick={() => void onSave()} disabled={saving}>{saving ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}保存释义</Button>
        </div>
      </div>
    </CardContent>
  </Card>;
}

function DefinitionList({ definitions, compact = false }: { definitions: Definition[]; compact?: boolean }) {
  // Group definitions by partOfSpeech
  const groups: Array<{ pos: string; items: Definition[] }> = [];
  for (const definition of definitions) {
    const pos = definition.partOfSpeech || "释义";
    const existing = groups.find((g) => g.pos === pos);
    if (existing) {
      existing.items.push(definition);
    } else {
      groups.push({ pos, items: [definition] });
    }
  }

  return <div className="space-y-4">{groups.map((group) => {
    const firstTone = group.items[0]?.source === "user" ? "purple" : group.items[0]?.source.startsWith("ai:") ? "green" : "blue";
    const firstSource = group.items[0]?.source === "user" ? "我的释义" : group.items[0]?.source.startsWith("ai:") ? "AI 翻译" : group.items[0]?.source;
    return <div key={group.pos} className={`rounded-[16px] border border-white/50 bg-white/40 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04] ${compact ? "p-3" : "p-4"}`}>
      <div className="flex flex-wrap gap-2">
        <Badge>{group.pos}</Badge>
        {firstSource && <Badge tone={firstTone}>{firstSource}</Badge>}
      </div>
      <div className="mt-2 space-y-2">
        {group.items.map((definition, index) => <div key={`${definition.senseId ?? index}-${definition.text}`}>
          <p className={`break-words ${compact ? "text-sm leading-6 text-secondary-label" : "leading-7"}`}>{definition.text}</p>
          {definition.usageNote && <p className="mt-1 text-xs text-secondary-label">用法：{definition.usageNote}</p>}
        </div>)}
      </div>
    </div>;
  })}</div>;
}
