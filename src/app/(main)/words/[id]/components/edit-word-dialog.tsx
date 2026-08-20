"use client";

import { useState } from "react";
import { errorMessage } from "@/lib/format";
import { AlertCircle, BookText, Check, Loader2, Sparkles } from "lucide-react";
import { Alert, Button, Dialog, Input } from "@/components/ui";
import { apiFetch } from "@/lib/client-api";
import { entryTypeLabel } from "@/lib/entry-type-label";
import type { YoudaoPreviewData } from "../word-detail-types";
import { PreviewContent } from "./youdao-preview-dialog";

type ApplyMode = "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE";

export function EditWordDialog({
  open,
  wordId,
  initialTerm,
  sourceLanguage,
  targetLanguage,
  entryType,
  onClose,
  onSaved,
}: {
  open: boolean;
  wordId: number;
  initialTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  entryType: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [term, setTerm] = useState(initialTerm);
  const [mode, setMode] = useState<ApplyMode>("FILL_MISSING_FIELDS");
  const [preview, setPreview] = useState<YoudaoPreviewData | null>(null);
  const [busy, setBusy] = useState(false);
  const [applying, setApplying] = useState(false);
  const [error, setError] = useState("");

  const termChanged = term.trim() !== initialTerm;

  async function fetchPreview() {
    if (!term.trim()) return;
    setBusy(true);
    setError("");
    setPreview(null);
    try {
      setPreview(await apiFetch<YoudaoPreviewData>(`/api/words/${wordId}/youdao-preview`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ term: term.trim() }),
      }));
    } catch (reason) {
      setError(errorMessage(reason, "有道词典获取失败"));
    } finally {
      setBusy(false);
    }
  }

  async function apply() {
    if (!preview?.hasContent) return;
    setApplying(true);
    setError("");
    try {
      await apiFetch(`/api/words/${wordId}/youdao-apply`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mode,
          content: preview.content,
          attempts: preview.attempts,
          newTerm: term.trim(),
        }),
      });
      onSaved();
      onClose();
    } catch (reason) {
      setError(errorMessage(reason, "保存词条失败"));
    } finally {
      setApplying(false);
    }
  }

  return <Dialog open={open} onClose={onClose} title="编辑词条" maxWidth="max-w-2xl">
    <div className="space-y-5">
      <div className="space-y-2">
        <label className="text-sm font-medium">词条文本</label>
        <Input
          value={term}
          onChange={(event) => { setTerm(event.target.value); setPreview(null); setError(""); }}
          placeholder="输入修改后的词条文本"
          maxLength={300}
          disabled={busy || applying}
        />
        <p className="text-xs text-secondary-label">
          {sourceLanguage} → {targetLanguage} · {entryTypeLabel(entryType)}
          {termChanged ? "（已修改，需重新初始化内容）" : "（文本未变化，可重新获取内容）"}
        </p>
      </div>

      <div className="rounded-[16px] border border-accent/10 bg-accent/[0.06] p-3 text-xs leading-5 text-secondary-label">
        修改词条后需点击「有道词典初始化」获取新内容并确认应用，成功后才保存词条文本；未初始化前词条不会发生变化。
      </div>

      {error && <Alert icon={<AlertCircle className="size-4" />}>{error}</Alert>}

      <div className="flex flex-wrap justify-end gap-2">
        <Button variant="ghost" onClick={onClose} disabled={busy || applying}>取消</Button>
        <Button variant="outline" onClick={() => void fetchPreview()} disabled={!term.trim() || busy || applying}>
          {busy ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}有道词典初始化
        </Button>
      </div>

      {preview && !preview.hasContent && !busy && <div className="space-y-4 py-4 text-center">
        <BookText className="mx-auto size-10 text-tertiary-label" />
        <p className="text-sm text-secondary-label">有道词典未返回该词条的有效内容，暂不能保存修改。</p>
        {preview.attempts.filter((attempt) => attempt.errorMessage).map((attempt, index) => <p key={index} className="text-xs text-tertiary-label">{attempt.errorMessage}</p>)}
      </div>}

      {preview && preview.hasContent && !busy && <div className="space-y-5">
        <PreviewContent preview={preview} />

        <div className="space-y-3 rounded-[18px] border border-white/50 bg-white/40 p-4 dark:border-white/[0.06] dark:bg-white/[0.04]">
          <p className="text-sm font-semibold">应用方式</p>
          <label className="flex cursor-pointer items-start gap-3">
            <input type="radio" name="edit-mode" className="mt-1 accent-accent" checked={mode === "FILL_MISSING_FIELDS"} onChange={() => setMode("FILL_MISSING_FIELDS")} />
            <span><span className="text-sm font-medium">仅补全缺失字段</span><span className="mt-0.5 block text-xs text-secondary-label">保留现有内容，只用有道结果填充空缺部分。</span></span>
          </label>
          <label className="flex cursor-pointer items-start gap-3">
            <input type="radio" name="edit-mode" className="mt-1 accent-accent" checked={mode === "FORCE_OVERWRITE"} onChange={() => setMode("FORCE_OVERWRITE")} />
            <span><span className="text-sm font-medium">覆盖替换</span><span className="mt-0.5 block text-xs text-secondary-label">用有道结果替换现有内容，但保留手动编辑的释义和手动添加的例句。</span></span>
          </label>
        </div>

        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={applying}>取消</Button>
          <Button onClick={() => void apply()} disabled={applying}>
            {applying ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}确认应用并保存词条
          </Button>
        </div>
      </div>}
    </div>
  </Dialog>;
}
