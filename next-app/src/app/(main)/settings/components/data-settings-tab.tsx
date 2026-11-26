import { useEffect, useRef, useState } from "react";
import { Check, Cloud, Copy, Download, Shield, Upload } from "lucide-react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { apiFetch } from "@/lib/client-api";

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
  const [syncStatus, setSyncStatus] = useState<CloudSyncStatus | null>(null);
  const [origin, setOrigin] = useState("");
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let active = true;
    void apiFetch<CloudSyncStatus>("/api/sync/status")
      .then((data) => {
        if (!active) return;
        setOrigin(window.location.origin);
        setSyncStatus(data);
      })
      .catch(() => {
        if (!active) return;
        setOrigin(window.location.origin);
        setSyncStatus(null);
      });
    return () => {
      active = false;
    };
  }, []);

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

  return (
    <div className="space-y-5">
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

      <Card>
        <CardHeader><CardTitle>备份与还原</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-secondary-label">将学习数据导出为 JSON 格式进行备份（兼容 Flutter 客户端导入）。</p>
          <div className="flex flex-wrap gap-2">
            <BackupLink href="/api/backups/json" icon={<Download className="size-4" />} label="下载 JSON 备份" />
          </div>
          <hr className="border-black/[0.06] dark:border-white/[0.08]" />
          <p className="text-sm text-secondary-label">从备份文件恢复。恢复操作将覆盖全部现有数据并自动重算统计。</p>
          <FileAction inputRef={restoreInput} accept=".json" label="上传备份文件并恢复" onChange={(file) => void onRestore(file)} />
        </CardContent>
      </Card>
    </div>
  );
}

function BackupLink({ href, icon, label }: { href: string; icon: React.ReactNode; label: string }) {
  return <a href={href} download className="inline-flex items-center gap-2 rounded-[14px] border border-white/50 bg-white/50 px-4 py-2 text-sm font-medium shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-xl transition hover:bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.05] dark:hover:bg-white/[0.08]">{icon}{label}</a>;
}

function FileAction({ inputRef, accept, label, onChange }: { inputRef: React.RefObject<HTMLInputElement | null>; accept: string; label: string; onChange: (file?: File) => void }) {
  return <label className="cursor-pointer"><span className="inline-flex cursor-pointer items-center gap-2 rounded-[14px] border border-white/50 bg-white/50 px-4 py-2 text-sm font-medium shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-xl transition hover:bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.05] dark:hover:bg-white/[0.08]" onClick={() => inputRef.current?.click()}><Upload className="size-4" />{label}</span><input ref={inputRef} type="file" accept={accept} className="hidden" onChange={(event) => onChange(event.target.files?.[0])} /></label>;
}
