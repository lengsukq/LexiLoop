import { useEffect, useRef, useState } from "react";
import {
  ArrowLeftRight,
  Check,
  Cloud,
  Copy,
  Database,
  Download,
  LoaderCircle,
  RefreshCw,
  Shield,
  Upload,
} from "lucide-react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Input, toast } from "@/components/ui";
import {
  APP_MODE_CHANGE_EVENT,
  clearLocalModeClient,
  setLocalModeClient,
  syncAppModeStorage,
  type AppMode,
} from "@/lib/app-mode";
import { apiFetch } from "@/lib/client-api";
import type { LocalCloudSyncResult } from "@/local/cloud-sync-client";

interface SyncPeerRecord {
  peerDeviceId: string;
  peerDeviceName: string;
  lastSyncedAt: number;
}

interface CloudSyncStatus {
  protocolVersion: number;
  passwordProtected: boolean;
  deviceId: string;
  datasetEpoch: string;
  wordCount: number;
  peers: SyncPeerRecord[];
}

function formatSyncTime(epochMs: number): string {
  if (!epochMs) return "尚未同步";
  const d = new Date(epochMs);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function DataSettingsTab({
  onRestore,
}: {
  onRestore: (file?: File) => Promise<void>;
}) {
  const restoreInput = useRef<HTMLInputElement>(null);
  const [appMode, setAppMode] = useState<AppMode>("cloud");
  const [switchingMode, setSwitchingMode] = useState(false);
  const [syncStatus, setSyncStatus] = useState<CloudSyncStatus | null>(null);
  const [origin, setOrigin] = useState("");
  const [copied, setCopied] = useState(false);

  // Local <-> Cloud sync controls (used in Browser Local Mode)
  const [remoteUrl, setRemoteUrl] = useState("");
  const [syncPassword, setSyncPassword] = useState("");
  const [syncing, setSyncing] = useState(false);
  const [syncReport, setSyncReport] = useState<LocalCloudSyncResult | null>(null);
  const [syncError, setSyncError] = useState("");
  const [downloadingBackup, setDownloadingBackup] = useState(false);

  useEffect(() => {
    const updateMode = () => {
      const detected = syncAppModeStorage();
      setAppMode(detected);
      return detected;
    };
    const timer = window.setTimeout(() => {
      updateMode();
      const currentOrigin = window.location.origin;
      setOrigin(currentOrigin);
      setRemoteUrl((prev) => prev || currentOrigin);
    }, 0);

    const onModeChange = () => {
      updateMode();
    };
    window.addEventListener(APP_MODE_CHANGE_EVENT, onModeChange);

    let active = true;
    void apiFetch<CloudSyncStatus>("/api/sync/status")
      .then((data) => {
        if (active) setSyncStatus(data);
      })
      .catch(() => {
        if (active) setSyncStatus(null);
      });

    return () => {
      active = false;
      window.clearTimeout(timer);
      window.removeEventListener(APP_MODE_CHANGE_EVENT, onModeChange);
    };
  }, []);

  async function switchMode(target: AppMode) {
    if (switchingMode) return;
    setSwitchingMode(true);
    try {
      if (target === "local") {
        setLocalModeClient();
        await fetch("/api/auth/local-mode", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ enabled: true }),
          cache: "no-store",
        }).catch(() => null);
        window.location.assign("/settings");
      } else {
        clearLocalModeClient();
        await fetch("/api/auth/local-mode", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ enabled: false }),
          cache: "no-store",
        }).catch(() => null);
        window.location.assign("/settings");
      }
    } catch {
      setSwitchingMode(false);
    }
  }

  async function copyOrigin() {
    if (!origin) return;
    try {
      await navigator.clipboard.writeText(origin);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1800);
    } catch {
      // Clipboard unavailable in insecure contexts.
    }
  }

  async function handleDownloadJsonBackup() {
    if (appMode === "cloud") {
      window.location.assign("/api/backups/json");
      return;
    }
    if (downloadingBackup) return;
    setDownloadingBackup(true);
    try {
      const payload = await apiFetch<Record<string, unknown>>("/api/backups/json");
      const jsonText = JSON.stringify(payload, null, 2);
      const blob = new Blob([jsonText], { type: "application/json; charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `lexiloop-local-${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
      toast.success("已从浏览器本地库导出 JSON 备份", "导出完成");
    } catch (reason) {
      toast.error(reason instanceof Error ? reason.message : "导出失败", "导出失败");
    } finally {
      setDownloadingBackup(false);
    }
  }

  async function handleLocalCloudSync() {
    if (syncing) return;
    setSyncing(true);
    setSyncError("");
    try {
      const { syncLocalWithCloud } = await import("@/local/cloud-sync-client");
      const result = await syncLocalWithCloud({
        serverUrl: remoteUrl || window.location.origin,
        password: syncPassword,
      });
      setSyncReport(result);
      const latestStatus = await apiFetch<CloudSyncStatus>("/api/sync/status").catch(() => null);
      if (latestStatus) setSyncStatus(latestStatus);
      toast.success(
        `本地 ${result.localWordCount} 词 · 云端 ${result.serverWordCount} 词`,
        "双向同步完成",
      );
    } catch (reason) {
      const msg = reason instanceof Error ? reason.message : "双向同步失败";
      setSyncError(msg);
      toast.error(msg, "同步失败");
    } finally {
      setSyncing(false);
    }
  }

  return (
    <div className="space-y-5">
      <Card>
        <CardHeader className="flex flex-row items-center justify-between gap-3">
          <CardTitle className="flex items-center gap-2">
            <Database className="size-4 text-accent" />
            数据库运行模式
          </CardTitle>
          <Badge tone={appMode === "local" ? "blue" : "green"}>
            {appMode === "local" ? "浏览器本地模式（免密）" : "云端数据库模式"}
          </Badge>
        </CardHeader>
        <CardContent className="space-y-4">
          {appMode === "local" ? (
            <p className="text-sm text-secondary-label">
              当前词库、学习进度与个人设置均直接保存在本机浏览器的 IndexedDB（PostgreSQL WASM）中，无需密码即可使用。注意：清除浏览器站点数据或使用隐私无痕模式会清空本地库，建议定期下载 JSON 备份或下方同步至云端。
            </p>
          ) : (
            <p className="text-sm text-secondary-label">
              当前正在读写服务器云端 PostgreSQL 数据库。你也可以切换为免密的浏览器本地模式，将数据独立保存在本机浏览器中使用。
            </p>
          )}
          <div className="flex flex-wrap items-center gap-2">
            <Button
              type="button"
              variant="outline"
              disabled={switchingMode}
              onClick={() => void switchMode(appMode === "local" ? "cloud" : "local")}
            >
              {switchingMode ? <LoaderCircle className="size-4 animate-spin" /> : <ArrowLeftRight className="size-4" />}
              {appMode === "local" ? "切换到云端数据库模式（登录）" : "切换到浏览器本地模式（免密）"}
            </Button>
          </div>
        </CardContent>
      </Card>

      {appMode === "local" ? (
        <Card>
          <CardHeader className="flex flex-row items-center justify-between gap-3">
            <CardTitle className="flex items-center gap-2">
              <Cloud className="size-4 text-accent" />
              与云端 / Flutter 双向同步
            </CardTitle>
            {syncStatus && (
              <Badge tone="slate">
                本地词条：{syncStatus.wordCount} 个
              </Badge>
            )}
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-secondary-label">
              可将当前浏览器 IndexedDB 中的学习记录、词库与个人词包，安全合并推送到云端服务器（并拉取云端或 Flutter 客户端的最新进度）。
            </p>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="space-y-1.5 text-xs font-medium text-secondary-label">
                <span>云端服务器地址</span>
                <Input
                  value={remoteUrl}
                  onChange={(event) => setRemoteUrl(event.target.value)}
                  placeholder="https://lexi.lengsu.top"
                />
              </label>
              <label className="space-y-1.5 text-xs font-medium text-secondary-label">
                <span>云端访问密码（如有启用密码保护）</span>
                <Input
                  type="password"
                  value={syncPassword}
                  onChange={(event) => setSyncPassword(event.target.value)}
                  placeholder="输入云端登录密码"
                />
              </label>
            </div>
            {syncError && (
              <p className="rounded-[12px] bg-danger/10 px-3 py-2 text-xs font-medium text-danger-deep dark:text-[#ff6961]">
                {syncError}
              </p>
            )}
            {syncReport && (
              <div className="rounded-[12px] border border-black/[0.06] bg-black/[0.02] px-3.5 py-2.5 text-xs text-secondary-label dark:border-white/[0.08] dark:bg-white/[0.03]">
                <div>拉取云端：+{syncReport.pulled.addedWords} 新增，{syncReport.pulled.updatedWords} 更新，+{syncReport.pulled.addedLogs} 学习记录</div>
                <div className="mt-1">推送云端：+{syncReport.pushed.addedWords} 新增，{syncReport.pushed.updatedWords} 更新，+{syncReport.pushed.addedLogs} 学习记录</div>
              </div>
            )}
            <Button type="button" onClick={() => void handleLocalCloudSync()} disabled={syncing}>
              {syncing ? <LoaderCircle className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}
              {syncing ? "正在双向同步…" : "立即与云端双向同步"}
            </Button>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader className="flex flex-row items-center justify-between gap-3">
            <CardTitle className="flex items-center gap-2">
              <Cloud className="size-4 text-accent" />
              与 Flutter 跨端云同步
            </CardTitle>
            {syncStatus && (
              <Badge tone={syncStatus.passwordProtected ? "green" : "amber"}>
                <Shield className="mr-1 size-3" />
                {syncStatus.passwordProtected ? "已启用密码保护" : "未设访问密码"}
              </Badge>
            )}
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-secondary-label">
              在 Flutter 应用「设置 → 数据管理 → Next.js 云端同步」中填入下方服务器地址与登录密码，即可与本站点进行双向增量互传（自动 GZip 压缩与分片，兼容 Vercel）。
            </p>
            <div className="flex flex-wrap items-center gap-2 rounded-[14px] border border-black/[0.06] bg-black/[0.02] px-3.5 py-2.5 dark:border-white/[0.08] dark:bg-white/[0.03]">
              <code className="flex-1 truncate text-xs text-label">{origin || "加载当前站点地址…"}</code>
              <Button type="button" variant="outline" size="sm" onClick={() => void copyOrigin()} disabled={!origin}>
                {copied ? <Check className="size-3.5" /> : <Copy className="size-3.5" />}
                {copied ? "已复制" : "复制地址"}
              </Button>
            </div>
            {syncStatus && (
              <div className="space-y-2 text-xs text-secondary-label">
                <div className="flex flex-wrap gap-x-4 gap-y-1">
                  <span>云端词条：{syncStatus.wordCount} 个</span>
                  <span>协议版本：v{syncStatus.protocolVersion}</span>
                  <span>已关联设备：{syncStatus.peers.length} 台</span>
                </div>
                {syncStatus.peers.length > 0 && (
                  <div className="divide-y divide-black/[0.05] rounded-[12px] border border-black/[0.06] dark:divide-white/[0.06] dark:border-white/[0.08]">
                    {syncStatus.peers.slice(0, 5).map((peer) => (
                      <div key={peer.peerDeviceId} className="flex items-center justify-between px-3 py-2">
                        <span className="font-medium text-label">{peer.peerDeviceName || peer.peerDeviceId}</span>
                        <span className="text-tertiary-label">上次同步：{formatSyncTime(peer.lastSyncedAt)}</span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader><CardTitle>备份与还原</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-secondary-label">
            将{appMode === "local" ? "浏览器本地" : "当前"}学习数据导出为 JSON 格式进行备份（兼容 Flutter 客户端与云端互导）。
          </p>
          <div className="flex flex-wrap gap-2">
            <Button
              type="button"
              variant="outline"
              onClick={() => void handleDownloadJsonBackup()}
              disabled={downloadingBackup}
            >
              {downloadingBackup ? <LoaderCircle className="size-4 animate-spin" /> : <Download className="size-4" />}
              下载 JSON 备份
            </Button>
          </div>
          <hr className="border-black/[0.06] dark:border-white/[0.08]" />
          <p className="text-sm text-secondary-label">
            从备份文件恢复到{appMode === "local" ? "浏览器本地数据库" : "当前数据库"}。恢复操作将覆盖全部现有数据并自动重算统计。
          </p>
          <FileAction inputRef={restoreInput} accept=".json" label="上传备份文件并恢复" onChange={(file) => void onRestore(file)} />
        </CardContent>
      </Card>
    </div>
  );
}

function FileAction({ inputRef, accept, label, onChange }: { inputRef: React.RefObject<HTMLInputElement | null>; accept: string; label: string; onChange: (file?: File) => void }) {
  return <label className="cursor-pointer"><span className="inline-flex cursor-pointer items-center gap-2 rounded-[14px] border border-white/50 bg-white/50 px-4 py-2 text-sm font-medium shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-xl transition hover:bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.05] dark:hover:bg-white/[0.08]" onClick={() => inputRef.current?.click()}><Upload className="size-4" />{label}</span><input ref={inputRef} type="file" accept={accept} className="hidden" onChange={(event) => onChange(event.target.files?.[0])} /></label>;
}
