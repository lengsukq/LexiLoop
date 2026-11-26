import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { waitForAiTask } from "@/lib/ai-task-client";
import { apiFetch } from "@/lib/client-api";
import { playEntryTtsPreferYoudao } from "@/lib/tts-client";
import { toast } from "@/components/ui";
import type { RelatedWordItem } from "@/lib/types";
import type {
  RelatedPreview,
  RelatedSelection,
  RelationType,
  WordDetail,
  YoudaoPreviewData,
} from "./word-detail-types";

function errorMessage(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}

export function useWordDetail(wordId: string) {
  const router = useRouter();
  const [word, setWord] = useState<WordDetail | null>(null);
  const [note, setNote] = useState("");
  const [manualDefinition, setManualDefinition] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const [selectedAccent, setSelectedAccent] = useState<"US" | "UK">("US");
  const [ttsTip, setTtsTip] = useState("");
  const [relatedSelection, setRelatedSelection] = useState<RelatedSelection | null>(null);
  const [relatedPreview, setRelatedPreview] = useState<RelatedPreview | null>(null);
  const [relatedBusy, setRelatedBusy] = useState(false);
  const [relatedMessage, setRelatedMessage] = useState("");
  const [mnemonicBusy, setMnemonicBusy] = useState(false);
  const [mnemonicError, setMnemonicError] = useState("");
  const [translationBusy, setTranslationBusy] = useState(false);
  const [translationMessage, setTranslationMessage] = useState("");
  const [youdaoOpen, setYoudaoOpen] = useState(false);
  const [youdaoPreview, setYoudaoPreview] = useState<YoudaoPreviewData | null>(null);
  const [youdaoBusy, setYoudaoBusy] = useState(false);
  const [youdaoApplying, setYoudaoApplying] = useState(false);
  const [youdaoError, setYoudaoError] = useState("");

  const applyWord = useCallback((data: WordDetail) => {
    setWord(data);
    setNote(data.userNote ?? "");
    setManualDefinition(
      data.content.definitions.find(
        (definition) => definition.source === "user" && definition.isUserEdited,
      )?.text ?? "",
    );
  }, []);

  const load = useCallback(async () => {
    try {
      applyWord(await apiFetch<WordDetail>(`/api/words/${wordId}`));
      setError("");
    } catch (reason) {
      setError(errorMessage(reason, "加载失败"));
    }
  }, [applyWord, wordId]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  async function patch(values: Record<string, unknown>) {
    if (!word) return;
    setSaving(true);
    try {
      applyWord(await apiFetch<WordDetail>(`/api/words/${word.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(values),
      }));
    } catch (reason) {
      setError(errorMessage(reason, "保存失败"));
    } finally {
      setSaving(false);
    }
  }

  async function saveManualDefinition() {
    if (!word) return;
    setSaving(true);
    setError("");
    try {
      applyWord(await apiFetch<WordDetail>(`/api/words/${word.id}/content`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ definition: manualDefinition }),
      }));
      toast.success("手动释义已保存");
    } catch (reason) {
      const err = errorMessage(reason, "保存手动释义失败");
      setError(err);
      toast.error(err);
    } finally {
      setSaving(false);
    }
  }

  async function initialize(mode: "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE" = "FILL_MISSING_FIELDS") {
    if (!word) return;
    try {
      await apiFetch(`/api/words/${word.id}/initialize`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode }),
      });
      toast.success("已创建词条初始化任务");
      await load();
    } catch (reason) {
      const err = errorMessage(reason, "创建任务失败");
      setError(err);
      toast.error(err);
    }
  }

  async function remove() {
    if (!word || !window.confirm(`确定删除“${word.term}”及全部学习记录吗？`)) return;
    try {
      await apiFetch(`/api/words/${word.id}`, { method: "DELETE" });
      toast.success(`已删除词条“${word.term}”`);
      router.push("/words");
    } catch (reason) {
      const err = errorMessage(reason, "删除失败");
      setError(err);
      toast.error(err);
    }
  }

  async function openRelated(item: RelatedWordItem, relation: RelationType) {
    if (!word) return;
    setRelatedSelection({ item, relation });
    setRelatedPreview(null);
    setRelatedMessage("");
    setRelatedBusy(true);
    try {
      setRelatedPreview(await apiFetch<RelatedPreview>(
        `/api/words/${word.id}/related?term=${encodeURIComponent(item.word)}`,
      ));
    } catch (reason) {
      setRelatedMessage(errorMessage(reason, "读取关联词状态失败"));
    } finally {
      setRelatedBusy(false);
    }
  }

  async function addRelated() {
    if (!word || !relatedSelection) return;
    setRelatedBusy(true);
    setRelatedMessage("");
    try {
      const result = await apiFetch<{
        wordId: number;
        term: string;
        created: boolean;
        queued: boolean;
        initializationStatus: string;
      }>(`/api/words/${word.id}/related`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          term: relatedSelection.item.word,
          relation: relatedSelection.relation,
        }),
      });
      setRelatedPreview((current) => current ? {
        ...current,
        existing: {
          id: result.wordId,
          term: result.term,
          initializationStatus: result.initializationStatus,
          masteryLevel: "NEW",
          masteryScore: 0,
        },
      } : current);
      setRelatedMessage(result.created
        ? `“${result.term}”已加入词库并进入初始化队列。`
        : result.queued
          ? `“${result.term}”已重新加入初始化队列。`
          : `“${result.term}”已经在词库中。`);
    } catch (reason) {
      setRelatedMessage(errorMessage(reason, "加入关联词失败"));
    } finally {
      setRelatedBusy(false);
    }
  }

  async function playText(text = word?.term) {
    if (!text || !word) return;
    setTtsTip("");
    const isWord = text === word.term;
    const preferYoudao = isWord && word.content.pronunciations.some((pronunciation) => pronunciation.source === "youdao");
    const played = await playEntryTtsPreferYoudao(text, isWord ? word.entryType : "SENTENCE", selectedAccent, preferYoudao);
    if (!played) setTtsTip("发音播放失败，请检查网络。");
  }

  async function runAiTask(
    endpoint: string,
    setBusy: (busy: boolean) => void,
    onSuccess: () => void,
    onError: (message: string) => void,
  ) {
    if (!word) return;
    setBusy(true);
    setError("");
    try {
      const task = await apiFetch<{ jobId: number }>(`/api/words/${word.id}/${endpoint}`, {
        method: "POST",
      });
      await waitForAiTask(task.jobId);
      onSuccess();
      await load();
    } catch (reason) {
      onError(errorMessage(reason, "AI 任务失败"));
    } finally {
      setBusy(false);
    }
  }

  async function generateMnemonic() {
    setMnemonicError("");
    await runAiTask("mnemonic", setMnemonicBusy, () => undefined, setMnemonicError);
  }

  async function translateExamples() {
    setTranslationMessage("");
    await runAiTask(
      "example-translations",
      setTranslationBusy,
      () => setTranslationMessage("已补全缺失的中文翻译。"),
      setTranslationMessage,
    );
  }

  async function translateExample(index: number) {
    if (!word) return;
    setTranslationMessage("");
    try {
      const result = await apiFetch<{ translated: boolean }>(`/api/words/${word.id}/example-translations`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ index }),
      });
      await load();
      setTranslationMessage(result.translated ? "已完成这条例句的中文翻译。" : "这条例句已经有翻译，或内容刚刚发生变化。");
    } catch (reason) {
      setTranslationMessage(errorMessage(reason, "例句翻译失败"));
    }
  }

  async function deleteExample(index: number) {
    if (!word) return;
    try {
      applyWord(await apiFetch<WordDetail>(`/api/words/${word.id}/examples`, {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ index }),
      }));
    } catch (reason) {
      setError(errorMessage(reason, "删除例句失败"));
    }
  }

  async function translateSummary() {
    setTranslationMessage("");
    await runAiTask(
      "summary-translation",
      setTranslationBusy,
      () => setTranslationMessage("已补全词条中文释义。"),
      setTranslationMessage,
    );
  }

  async function fetchYoudaoPreview() {
    if (!word) return;
    setYoudaoOpen(true);
    setYoudaoPreview(null);
    setYoudaoError("");
    setYoudaoBusy(true);
    try {
      setYoudaoPreview(await apiFetch<YoudaoPreviewData>(`/api/words/${word.id}/youdao-preview`, { method: "POST" }));
    } catch (reason) {
      setYoudaoError(errorMessage(reason, "有道词典获取失败"));
    } finally {
      setYoudaoBusy(false);
    }
  }

  async function applyYoudao(mode: "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE") {
    if (!word || !youdaoPreview) return;
    setYoudaoApplying(true);
    setYoudaoError("");
    try {
      applyWord(await apiFetch<WordDetail>(`/api/words/${word.id}/youdao-apply`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode, content: youdaoPreview.content, attempts: youdaoPreview.attempts }),
      }));
      setYoudaoOpen(false);
      setYoudaoPreview(null);
      toast.success("已应用有道词典内容");
    } catch (reason) {
      setYoudaoError(errorMessage(reason, "应用有道词典内容失败"));
    } finally {
      setYoudaoApplying(false);
    }
  }

  return {
    word,
    note,
    setNote,
    manualDefinition,
    setManualDefinition,
    error,
    saving,
    selectedAccent,
    setSelectedAccent,
    ttsTip,
    relatedSelection,
    setRelatedSelection,
    relatedPreview,
    relatedBusy,
    relatedMessage,
    mnemonicBusy,
    mnemonicError,
    translationBusy,
    translationMessage,
    load,
    patch,
    saveManualDefinition,
    initialize,
    remove,
    openRelated,
    addRelated,
    playText,
    generateMnemonic,
    translateExamples,
    translateExample,
    deleteExample,
    translateSummary,
    youdaoOpen,
    setYoudaoOpen,
    youdaoPreview,
    youdaoBusy,
    youdaoApplying,
    youdaoError,
    fetchYoudaoPreview,
    applyYoudao,
  };
}
