# LexiLoop 纯 Flutter 迁移进度

> 分支：`flutter`（与 `main` 的 Next.js 实现完全隔离，不共存）
> 目标：Android + macOS 双端，纯本地运行，不依赖自建服务端
> 本文档只记录**事实状态**，进度判断以仓库里的代码与测试为准。

---

## 1. 门禁（每次提交前必须全绿）

```bash
dart format --set-exit-if-changed lib test
dart analyze --fatal-infos --fatal-warnings lib test
flutter test
flutter test test/architecture
flutter build macos --debug
```

---

## 2. 已完成

### 2.1 P0 地基

| 内容 | 位置 |
|---|---|
| 数值常量唯一出处 | `lib/core/constants.dart` |
| 错误码与 sealed 错误类型 | `lib/core/errors.dart` |
| 平台能力差异（TTS、模糊降级） | `lib/core/platform.dart` |
| 本地时区日界工具 | `lib/core/date_key.dart` |
| 领域枚举（19 个，带稳定 wire 标识） | `lib/domain/enums.dart` |
| 液态玻璃视觉系统 | `lib/ui/glass.dart`、`lib/ui/theme/` |
| 自适应外壳（≥1024 侧边栏 / 否则底部 Tab） | `lib/ui/adaptive_shell.dart` |
| 架构守卫测试（8 条） | `test/architecture/` |

### 2.2 P0 数据层

- Drift 15 表 schema，与旧版 PostgreSQL 逐列对齐（`test/data/db/column_names_test.dart` 强制）
- 部分唯一索引 `initialization_jobs_active_word_task_unique`（Drift 表达不了，手工 DDL）
- 外键级联、枚举往返、8 种学习模式可写

### 2.3 P1 备份导入与词库

- `BackupImporter`：12 表按父子序导入、枚举值校验、未知列过滤、`word_review_stats` 重算
- 真实备份（33,107 行 / 1417 词）端到端验证通过
- `WordDao` / 单词列表页（搜索、掌握度筛选、分页）

### 2.4 P2 复习引擎

| 模块 | 位置 | 要点 |
|---|---|---|
| 文本归一化 | `lib/domain/text/normalizer.dart` | NFKC + 小写语言族 |
| 释义解析 | `lib/domain/dictionary/definitions.dart` | 目标语言优先、空文本过滤 |
| 拼写容错 | `lib/domain/review/spelling.dart` | 缩写展开、英美拼写、编辑距离 |
| 客观判题 | `lib/domain/review/answer_evaluator.dart` | 客观题答错降级 AGAIN，主观题采信自评 |
| 熟练度 | `lib/domain/review/mastery.dart` | 六分项加权 + 可提取性衰减 |
| 题型选择 | `lib/domain/review/question_type.dart` | 模式 × 位置 × 熟练分分层 |
| 候选抽题 | `lib/domain/review/candidate_selection.dart` | 三池加权、新词软上限、交错配比 |
| 错词状态 | `lib/domain/review/wrong_state.dart` | 按**自然日**累加连对，同一天刷题不解除 |
| 作答时长 | `lib/domain/review/duration.dart` | 上界夹取，避免挂机污染统计 |
| FSRS 适配 | `lib/services/fsrs_scheduler.dart` | 包裹 `package:fsrs`，关闭 fuzz 保证预览确定 |
| 题目载荷 | `lib/domain/review/question_payload.dart` | 打乱、挖空、字母块（随机源可注入） |
| 选项生成 | `lib/services/question_builder.dart` | 易混词 → 活跃错词 → 全局池 三级回退 |
| 复习 DAO | `lib/data/db/daos/review_dao.dart` | 幂等查询、认领题目、卡片与日志、统计窗口重算 |
| 学习 DAO | `lib/data/db/daos/study_dao.dart` | 候选池 SQL、会话 CRUD、插题位置、每日计划统计 |
| 作答流水线 | `lib/services/review_service.dart` | 单事务：判题 → FSRS → 日志 → 统计 → 错词 → 熟练度 → 插题 → 收尾 |
| 会话编排 | `lib/services/study_service.dart` | 开始/恢复会话、跳过、每日计划 |
| 设置 | `lib/domain/models/app_settings.dart`、`lib/services/settings_service.dart` | 按 tab 分组、未建模键原样保留 |
| 朗读 | `lib/services/tts_service.dart` | 引擎抽象（可测）、语速按内容类型区分 |

### 2.5 P2 界面与 P3/P4 功能

| 模块 | 位置 | 要点 |
|---|---|---|
| 学习会话页 | `lib/features/study/**` | 8 种题型的作答控件、四档自评即提交、反馈与总结；按职责拆成 13 个组件 |
| 词条详情页 | `lib/features/word_detail/**` | 12 张卡片（释义/例句/短语/变形/同反义/词族/易混/词根词缀/学习情况/复习历史/笔记/助记） |
| 仪表盘 | `lib/features/dashboard/**` | 今日计划、统计、到期与错词提醒、平台能力 |
| 统计页 | `lib/features/statistics/**` | 逐日趋势折线、掌握分布、题型正确率、最近作答 |
| 手动添加词条 | `lib/features/add/**` | 离线可用；不建服务端预览表 |
| CSV 导入 | `lib/data/import/**`、`lib/services/csv_import_service.dart`、`lib/features/import/**` | EasyDict 列名别名、三种导入模式、批次撤销 |
| 设置页 | `lib/features/settings/**` | 6 个 tab，即时保存 |
| 朗读 | `lib/services/tts_service.dart` | 引擎抽象可测；学习页与详情页的朗读按钮待接 |
| 词条写入 | `lib/services/word_edit_service.dart` | 创建/更新/暂停/笔记/删除/入队初始化 |

### 2.6 迁移中修正的旧版缺陷

这些是重写时**有意偏离**旧版的地方，每条都有注释与测试钉住：

1. **自适应插题的首次延迟是死代码**：旧版用「本词已 ANSWERED 的题目数」判断是第几次错，
   但认领当前题时它已被置为 ANSWERED，计数永远 ≥1，导致
   「首次错隔 5 题复现」永不生效、每词每会话最多只插一道题。
   本版改为统计**本次之前**的作答次数。
2. **`questionFor` 的分支顺序把「错词任务」盖掉了**：旧版 `taskType === "WRONG"`
   优先于 `mode === "DAILY"`，而按模式分支书写会先命中 DAILY。
   本版按旧版的判定顺序书写，并在注释里说明顺序是语义的一部分。
3. **`study_sessions.session_type` 的 PG CHECK 只有 6 个值**，而代码会写入 8 种
   （`SENTENCE_REVIEW`、`AI_RECOMMENDED` 会被拒绝）。本版改为
   `session_type` 记实际使用的模式、真实来源放 `source_type`。
4. **`max_attempts` 有两个来源**（设置算出 2、导入路径硬编码 5）。本版统一由设置推导。
5. **`WORKER_STALE_AFTER_MS = 30_000` 未被使用**（实际是 10 分钟）。本版单进程启动时全量重置 RUNNING。
6. **空 catch 与字符串判错**（`error.message === "WORD_NOT_FOUND"` 约 15 处）。
   本版用 sealed `AppError` + 错误码枚举，并有守卫测试禁止回归。
7. **`FSRS` 实例的全局缓存无上限**。本版改为调用方持有实例。
8. **干扰项池是模块级可变全局变量**。本版每次按需查询。
9. **腾讯翻译 provider 需要把 SecretKey 内嵌进客户端**，本版放弃该 provider。
10. **`target_language` 用 `zh-CN` 而不是 `zh`**。真实备份（1417 词条）里
    `words.target_language` 与 `definitions_json[].language` 全是 `zh-CN`，
    而语言映射表若写成裸 `zh`，手动添加的词条释义会永远匹配不上。
11. **`word_contents` 各 JSON 列的解析在两个 DAO 里各写了一份**（约 300 行重复）。
    本版抽到 `domain/dictionary/content_parse.dart`，并用 27MB 生产备份
    逐列核对了真实键名（`phrases_json` 用 `phrase`、`forms_json` 用
    `type`+`value`、`tags_json` 是纯字符串数组、
    `summary/learning/sentence_analysis` 是对象而非数组）。

---

## 3. 进行中

| 工作流 | 范围 |
|---|---|
| 词典 provider + 初始化队列 + LLM | `lib/data/dictionary/**`、`lib/services/dictionary|llm|initialization/**` |
| 小游戏 + 配对 + 音标训练 | `lib/features/games|match|phonetics/**`、`lib/domain/games|phonetics/**` |

---

## 4. 待办

| 阶段 | 内容 |
|---|---|
| P4 | 初始化队列界面（`/initialize`）、每日 AI 建议接入界面、模型选择对话框 |
| P6 | 学习页与详情页的朗读按钮接入 `TtsService`、液态玻璃打磨、双端 TTS 实测校准、打包与签名 |
| — | Android 端实机验证（由用户负责；`flutter doctor --android-licenses` 尚未接受） |

---

## 5. 与旧版的刻意差异（非缺陷）

| 项 | 旧版 | 本版 | 原因 |
|---|---|---|---|
| 时区 | 固定 `APP_TIMEZONE=Asia/Shanghai` | 设备本地时区 | 纯本地应用没有服务端时区概念 |
| 备份恢复 | 服务端 API | 本地文件选择 + 直接写库 | 无服务端 |
| 音频缓存 | 服务端内存 LRU（200 条） | 未实现（macOS 不支持 `synthesizeToFile`） | 双端能力不对等 |
| 幂等键 | 服务端唯一索引 | 本地唯一索引（同样强制） | 离线重放更需要 |
