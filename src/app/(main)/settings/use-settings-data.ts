import { useCallback, useEffect, useState } from "react";
import { apiFetch } from "@/lib/client-api";
import { configureTtsSpeeds } from "@/lib/tts-client";
import type { AppSettings } from "@/lib/types";
import type { EcdictStatus, TestState } from "./settings-shared";

function errorMessage(reason: unknown, fallback: string): string {
  return reason instanceof Error ? reason.message : fallback;
}

export function useSettingsData() {
  const [settings, setSettings] = useState<AppSettings | null>(null);
  const [ecdict, setEcdict] = useState<EcdictStatus | null>(null);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState("");
  const [ttsState, setTtsState] = useState<TestState>("idle");
  const [ttsMessage, setTtsMessage] = useState("");
  const [tencentTestState, setTencentTestState] = useState<TestState>("idle");
  const [tencentTestMessage, setTencentTestMessage] = useState("");

  const resetFeedback = useCallback(() => {
    setError("");
    setMessage("");
  }, []);

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
      setError(errorMessage(reason, "加载失败"));
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
    resetFeedback();
    try {
      const saved = await apiFetch<AppSettings>("/api/settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(settings),
      });
      setSettings(saved);
      configureTtsSpeeds({ word: saved.wordSpeed, phrase: saved.phraseSpeed, sentence: saved.sentenceSpeed });
      setMessage("学习设置已保存。新会话和内置后台引擎会使用最新配置。");
    } catch (reason) {
      setError(errorMessage(reason, "保存失败"));
    } finally {
      setBusy("");
    }
  }

  async function ecdictAction(action: "download" | "enable" | "disable" | "remove") {
    setBusy(action);
    resetFeedback();
    try {
      const status = await apiFetch<EcdictStatus>("/api/settings/ecdict", {
        method: action === "remove" ? "DELETE" : "POST",
        headers: action === "remove" ? undefined : { "Content-Type": "application/json" },
        body: action === "remove" ? undefined : JSON.stringify({ action }),
      });
      setEcdict(status);
      // Sync ecdictEnabled into the local settings state so the Study tab's
      // data-source order list and the backend pipeline see the correct value.
      setSettings((current) => current ? { ...current, ecdictEnabled: status.enabled } : current);
      setMessage(action === "download" ? "ECDICT 已下载并启用。" : action === "remove" ? "ECDICT 已移除。" : "ECDICT 状态已更新。");
    } catch (reason) {
      setError(errorMessage(reason, "操作失败"));
    } finally {
      setBusy("");
    }
  }

  async function uploadEcdict(file?: File) {
    if (!file) return;
    setBusy("upload-ecdict");
    resetFeedback();
    try {
      const form = new FormData();
      form.append("file", file);
      const status = await apiFetch<EcdictStatus>("/api/settings/ecdict", { method: "PUT", body: form });
      setEcdict(status);
      setSettings((current) => current ? { ...current, ecdictEnabled: status.enabled } : current);
      setMessage("ECDICT 文件校验通过并已启用。");
    } catch (reason) {
      setError(errorMessage(reason, "上传失败"));
    } finally {
      setBusy("");
    }
  }

  async function restore(file?: File) {
    if (!file || !window.confirm("恢复会替换当前全部 LexiLoop 数据。已确认有可用备份吗？")) return;
    setBusy("restore");
    resetFeedback();
    try {
      const form = new FormData();
      form.append("file", file);
      const result = await apiFetch<{ message: string }>("/api/backups/restore", { method: "POST", body: form });
      setMessage(result.message);
    } catch (reason) {
      setError(errorMessage(reason, "恢复失败"));
    } finally {
      setBusy("");
    }
  }

  async function testTts() {
    setTtsState("testing");
    setTtsMessage("");
    try {
      const response = await fetch("/api/tts?word=LexiLoop&accent=US");
      if (!response.ok) {
        const body = await response.json().catch(() => ({ error: "未知错误" })) as { error?: string };
        throw new Error(body.error || "测试失败");
      }
      const audioUrl = URL.createObjectURL(await response.blob());
      const audio = new Audio(audioUrl);
      audio.addEventListener("ended", () => URL.revokeObjectURL(audioUrl), { once: true });
      await audio.play();
      setTtsState("success");
      setTtsMessage("播放正常");
    } catch (reason) {
      setTtsState("error");
      setTtsMessage(errorMessage(reason, "网络请求失败"));
    }
  }

  async function testTencentTranslate() {
    if (!settings) return;
    setTencentTestState("testing");
    setTencentTestMessage("");
    try {
      const response = await fetch("/api/settings/test-tencent-translate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          secretId: settings.tencentTranslateSecretId,
          secretKey: settings.tencentTranslateSecretKey,
          projectId: settings.tencentTranslateProjectId,
        }),
      });
      const body = await response.json().catch(() => ({})) as { data?: { translation?: string; durationMs?: number }; error?: { code?: string; message?: string } };
      if (!response.ok) {
        throw new Error(body.error?.message || `HTTP ${response.status}`);
      }
      setTencentTestState("success");
      setTencentTestMessage(`连接成功："hello" → "${body.data?.translation}"(${body.data?.durationMs}ms)`);
    } catch (reason) {
      setTencentTestState("error");
      setTencentTestMessage(errorMessage(reason, "连接失败"));
    }
  }

  return {
    settings,
    setSettings,
    ecdict,
    error,
    message,
    busy,
    ttsState,
    ttsMessage,
    tencentTestState,
    tencentTestMessage,
    load,
    update,
    save,
    ecdictAction,
    uploadEcdict,
    restore,
    testTts,
    testTencentTranslate,
  };
}
