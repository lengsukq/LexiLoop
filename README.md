# LexiLoop 词环

LexiLoop 是一个私人向、单用户、自托管的词汇复习应用。它导入 EasyDict Favorites CSV，只保存并初始化用户实际收藏的词条，不构建完整业务词典库。

## 技术栈

- **Next.js 16** App Router、**React 19**、TypeScript strict
- **Tailwind CSS 4**、Recharts、Lucide、framer-motion
- **PostgreSQL**（自 v1.0 起唯一业务数据库，已移除 SQLite 依赖）
- OpenAI-compatible / Anthropic 结构化 AI 初始化
- Edge TTS 免费发音 + 有道 TTS
- **ts-fsrs**（FSRS 间隔重复）
- Vitest、Playwright

## 主要功能

- **EasyDict CSV 导入**：服务端预览、表头/UTF-8/行数校验、文件内去重、三种重复导入策略（SKIP_EXISTING / FILL_MISSING / FORCE_DICTIONARY_REFRESH）与安全批量撤销
- **AI 词条初始化**：生成分词义释义、例句、搭配、词形、同根词、词根词缀、近反义词、易混词和学习提示，结果经 JSON Schema、Zod 业务校验、词条一致性检查与质量评分
- **有道词典集成**：详情页有道内容预览、一键应用（FILL_MISSING_FIELDS / FORCE_OVERWRITE），支持修改词条文本后重新初始化并自动归一化
- **编辑词条对话框**：直接在单词详情或列表修改词条，通过有道重新初始化新内容
- **词典数据源**：有道、DictionaryAPI.dev、MyMemory，可选用腾讯翻译与 Merriam-Webster；Edge TTS 独立负责免费发音
- **内置后台引擎**：任务锁、真实心跳、超时自动恢复、退避重试与失败重试；每日 AI 建议与周期维护随应用自动运行
- **FSRS 间隔重复**：稳定答案幂等、同题防重复、跨日错词强化、熟练度与掌握状态（NEW / LEARNING / FAMILIAR / PROFICIENT / MASTERED）
- **每日学习队列**：到期复习、错词、新词交错去重，专项听力/拼写/句子复习；24 小时会话恢复、稍后再学、过期会话自动释放
- **学习游戏**：单词拼建（WORD_BUILDER）、听力选择、释义速答、打地鼠、单词堆叠、单词俄罗斯方块，以及配对（Match）与音标（Phonetics）练习，成绩计入排行榜
- **学习统计**：按 7/30/90/365 天的趋势图、掌握度分布、连续学习天数；时长仅累计有效做题时间
- **JSON 备份导出**：一键下载完整 JSON 备份
- **单密码认证**：可选 `LEXILOOP_PASSWORD` 登录保护

## 快速开始（本地开发）

前置要求：Node.js ≥ 22、Yarn 1.22、一个可访问的 PostgreSQL 实例。

```bash
cp .env.example .env
corepack enable
yarn install --frozen-lockfile
# 在 .env 中配置 DATABASE_URL（PostgreSQL 连接串）
yarn db:migrate   # 应用数据库迁移
yarn dev
```

后台引擎（初始化 Worker、每日 AI 建议、周期维护）通过 Next.js `instrumentation` 随应用自动启动，无需单独进程，也无需配置。

质量检查：

```bash
yarn check   # typecheck + lint + test + build
```

## 数据库：PostgreSQL

- `DATABASE_URL` 为必需环境变量，应用以 PostgreSQL 模式运行。
- 迁移文件位于 `src/db/migrations/pg/`，由 `yarn db:migrate` 在独立事务内逐个应用，失败不会留下半成品 schema。
- 代码通过统一的异步 SQL 门面（`src/db/executor.ts`）访问数据库，`?` 占位符会自动改写为 `$n`。
- 测试自动从 `DATABASE_URL` 派生独立的 `<库名>_test` 数据库，避免触碰真实数据。

### 从旧版 SQLite 迁移

如果此前使用 SQLite 版本，可用一次性脚本迁移到 PostgreSQL（需本机安装 `sqlite3` CLI）：

```bash
npx tsx scripts/migrate-sqlite-to-pg.ts /path/to/backup.sqlite
```

脚本会清空目标库后按外键顺序批量导入全部表、修复孤立引用、重置自增序列并逐表校验行数。

## Vercel 部署（Serverless）

LexiLoop 的后台引擎默认以常驻进程（`instrumentation`）运行，适合自托管。Vercel 的 serverless 函数在请求结束后会被冻结，常驻循环无法持续，因此部署到 Vercel 时会自动切换到 **tick 驱动模式**：初始化任务由定时 Cron 与请求内按需触发推进，无需单独 Worker 进程。

### 环境变量

在 Vercel 项目 **Settings → Environment Variables** 中配置：

| 变量 | 说明 |
| --- | --- |
| `DATABASE_URL` | 公网可达的 PostgreSQL 连接串（如 Neon / Supabase 免费层），不能是 localhost |
| `LEXILOOP_PASSWORD` | 可选，登录密码 |
| `CRON_SECRET` | 可选，访问 `/api/background/tick` 的 Bearer 密钥（非 Vercel Cron 触发时要求） |
| `APP_TIMEZONE` | 可选，默认 `Asia/Shanghai` |

### 首次部署

首次部署后数据库 schema 可能为空。两种方式初始化：

1. 推荐：部署前在本地对线上库执行一次迁移：`DATABASE_URL=<线上连接串> yarn db:migrate`
2. 兜底：应用首次访问时 `src/db/client.ts` 会自动应用所有待执行迁移（表数量较少，通常可在一个请求内完成）

### 初始化任务的驱动方式

- **按需触发（主要）**：初始化状态接口 `/api/initialization/status` 在返回前会顺带处理一批任务；在「词条初始化」页面（每 3 秒轮询）即可实时推进队列。CSV 导入提交 `/api/imports/commit` 后也会立即触发一轮处理。
- **定时 Cron（兜底）**：`/api/background/tick` 按 `vercel.json` 中的计划执行。注意 Cron 频率受套餐限制：Hobby 计划每天最多触发 1 次，Pro 计划可到每分钟（本项目配置为每 10 分钟一次）。

单次 tick 默认最多处理 3 个任务，避免超出 serverless 函数执行时长限制；任务量大时可在「设置」中临时调低 `backgroundConcurrency`。

### 其他注意

- Edge TTS 发音通过 WebSocket 合成（最长 15 秒），TTS 相关接口已放宽函数超时到 60 秒（Hobby 计划上限）。
- 健康检查 `/api/health` 的 `backgroundEngine` 在 Vercel 上显示的是最近一次 tick 的心跳，不代表常驻 Worker 存在。

## 环境变量

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `DATABASE_URL` | PostgreSQL 连接串，必需 | — |
| `APP_TIMEZONE` | 应用时区 | `Asia/Shanghai` |
| `LEXILOOP_PASSWORD` | 登录密码；留空不启用认证 | — |

> 说明：词典数据源开关（DictionaryAPI.dev / MyMemory / 有道）、初始化并行数、AI 重试次数等均可在「设置」页面配置，不再提供环境变量；后台引擎始终随应用自动启动。代码中已不再使用 SQLite 相关环境变量（`DATABASE_PATH`、`ECDICT_DATABASE_PATH`、`ECDICT_ENABLED` 等）。

## 认证

在 `.env` 中设置 `LEXILOOP_PASSWORD` 后，进入 LexiLoop 需要输入密码（无需用户名），登录状态默认保留 7 天；`/api/health` 保留为公开健康检查入口。修改或移除密码后，重启应用进程使新的环境变量生效。

密码只在运行时注入，不会写入数据库。

## EasyDict CSV

必要列：

```csv
queryText,queryFromLanguage,queryToLanguage,timestamp
cotton,English,Simplified Chinese,2026-07-27T08:00:00Z
```

## AI 词条初始化

在「设置 → 大模型配置」中启用 **AI 词条初始化**，配置提供商、Base URL、API Key 和模型。支持 OpenAI-compatible 接口（可指向任意兼容 Base URL）与 Anthropic 两种 API 类型。

AI 只生成结构化学习内容，不生成音频 URL，实际发音继续由 Edge TTS 按需生成。AI 返回内容会经过严格 JSON Schema、Zod 业务校验、词条一致性检查和质量评分；模型、Token、提示词版本和质量分会记录在初始化历史中。词条输入放在 `<term_data>` 中并明确声明为不可信数据，避免词条文本被当作模型指令。

词条详情中的近义词、反义词、同根词和易混词可以点击查看说明和词库状态；未加入时可一键创建词条并进入初始化队列。初始化页面还可以批量补齐所有尚未经过 AI 的旧词条，或在确认 Token 风险后强制重新生成全部词条。强制刷新保留用户手动释义和用户例句，不会覆盖。

## 数据源说明

LexiLoop 不将有道完整词典 API 结果写入长期缓存，因为相关官方条款与本项目长期写入数据库、反复学习的需求冲突。默认使用允许该使用方式的公开数据源。有道仅在预览/应用时按需获取。

完整架构见 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。
