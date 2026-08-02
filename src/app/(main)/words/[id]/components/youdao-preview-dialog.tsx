"use client";

import { useState } from "react";
import { AlertCircle, BookText, Check, Loader2, RefreshCw } from "lucide-react";
import { Badge, Button, Dialog } from "@/components/ui";
import type { YoudaoPreviewData } from "../word-detail-types";

type ApplyMode = "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE";

export function YoudaoPreviewDialog({
  open,
  preview,
  busy,
  applying,
  error,
  onClose,
  onRetry,
  onApply,
}: {
  open: boolean;
  preview: YoudaoPreviewData | null;
  busy: boolean;
  applying: boolean;
  error: string;
  onClose: () => void;
  onRetry: () => void;
  onApply: (mode: ApplyMode) => Promise<void>;
}) {
  const [mode, setMode] = useState<ApplyMode>("FILL_MISSING_FIELDS");

  return <Dialog open={open} onClose={onClose} title="有道词典获取" maxWidth="max-w-2xl">
    {busy && <div className="flex flex-col items-center justify-center gap-3 py-14 text-sm text-[#6e6e73] dark:text-[#98989d]"><Loader2 className="size-7 animate-spin text-[#007aff]" />正在从有道词典获取内容…</div>}

    {!busy && error && <div className="space-y-4 py-6 text-center">
      <AlertCircle className="mx-auto size-10 text-[#ff3b30]" />
      <p className="text-sm text-[#d70015] dark:text-[#ff453a]">{error}</p>
      <div className="flex justify-center gap-2">
        <Button variant="ghost" onClick={onClose}>关闭</Button>
        <Button variant="outline" onClick={onRetry}><RefreshCw className="size-4" />重试</Button>
      </div>
    </div>}

    {!busy && !error && preview && !preview.hasContent && <div className="space-y-4 py-6 text-center">
      <BookText className="mx-auto size-10 text-[#aeaeb2]" />
      <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">有道词典未返回该词条的有效内容。</p>
      {preview.attempts.filter((attempt) => attempt.errorMessage).map((attempt, index) => <p key={index} className="text-xs text-[#aeaeb2]">{attempt.errorMessage}</p>)}
      <div className="flex justify-center"><Button variant="ghost" onClick={onClose}>关闭</Button></div>
    </div>}

    {!busy && !error && preview && preview.hasContent && <div className="space-y-5">
      <PreviewContent preview={preview} />

      <div className="space-y-3 rounded-[18px] border border-white/50 bg-white/40 p-4 dark:border-white/[0.06] dark:bg-white/[0.04]">
        <p className="text-sm font-semibold">应用方式</p>
        <label className="flex cursor-pointer items-start gap-3">
          <input type="radio" name="youdao-mode" className="mt-1 accent-[#007aff]" checked={mode === "FILL_MISSING_FIELDS"} onChange={() => setMode("FILL_MISSING_FIELDS")} />
          <span><span className="text-sm font-medium">仅补全缺失字段</span><span className="mt-0.5 block text-xs text-[#6e6e73] dark:text-[#98989d]">保留现有内容，只用有道结果填充空缺部分。</span></span>
        </label>
        <label className="flex cursor-pointer items-start gap-3">
          <input type="radio" name="youdao-mode" className="mt-1 accent-[#007aff]" checked={mode === "FORCE_OVERWRITE"} onChange={() => setMode("FORCE_OVERWRITE")} />
          <span><span className="text-sm font-medium">覆盖替换</span><span className="mt-0.5 block text-xs text-[#6e6e73] dark:text-[#98989d]">用有道结果替换现有内容，但保留手动编辑的释义和手动添加的例句。</span></span>
        </label>
      </div>

      <div className="flex justify-end gap-2">
        <Button variant="ghost" onClick={onClose} disabled={applying}>取消</Button>
        <Button onClick={() => void onApply(mode)} disabled={applying}>{applying ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}确认应用</Button>
      </div>
    </div>}
  </Dialog>;
}

export function PreviewContent({ preview }: { preview: YoudaoPreviewData }) {
  const { content } = preview;
  return <div className="max-h-[45vh] space-y-4 overflow-y-auto pr-1">
    {content.summary.translation && <div className="rounded-[16px] border border-[#007aff]/10 bg-[#007aff]/[0.06] p-3">
      <p className="text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">翻译摘要</p>
      <p className="mt-1 text-sm font-medium leading-6">{content.summary.translation}</p>
    </div>}

    {content.pronunciations.length > 0 && <div className="flex flex-wrap gap-2">
      {content.pronunciations.map((item) => <Badge key={item.accent} tone="blue">{item.accent === "UK" ? "英" : "美"} /{item.phonetic}/</Badge>)}
    </div>}

    {content.definitions.length > 0 && <Section label="释义">
      {content.definitions.map((definition, index) => <div key={`${definition.senseId}-${index}`} className="rounded-[14px] border border-white/50 bg-white/40 p-3 dark:border-white/[0.06] dark:bg-white/[0.04]">
        <div className="flex flex-wrap gap-2">{definition.partOfSpeech && <Badge>{definition.partOfSpeech}</Badge>}</div>
        <p className="mt-1.5 text-sm leading-6">{definition.text}</p>
      </div>)}
    </Section>}

    {content.examples.length > 0 && <Section label="例句">
      {content.examples.map((example, index) => <div key={`${example.sentence}-${index}`} className="rounded-[14px] border-l-4 border-[#007aff]/40 bg-white/40 p-3 dark:bg-white/[0.04]">
        <p className="text-sm italic leading-6">{example.sentence}</p>
        {example.translation && <p className="mt-1 text-xs text-[#6e6e73] dark:text-[#98989d]">{example.translation}</p>}
      </div>)}
    </Section>}

    {content.phrases.length > 0 && <Section label="短语搭配">
      <div className="flex flex-wrap gap-2">{content.phrases.map((phrase, index) => <Badge key={`${phrase.phrase}-${index}`}>{phrase.phrase}{phrase.translation ? ` · ${phrase.translation}` : ""}</Badge>)}</div>
    </Section>}

    {content.forms.length > 0 && <Section label="词形变化">
      <div className="flex flex-wrap gap-2">{content.forms.map((form, index) => <Badge key={`${form.type}-${index}`} tone="purple">{formLabel(form.type)}: {form.value}</Badge>)}</div>
    </Section>}
  </div>;
}

export function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return <div className="space-y-2">
    <p className="text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">{label}</p>
    <div className="space-y-2">{children}</div>
  </div>;
}

export function formLabel(type: string): string {
  const labels: Record<string, string> = {
    PLURAL: "复数", THIRD_PERSON: "三单", PRESENT_PARTICIPLE: "现在分词",
    PAST: "过去式", PAST_PARTICIPLE: "过去分词", COMPARATIVE: "比较级", SUPERLATIVE: "最高级",
  };
  return labels[type] ?? type;
}
