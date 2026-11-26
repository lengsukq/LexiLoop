"use client";

import { Suspense, useCallback, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { PageHeader, Segmented } from "@/components/ui";
import { ManualTab } from "@/components/add/manual-tab";
import { CsvTab } from "@/components/add/csv-tab";
import ArticleTab from "@/components/add/article-tab";

import { motion, AnimatePresence } from "framer-motion";

type AddTab = "manual" | "csv" | "article";

function AddPageInner() {
  const searchParams = useSearchParams();
  const initial = (searchParams.get("tab") as AddTab | null) ?? "manual";
  const validInitial: AddTab = initial === "csv" || initial === "article" ? initial : "manual";
  const [active, setActive] = useState<AddTab>(validInitial);
  const [historyTick, setHistoryTick] = useState(0);

  useEffect(() => {
    const param = searchParams.get("tab") as AddTab | null;
    // eslint-disable-next-line react-hooks/set-state-in-effect -- sync URL tab param into local tab state
    if (param === "manual" || param === "csv" || param === "article") setActive(param);
  }, [searchParams]);

  const onImported = useCallback(() => setHistoryTick((n) => n + 1), []);

  return <div className="space-y-6">
    <PageHeader title="添加" description="手动输入 / CSV 批量 / 粘贴文章智能导词，预览后再写入词库。" />
    <Segmented<AddTab>
      options={[
        { value: "manual", label: "手动输入" },
        { value: "csv", label: "CSV 文件" },
        { value: "article", label: "粘贴文章 · AI" },
      ]}
      value={active}
      onChange={setActive}
      className="w-full sm:w-auto"
    />
    <AnimatePresence mode="wait">
      <motion.div
        key={active}
        initial={{ opacity: 0, y: 6 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -6 }}
        transition={{ duration: 0.18, ease: "easeOut" }}
      >
        {active === "manual" && <ManualTab />}
        {active === "csv" && <CsvTab key={`csv-${historyTick}`} onImported={onImported} />}
        {active === "article" && <ArticleTab key={`article-${historyTick}`} onImported={onImported} />}
      </motion.div>
    </AnimatePresence>
  </div>;
}

export default function AddPage() {
  return <Suspense fallback={<div className="space-y-6"><PageHeader title="添加" description="手动输入 / CSV 批量 / 粘贴文章智能导词，预览后再写入词库。" /></div>}>
    <AddPageInner />
  </Suspense>;
}
