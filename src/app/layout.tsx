import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title: { default: "LexiLoop 词环", template: "%s · LexiLoop" }, description: "导入 EasyDict 收藏词汇，使用 FSRS、错词强化、听力和拼写进行循环复习。" };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="zh-CN"><body>{children}</body></html>; }
