# LexiLoop Clean Code 代码审查报告

> 审查范围：业务逻辑层（src/modules、src/lib、src/db）、UI 与 API 层（src/components、src/app）、测试与工程配置（tests/、配置文件）。
> 审查日期：2026-08-16。以下发现按严重度（🔴 高 / 🟡 中 / 🟢 低）分类，每条含位置、问题与修复方向。

---

## 一、业务逻辑层（src/modules、src/lib、src/db）

### 过长的函数 / 职责过多

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🔴 | `initialization/worker.ts:181-275` | `processJob` 约 95 行上帝函数：任务分支、词条校验、模式分支、Provider 调用、落库、补任务排队、异常重试全在一个函数 | 拆为 `validate` / `processPattern` / `persist` 等单职责函数 |
| 🔴 | `translations/service.ts` | 整个文件函数全部压成单行，阅读成本极高；且 `translateMissingExamples`/`translateMissingSummary` 硬编码源语言 `"en"`，与 `translateMissingDefinitions` 的真实源语言不一致——疑似 bug | 拆分多行、统一源语言处理 |
| 🔴 | `study/view.ts:48-65` `getStudySession` | 会话查询、行映射、选项生成、resumeIndex 计算堆在单行 SQL + 单行 map | 拆分步骤 |
| 🔴 | `study/candidates.ts` | `scopeSql`/`availabilitySql`/`newCandidates`/`selectCandidates` 单行超长；`selectCandidates` 一个 return 含 4 个模式分支 + 2 组权值表 | 拆分模式函数、提取权值常量 |
| 🟡 | `study/service.ts:39-56` `startStudySession` | 多分支与持久化逻辑挤在一起 | 提取 resume/scope/推荐分支 |
| 🟡 | `manual/service.ts:111-178` `confirmManualPreview` | 认领、建词、内容合并、落库、禁用任务、回写预览 7 个职责 | 拆函数 |
| 🟡 | `dictionary/pipeline.ts:115-172` / `dictionary/selection.ts:119-177` | 长 if 链 + 嵌套三元 | 表驱动 / 提前返回 |

### 魔法数字 / 魔法字符串

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🔴 | `suggestions/candidates.ts:66-85` `score()` | 一个表达式中 13 个裸权重（120/75/38/55/…/5），无法调优 | 参照 `reviews/mastery.ts` 命名常量写法 |
| 🔴 | `suggestions/metrics.ts:74-83` | 裸公式 `1.5/0.7/55/70/…/0.14`，无注释无常量 | 命名常量 |
| 🔴 | `games/completion.ts:6-8`、`matching/service.ts:95-111`、`phonetics/service.ts:44-56` | 三套游戏/匹配计分各一套裸权重 | 统一命名常量 |
| 🟡 | `study/candidates.ts:47-51,93,98,129,190` | 排序权重、`0.999999`、`0.001`、`1.25`、题型配比裸数 | 常量 |
| 🟡 | `suggestions/content.ts:62-115` | 阈值 75/80/90/15/0.25/60/85 裸数 | 常量 |
| 🟡 | `words/queries.ts:25` | `dueAt` 兜底 `9223372036854775807` int64 上限裸数 | 常量 |
| 🟡 | `words/related.ts:85`、`imports/commit.ts:47` 等 | `max_attempts 5`、优先级 `10/60/30/80/90/20` 硬编码 | 常量 |
| 🟡 | `anthropic-version "2023-06-01"` 散布 5+ 处、`"PARALLEL_MERGE"`、`"ai:%"`、`"；"` 分隔符 | 字面量重复 | 常量 |
| 🟢 | `practice/sessions.ts:118`、`phonetics/selection.ts:83,99,58`、`api.ts:23` | 小阈值/上限 | 常量或注释 |

### 重复逻辑（本仓库最严重类别）

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🔴 | `initialization/worker.ts:98-133`、`words/youdao-refresh.ts:87-121`、`words/mutations.ts:61-68`、`manual/storage.ts:11-25` | `word_contents` 全字段 upsert 4+ 份复制，改字段要改 4 处 | 抽 `saveWordContent()` 单一落库助手 |
| 🔴 | `suggestions/ai.ts:106-159`、`ai-tasks/supplemental.ts:37-48`、`translations/provider.ts:14-23`、`dictionary/providers/ai-lexical-transport.ts:12-53` | LLM 请求层重复 4+ 处；默认参数已漂移（max_tokens 300 vs 2000、temperature 0.7 vs 0.2、timeout 30s vs 180s） | 统一到 `modules/llm/` 单客户端 |
| 🔴 | `reviews/answer-evaluation.ts:26-30`、`suggestions/candidates.ts:86-91`、`practice/candidates.ts:13-27`、`study/view.ts:67-80`、`words/queries.ts:58` | 「取目标语言释义文本」重复 5 处 | 收敛到 `dictionary/content.ts` |
| 🔴 | `study/candidates.ts:27-40` vs `suggestions/candidates.ts:12-16` | 「定义可用」SQL 完全一致复制 | 合并为一个 SQL 构造模块 |
| 🔴 | `study/candidates.ts:41`、`study/service.ts:30`、`study/adaptive.ts:20-22`、`statistics/service.ts:22-23` 等 6+ 文件 | 会话排除字面量 `'MATCH_GAME'/'GAME_%'/'SESSION_EXPIRED'/'PROGRESS_RESET'` | 抽常量 |
| 🔴 | `study/service.ts:10-21` vs `background/maintenance.ts:86-105`；`imports/commit.ts:18-28`、`words/mutations.ts:8-20` | `expireStaleSessions`/取消 pending 逻辑多份 | 合并统一 |
| 🟡 | `initialization/queue.ts:40-93`、`imports/commit.ts:37-49`、`words/related.ts:75-90` | 初始化任务入队三次重实现，后两者硬编码 `max_attempts 5` | 统一 `enqueueJob` |
| 🟡 | `db/executor.ts:106-116` vs `scripts/migrate-sqlite-to-pg.ts:67-77` | `normalizePgUrl` 重复 | 复用 |
| 🟡 | `initialization/worker.ts:35-40` vs `words/youdao-refresh.ts:43-48` | `preserveUserContent` 一模一样 | 复用 |
| 🟡 | `study/view.ts:82-88` vs `lib/array.ts` | `shuffle` 自写第二遍 | 引用公共实现 |
| 🟡 | `imports/commit.ts:13-16` vs `initialization/queue.ts:23-30` | `strongerMode` 重复 | 复用 |
| 🟡 | `reviews/repository.ts:189-222 / 237-288 / 438-479 / 481-506` | `insertReviewLog+saveReviewCard` 与 finalize 两类 SQL 内部重复 | 合并 SQL 构造 |
| 🟡 | mymemory/dictionary-api/tencent-translate/ai-lexical | Provider 错误归一化（timeout + NETWORK_ERROR + String(error)）重复 | 提取公共 helper |
| 🟢 | `dictionary/pipeline.ts:143-159` vs `manual/service.ts:57-71` | Provider 顺序兜底在两层级各写一份 | manual 复用 pipeline |

### 糟糕的命名

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🟡 | `db/executor.ts:203-205` | `wrapper.immediate/deferred/exclusive` 三个名字全部指向同一 `run`，语义撒谎（事务隔离未实现） | 改名或明确文档化 |
| 🟡 | `db/client.ts:19` | 导出名 `sqlite` 实际只在 Postgres 模式运行 | 改名或补注释 |
| 🟡 | `dictionary/pipeline.ts:120,170` | `requiredProviderFailure` 永远返回 `null`，却是死分支 | 删除或真正实现 |
| 🟢 | `background/tick.ts:143` | `processed: totalClaimed` 命名误导且 `updateHeartbeat` 未 await | 改名 + await |
| 🟢 | `study/candidates.ts:8-11` | 单行声明多类型、SQL 别名 `x/c/w` 无注释 | 展开 + 注释 |

### 空 catch / 错误处理不一致

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🟡 | `games/completion.ts:23`、`matching/service.ts:149-150`、`phonetics/service.ts:86-87` | `error.message === "PRACTICE_SESSION_NOT_FOUND"` 字符串判错 | 统一错误类/常量 |
| 🟡 | `ai-tasks/supplemental.ts:44`、`translations/provider.ts:17,21`、`lib/tencent-translate-client.ts:125`、`app/api/settings/models/route.ts:47` | fetch 后 JSON.parse 空 catch 靠后续兜底 | 显式判空 |
| 🟢 | 大量 defensive JSON.parse 静默 `catch { return [] }` | 脏数据被静默吞掉 | 关键路径记录告警 |
| 🟢 | `background/tick.ts:122-127,134` | `updateHeartbeat` fire-and-forget，有 unhandled rejection | await + catch |
| 🟢 | `reviews/repository.ts:415-421` | `loadReviewStatistics` 名为 load 却在内部写库 | getter 去副作用 |

### 深层嵌套 / 提前返回

- 🟡 `suggestions/service.ts:27-40`：`for [1,2]` + try/catch + 条件 break 缠绕，用两次顺序尝试清晰得多
- 🟡 `initialization/queue.ts:40-93`：`taskType === "INITIALIZE"` 三元在 4 处重复求值，按任务类型拆两个分支函数
- 🟡 `dictionary/selection.ts:136-176`：`if/else if` 长链 + summary/learning/sentenceAnalysis 三分支结构相同（表驱动）
- 🟡 `words/youdao-refresh.ts:62-73` / `options.ts:24,43,59`：throw 三连 / 嵌套三元
- 🟢 `statistics/service.ts:54-56`、`words/queries.ts:29`、`initialization/queries.ts:60`：`"1 = 1"` 占位条件

### 副作用隐晦 / 纯函数混用

- 🟡 `db/executor.ts:153-158,182-201`：Postgres 事务用进程级 AsyncLocalStorage + 共享 ready promise，行为正确但极隐晦
- 🟡 `reviews/repository.ts:421`：读函数内写库
- 🟡 `study/view.ts:14-46`：模块级可变 `distractorPool` 全局缓存跨请求共享，并发测试不友好
- 🟢 `suggestions/service.ts:74`：对共享缓存对象就地写入
- 🟢 `tts/service.ts:90-157`：成功路径残留 15s 定时器不 clearTimeout
- 🟢 `initialization/configured.ts:37-40`：`candidates()` 被调用两次（重复全表扫描）

### 死代码 / 未使用 / 可疑默认

- 🟡 `dictionary/pipeline.ts:120,170` + `manual/service.ts:49-54`：恒 null 字段 + 新写的死分支
- 🟡 `lib/config.ts:4-22 DEFAULT_LLM_CONFIG`：内置联网默认 Provider（"opencode-zen" + public apiKey），若刻意需注释说明
- 🟢 `llm/service.ts`：纯类型 re-export（多层 `service.ts` 转发表可接受）

### SQL / 事务 / 资源

- 🟡 动态 SQL 拼接（白名单内）：`words/mutations.ts:30-38`、`imports/commit.ts:93`、`words/related.ts:108`、`translations/service.ts:8`、`words/queries.ts:20-26`——建议统一白名单断言
- 🟡 事务模式不一致：绝大多数用 `.immediate()`，但 `settings/service.ts:112-114` 与 `initialization/bulk.ts:24-31` 用默认 deferred
- 🟡 `reviews/repository.ts:446,456-460`：`hasPending` 子查询字符串插值嵌 UPDATE
- 🟢 `reviews/fsrs.ts:4`：全局 `fsrsInstances` Map 无上限（实际受 0.7–0.99 约束，风险低）
- 🟢 `statistics/getStatistics:65-126`：整段三天日志拉进内存聚合

---

## 二、UI 与 API 层（src/components、src/app）

### 过大组件 / 巨型 JSX

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🔴 | `study-client.tsx`（497 行） | 20 个 useState/useRef/useEffect、5 种题型、4 整屏分支；ZH_TO_EN_CHOICE 与 EN_TO_ZH_CHOICE 两份几乎相同 JSX；操作栏 4 层嵌套三元 | 拆 `ChoiceQuestion`/`SpellingQuestion`/`ListenQuestion` + `QuestionActionBar` + `CompletionCard` |
| 🔴 | `initialize/page.tsx`（596 行） | 移动卡片视图（379-413）与桌面表格视图（434-494）各渲染一遍；任务子列表写两遍；详情 Dialog 90 行内联 | 抽 `WordRow` + `InitializationJobDetail` |
| 🔴 | `games/page.tsx`（543 行） | 游戏状态机 + 6 模式渲染 + WORD_BUILDER 拖拽逻辑全在一个组件；setup hero 与 match/phonetics 重复 | 抽 `WordBuilder` 等子组件 |
| 🟡 | `use-word-detail.ts`（343 行） | 一个 hook 返回约 40 字段，混 6 个领域 | 按领域拆小 hook |

### 重复 JSX / 样式 / 模式

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🔴 | `games/page.tsx:541-543`、`phonetic-question.tsx:102-122`、`study-client.tsx:330-368` | 三份「选项网格」独立实现（选错红色高亮+禁用+图标） | 抽公共 `ChoiceGrid` |
| 🔴 | 9 处 `setTimeout(() => void load(), 0)` | load-on-mount 模式重复 | 抽 `useInitialLoad` |
| 🔴 | `use-word-detail.ts:15`、`use-settings-data.ts:12` + 约 20 处内联 | `reason instanceof Error ? reason.message : fallback` 重复 | 收进 `lib/client-api.ts` |
| 🟡 | `word-header.tsx:136`、`edit-word-dialog.tsx:146`、`study-client.tsx:59`、`import/page.tsx:89` | `entryTypeLabel` 定义 4 份 | 公共模块 |
| 🟡 | `initialize/page.tsx:344-349`、`words/page.tsx:39`、`status-badges.tsx:4-9` 等 | 状态标签 map 重复 3 处 | 公共模块 |
| 🟡 | `youdao-preview-dialog.tsx:297-304` vs `edit-word-dialog.tsx:489-496` | 应用模式 radio 逐字重复 | 抽组件 |
| 🟡 | `study-settings-tab.tsx:125-142` | word/phrase/sentence 三个 Select 只有 key 不同 | 抽 `SpeedSelect` |

### hooks 使用不当

- 🟡 `whack-a-mole.tsx:44-60`、`word-tetris.tsx:83-87`：空依赖 + eslint-disable 的 effect（靠父级 key 换实例掩盖 stale closure）
- 🟢 `games/page.tsx:349-352`：无依赖 effect 每次渲染跑，直接渲染期赋值 `dragMoveRef.current = handleDragMove`
- 🟢 `study-client.tsx:182-195`：自动播放 effect 依赖表达不精确（靠 playbackKey 防重，可接受）

### props 传递地狱 / 状态提升不当

- 🔴 设置页：`settings/page.tsx:44-59` 传 13 + 8 个回调 props；`useLlmSettings` + `useSettingsData` 页面粘合——建议 Provider/reducer 收敛
- 🔴 词条详情页：`page.tsx:39-52` 传 11 + 6 + 7 个 props（配合 40 字段 hook）——按领域拆 hook 后用 context

### API route 重复 / 响应不一致

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🔴 | `api/initialization/[id]/route.ts:12-14` | 裸 `new Response("Invalid job ID")` / `new Response("Job not found")`，不走 ok/fail 信封；`Number.isFinite` 放过 `1.5` —— 唯一破坏协议的路由 | `fail("JOB_ID_INVALID")` / `fail("JOB_NOT_FOUND",...,404)` + `Number.isInteger` |
| 🔴 | 约 15 个 route | `error.message === "WORD_NOT_FOUND"` 等字符串判错；study/answer 内联错误码→文案映射表 | `ApiError { code, status }` + `handleRouteError` 包装器（沿用 imports/[id]/rollback 与 manual 的带 code 错误类范式） |
| 🔴 | games/match/phonetics 的 `sessions/[id]/complete` 三路由 | zod schema、id 解析、catch 链几乎逐字重复 | `createCompleteHandler({schema, service, notFoundCode})` 工厂 |
| 🔴 | words/[id]/mnemonic、summary-translation、initialize（及 example-translations） | queueAiTask 三胞胎 | 抽出公共 `handleQueueAiTask` |
| 🟡 | `/api/tts/route.ts` vs `/api/tts/youdao/route.ts` | 几乎逐字节重复 | 抽 `handleTtsGet` |
| 🟡 | settings/models 与 settings/test-provider | `normalizeBaseUrl` + 15 秒超时重复；TIMEOUT 文案不一致 | 公共 helper |
| 🟡 | id 解析样板重复约 10 处 | `Number(id)` + 校验 | `parseRouteId(params)` |

- 🟢 `health/route.ts`：路由里直接操作 sqlite + 硬编码 `version: "1.0.0"`（与 app-shell 的 "LexiLoop v1.0" 重复）
- 🟢 `backups/json/route.ts:6`：下载场景裸 Response 与错误路径信封双轨（可接受但需注释）

### 魔法数字（UI）

- 🟡 动画/反馈延迟十余处：games 260/220（三份）/420/440/350、match 280/460、study 650/500/220、whack-a-mole 150/130/320/430/400、word-stack 400/620 及内联 "11s"/"14s"——集中为 `ANIMATION_MS` 常量
- 🟡 超时/轮询：`ai-task-client.ts:10,19` 90_000/800、15 秒、8 秒、`game-hud.tsx:8` 10_000；initialize 页注释写死「3 秒/60 秒」与 keepalive 常量重复
- 🟡 分页/限制：words `limit: "40"`（服务端默认 50、configurator 20）、initialize `PAGE_SIZE=50` 局部常量、statistics `slice(0,30)`、import `slice(0,200)`/`limit:20`、CSV 文案写死 "10MB/20,000 行" 而常量在 lib/config.ts

### 命名 / 死代码 / 假 UI

- 🟢 `initialize/page.tsx:96-100 formatTs`：`typeof ts === "number" ? new Date(ts) : new Date(ts)` 两个分支完全相同（死分支）
- 🟢 `games/page.tsx:243-245 markMistake`：逐字直通包装（可删）
- 🟢 `import/page.tsx:237 Progress value={75}`：假进度，误导性 UI
- 🟢 `use-phonetic-game.ts:24-26 expectedChoice` 与 `phonetic-question.tsx:18-20 correctChoice` 同一映射写两份

### 耦合 / 客户端做了服务端逻辑

- 🟡 `study-client.tsx:271-285`：rate() 成功后在客户端手工递增 completed/correct/wrong 并改写 item 状态（服务端逻辑复制到客户端）——建议 `/api/study/answer` 返回增量
- 🟡 `study-client.tsx:12-17 clientId()`：手写 UUID 替换模板，直接用 `crypto.randomUUID()`
- 🟡 `tts-client.ts:28-33 ensureSpeedConfig`：raw fetch 不走 apiFetch，与 use-settings-data 双数据源
- 🟢 `learning-overview.tsx:81-90`：为两个数字整体重拉 `/api/dashboard`
- 🟢 `login-form.tsx:22-28`：手写 fetch + 手写信封解析，绕过 apiFetch 的 401 重定向

### 错误三态一致性

- 🟡 重试按钮时有时无（首页有/initialize 无/study 有/words 无）；Loader2 尺寸文案约 10 处各写一遍——抽 `PageLoader`/`ErrorBanner`
- 🟡 `words/page.tsx:52-55`：加载失败时 data 不清空，错误横幅叠加在过期列表之上

---

## 三、测试与工程配置（tests/ 与配置文件）

### 高严重度

| 严重度 | 位置 | 问题 | 修复方向 |
| --- | --- | --- | --- |
| 🔴 | `tests/setup.ts:54-64` | 全局 beforeEach 对每个测试文件（含纯逻辑的 mastery/import-parser/tts-client/auth）都连库 + 18 表 DELETE；`db/client.ts:8` 无 DATABASE_URL 时 throw，纯单测在无库环境全挂 | 单测解耦 PG；DB 测试惰性初始化 |
| 🔴 | 14 个测试文件 | `INSERT INTO words` + `word_contents`（10 个 JSON 列）逐字复制；`html()` 复制 3 份；`insertDueCard` 复制 2 份 | 抽 `tests/helpers/db-factories.ts` |
| 🔴 | `tests/setup.ts:8-19` vs `scripts/load-local-env.ts:9-19` | .env 解析逻辑逐行相同；`_test` 库派生正则两份 + 硬编码 `neondb_test` | 抽 `tests/helpers/test-env.ts` 共用 |
| 🔴 | `tests/setup.ts:57-63` | 声称「不发起真实 HTTP 请求」但 `DEFAULT_SETTINGS.youdaoEnabled = true`，未 stub fetch 时真实打到有道官网 | setup 默认关闭 youdao/merriamWebster/tencent + afterEach `vi.unstubAllGlobals()` |

### 中严重度

- 🟡 弱断言/死断言：`business-closure.test.ts:141 toBeTruthy`、`sentence-crawl.test.ts:87 not.toBe("FAILED")`（应 toBe("READY")）、`settings.test.ts:13` 未校验错误信息与值保持、`tts-client.test.ts:64 toBeLessThanOrEqual(2)`（应恰好 2）、`study-prioritization.test.ts:126-129` 统计断言魔法数
- 🟡 `multi-meaning-review.test.ts:45-89`：一个 it 塞 4 个场景，应 `it.each`
- 🟡 `youdao-provider.test.ts:102`：测试名 "only supports English word entries" 与断言矛盾
- 🟡 测试数据魔法值：`business-closure.test.ts:204` 的 `999999`、review_cards FSRS 魔法值 `1,5,1,1,1,0,2,0`、`statistics-duration.test.ts:30` 的 `8*60*60*1000`
- 🟡 `vitest.config.ts:13`：coverage 死配置（无 provider 依赖）；`package.json:49` next 在 devDependencies；`.gitignore:13-22` 过期 SQLite 条目；`.env.example` 缺 `TEST_DATABASE_URL`/`PLAYWRIGHT_BASE_URL`/`CRON_SECRET`
- 🟡 `vitest.config.ts:10` `fileParallelism: false` 全部串行 + 每文件重建连接/迁移/清表，`testTimeout/hookTimeout` 偏高

### 低严重度

- 🟢 E2E 无认证处理（`tests/e2e/smoke.spec.ts:3`、`mobile.spec.ts`），设置密码后全挂
- 🟢 5 个零引用依赖：`framer-motion`、`date-fns`、`@testing-library/react`、`@testing-library/jest-dom`、`jsdom`
- 🟢 `business-closure.test.ts:220-238` 手写 fetch 保存/恢复 vs 其余统一 `vi.stubGlobal`
- 🟢 `manual-preview.test.ts:52-54` afterEach 与全局重复
- 🟢 `scripts/migrate-sqlite-to-pg.ts` 无脚本入口（一次性脚本建议挪 legacy/）
- 🟢 `next.config.ts:11-13` turbopack root 只对 dev 生效，build 强制 --webpack
- 🟢 `next-env.d.ts` 引用 `.next/types/routes.d.ts`（gitignore 内），新克隆首次 tsc 报错（Next 16 已知行为）

### 做得好的地方

- 测试命名整体良好、断言大多有明确期望值
- `vi.hoisted` + `vi.mock` 模块级 mock 用法正确
- 全局 beforeEach 清表 + afterAll 关连接方向正确，`ALL_TABLES` 与 18 张表一致
- 网络调用普遍通过 `vi.stubGlobal("fetch")` mock

---

## 修复优先级建议

1. **API 错误协议统一**（裸 Response + 全仓字符串错误码）——唯一会造成客户端实际取不到错误信息的缺陷
2. **统一 LLM 请求层**——最大 DRY 违约点，默认参数已漂移
3. **`saveWordContent()` / 释义提取 / 定义 SQL 公共助手**——消除「改库必漏」与行为漂移
4. **拆 study/initialize/games 巨型组件**——UI 可维护性大头
5. **测试 fixture 工厂 + 单测解耦 PG + setup 关有道**——测试基建最大负债
6. 魔法数字集中、配置清理、死代码移除等机械性任务按节奏推进
