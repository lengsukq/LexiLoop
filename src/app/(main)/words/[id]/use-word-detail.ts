import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { waitForAiTask } from "@/lib/ai-task-client";
import { apiFetch } from "@/lib/client-api";
import type { RelatedWordItem } from "@/lib/types";
import type {
  RelatedPreview,
  RelatedSelection,
  RelationType,
  WordDetail,
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
  const [selectedAccent, setSelectedAccent] = useState<"US" | "UK" | "GENERAL">("US");
  const [ttsTip, setTtsTip] = useState("");
  const [relatedSelection, setRelatedSelection] = useState<RelatedSelection | null>(null);
  const [relatedPreview, setRelatedPreview] = useState<RelatedPreview | null>(null);
  const [relatedBusy, setRelatedBusy] = useState(false);
  const [relatedMessage, setRelatedMessage] = useState("");
  const [mnemonicBusy, setMnemonicBusy] = useState(false);
  const [mnemonicError, setMnemonicError] = useState("");
  const [translationBusy, setTranslationBusy] = useState(false);
  const [translationMessage, setTranslationMessage] = useState("");

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
    } catch (reason) {
      setError(errorMessage(reason, "保存手动释义失败"));
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
      await load();
    } catch (reason) {
      setError(errorMessage(reason, "创建任务失败"));
    }
  }

  async function remove() {
    if (!word || !window.confirm(`确定删除“${word.term}”及全部学习记录吗？`)) return;
    try {
      await apiFetch(`/api/words/${word.id}`, { method: "DELETE" });
      router.push("/words");
    } catch (reason) {
      setError(errorMessage(reason, "删除失败"));
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
    if (!text) return;
    setTtsTip("");
    try {
      const response = await fetch(
        `/api/tts?word=${encodeURIComponent(text)}&accent=${encodeURIComponent(selectedAccent)}`,
      );
      if (!response.ok) throw new Error("TTS 请求失败");
      const url = URL.createObjectURL(await response.blob());
      const audio = new Audio(url);
      audio.addEventListener("ended", () => URL.revokeObjectURL(url), { once: true });
      await audio.play();
    } catch {
      setTtsTip("Edge TTS 发音失败，请检查网络。");
    }
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

  async function translateSummary() {
    setTranslationMessage("");
    await runAiTask(
      "summary-translation",
      setTranslationBusy,
      () => setTranslationMessage("已补全词条中文释义。"),
      setTranslationMessage,
    );
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
    translateSummary,
  };
}
