"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { BarChart3, BookMarked, Home, Import, MoreHorizontal, PlayCircle, PlusCircle, RefreshCw, Settings, X } from "lucide-react";
import { cn } from "@/lib/cn";
import { Logo } from "./logo";
import { BackgroundKeepalive } from "@/components/background-keepalive";

const navigation = [
  { label: "今日", href: "/", icon: Home },
  { label: "复习", href: "/study", icon: PlayCircle },
  { label: "单词本", href: "/words", icon: BookMarked },
  { label: "添加", href: "/create", icon: PlusCircle },
  { label: "导入", href: "/import", icon: Import },
  { label: "初始化", href: "/initialize", icon: RefreshCw },
  { label: "统计", href: "/statistics", icon: BarChart3 },
  { label: "设置", href: "/settings", icon: Settings },
];

/** Mobile: primary tabs shown directly in the tab bar */
const mobilePrimary = ["/", "/study", "/words", "/create"];

function isActive(href: string, pathname: string) {
  return href === "/" ? pathname === "/" : pathname.startsWith(href);
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const [moreOpen, setMoreOpen] = useState(false);
  const isStudyScreen = pathname.startsWith("/study") || pathname.startsWith("/match") || pathname.startsWith("/games") || pathname.startsWith("/phonetics");

  const primaryNav = navigation.filter((item) => mobilePrimary.includes(item.href));
  const secondaryNav = navigation.filter((item) => !mobilePrimary.includes(item.href));
  const secondaryActive = secondaryNav.some((item) => isActive(item.href, pathname));

  return (
    <div className="min-h-screen bg-[#f2f2f7] text-[#1c1c1e] dark:bg-black dark:text-[#f5f5f7]">
      {/* 全局常驻后台保活：跨页面切换持续推进初始化队列 */}
      <BackgroundKeepalive />
      {/* Desktop Sidebar — Liquid Glass */}
      <aside className="liquid-glass liquid-glass-specular liquid-glass-edge fixed inset-y-0 left-0 z-30 hidden w-[264px] flex-col p-6 lg:flex">
        <Logo href="/" />

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
      <main className={cn("app-main lg:pb-8", isStudyScreen ? "pb-4" : "pb-[calc(6.5rem+env(safe-area-inset-bottom))]")}>
        <div className="mx-auto max-w-6xl px-4 py-4 sm:px-6 sm:py-6 lg:px-8 lg:py-8">{children}</div>
      </main>

      {/* Mobile More Sheet */}
      {moreOpen && (
        <div className="fixed inset-0 z-40 flex flex-col justify-end lg:hidden">
          <div className="absolute inset-0 bg-black/25 backdrop-blur-md" onClick={() => setMoreOpen(false)} />
          <div className="relative mx-4 mb-[calc(5rem+env(safe-area-inset-bottom))] max-h-[60vh] overflow-y-auto">
            <div className="liquid-glass-elevated liquid-glass-specular animate-scale-in rounded-[26px] p-4">
              <div className="mb-3 flex items-center justify-between px-1">
                <span className="text-sm font-semibold text-[#6e6e73] dark:text-[#98989d]">更多</span>
                <button className="ios-press grid size-7 place-items-center rounded-full bg-black/[0.06] text-[#6e6e73] dark:bg-white/[0.08] dark:text-[#98989d]" onClick={() => setMoreOpen(false)}>
                  <X className="size-3.5" />
                </button>
              </div>
              <div className="grid grid-cols-2 gap-2">
                {secondaryNav.map((item) => {
                  const active = isActive(item.href, pathname);
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      onClick={() => setMoreOpen(false)}
                      className={cn(
                        "ios-press flex items-center gap-3 rounded-[16px] px-4 py-3.5 text-[15px] font-medium transition-all",
                        active
                          ? "glass-inner text-[#007aff] dark:text-[#0a84ff]"
                          : "text-[#6e6e73] hover:bg-white/40 dark:text-[#98989d] dark:hover:bg-white/[0.06]",
                      )}
                    >
                      <item.icon className="size-5" />
                      {item.label}
                    </Link>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Mobile Tab Bar — Floating Liquid Glass Pill (5 primary + more) */}
      {!isStudyScreen && <nav className="fixed inset-x-3 bottom-[max(0.75rem,env(safe-area-inset-bottom))] z-30 lg:hidden" aria-label="主导航">
        <div className="liquid-glass liquid-glass-specular liquid-glass-edge relative mx-auto flex max-w-md items-center justify-around rounded-[22px] px-1.5 py-2 shadow-[0_16px_60px_rgba(0,0,0,0.14),0_4px_16px_rgba(0,0,0,0.08)]">
          {primaryNav.map((item) => {
            const active = isActive(item.href, pathname);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "ios-press relative z-10 flex min-w-0 flex-1 flex-col items-center gap-0.5 rounded-[12px] px-1 py-1.5 transition-all duration-200",
                  active ? "text-[#007aff] dark:text-[#0a84ff]" : "text-[#8e8e93] dark:text-[#636366]",
                )}
              >
                <item.icon className={cn("size-[22px] transition-all", active && "drop-shadow-[0_1px_4px_rgba(0,122,255,0.5)]")} />
                <span className={cn("text-[10px] leading-tight", active ? "font-bold" : "font-medium")}>{item.label}</span>
              </Link>
            );
          })}
          <button
            onClick={() => setMoreOpen((open) => !open)}
            aria-expanded={moreOpen}
            aria-label={moreOpen ? "收起更多导航" : "打开更多导航"}
            className={cn(
              "ios-press relative z-10 flex min-w-0 flex-1 flex-col items-center gap-0.5 rounded-[12px] px-1 py-1.5 transition-all duration-200",
              secondaryActive || moreOpen ? "text-[#007aff] dark:text-[#0a84ff]" : "text-[#8e8e93] dark:text-[#636366]",
            )}
          >
            {moreOpen ? <X className="size-[22px]" /> : <MoreHorizontal className={cn("size-[22px] transition-all", secondaryActive && "drop-shadow-[0_1px_4px_rgba(0,122,255,0.5)]")} />}
            <span className={cn("text-[10px] leading-tight", secondaryActive || moreOpen ? "font-bold" : "font-medium")}>{moreOpen ? "收起" : "更多"}</span>
          </button>
        </div>
      </nav>}
    </div>
  );
}
