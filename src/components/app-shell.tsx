"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { AudioLines, BarChart3, BookMarked, Home, MoreHorizontal, PlayCircle, PlusCircle, RefreshCw, Settings, Sparkles, X } from "lucide-react";
import { motion } from "framer-motion";
import { cn } from "@/lib/cn";
import { Logo } from "./logo";
import { BackgroundKeepalive } from "@/components/background-keepalive";
import { ToastContainer } from "./toast";
import { Kbd } from "./ui";

const navigation = [
  { label: "今日", href: "/", icon: Home, shortcut: "1" },
  { label: "复习", href: "/study", icon: PlayCircle, shortcut: "2" },
  { label: "单词本", href: "/words", icon: BookMarked, shortcut: "3" },
  { label: "音标", href: "/phonetics", icon: AudioLines, shortcut: "4" },
  { label: "添加", href: "/add", icon: PlusCircle, shortcut: "5" },
  { label: "初始化", href: "/initialize", icon: RefreshCw, shortcut: "6" },
  { label: "统计", href: "/statistics", icon: BarChart3, shortcut: "7" },
  { label: "设置", href: "/settings", icon: Settings, shortcut: "8" },
];

/** Mobile: primary tabs shown directly in the tab bar */
const mobilePrimary = ["/", "/study", "/words", "/add"];

function isActive(href: string, pathname: string) {
  return href === "/" ? pathname === "/" : pathname.startsWith(href);
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [moreOpen, setMoreOpen] = useState(false);
  const isStudyScreen = pathname.startsWith("/study") || pathname.startsWith("/match") || pathname.startsWith("/games") || pathname.startsWith("/phonetics");

  const primaryNav = navigation.filter((item) => mobilePrimary.includes(item.href));
  const secondaryNav = navigation.filter((item) => !mobilePrimary.includes(item.href));
  const secondaryActive = secondaryNav.some((item) => isActive(item.href, pathname));

  // 桌面端全局快捷键：Cmd/Ctrl + 1-8 快速切换主导航
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (
        e.target instanceof HTMLInputElement ||
        e.target instanceof HTMLTextAreaElement ||
        e.target instanceof HTMLSelectElement ||
        (e.target as HTMLElement)?.isContentEditable
      ) {
        return;
      }
      if ((e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey) {
        const num = parseInt(e.key, 10);
        if (num >= 1 && num <= navigation.length) {
          e.preventDefault();
          const target = navigation[num - 1];
          if (target && !isActive(target.href, pathname)) {
            router.push(target.href);
          }
        }
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [pathname, router]);

  return (
    <div className="min-h-screen bg-[#f2f2f7] text-[#1c1c1e] dark:bg-black dark:text-[#f5f5f7]">
      {/* 全局 Toast 消息容器 */}
      <ToastContainer />
      {/* 全局常驻后台保活：跨页面切换持续推进初始化队列 */}
      <BackgroundKeepalive />

      {/* Desktop Sidebar — Liquid Glass */}
      <aside className="liquid-glass liquid-glass-specular liquid-glass-edge fixed inset-y-0 left-0 z-30 hidden w-[256px] flex-col p-4.5 lg:flex">
        <Logo href="/" />

        <nav className="relative z-10 mt-6 flex-1 space-y-1">
          {navigation.map((item) => {
            const active = isActive(item.href, pathname);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={cn(
                  "group relative flex items-center justify-between rounded-[13px] px-3.5 py-2.5 text-[14.5px] font-medium transition-colors duration-150 focus-visible:outline-none",
                  active
                    ? "text-accent font-semibold dark:text-[#0a84ff]"
                    : "text-secondary-label hover:text-label dark:text-secondary-label dark:hover:text-[#f5f5f7]",
                )}
              >
                {active && (
                  <motion.div
                    layoutId="sidebar-active-pill"
                    className="absolute inset-0 rounded-[13px] bg-accent/10 shadow-[inset_0_1px_0_rgba(255,255,255,0.7),0_2px_8px_rgba(0,122,255,0.06)] dark:bg-accent/15 dark:shadow-[inset_0_1px_0_rgba(255,255,255,0.1),0_2px_8px_rgba(10,132,255,0.14)]"
                    transition={{ type: "spring", stiffness: 480, damping: 36 }}
                  />
                )}
                <span className="relative z-10 flex items-center gap-3">
                  <item.icon className={cn("size-4.5 transition-transform duration-200", active && "scale-105")} />
                  {item.label}
                </span>
                <span className="relative z-10 opacity-0 transition-opacity duration-150 group-hover:opacity-100">
                  <Kbd className="text-[9px] py-0 px-1 opacity-70">⌘{item.shortcut}</Kbd>
                </span>
              </Link>
            );
          })}
        </nav>

        {/* 侧边栏底部 mini 状态卡片 */}
        <div className="relative z-10 mt-auto space-y-2.5 pt-3">
          <div className="liquid-glass-subtle rounded-[14px] p-2.5 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="relative flex size-2">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-success opacity-75" />
                <span className="relative inline-flex size-2 rounded-full bg-success" />
              </span>
              <span className="text-[11.5px] font-medium text-secondary-label">自托管运行中</span>
            </div>
            <span className="inline-flex items-center gap-1 text-[10.5px] text-tertiary-label">
              <Sparkles className="size-3 text-accent" />
              FSRS
            </span>
          </div>
          <div className="flex items-center justify-between px-2 text-[11px] text-tertiary-label dark:text-[#545458]">
            <span>LexiLoop v1.0</span>
            <span>按 ⌘1-8 快捷切换</span>
          </div>
        </div>
      </aside>

      {/* Main Content with subtle page entrance transition */}
      <main className={cn("app-main lg:pb-8", isStudyScreen ? "pb-4" : "pb-[calc(6rem+env(safe-area-inset-bottom))]")}>
        <div className="mx-auto max-w-6xl px-4 py-4 sm:px-6 sm:py-6 lg:px-8 lg:py-7">
          <motion.div
            key={pathname}
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.2, ease: [0.16, 1, 0.3, 1] }}
          >
            {children}
          </motion.div>
        </div>
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
      {!isStudyScreen && (
        <nav className="fixed inset-x-3 bottom-[max(0.6rem,env(safe-area-inset-bottom))] z-30 lg:hidden" aria-label="主导航">
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
        </nav>
      )}
    </div>
  );
}

