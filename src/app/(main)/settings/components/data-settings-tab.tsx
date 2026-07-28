import { useRef } from "react";
import { Download, HardDrive, Loader2, Trash2, Upload } from "lucide-react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import { formatBytes, type EcdictStatus } from "../settings-shared";

export function DataSettingsTab({
  ecdict,
  busy,
  onEcdictAction,
  onUploadEcdict,
  onRestore,
}: {
  ecdict: EcdictStatus | null;
  busy: string;
  onEcdictAction: (action: "download" | "enable" | "disable" | "remove") => Promise<void>;
  onUploadEcdict: (file?: File) => Promise<void>;
  onRestore: (file?: File) => Promise<void>;
}) {
  const ecdictInput = useRef<HTMLInputElement>(null);
  const restoreInput = useRef<HTMLInputElement>(null);

  return (
    <div className="space-y-5">
      <Card>
        <CardHeader><CardTitle>备份与还原</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">将学习数据导出为 SQLite 或 JSON 格式进行备份。</p>
          <div className="flex flex-wrap gap-2">
            <BackupLink href="/api/backups/sqlite" icon={<HardDrive className="size-4" />} label="下载 SQLite 备份" />
            <BackupLink href="/api/backups/json" icon={<Download className="size-4" />} label="下载 JSON 备份" />
          </div>
          <hr className="border-black/[0.06] dark:border-white/[0.08]" />
          <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">从备份文件恢复。恢复操作将覆盖全部现有数据。</p>
          <FileAction inputRef={restoreInput} accept=".sqlite,.json" label="上传备份文件并恢复" onChange={(file) => void onRestore(file)} />
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>ECDICT 词典</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">ECDICT 提供大规模离线英汉词典数据，用词形、词源和真人发音补充在线来源。</p>
          {!ecdict ? <LoadingState /> : ecdict.installed
            ? <InstalledEcdict status={ecdict} busy={busy} onAction={onEcdictAction} />
            : <MissingEcdict busy={busy} inputRef={ecdictInput} onAction={onEcdictAction} onUpload={onUploadEcdict} />}
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

function LoadingState() {
  return <div className="flex items-center gap-2 text-sm text-[#aeaeb2]"><Loader2 className="size-4 animate-spin" />加载中...</div>;
}

function InstalledEcdict({ status, busy, onAction }: { status: EcdictStatus; busy: string; onAction: (action: "enable" | "disable" | "remove") => Promise<void> }) {
  return <div className="space-y-3"><div className="flex items-center gap-3"><Badge className="border-[#34c759]/30 text-[#34c759]" tone="green">{status.enabled ? "已启用" : "已禁用"}</Badge><span className="text-xs text-[#aeaeb2]">{formatBytes(status.fileSize)}</span></div><div className="flex flex-wrap gap-2">{status.enabled ? <Button variant="outline" size="sm" onClick={() => void onAction("disable")} disabled={busy === "disable"}>停用</Button> : <Button variant="outline" size="sm" onClick={() => void onAction("enable")} disabled={busy === "enable"}>启用</Button>}<Button variant="outline" size="sm" onClick={() => void onAction("remove")} disabled={busy === "remove"} className="text-[#ff3b30]">{busy === "remove" ? <Loader2 className="size-4 animate-spin" /> : <Trash2 className="size-4" />}移除</Button></div></div>;
}

function MissingEcdict({ busy, inputRef, onAction, onUpload }: { busy: string; inputRef: React.RefObject<HTMLInputElement | null>; onAction: (action: "download") => Promise<void>; onUpload: (file?: File) => Promise<void> }) {
  return <div className="space-y-3"><p className="text-xs text-[#aeaeb2]">尚未安装 ECDICT 词典（约 700MB）</p><div className="flex flex-wrap gap-2"><Button variant="outline" size="sm" onClick={() => void onAction("download")} disabled={busy === "download"}>{busy === "download" ? <Loader2 className="size-4 animate-spin" /> : <Download className="size-4" />}下载并启用</Button><FileAction inputRef={inputRef} accept=".sqlite,.mdb" label="上传自定义文件" onChange={(file) => void onUpload(file)} /></div></div>;
}
