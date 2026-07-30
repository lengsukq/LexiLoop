import type { ButtonHTMLAttributes, HTMLAttributes, ReactNode } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/cn";

export function buttonClass(
  variant: "primary" | "secondary" | "outline" | "ghost" | "danger" = "primary",
  size: "sm" | "md" | "lg" = "md",
) {
  return cn(
    "inline-flex items-center justify-center gap-2 rounded-2xl font-semibold transition-all duration-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#007aff]/50 disabled:pointer-events-none disabled:opacity-40 ios-press",
    size === "sm" ? "h-9 px-3.5 text-[13px]" : size === "lg" ? "h-[54px] px-8 text-[17px]" : "h-11 px-5 text-[15px]",
    variant === "primary" && "bg-gradient-to-b from-[#0a84ff] to-[#007aff] text-white shadow-[0_4px_16px_rgba(0,122,255,0.35),inset_0_1px_0_rgba(255,255,255,0.2)] hover:shadow-[0_6px_24px_rgba(0,122,255,0.4)]",
    variant === "secondary" && "bg-[#007aff]/10 text-[#007aff] shadow-[inset_0_1px_0_rgba(255,255,255,0.5)] hover:bg-[#007aff]/15 dark:bg-[#0a84ff]/15 dark:text-[#0a84ff]",
    variant === "outline" && "border border-white/50 bg-white/50 text-[#1c1c1e] shadow-[0_4px_16px_rgba(0,0,0,0.05),inset_0_1px_0_rgba(255,255,255,0.8)] backdrop-blur-2xl hover:bg-white/70 hover:shadow-[0_8px_32px_rgba(0,0,0,0.08)] dark:border-white/[0.1] dark:bg-white/[0.06] dark:text-[#f5f5f7] dark:hover:bg-white/[0.1]",
    variant === "ghost" && "text-[#6e6e73] hover:bg-black/[0.04] dark:text-[#98989d] dark:hover:bg-white/[0.08]",
    variant === "danger" && "bg-gradient-to-b from-[#ff453a] to-[#ff3b30] text-white shadow-[0_4px_16px_rgba(255,59,48,0.35),inset_0_1px_0_rgba(255,255,255,0.2)] hover:shadow-[0_6px_24px_rgba(255,59,48,0.4)]",
  );
}

export function Button({ className, variant = "primary", size = "md", ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Parameters<typeof buttonClass>[0]; size?: Parameters<typeof buttonClass>[1] }) {
  return <button className={cn(buttonClass(variant, size), className)} {...props} />;
}

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "liquid-glass-elevated liquid-glass-specular overflow-hidden rounded-[20px] transition-all duration-300 sm:rounded-[22px]",
        className,
      )}
      {...props}
    />
  );
}

export function CardHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("relative z-10 px-4 pb-2 pt-4 sm:px-5 sm:pt-5", className)} {...props} />;
}

export function CardContent({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("relative z-10 px-4 pb-4 pt-2 sm:px-5 sm:pb-5", className)} {...props} />;
}

export function CardTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return <h2 className={cn("text-[17px] font-bold tracking-tight text-[#1c1c1e] dark:text-[#f5f5f7]", className)} {...props} />;
}

export function Badge({ children, tone = "slate", className }: { children: ReactNode; tone?: "slate" | "green" | "amber" | "red" | "blue" | "purple" | "glass"; className?: string }) {
  const tones: Record<string, string> = {
    slate: "bg-[#8e8e93]/12 text-[#6e6e73] dark:bg-[#98989d]/15 dark:text-[#98989d]",
    green: "bg-[#34c759]/12 text-[#248a3d] dark:bg-[#30d158]/15 dark:text-[#30d158]",
    amber: "bg-[#ff9500]/12 text-[#c93400] dark:bg-[#ff9f0a]/15 dark:text-[#ff9f0a]",
    red: "bg-[#ff3b30]/12 text-[#d70015] dark:bg-[#ff453a]/15 dark:text-[#ff453a]",
    blue: "bg-[#007aff]/12 text-[#0040dd] dark:bg-[#0a84ff]/15 dark:text-[#0a84ff]",
    purple: "bg-[#af52de]/12 text-[#8944ab] dark:bg-[#bf5af2]/15 dark:text-[#bf5af2]",
    glass: "border border-white/25 bg-white/[0.18] text-white shadow-[inset_0_1px_0_rgba(255,255,255,0.2)] backdrop-blur-md",
  };
  return <span className={cn("inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold", tones[tone], className)}>{children}</span>;
}

export function Progress({ value, max = 100, className }: { value: number; max?: number; className?: string }) {
  const percent = Math.max(0, Math.min(100, max ? (value / max) * 100 : 0));
  return (
    <div className={cn("h-[7px] overflow-hidden rounded-full bg-black/[0.06] shadow-[inset_0_1px_2px_rgba(0,0,0,0.06)] dark:bg-white/[0.08]", className)}>
      <div
        className="h-full rounded-full bg-gradient-to-r from-[#007aff] via-[#5ac8fa] to-[#007aff] shadow-[0_1px_4px_rgba(0,122,255,0.3)] transition-all duration-700 ease-out"
        style={{ width: `${percent}%` }}
      />
    </div>
  );
}

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={cn(
        "h-11 w-full rounded-[14px] border border-white/50 bg-white/50 px-4 text-[15px] shadow-[0_4px_16px_rgba(0,0,0,0.04),inset_0_1px_3px_rgba(0,0,0,0.03)] backdrop-blur-2xl outline-none transition-all duration-300 placeholder:text-[#aeaeb2] focus:border-[#007aff]/40 focus:shadow-[0_8px_32px_rgba(0,122,255,0.10),0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08] dark:bg-white/[0.06] dark:placeholder:text-[#636366] dark:focus:shadow-[0_8px_32px_rgba(10,132,255,0.12),0_0_0_4px_rgba(10,132,255,0.1)]",
        props.className,
      )}
    />
  );
}

export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={cn(
        "h-11 rounded-xl border border-white/50 bg-white/50 px-4 text-[15px] shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-2xl outline-none transition-all focus:border-[#007aff]/40 focus:shadow-[0_8px_32px_rgba(0,122,255,0.10)] dark:border-white/[0.08] dark:bg-white/[0.06]",
        props.className,
      )}
    />
  );
}

export function EmptyState({ icon, title, description, action }: { icon?: ReactNode; title: string; description: string; action?: ReactNode }) {
  return (
    <div className="liquid-glass-elevated animate-scale-in flex min-h-56 flex-col items-center justify-center rounded-[22px] p-6 text-center sm:min-h-64 sm:rounded-[28px] sm:p-10">
      {icon}
      <h2 className="mt-4 text-xl font-bold tracking-tight text-[#1c1c1e] dark:text-[#f5f5f7]">{title}</h2>
      <p className="mt-2 max-w-md text-[15px] leading-relaxed text-[#6e6e73] dark:text-[#98989d]">{description}</p>
      {action && <div className="mt-6">{action}</div>}
    </div>
  );
}

export function PageHeader({ title, description, action }: { title: string; description?: string; action?: ReactNode }) {
  return (
    <div className="animate-fade-down flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="text-[28px] font-bold tracking-tight text-[#1c1c1e] dark:text-[#f5f5f7]">{title}</h1>
        {description && <p className="mt-1 text-[15px] text-[#6e6e73] dark:text-[#98989d]">{description}</p>}
      </div>
      {action}
    </div>
  );
}

export function Dialog({ open, onClose, title, children, maxWidth = "max-w-lg", keepMounted = false }: { open: boolean; onClose: () => void; title: string; children: ReactNode; maxWidth?: string; keepMounted?: boolean }) {
  if (!open && !keepMounted) return null;
  return (
    <div className={`fixed inset-0 z-50 flex items-center justify-center p-4 ${open ? "" : "hidden"}`}>
      <div className="absolute inset-0 bg-black/25 backdrop-blur-md" onClick={onClose} />
      <div className={`liquid-glass-elevated liquid-glass-specular animate-scale-in relative z-10 max-h-[85vh] w-full ${maxWidth} overflow-y-auto rounded-[28px] p-6`}>
        <div className="mb-5 flex items-center justify-between">
          <h2 className="text-xl font-bold text-[#1c1c1e] dark:text-[#f5f5f7]">{title}</h2>
          <button onClick={onClose} className="ios-press grid size-8 place-items-center rounded-full bg-black/[0.06] text-[#6e6e73] dark:bg-white/[0.08] dark:text-[#98989d]">
            <svg className="size-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

function paginationRange(page: number, totalPages: number): (number | "...")[] {
  if (totalPages <= 7) return Array.from({ length: totalPages }, (_, i) => i + 1);
  const pages: (number | "...")[] = [1];
  const start = Math.max(2, page - 1);
  const end = Math.min(totalPages - 1, page + 1);
  if (start > 2) pages.push("...");
  for (let i = start; i <= end; i++) pages.push(i);
  if (end < totalPages - 1) pages.push("...");
  pages.push(totalPages);
  return pages;
}

export function Pagination({ page, totalPages, total, onChange, className, sticky = false }: {
  page: number; totalPages: number; total?: number; onChange: (page: number) => void; className?: string; sticky?: boolean;
}) {
  if (totalPages <= 1) return null;
  return (
    <div className={cn(
      sticky ? "flex-row items-center justify-between gap-2" : "flex-col items-center gap-3 sm:flex-row sm:justify-between",
      sticky && "liquid-glass liquid-glass-specular liquid-glass-edge sticky top-3 z-20 mx-auto w-full overflow-hidden rounded-[18px] bg-white/[0.9] px-2.5 py-2 shadow-[0_10px_28px_rgba(0,0,0,0.12),0_3px_12px_rgba(0,0,0,0.06)] backdrop-blur-2xl dark:bg-[#1c1c1e]/[0.9] sm:rounded-[20px] sm:px-4 sm:py-3",
      className,
    )}>
      {total !== undefined && <p className={cn("text-sm text-[#6e6e73] dark:text-[#98989d]", sticky && "whitespace-nowrap text-xs")}>共 {total} 条</p>}
      <nav className={cn("flex items-center gap-1.5", sticky && "gap-1 sm:gap-1.5")}>
        <button
          className={cn(sticky ? "ios-press grid size-9 place-items-center rounded-[11px]" : "ios-press grid size-10 place-items-center rounded-[12px]", "border border-white/50 bg-white/50 shadow-[0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-sm transition disabled:pointer-events-none disabled:opacity-35 dark:border-white/[0.08] dark:bg-white/[0.05]", sticky && "sm:size-10 sm:rounded-[12px]")}
          disabled={page <= 1}
          onClick={() => onChange(page - 1)}
          aria-label="上一页"
        ><ChevronLeft className="size-4" /></button>
        {paginationRange(page, totalPages).map((item, index) =>
          item === "..." ? (
            <span key={`ellipsis-${index}`} className="px-1 text-sm text-[#aeaeb2]">…</span>
          ) : (
            <button
              key={item}
              className={cn(
                sticky ? "ios-press size-9 rounded-[11px] text-[13px] font-medium transition-all duration-200 sm:size-10 sm:rounded-[12px] sm:text-sm" : "ios-press size-10 rounded-[12px] text-sm font-medium transition-all duration-200",
                item === page
                  ? "bg-gradient-to-b from-[#0a84ff] to-[#007aff] text-white shadow-[0_4px_14px_rgba(0,122,255,0.35),inset_0_1px_0_rgba(255,255,255,0.2)]"
                  : "border border-white/50 bg-white/50 text-[#6e6e73] shadow-[0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-sm hover:bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.05] dark:text-[#98989d] dark:hover:bg-white/[0.1]",
              )}
              onClick={() => onChange(item)}
            >{item}</button>
          ),
        )}
        <button
          className={cn(sticky ? "ios-press grid size-9 place-items-center rounded-[11px]" : "ios-press grid size-10 place-items-center rounded-[12px]", "border border-white/50 bg-white/50 shadow-[0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-sm transition disabled:pointer-events-none disabled:opacity-35 dark:border-white/[0.08] dark:bg-white/[0.05]", sticky && "sm:size-10 sm:rounded-[12px]")}
          disabled={page >= totalPages}
          onClick={() => onChange(page + 1)}
          aria-label="下一页"
        ><ChevronRight className="size-4" /></button>
      </nav>
    </div>
  );
}
