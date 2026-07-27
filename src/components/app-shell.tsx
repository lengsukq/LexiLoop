"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { BarChart3, BookMarked, BookOpen, Home, Import, PlusCircle, RefreshCw, Settings } from "lucide-react";
import { cn } from "@/lib/cn";

const navigation = [
  { label: "今日", href: "/", icon: Home },
  { label: "单词本", href: "/words", icon: BookMarked },
  { label: "添加", href: "/create", icon: PlusCircle },
  { label: "导入", href: "/import", icon: Import },
  { label: "初始化", href: "/initialize", icon: RefreshCw },
  { label: "统计", href: "/statistics", icon: BarChart3 },
  { label: "设置", href: "/settings", icon: Settings },
];

function isActive(href: string, pathname: string) {
  return href === "/" ? pathname === "/" : pathname.startsWith(href);
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  return (
    <div className="min-h-screen bg-[#f2f2f7] text-[#1c1c1e] dark:bg-black dark:text-[#f5f5f7]">
      {/* Desktop Sidebar — Liquid Glass */}
      <aside className="liquid-glass liquid-glass-specular liquid-glass-edge fixed inset-y-0 left-0 z-30 hidden w-[264px] flex-col p-6 lg:flex">
        <Link href="/" className="ios-press relative z-10 flex items-center gap-3.5 rounded-[18px] px-3 py-3">
          <span className="grid size-12 place-items-center rounded-[16px] bg-gradient-to-br from-[#0a84ff] to-[#5856d6] text-white shadow-[0_6px_20px_rgba(0,122,255,0.4),inset_0_1px_0_rgba(255,255,255,0.3)]">
            <BookOpen className="size-5" />
          </span>
          <div>
            <div className="text-[18px] font-bold tracking-tight">LexiLoop</div>
            <div className="text-[11px] font-medium text-[#8e8e93] dark:text-[#636366]">词环 · 循环记忆</div>
          </div>
        </Link>

        <nav className="relative z-10 mt-8 flex-1 space-y-1.5">
          {navigation.map((item) => {
            const active = isActive(item.href, pathname);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "ios-press flex items-center gap-3 rounded-[14px] px-4 py-3 text-[15px] font-medium transition-all duration-300",
                  active
                    ? "glass-inner text-[#007aff] shadow-[0_4px_20px_rgba(0,122,255,0.12),inset_0_1px_0_rgba(255,255,255,0.8)] dark:text-[#0a84ff]"
                    : "text-[#6e6e73] hover:bg-white/40 hover:text-[#1c1c1e] hover:shadow-[0_4px_16px_rgba(0,0,0,0.04)] hover:backdrop-blur-xl dark:text-[#98989d] dark:hover:bg-white/[0.06] dark:hover:text-[#f5f5f7]",
                )}
              >
                <item.icon className={cn("size-5 transition-all", active && "drop-shadow-[0_1px_3px_rgba(0,122,255,0.4)]")} />
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="relative z-10 px-3 text-xs text-[#aeaeb2] dark:text-[#48484a]">LexiLoop v1.0 · 自托管</div>
      </aside>

      {/* Main Content */}
      <main className="app-main pb-28 lg:pb-8">
        <div className="mx-auto max-w-6xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">{children}</div>
      </main>

      {/* Mobile Tab Bar — Floating Liquid Glass Pill */}
      <nav className="fixed inset-x-4 bottom-4 z-30 lg:hidden">
        <div className="liquid-glass liquid-glass-specular liquid-glass-edge relative mx-auto flex max-w-md items-center justify-around rounded-[26px] px-2 py-2.5 shadow-[0_16px_60px_rgba(0,0,0,0.14),0_4px_16px_rgba(0,0,0,0.08)]">
          {navigation.map((item) => {
            const active = isActive(item.href, pathname);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "ios-press relative z-10 flex flex-col items-center gap-0.5 rounded-[12px] px-2.5 py-1.5 transition-all duration-200",
                  active ? "text-[#007aff] dark:text-[#0a84ff]" : "text-[#8e8e93] dark:text-[#636366]",
                )}
              >
                <item.icon className={cn("size-[22px] transition-all", active && "drop-shadow-[0_1px_4px_rgba(0,122,255,0.5)]")} />
                <span className={cn("text-[10px] leading-tight", active ? "font-bold" : "font-medium")}>{item.label}</span>
              </Link>
            );
          })}
        </div>
      </nav>
    </div>
  );
}
