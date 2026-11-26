import Link from "next/link";
import { ExternalLink, Loader2, Plus, X } from "lucide-react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, buttonClass } from "@/components/ui";
import { InitializationBadge } from "@/components/status-badges";
import type { RelatedPreview, RelatedSelection, RelationType } from "../word-detail-types";

export function RelatedWordDialog({
  selection,
  preview,
  busy,
  message,
  onClose,
  onAdd,
}: {
  selection: RelatedSelection;
  preview: RelatedPreview | null;
  busy: boolean;
  message: string;
  onClose: () => void;
  onAdd: () => Promise<void>;
}) {
  const canAdd = !preview?.existing || !["READY", "PARTIAL"].includes(preview.existing.initializationStatus);

  return <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
    <button type="button" aria-label="关闭关联词提示" className="absolute inset-0 bg-black/30 backdrop-blur-md" onClick={onClose} />
    <Card className="relative z-10 w-full max-w-md shadow-2xl">
      <CardHeader>
        <div className="flex items-start justify-between gap-4">
          <div><Badge tone="purple">{relationLabel(selection.relation)}</Badge><CardTitle className="mt-3 text-2xl">{selection.item.word}</CardTitle>{selection.item.translation && <p className="mt-1 text-sm text-secondary-label">{selection.item.translation}</p>}</div>
          <Button variant="ghost" size="sm" onClick={onClose}><X className="size-4" /></Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        {selection.item.difference && <div className="rounded-[16px] border border-purple/10 bg-purple/[0.06] p-3 text-sm leading-6 text-purple-deep">{selection.item.difference}</div>}
        {busy && !preview
          ? <div className="flex items-center justify-center gap-2 py-6 text-sm text-secondary-label"><Loader2 className="size-5 animate-spin" />正在检查词库状态…</div>
          : preview && <PreviewStatus preview={preview} />}
        {message && <div className="rounded-[16px] border border-success/10 bg-success/[0.06] p-3 text-sm text-success-deep">{message}</div>}
        <div className="flex justify-end gap-2">
          {preview?.existing && <Link href={`/words/${preview.existing.id}`} className={buttonClass("outline")}><ExternalLink className="size-4" />打开词条</Link>}
          {canAdd && <Button onClick={() => void onAdd()} disabled={busy || !preview}>{busy ? <Loader2 className="size-4 animate-spin" /> : <Plus className="size-4" />}{preview?.existing ? "加入初始化" : "加入词库并初始化"}</Button>}
        </div>
      </CardContent>
    </Card>
  </div>;
}

function PreviewStatus({ preview }: { preview: RelatedPreview }) {
  return <div className="rounded-[16px] border border-white/50 bg-white/40 p-3 text-sm dark:border-white/[0.06] dark:bg-white/[0.04]">
    <div className="flex items-center justify-between"><span className="text-secondary-label">词库状态</span>{preview.existing ? <InitializationBadge status={preview.existing.initializationStatus} /> : <Badge>尚未加入</Badge>}</div>
    <div className="mt-2 flex items-center justify-between"><span className="text-secondary-label">语言方向</span><span>{preview.sourceLanguage} → {preview.targetLanguage}</span></div>
    {preview.partOfSpeech && <div className="mt-2 flex items-center justify-between"><span className="text-secondary-label">词性</span><span>{preview.partOfSpeech}</span></div>}
  </div>;
}

function relationLabel(relation: RelationType): string {
  return {
    SYNONYM: "近义词",
    ANTONYM: "反义词",
    WORD_FAMILY: "同根词 / 词族",
    CONFUSED_WITH: "易混词",
  }[relation];
}
