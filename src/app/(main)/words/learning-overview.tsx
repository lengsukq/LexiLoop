"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { ArrowRight, BookOpen } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { Card, CardContent, Progress } from "@/components/ui";

interface DashboardSummary {
  totalWords: number;
  masteredWords: number;
}

export function LearningOverview() {
  const [data, setData] = useState<DashboardSummary | null>(null);

  const load = useCallback(async () => {
    try {
      setData(await apiFetch<DashboardSummary>("/api/dashboard"));
    } catch {
      // The word list remains fully usable if the optional summary is unavailable.
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  if (!data || data.totalWords === 0) return null;

  const remainingWords = Math.max(0, data.totalWords - data.masteredWords);
  const masteryPercent = Math.round((data.masteredWords / data.totalWords) * 100);

  return (
    <Card className="animate-fade-up border-white/70 bg-white/60 shadow-[0_8px_28px_rgba(0,0,0,0.05),inset_0_1px_0_rgba(255,255,255,0.95)] dark:border-white/[0.1] dark:bg-white/[0.06]">
      <CardContent className="flex items-center gap-3.5 p-4 sm:gap-4 sm:px-5 sm:py-4">
        <span className="grid size-10 shrink-0 place-items-center rounded-[13px] bg-[#007aff]/10 text-[#007aff] dark:bg-[#0a84ff]/15 dark:text-[#0a84ff]">
          <BookOpen className="size-5" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline justify-between gap-3">
            <div className="min-w-0">
              <h2 className="truncate text-[15px] font-semibold">当前词条掌握程度</h2>
              <p className="mt-0.5 truncate text-xs text-[#8e8e93] dark:text-[#98989d]">已掌握 {data.masteredWords} / {data.totalWords} 个词条 · 还有 {remainingWords} 个待继续学习</p>
            </div>
            <span className="shrink-0 text-[22px] font-bold tracking-tight text-[#007aff] dark:text-[#0a84ff]">{masteryPercent}%</span>
          </div>
          <Progress value={data.masteredWords} max={data.totalWords} className="mt-2.5 h-2" />
        </div>
        <Link href="/statistics" className="ios-press hidden shrink-0 items-center gap-1 rounded-full px-2 py-1 text-[13px] font-semibold text-[#007aff] hover:bg-[#007aff]/10 dark:text-[#0a84ff] sm:inline-flex">
          详细统计 <ArrowRight className="size-3.5" />
        </Link>
      </CardContent>
    </Card>
  );
}
