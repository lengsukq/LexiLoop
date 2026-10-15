# LexiLoop 纯 Flutter 迁移 — 进度汇报

> 分支：`flutter`（从 `main` 的 `3bc6538` 开出，与 Next.js 实现完全隔离）
> 汇报时间：2026-10-15
> 汇报时最新提交：`aa617ae`
> 工作目录：`/Users/leo/Documents/code/LexiLoop`

---

## 1. 结论摘要

**主体已迁移完成，可以编译、可以跑、可以自测。** 核心引擎（判题、FSRS、熟练度、
错词、抽题、会话编排）与全部 8 个主导航页面、词条详情、导入、设置、游戏、配对、
音标训练都已落地，并有 826 项自动化测试覆盖。

初始化任务的 worker 此前只存在于测试里，现已接入应用生命周期：启动时回收崩溃
遗留的 RUNNING 任务并处理首批，之后每 10 分钟推进一批；队列页另有「立即处理一批」
按钮，用户不必等定时器。「导入词条 → 自动补全释义」这条链路现在在真机上会跑。
详见 §5。

### 门禁现状（汇报时实测）

| 检查 | 结果 |
|---|---|
| `dart format --set-exit-if-changed lib test` | 通过（0 changed） |
| `dart analyze --fatal-infos --fatal-warnings lib test` | **No issues found** |
| `flutter test` | **847 passed / 1 skipped / 0 failed** |
| `flutter test test/architecture` | **8/8 通过** |
| `flutter build macos --debug` | **✓ 构建成功** |

> 1 项 skipped 是「真实备份导入」测试，需要设 `LEXILOOP_BACKUP_PATH` 才会跑。

### 规模

| 区域 | 文件 | 行数 |
|---|---|---|
| `lib/core` | 5 | 1,199 |
| `lib/domain` | 31 | 9,515 |
| `lib/data` | 43 | 12,533 |
| `lib/services` | 26 | 8,893 |
| `lib/ui` | 6 | 1,570 |
| `lib/features` | 93 | 15,159 |
| `lib/app` | 2 | 166 |
| **lib 合计** | **208** | **49,152** |
| `test` | 57 个测试文件 | 18,342 |

> 不计 `*.g.dart`（Drift 生成代码）。

---

## 2. 技术栈

| 项 | 版本 / 说明 |
|---|---|
| Flutter / Dart | 3.47.5 / 3.13.4（用 Flutter 自带的 Dart，`/opt/homebrew/bin/dart` 已指向它） |
| 数据库 | Drift 2.35.2 + SQLite（sqlite3 3.x 经 Dart build hooks 自动打包；`sqlite3_flutter_libs` 已 EOL 并移除） |
| 状态管理 | Riverpod 3.4.3（`Provider` / `NotifierProvider` / `AsyncNotifierProvider` / `FutureProvider`） |
| 路由 | go_router 18.0.2 + `StatefulShellRoute.indexedStack` |
| 间隔重复 | `fsrs` 2.0.1 |
| 其他 | `flutter_tts`、`dio`、`fl_chart`、`csv`、`unorm_dart`、`file_picker`、`share_plus`、`window_manager` |
| Lint | `very_good_analysis` 11.0.0 + 严格错误级规则 |

---

## 3. 已完成功能

### 3.1 地基（`lib/core`、`lib/ui`）

| 内容 | 位置 |
|---|---|
| 全应用数值常量唯一出处 | `lib/core/constants.dart`（~700 行，每项标注旧版来源） |
| 错误码枚举（~60 个）+ sealed `AppError` 层次 | `lib/core/errors.dart` |
| 平台能力差异（TTS 落盘、模糊降级） | `lib/core/platform.dart` |
| 设备本地时区的日界工具 | `lib/core/date_key.dart` |
| 领域枚举（19 个，带稳定 `wire` 标识） | `lib/domain/enums.dart` |
| 液态玻璃视觉系统 | `lib/ui/glass.dart`、`lib/ui/theme/` |
| 自适应外壳（≥1024 侧边栏 / 否则底部 Tab） | `lib/ui/adaptive_shell.dart` |
| 架构守卫测试（8 条） | `test/architecture/` |

### 3.2 数据层（`lib/data`）

- **Drift 15 表 schema**，与旧版 PostgreSQL 逐列对齐（`test/data/db/column_names_test.dart` 强制）
- 部分唯一索引 `initialization_jobs_active_word_task_unique`（Drift 表达不了，手工 DDL）
- 外键级联、枚举往返、8 种学习模式可写
- DAO：`WordDao`、`WordDetailDao`、`ReviewDao`、`StudyDao`、`StatisticsDao`、`SettingsDao`、`GameDao`
- **备份导入**：12 表按父子序、枚举校验、未知列过滤、`word_review_stats` 重算。
  真实备份（33,107 行 / 1417 词 / 27MB）端到端验证通过
- **CSV 导入**：EasyDict 列名别名（中英 + 大小写/下划线/空格宽松匹配）、
  三种导入模式（跳过 / 补空 / 覆盖）、批次撤销、过期预览清理
- **词典 provider**：有道（双端点重试 + HTML 解析）、爱词霸、dictionaryapi.dev、
  MyMemory、Merriam-Webster、AI 词条生成；HTML 解析为手写扫描器（未引入 `package:html`）
- **LLM 客户端**：OpenAI 兼容 / Anthropic 双协议、三层降级、超时与思考预算夹取

### 3.3 领域层（`lib/domain`）

| 模块 | 位置 |
|---|---|
| 文本归一化（NFKC + 小写语言族） | `text/normalizer.dart` |
| 释义解析 + `word_contents` JSON 解析原语 | `dictionary/definitions.dart`、`dictionary/content_parse.dart` |
| 拼写容错（缩写展开、英美拼写、编辑距离） | `review/spelling.dart` |
| 客观判题 | `review/answer_evaluator.dart` |
| 熟练度评分 + 掌握等级 | `review/mastery.dart` |
| 题型选择（模式 × 位置 × 熟练分分层） | `review/question_type.dart` |
| 候选抽题（三池加权、新词软上限、交错配比） | `review/candidate_selection.dart` |
| 错词状态（按**自然日**累加连对） | `review/wrong_state.dart` |
| 作答时长上界 | `review/duration.dart` |
| 题目载荷（打乱 / 挖空 / 字母块） | `review/question_payload.dart` |
| 游戏规则与计分（纯状态机） | `games/**` |
| 音标目录（48 音标）+ 出题规则 | `phonetics/**` |

### 3.4 服务层（`lib/services`）

| 服务 | 行数 | 说明 |
|---|---|---|
| `review_service.dart` | 393 | 单事务：认领题目 → 判题 → FSRS → 日志 → 统计 → 错词 → 熟练度 → 插题 → 收尾 |
| `study_service.dart` | 349 | 开始/恢复会话、跳过、每日计划 |
| `fsrs_scheduler.dart` | 252 | `package:fsrs` 适配；刻意关闭 fuzz 保证预览确定 |
| `question_builder.dart` | 237 | 干扰项三级回退（易混词 → 活跃错词 → 全局池） |
| `tts_service.dart` | 181 | 引擎抽象（可测）、语速按内容类型区分 |
| `word_edit_service.dart` | 345 | 创建/更新/暂停/笔记/删除/入队初始化 |
| `csv_import_service.dart` | 1,007 | 预览 / 提交 / 撤销 / 历史 / 清理 |
| `suggestion_service.dart` | 1,513 | 每日建议：规则式 + AI，质量分不达标回退 |
| `game_service.dart` 等 3 个 | 683 | 游戏 / 配对 / 音标训练会话与结算 |
| `dictionary/**` | 854 | provider 选择、合并管线、查找入口 |
| `llm/**` | 1,074 | 客户端、配置解析、JSON 输出校验 |
| `initialization/**` | 1,900 | worker、查询、补充任务（助记 / 例句翻译）、后台维护调度 |

### 3.5 界面（`lib/features`，93 文件 / 15,159 行）

| 页面 | 路径 | 行数 | 对应旧版 |
|---|---|---|---|
| 今日（仪表盘） | `/` | 1,267 | `app/(main)/page.tsx` |
| 学习会话 | `/study` | 2,041 | `study/study-client.tsx`（497 行 → 13 个组件） |
| 词库列表 | `/words` | 474 | `words/page.tsx` |
| 词条详情 | `/words/:id` | 1,821 | `words/[id]/**`（12 张卡片） |
| 音标训练 | `/phonetics` | 893 | `phonetics/**` |
| 添加词条 | `/add` | 709 | `add/manual-tab.tsx` |
| 初始化队列 | `/initialize` | 855 | `initialize/page.tsx` |
| 统计 | `/statistics` | 1,130 | `statistics/page.tsx` |
| 设置 | `/settings` | 1,451 | `settings/**`（6 个 tab） |
| CSV 导入 | `/import` | 1,313 | `import/page.tsx` |
| 小游戏 | `/games` | 2,431 | `games/**`（543 行 → 13 个组件） |
| 配对游戏 | `/match` | 712 | `match/page.tsx` |

---

## 4. 迁移中修正的旧版缺陷

每条都有注释与测试钉住，不是「顺手改改」。

1. **自适应插题的首次延迟是死代码**。旧版用「本词在会话内已 ANSWERED 的题目数」
   判断是第几次错，但认领当前题时它已被置为 ANSWERED，计数永远 ≥1，
   导致「首次错隔 5 题复现」永不生效、每词每会话最多只插一道题。
   本版改为统计**本次之前**的作答次数。
2. **`questionFor` 的分支顺序把「错词任务」盖掉了**。旧版 `taskType === "WRONG"`
   优先于 `mode === "DAILY"`，按模式分支书写会先命中 DAILY。本版按旧版判定顺序书写。
3. **`study_sessions.session_type` 的 PG CHECK 只有 6 个值**，而代码会写入 8 种
   （`SENTENCE_REVIEW`、`AI_RECOMMENDED` 会被拒绝）。本版 `session_type` 记实际
   使用的模式、真实来源放 `source_type`。
4. **`max_attempts` 有两个来源**（设置算出 2、导入路径硬编码 5）。本版统一由设置推导。
5. **`WORKER_STALE_AFTER_MS = 30_000` 未被使用**（实际是 10 分钟）。
6. **空 catch 与字符串判错**（`error.message === "WORD_NOT_FOUND"` 约 15 处）。
   本版用 sealed `AppError` + 错误码枚举，并有守卫禁止回归。
7. **`FSRS` 实例的全局缓存无上限**。本版由调用方持有实例。
8. **干扰项池是模块级可变全局变量**。本版每次按需查询。
9. **腾讯翻译 provider 需要把 SecretKey 内嵌进客户端**，本版放弃该 provider。
10. **`target_language` 用 `zh-CN` 而不是 `zh`**。真实备份里
    `words.target_language` 与 `definitions_json[].language` 全是 `zh-CN`；
    若语言映射写成裸 `zh`，手动添加的词条的释义会永远匹配不上。
11. **`word_contents` 各 JSON 列的解析在两个 DAO 里各写了一份**（约 300 行重复）。
    本版抽到 `domain/dictionary/content_parse.dart`，并用 27MB 生产备份逐列核对
    真实键名（`phrases_json` 用 `phrase`、`forms_json` 用 `type`+`value`、
    `tags_json` 是纯字符串数组、`summary/learning/sentence_analysis` 是对象而非数组）。
12. **计分权重在旧版分散在三处**（`games/completion.ts`、`matching/service.ts`、
    `games/service.ts`）。本版收敛到 `domain/games/game_mode.dart` 的模式规则表。
13. **学习页交互顺序**：旧版是「先作答 → 再选四档自评（选了即提交）」。
    中途实现曾做成「确认提交 → 再展示只读的已记录等级」，导致用户无法在客观题上
    表达「模糊 / 简单」；已改回旧版顺序。

---

## 5. 初始化任务的接线（本次补齐）

此前 worker 只在测试里被构造，「导入词条 → 自动补全释义」在真机上不会跑。
现已补齐，分三层：

| 层 | 内容 | 位置 |
|---|---|---|
| 执行 | `InitializationJobRunner` 接口 + `InitializationWorker` 实现 | `lib/services/initialization/job_runner.dart` |
| 策略 | `InitializationMaintenance`：启动回收、失败回收、首批处理、周期 tick、重入保护 | `lib/services/initialization/initialization_maintenance.dart` |
| 点火 | `MaintenanceBootstrap` 包在 `ProviderScope` 内、`LexiLoopApp` 外 | `lib/app/maintenance_bootstrap.dart`、`lib/main.dart` |

| 模块 | 状态 |
|---|---|
| `InitializationWorker` | **已接线**：`initializationJobRunnerProvider` 由 `MaintenanceBootstrap` 在首帧后 `start()`，随后每 10 分钟推进一批 |
| `DictionaryLookupService` / `ProviderPipeline` | **可达**（随 worker 注入）：有道 / 爱词霸 / dictionaryapi.dev / MyMemory / MW |
| `LlmSupplementalTaskRunner`（助记词、例句翻译） | **可达**（依赖 worker） |
| `LlmClient` | 已接线（`SuggestionService` 的每日建议 + worker 的词条级生成） |
| 手动添加页的「词典补全」预览 | 仍未实现：手动添加只支持用户自己填内容（离线可用）；旧版是先调词典出预览再确认 |

配套：初始化队列页新增「立即处理一批」按钮，用户不必等定时器；
`InitializationQueries` 的 provider 上移到 `lib/data/db/dao_providers.dart`
（原先放在 `features/initialize`，会让 data 层反向依赖界面层）。

**为什么点火器挂在 `main()` 而不是 `LexiLoopApp`**：`pumpAndSettle` 遇到未取消的
`Timer.periodic` 会挂住，测试进程结尾也会报「Timer 仍在挂起」。放在 `main()` 里，
测试直接 `pumpWidget(LexiLoopApp())` 就不会启动定时器。

---

## 6. 与旧版的刻意差异（非缺陷）

| 项 | 旧版 | 本版 | 原因 |
|---|---|---|---|
| 时区 | 固定 `APP_TIMEZONE=Asia/Shanghai` | 设备本地时区 | 纯本地应用没有服务端时区概念 |
| 备份恢复 | 服务端 API | 本地文件选择 + 直接写库 | 无服务端 |
| 手动添加预览 | 落库到 `manual_previews`（带 TTL 与令牌认领） | 不建预览表，直接写库 | 单用户本地应用没有并发认领问题 |
| CSV 预览 | 落库到 `import_previews` | 落 `import_batches` / `import_rows`（不落词条） | 保留批次撤销与历史能力 |
| 音频缓存 | 服务端内存 LRU（200 条） | 未实现 | macOS 不支持 `synthesizeToFile`，双端能力不对等 |
| 幂等键 | 服务端唯一索引 | 本地唯一索引（同样强制） | 离线重放更需要 |
| 干扰项池 | 模块级可变全局缓存 | 每次按需 `ORDER BY RANDOM()` | 全局可变状态是基线文档点名的问题 |
| FSRS fuzz | `enable_fuzz: true` | 关闭 | Dart 版 fuzz 用未播种 `Random`，会让预览不单调且不可复现 |

---

## 7. 未完成 / 待办

| 优先级 | 事项 |
|---|---|
| **高** | Android 端实机验证（由你负责；`flutter doctor --android-licenses` 尚未接受，且存在重复的 `adb` 二进制） |
| **高** | 词典 provider 的**真实网络联调**：解析器只用旧版单测的 fixture 验证过；接线后需要真机联网跑一次（有道 / 爱词霸 的页面结构会变） |
| 中 | 手动添加页的「词典补全」预览路径 |
| 中 | 设置页的模型选择对话框（拉取 `GET {baseUrl}/models` 的界面；服务端能力已有） |
| 中 | `initializationJobPageSize` 目前在 `lib/data/dictionary/dictionary_constants.dart`，位置不合适，应移到 `lib/core/constants.dart` |
| 低 | `lib/features/*/widgets/` 里有两份同类的卡片底板（`DetailSectionCard` 与 `DashboardCard`），应合并到 `lib/ui/widgets/` |
| 低 | Android 打包与签名（`minSdk 26`、`targetSdk 35`、INTERNET 权限已配） |
| 低 | 液态玻璃在 Android 中低端机的实测校准（`PlatformCaps.needsBlurDowngrade` 已预留） |

---

## 8. 如何验证

```bash
cd /Users/leo/Documents/code/LexiLoop

# 门禁
dart format --set-exit-if-changed lib test
dart analyze --fatal-infos --fatal-warnings lib test
flutter test
flutter test test/architecture

# macOS 跑起来
flutter run -d macos

# 真实备份导入（可选，需要 27MB 备份文件）
LEXILOOP_BACKUP_PATH=/Users/leo/Documents/lexiloop-backups/lexiloop-backup-20261014-222752.json \
  flutter test test/data/backup/backup_import_test.dart
```

手工验收建议顺序：

1. 启动 → 「设置 → 数据管理 → 备份导入」导入真实备份 → 「词库」应出现 1417 个词条
2. 「词库」点任一词条 → 详情页应显示释义 / 例句 / 学习情况 / 复习历史
3. 「今日」→「开始学习」→ 走完一轮（含选择题、拼写题、字母拼图、填空、听力）
4. 「统计」→ 趋势图、掌握分布、题型正确率应有真实数字
5. 「添加」→ 手动填一个词 → 「词库」里能找到
6. 「初始化」→ 导入的词条任务应出现在队列里 → 点「立即处理一批」→ 状态应从
   「排队中」变为「已完成」，且词条详情里多出词典抓来的释义与例句
7. 「今日」→「趣味训练」→ 四个小游戏 + 配对 + 音标

---

## 9. 已知风险

1. **词典解析依赖外部 HTML 结构**。有道与爱词霸的页面结构会变；解析器有单测
   （用旧版单测里的 fixture），但**没有真实网络联调**。provider 现在已可达，
   这是接线后最需要验证的一环。
2. **`word_contents` 里 `phrases_json` / `forms_json` / `tags_json` 的键名**已用真实
   备份核对过，但备份只有 1417 个词条；若将来导入别的数据源，需要重新核对。
3. **`streakDays` 的实现**用 `SELECT DISTINCT date(reviewed_at/1000,'unixepoch','localtime')`
   后在 Dart 里倒推，未设回看窗口；个人库量级没问题，日志过百万时需加窗口。
4. **测试覆盖率不均**：`test/features` 有 9 个文件，但 `lib/features` 有 93 个文件。
   界面测试集中在学习页、详情页、仪表盘、导入、设置、初始化队列；游戏与音标的
   界面测试较少（规则与状态机的测试较全）。
5. **本次有两处架构守卫误报被修正**（`}` 开头的续行被当成函数签名、`limits.$2` 里的
   `$2` 被当成裸数字）。修的是守卫而不是迁就代码——误报会让守卫失去可信度。
   但也说明守卫是启发式的，遇到新写法可能再误报。

---

## 10. 提交历史（本分支）

```
aa617ae feat(p4/p5): 首页今日建议卡片、游戏与音标训练接入；修正守卫误报
30cf274 feat: 首页「趣味训练」入口、小游戏与配对改为顶层路由
fbefb37 feat(p4): 初始化队列监控页
069ef01 feat: 接入游戏、配对、音标训练路由
d04ab81 feat(p6): 学习页与词条详情页接入系统朗读
b534e82 docs: 更新迁移进度
56f02ec refactor: 抽出 word_contents JSON 解析原语、上移常量、接线路由
c1827b4 feat(p2/p3): 手动添加词条页、学习页交互修正、词条写入服务
1f6191e test: 冒烟测试注入内存数据库与 ProviderScope
9225ccb feat(p3): 统计页与统计查询
6c488eb feat(p2): 学习会话 DAO、FSRS 适配、题目载荷、作答流水线
0331f03 feat(p2/p6): 朗读服务、服务 provider 收敛、迁移进度文档
cb0bf34 feat(p2): 复习领域层、复习 DAO 与设置服务
9479593 feat(p1): 备份导入服务、词库 DAO 与单词列表页
8791f92 feat(p0): Drift 15 表 schema、枚举映射与数据库守卫测试
14da67e feat(p0): 双端地基 — 主题、自适应外壳、Drift 常量层与架构守卫
f733b30 chore: 初始化 Flutter 工程（flutter 分支，脱离 Next.js）
```

---

## 11. 相关文档

| 文档 | 内容 |
|---|---|
| [`FLUTTER_MIGRATION_STATUS.md`](FLUTTER_MIGRATION_STATUS.md) | 分阶段进度清单（与本文互补：本文偏汇报，它偏清单） |
| [`FLUTTER_MIGRATION_REPORT.md`](FLUTTER_MIGRATION_REPORT.md) | 迁移可行性评估：外部服务清单、各层难度、双端差异 |
| [`FLUTTER_MIGRATION_UI_AUDIT.md`](FLUTTER_MIGRATION_UI_AUDIT.md) | 旧版界面复杂度审计 |
| [`CLEAN_CODE_BASELINE.md`](CLEAN_CODE_BASELINE.md) | 旧版 231 行整洁度整改清单（守卫测试的由来） |
| [`ARCHITECTURE_BASELINE.md`](ARCHITECTURE_BASELINE.md) | 旧版分层与模块边界 |
