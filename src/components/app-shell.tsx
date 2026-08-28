"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { BarChart3, BookMarked, Home, MoreHorizontal, PlayCircle, PlusCircle, RefreshCw, Settings, X } from "lucide-react";
import { cn } from "@/lib/cn";
import { Logo } from "./logo";
import { BackgroundKeepalive } from "@/components/background-keepalive";
import { ToastContainer } from "./toast";

const navigation = [
  { label: "今日", href: "/", icon: Home },
  { label: "复习", href: "/study", icon: PlayCircle },
  { label: "单词本", href: "/words", icon: BookMarked },
  { label: "添加", href: "/add", icon: PlusCircle },
  { label: "初始化", href: "/initialize", icon: RefreshCw },
  { label: "统计", href: "/statistics", icon: BarChart3 },
  { label: "设置", href: "/settings", icon: Settings },
];

/** Mobile: primary tabs shown directly in the tab bar */
const mobilePrimary = ["/", "/study", "/words", "/add"];

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
      {/* 全局 Toast 消息容器 */}
      <ToastContainer />
      {/* 全局常驻后台保活：跨页面切换持续推进初始化队列 */}
      <BackgroundKeepalive />
      {/* Desktop Sidebar — Liquid Glass */}
      <aside className="liquid-glass liquid-glass-specular liquid-glass-edge fixed inset-y-0 left-0 z-30 hidden w-[256px] flex-col p-5 lg:flex">
        <Logo href="/" />

        <nav className="relative z-10 mt-7 flex-1 space-y-1">
          {navigation.map((item) => {
            const active = isActive(item.href, pathname);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "ios-press flex items-center gap-3 rounded-[13px] px-3.5 py-2.5 text-[14.5px] font-medium transition-all duration-200",
                  active
                    ? "bg-accent/10 text-accent font-semibold shadow-[inset_0_1px_0_rgba(255,255,255,0.6)] dark:bg-accent/15 dark:text-[#0a84ff]"
                    : "text-secondary-label hover:bg-black/[0.04] hover:text-[#1c1c1e] dark:text-secondary-label dark:hover:bg-white/[0.06] dark:hover:text-[#f5f5f7]",
                )}
              >
                <item.icon className={cn("size-4.5 transition-transform duration-200", active && "scale-105")} />
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="relative z-10 px-3 text-xs text-tertiary-label dark:text-[#545458]">LexiLoop v1.0 · 自托管</div>
      </aside>

      {/* Main Content */}
      <main className={cn("app-main lg:pb-8", isStudyScreen ? "pb-4" : "pb-[calc(6rem+env(safe-area-inset-bottom))]")}>
        <div className="mx-auto max-w-6xl px-4 py-4 sm:px-6 sm:py-6 lg:px-8 lg:py-7">{children}</div>
      </main>

      {/* Mobile More Sheet */}
      {moreOpen && (
        <div className="fixed inset-0 z-40 flex flex-col justify-end lg:hidden">
          <div className="absolute inset-0 bg-black/20 backdrop-blur-sm transition-opacity duration-200" onClick={() => setMoreOpen(false)} />
          <div className="relative mx-3.5 mb-[calc(4.75rem+env(safe-area-inset-bottom))] max-h-[60vh] overflow-y-auto">
            <div className="liquid-glass-elevated liquid-glass-specular animate-scale-in rounded-[24px] p-4 shadow-[0_20px_50px_-12px_rgba(0,0,0,0.18)]">
              <div className="mb-3 flex items-center justify-between px-1">
                <span className="text-xs font-semibold text-secondary-label uppercase tracking-wider">更多导航</span>
                <button className="ios-press grid size-7 place-items-center rounded-full bg-black/[0.05] text-secondary-label dark:bg-white/[0.08] dark:text-secondary-label" onClick={() => setMoreOpen(false)}>
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
                        "ios-press flex items-center gap-2.5 rounded-[14px] px-3.5 py-3 text-[14px] font-medium transition-all",
                        active
                          ? "bg-accent/10 text-accent font-semibold dark:bg-accent/15"
                          : "text-secondary-label hover:bg-black/[0.04] dark:text-secondary-label dark:hover:bg-white/[0.06]",
                      )}
                    >
                      <item.icon className="size-4.5" />
                      {item.label}
                    </Link>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Mobile Tab Bar — Floating Liquid Glass Pill */}
      {!isStudyScreen && <nav className="fixed inset-x-3 bottom-[max(0.6rem,env(safe-area-inset-bottom))] z-30 lg:hidden" aria-label="主导航">
        <div className="liquid-glass liquid-glass-specular relative mx-auto flex max-w-md items-center justify-around rounded-[20px] px-1 py-1.5 shadow-[0_12px_32px_-4px_rgba(0,0,0,0.12),0_2px_8px_rgba(0,0,0,0.04)]">
          {primaryNav.map((item) => {
            const active = isActive(item.href, pathname);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "ios-press relative z-10 flex min-w-0 flex-1 flex-col items-center gap-0.5 rounded-[12px] px-1 py-1.5 transition-all duration-150",
                  active ? "text-accent" : "text-quaternary-label dark:text-[#636366]",
                )}
              >
                <item.icon className={cn("size-[20px] transition-transform duration-150", active && "scale-105")} />
                <span className={cn("text-[10px] leading-tight", active ? "font-semibold" : "font-medium")}>{item.label}</span>
              </Link>
            );
          })}
          <button
            onClick={() => setMoreOpen((open) => !open)}
            aria-expanded={moreOpen}
            aria-label={moreOpen ? "收起更多导航" : "打开更多导航"}
            className={cn(
              "ios-press relative z-10 flex min-w-0 flex-1 flex-col items-center gap-0.5 rounded-[12px] px-1 py-1.5 transition-all duration-150",
              secondaryActive || moreOpen ? "text-accent" : "text-quaternary-label dark:text-[#636366]",
            )}
          >
            {moreOpen ? <X className="size-[20px]" /> : <MoreHorizontal className={cn("size-[20px] transition-transform duration-150", secondaryActive && "scale-105")} />}
            <span className={cn("text-[10px] leading-tight", secondaryActive || moreOpen ? "font-semibold" : "font-medium")}>{moreOpen ? "收起" : "更多"}</span>
          </button>
        </div>
      </nav>}
    </div>
  );
}

