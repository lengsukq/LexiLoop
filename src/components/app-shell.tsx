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

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  return <div className="min-h-screen bg-slate-50 text-slate-900 dark:bg-slate-950 dark:text-slate-100">
    <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 border-r border-slate-200 bg-white p-4 lg:block dark:border-slate-800 dark:bg-slate-900">
      <Link href="/" className="flex items-center gap-3 px-3 py-3"><span className="grid size-10 place-items-center rounded-2xl bg-indigo-600 text-white"><BookOpen className="size-5" /></span><div><div className="font-bold">LexiLoop</div><div className="text-xs text-slate-400">词环 · 循环记忆</div></div></Link>
      <nav className="mt-5 space-y-1">{navigation.map((item) => { const active = item.href === "/" ? pathname === "/" : pathname.startsWith(item.href); return <Link key={item.href} href={item.href} className={cn("flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition", active ? "bg-indigo-50 text-indigo-700 dark:bg-indigo-950/60 dark:text-indigo-200" : "text-slate-500 hover:bg-slate-100 hover:text-slate-900 dark:hover:bg-slate-800 dark:hover:text-white")}><item.icon className="size-5" />{item.label}</Link>; })}</nav>
      <div className="absolute bottom-5 left-7 text-xs text-slate-400">LexiLoop v1.0.0 · 单用户自托管</div>
    </aside>
    <main className="pb-20 lg:ml-64 lg:pb-0"><div className="mx-auto max-w-7xl p-4 sm:p-6 lg:p-8">{children}</div></main>
    <nav className="fixed inset-x-0 bottom-0 z-30 grid grid-cols-7 border-t border-slate-200 bg-white/95 px-1 py-1 backdrop-blur lg:hidden dark:border-slate-800 dark:bg-slate-900/95">{navigation.map((item) => { const active = item.href === "/" ? pathname === "/" : pathname.startsWith(item.href); return <Link key={item.href} href={item.href} className={cn("flex flex-col items-center gap-1 rounded-lg py-2 text-[10px]", active ? "text-indigo-600" : "text-slate-400")}><item.icon className="size-5" />{item.label}</Link>; })}</nav>
  </div>;
}
