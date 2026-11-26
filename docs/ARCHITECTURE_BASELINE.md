# LexiLoop 开发与架构文档

> ⚠️ **本文档描述的是旧版 Next.js 实现（`main` 分支，`src/` 目录），不是当前代码。**
> 当前实现是纯 Flutter 客户端（`flutter` 分支，`lib/` 目录），
> 见 [`FLUTTER_MIGRATION_STATUS.md`](FLUTTER_MIGRATION_STATUS.md) 与
> [`FLUTTER_PARITY.md`](FLUTTER_PARITY.md)。
> 保留本文档是因为它是迁移的**对照基准**：`lib/core/constants.dart`、
> `lib/core/errors.dart` 与各服务的注释大量引用它的分层与模块边界来
> 说明「为什么这样写」。文中的 PostgreSQL、Next.js、服务端 API、
> 密码登录等都不存在于当前实现。


## 1. 定位

LexiLoop（词环）是单用户、自托管的 Next.js 词汇学习应用。核心原则：只初始化 CSV 中实际导入的词条；PostgreSQL 是唯一业务数据源；无需账号、多用户和云端数据库。

## 2. 技术栈

- Next.js 16 App Router、React 19、TypeScript strict
- Tailwind CSS 4、Recharts、Lucide
- PostgreSQL（`pg` + 统一 SQL 门面 `src/db/executor.ts`）
- OpenAI-compatible / Anthropic 结构化 AI 初始化；Edge TTS 发音
- ts-fsrs
- Vitest、Playwright

## 认证

应用支持通过运行时环境变量 `LEXILOOP_PASSWORD` 启用单密码登录。变量未设置或为空时不启用认证；设置后，页面和业务 API 都需要有效的 7 天登录 Cookie，`/api/health` 保留为公开健康检查入口。密码不写入数据库，修改密码需要重新创建 app 容器。

## 3. 核心流程

1. 上传 EasyDict CSV。
2. 服务端验证表头、UTF-8、大小、行数、字段和时间。
3. 持久化预览令牌，识别新增、已有、文件内重复、无效行。
4. 提交时在立即事务中一次性领取预览令牌；根据策略创建或升级初始化任务，防止并发重复提交。
5. Worker 原子领取任务，写入真实心跳；启用 AI 时优先生成完整结构化词汇内容，再由 DictionaryAPI/ECDICT 补充音标、真人音频或离线词形。
6. READY / PARTIAL 词条进入每日学习队列。
7. 服务端根据题型判题，使用 FSRS 更新卡片，并同步错词、熟练度、会话统计。

## 4. 导入策略

- `SKIP_EXISTING`：仅新增。
- `FILL_MISSING`：新增 + 已有词条补字段。
- `FORCE_DICTIONARY_REFRESH`：重新获取已有词典内容，保留学习进度。
- 可选重置本批已有词条的复习卡、日志、错词和熟练度；同时取消该词尚未完成的旧题目。
- 导入历史支持安全撤销：仅删除本批新建且尚未学习、未进入会话、未被后续导入引用的词条。
- 修改过已有词条或重置过学习进度的批次不允许无损撤销。

## 5. AI 词条初始化

`IMPORT_ENRICHMENT` 启用后，Worker 调用配置的大模型生成：

- 分词义的源语言解释、目标语言翻译、词性、语域和用法说明；
- 每个主要词义最多两个例句；
- 搭配、短语、习语、词形变化；
- 同根词/词族、词根、前后缀；
- 近义词、反义词、易混词及差异说明；
- CEFR、词频、发音提示、记忆提示和常见错误。

OpenAI-compatible 接口优先使用 strict JSON Schema；不支持时依次退回 JSON Object 和普通 JSON。Anthropic 使用 Messages API 并在提示词中附带同一 Schema。所有返回都经过 Zod 严格校验、目标词一致性检查和质量评分。低于质量阈值的内容不会写入数据库。Provider 尝试记录模型、提示词版本、Schema 版本、输入/输出 Token、完成原因和质量分。

词条输入放在 `<term_data>` 中并明确声明为不可信数据，避免词条文本被当作模型指令。无法确认的词根、词源或关联词必须返回空数组。AI 不生成音频地址，Edge TTS 独立负责实际发音。

AI 生成的近义词、反义词、同根词和易混词保存为结构化对象。详情页点击后调用关联词预览接口；加入时继承父词条语言方向，使用唯一身份约束防重复，并创建或复用初始化任务。初始化页支持批量扫描：默认只选择没有 AI SUCCESS 记录的词条；强制模式选择全部词条，并将已有活动任务升级为 FORCE_OVERWRITE 而不重复创建。

## 6. Worker 可靠性

- 事务串行领取（`SELECT ... FOR UPDATE SKIP LOCKED`）。
- 同一词条仅允许一个 QUEUED / RUNNING 任务（partial unique index）。
- RUNNING 锁超过十分钟自动回到 QUEUED（`recoverStaleJobs`）。
- 已有 READY / PARTIAL 内容的词在补充或刷新期间继续可学习；刷新失败不会覆盖旧内容。
- 强制刷新保留用户手动释义和用户例句。
- 瞬时错误按 5 秒、30 秒、2 分钟、10 分钟、30 分钟退避。
- Provider 尝试记录字段、耗时和错误。
- `/api/health` 根据真实心跳报告 `idle/working/stale/not_required`。

### 6.1 后台驱动（Vercel vs Docker）

- 单一原语 `src/modules/background/tick.ts:runBackgroundTick`，在 Vercel 与 Docker 间复用。
- Vercel：`vercel.json` 日级 Cron（`0 0 * * *`，Hobby 上限）+ 浏览器 `BackgroundKeepalive` 3s/60s 轮询 + `/api/initialization/status` 按需触发。
- Docker：`src/instrumentation.ts:register` 在 `NODE_ENV=production && VERCEL !== "1"` 时启动 `src/modules/background/docker-tick.ts` 的 10 秒进程内轮询（`workerId=lexiloop-docker`），无需浏览器在线；`BACKGROUND_DOCKER_TICK_ENABLED=false` 可关闭退化为纯 KeepAlive。

## 7. 学习模型

每日队列按到期复习、错词、新词交错，并对重叠词条去重后继续补足配置额度；专项模式包括听力和拼写。

学习会话在 24 小时内可恢复。待答词不会同时进入另一个新会话；过期会话自动关闭并释放词条。“稍后再学”不更新 FSRS，并在 12 小时内暂时移出队列。

答案 UUID 在同一题的网络重试中保持稳定。服务端校验会话、题目、词条和题型，并在立即事务中领取题目；即使更换 UUID，同一题也不能重复修改 FSRS。拼写题由服务端标准化判定，错误评分强制为 AGAIN。

错词解除要求至少跨三个连续自然日正确，不允许同一天重复刷题快速解除。熟练度由稳定性、正确率、间隔、连续正确、经验、遗忘和活跃错词共同计算；掌握等级分为 NEW、LEARNING、FAMILIAR、PROFICIENT、MASTERED。

有学习历史或学习会话记录的词条禁止硬删除，避免破坏历史会话聚合；用户应使用“暂停学习”。在线 Provider 无法给出释义时，可保存手动释义使词条进入 PARTIAL 并继续学习。

## 8. 备份恢复

JSON 备份导出（`/api/backups/json`），恢复经表与迁移版本校验。PostgreSQL 迁移位于 `src/db/migrations/pg/`，由 `yarn db:migrate` 在独立事务内逐个应用。

## 9. Docker 部署

见 `README.md#Docker 部署`、`Dockerfile`、`docker-compose.yml`、`scripts/deploy-queen.sh`。Vercel 构建（`VERCEL=1`）自动忽略 Docker 产物；Docker 构建输出 `standalone` 并通过 `src/instrumentation.ts` 启用进程内 tick。

## 10. 验收命令

```bash
yarn typecheck
yarn lint
yarn test
yarn build
yarn test:e2e
```
