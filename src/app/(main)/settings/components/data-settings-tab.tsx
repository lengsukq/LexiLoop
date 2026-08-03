import { useRef } from "react";
import { Download, Upload } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui";

export function DataSettingsTab({
  onRestore,
}: {
  onRestore: (file?: File) => Promise<void>;
}) {
  const restoreInput = useRef<HTMLInputElement>(null);

  return (
    <div className="space-y-5">
      <Card>
        <CardHeader><CardTitle>备份与还原</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">将学习数据导出为 JSON 格式进行备份。</p>
          <div className="flex flex-wrap gap-2">
            <BackupLink href="/api/backups/json" icon={<Download className="size-4" />} label="下载 JSON 备份" />
          </div>
          <hr className="border-black/[0.06] dark:border-white/[0.08]" />
          <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">从备份文件恢复。恢复操作将覆盖全部现有数据。</p>
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
