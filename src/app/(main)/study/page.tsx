import { Suspense } from "react";
import { StudyClient } from "./study-client";
export default function StudyPage() { return <Suspense fallback={<div className="grid min-h-[70vh] place-items-center text-sm text-secondary-label">正在准备学习会话…</div>}><StudyClient /></Suspense>; }
