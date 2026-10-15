# LexiLoop 纯 Flutter 迁移状态

> 分支：`flutter`（与 `main` 的 Next.js 实现完全隔离，不共存）
> 目标：Android + macOS 双端，纯本地运行，不依赖自建服务端
> 另有 Web 构建，用途是**在浏览器里自测**，见 [`FLUTTER_WEB.md`](FLUTTER_WEB.md)
> 本文档只记录**事实状态**；判定以仓库里的代码与测试为准，不以文档自述为准。

---

## 1. 规模

| 项 | 数量 |
|---|---|
| `lib/`（不含 `*.g.dart`） | 308 文件 / 76,577 行 |
| `test/` | 122 文件 / 37,397 行 |
| `lib/core/constants.dart` 顶层常量 | 375 条（数值常量的唯一出处） |
| Drift 表 | 15 张（与旧版 PostgreSQL 逐列对齐） |
| 架构守卫 | 9 条 |
| 直接依赖 | 18 个（不含 dev） |
| 测试 | **1640 通过 / 2 跳过** |

---

## 2. 门禁（每次提交前必须全绿）

```bash
dart format --set-exit-if-changed lib test
dart analyze --fatal-infos --fatal-warnings lib test
flutter test
flutter test test/architecture
flutter build macos --debug
flutter build web --release          # Web 目标
```

`test/architecture/architecture_test.dart` 是**结构守卫**而非行为测试：分层边界、
函数与 `build()` 行数上限、构造参数个数、空 `catch`、字符串判错、`lib/domain` 与
`lib/services` 的裸数字、`dart:io` 只允许出现在 `*_native.dart`、常量集中性。
它们把 [`CLEAN_CODE_BASELINE.md`](CLEAN_CODE_BASELINE.md) 记录过的旧版问题类型
变成了自动化约束。

---

## 3. 已完成

### 3.1 地基与数据层

| 内容 | 位置 |
|---|---|
| 数值常量唯一出处 | `lib/core/constants.dart` |
| 错误码与 sealed 错误类型 | `lib/core/errors.dart` |
| 平台能力矩阵（可构造的 `PlatformProfile`，便于穷举三态） | `lib/core/platform.dart` |
| 本地时区日界工具 | `lib/core/date_key.dart` |
| 领域枚举（19 个，带稳定 wire 标识） | `lib/domain/enums.dart` |
| 液态玻璃视觉系统 | `lib/ui/glass.dart`、`lib/ui/theme/` |
| 自适应外壳（≥1024 侧边栏 / 否则底部 Tab） | `lib/ui/adaptive_shell.dart` |
| 路由与路径常量 | `lib/app/router.dart`、`lib/ui/navigation/route_paths.dart` |
| 共享界面基元（卡片 / 错误重试 / 结算提示 / 重置开关） | `lib/ui/widgets/` |

- Drift 15 表 schema，与旧版 PostgreSQL 逐列对齐（`test/data/db/column_names_test.dart` 强制）
- 部分唯一索引 `initialization_jobs_active_word_task_unique`（Drift 表达不了，手工 DDL）
- 外键级联、枚举往返、8 种学习模式可写

### 3.2 备份导入与词库

- `BackupImporter`：12 表按父子序导入、枚举值校验、未知列过滤、`word_review_stats` 重算
- 真实备份（33,107 行 / 1417 词）端到端验证通过
- 无本地路径的云文件（Android `content://`、Web `blob:`）也能导入

### 3.3 复习引擎

| 模块 | 位置 | 要点 |
|---|---|---|
| 文本归一化 | `lib/domain/text/normalizer.dart` | NFKC + 小写语言族 |
| 释义解析 | `lib/domain/dictionary/definitions.dart` | 目标语言优先、空文本过滤 |
| 拼写容错 | `lib/domain/review/spelling.dart` | 缩写展开、英美拼写、编辑距离 |
| 客观判题 | `lib/domain/review/answer_evaluator.dart` | 客观题答错降级 AGAIN，主观题采信自评 |
| 熟练度 | `lib/domain/review/mastery.dart` | 六分项加权 + 可提取性衰减 |
| 题型选择 | `lib/domain/review/question_type.dart` | 模式 × 位置 × 熟练分分层 |
| 自适应插题 | `lib/domain/review/question_type.dart`、`lib/services/review_service.dart` | 首次错隔 5 题、二次错隔 10 题，每词每会话上限 2 |
| 提示与答案 diff | `lib/domain/review/{hint,answer_diff}.dart` | 阈值由调用方传入，领域层不内嵌数值 |
| 候选抽题 | `lib/domain/review/candidate_selection.dart` | 三池加权、新词软上限、交错配比 |
| 错词状态 | `lib/domain/review/wrong_state.dart` | 按**自然日**累加连对，同一天刷题不解除 |
| FSRS 适配 | `lib/services/fsrs_scheduler.dart` | 包裹 `package:fsrs`，关闭 fuzz 保证预览确定 |
| 题目载荷 / 选项生成 | `lib/domain/review/question_payload.dart`、`lib/services/question_builder.dart` | 打乱、挖空、字母块；易混词 → 活跃错词 → 全局池三级回退 |
| 复习 / 学习 DAO | `lib/data/db/daos/{review_dao,study_dao}.dart` | 幂等查询、认领题目、卡片与日志、候选池 SQL、插题位置 |
| 作答流水线 | `lib/services/review_service.dart` | 单事务：判题 → FSRS → 日志 → 统计 → 错词 → 熟练度 → 插题 → 收尾 |
| 会话编排 | `lib/services/study_service.dart` | 开始/恢复会话、跳过、每日计划 |
| 设置 | `lib/domain/models/app_settings.dart`、`lib/services/settings_service.dart` | 按 tab 分组、未建模键原样保留 |

### 3.4 服务与后台

| 模块 | 位置 | 要点 |
|---|---|---|
| 初始化后台维护 | `lib/services/initialization/**`、`lib/app/maintenance_bootstrap.dart` | 启动回收 RUNNING、失败回收入队、每 10 分钟推进一批、重入保护；队列页另有「立即处理一批」 |
| 词典管线 | `lib/services/dictionary/**`、`lib/data/dictionary/**` | 多数据源降级链、提前终止质量分、调用记录落 `provider_attempts` |
| LLM 客户端 | `lib/services/llm/**` | 候选链、超时与 token 边界、连通性探测 |
| 内容补全与翻译 | `lib/services/initialization/supplemental_tasks.dart` | 释义 → 摘要 → 例句三段；写库前重读最新 JSON；按 `translationBatchLimit` 分批 |
| 词条写入 | `lib/services/word_edit_service.dart` | 创建/改名/覆盖内容/暂停/笔记/删除/入队（活跃任务升级而非丢弃） |
| 进度重置 | `lib/services/learning_progress_reset.dart` | CSV 与文章导入共用；与词条写入同事务 |
| 朗读 | `lib/services/audio/**` | 真人录音优先 + 系统朗读兜底、本地 LRU 音频缓存（200 条）、可测的引擎抽象 |
| 导入 | `lib/services/{csv_import_service,article_import/**,manual_preview_service}.dart` | 三种 CSV 策略 + 批次撤销、文章 AI 选词、手动批量预览 |
| 备份 | `lib/services/backup*/**` | JSON 导出/导入，平台差异走条件导入 |
| 每日建议 | `lib/services/suggestion_service.dart` | 按天缓存、质量分 |

### 3.5 界面

| 模块 | 位置 |
|---|---|
| 学习会话页 | `lib/features/study/**`（19 个组件） |
| 词条详情页 | `lib/features/word_detail/**`（13 张卡片 + 5 个弹窗 + 顶部操作栏） |
| 单词本 | `lib/features/words/**` |
| 仪表盘 | `lib/features/dashboard/**` |
| 统计页 | `lib/features/statistics/**` |
| 添加页（离线手填 / 词典批量预览 / 粘贴文章） | `lib/features/add/**` |
| CSV 导入页 | `lib/features/import/**` |
| 初始化队列页 | `lib/features/initialize/**` |
| 设置页（6 个 tab） | `lib/features/settings/**` |
| 游戏 / 配对 / 音标 | `lib/features/{games,match,phonetics}/**` |

逐条功能对照见 [`FLUTTER_PARITY.md`](FLUTTER_PARITY.md)（78 条能力 + 5 条刻意舍弃 + 已知差异）。

---

## 4. 迁移中修正的旧版缺陷

这些是重写时**有意偏离**旧版的地方，每条都有注释与测试钉住：

1. **自适应插题的首次延迟是死代码**：旧版用「本词已 ANSWERED 的题目数」判断是第几次错，
   但认领当前题时它已被置为 ANSWERED，计数永远 ≥1，导致「首次错隔 5 题复现」永不生效、
   每词每会话最多只插一道题。本版改为统计**本次之前**的作答次数。
2. **`questionFor` 的分支顺序把「错词任务」盖掉了**：旧版 `taskType === "WRONG"`
   优先于 `mode === "DAILY"`，按模式分支书写会先命中 DAILY。本版按旧版判定顺序书写，
   并在注释里说明顺序是语义的一部分。
3. **`study_sessions.session_type` 的 PG CHECK 只有 6 个值**，而代码会写入 8 种
   （`SENTENCE_REVIEW`、`AI_RECOMMENDED` 会被拒绝）。本版 `session_type` 记实际使用的
   模式、真实来源放 `source_type`。
4. **`max_attempts` 有两个来源**（设置算出 2、导入路径硬编码 5）。本版统一由设置推导。
5. **`WORKER_STALE_AFTER_MS = 30_000` 未被使用**（实际是 10 分钟）。本版单进程启动时全量重置 RUNNING。
6. **空 catch 与字符串判错**（`error.message === "WORD_NOT_FOUND"` 约 15 处）。
   本版用 sealed `AppError` + 错误码枚举，并有守卫测试禁止回归。
7. **`FSRS` 实例的全局缓存无上限**。本版改为调用方持有实例。
8. **干扰项池是模块级可变全局变量**。本版每次按需查询。
9. **腾讯翻译 provider 需要把 SecretKey 内嵌进客户端**，本版放弃该 provider（见对照表 §11）。
10. **`target_language` 用 `zh-CN` 而不是 `zh`**。真实备份（1417 词条）里
    `words.target_language` 与 `definitions_json[].language` 全是 `zh-CN`；
    若语言映射写成裸 `zh`，手动添加的词条释义会永远匹配不上。
11. **`word_contents` 各 JSON 列的解析在两个 DAO 里各写了一份**（约 300 行重复）。
    本版抽到 `lib/domain/dictionary/content_parse.dart`，并用 27MB 生产备份逐列核对了
    真实键名（`phrases_json` 用 `phrase`、`forms_json` 用 `type`+`value`、
    `tags_json` 是纯字符串数组、`summary/learning/sentence_analysis` 是对象而非数组）。
12. **计分权重在旧版分散在三处**（`games/completion.ts`、`matching/service.ts`、
    `games/service.ts`）。本版收敛到 `lib/domain/games/game_mode.dart` 的模式规则表。
13. **学习页交互顺序**：旧版是「先作答 → 再选四档自评（选了即提交）」。中途实现曾做成
    「确认提交 → 再展示只读的已记录等级」，导致用户无法在客观题上表达「模糊 / 简单」；
    已改回旧版顺序。
14. **`enqueueInitialization` 的 `ON CONFLICT DO NOTHING`** 会让详情页「重新生成」在已有
    排队任务时点了没反应。本版改为按强弱**升级**已有活跃任务、优先级只升不降。
15. **例句翻译会覆盖并发写入**：旧版直接回写任务开始时的数组。本版三段翻译都在写库前
    重读最新 JSON。
16. **释义译文按下标配对**：模型重排或漏译时旧写法会把译文贴到别的释义上。本版按原文文本配对。
17. **列表页的到期排序**把没有复习卡的词条排在最前（`NULL` 在 `DESC` 里最大）。本版显式
    「有卡的在前、无卡的在后」。

---

## 5. 未验证项与已知风险

诚实清单——**这些不是「已完成」**：

1. **Android 端未做实机验证**。`flutter doctor --android-licenses` 尚未接受；`INTERNET`
   权限与 `minSdk 26` 已配好，但没有在真机上跑过。
2. **词典 provider 没有真实网络联调**。解析器只用旧版单测的 fixture 验证过；有道与
   爱词霸的页面结构会变，接线后需要真机联网跑一次。
3. **Web 端的数据源抓取受同源策略限制**（有实测结论，见
   [`FLUTTER_WEB.md`](FLUTTER_WEB.md)）：有道与爱词霸被挡、抛 `BROWSER_CORS_BLOCKED`；
   `dictionaryapi.dev` 的 CORS 状态因本机网络不可达**未能测定**。
4. **Web 端朗读未实测**：`flutter_tts` 有 web 实现，编译通过、能力位正确，但没有验证实际发音。
5. **Web 端有一条控制台断言**（`Bad state: RenderBox was not laid out`，窗口获得焦点时
   由根 `Focus(autofocus: true)` 触发）。应用功能不受影响，根因与影响面见
   [`FLUTTER_WEB.md`](FLUTTER_WEB.md)。
6. **`flutter run -d chrome` 在无 Chrome 的机器上无法附加调试器**（DWDS 握手失败）；
   同一 debug 构建在 `flutter run -d web-server` 下正常。请在装了 Chrome 的机器上复跑确认。
7. **测试覆盖不均**：界面测试集中在学习页、详情页、单词本、仪表盘、导入、设置、初始化队列；
   游戏与音标的**界面**测试较少（规则与状态机测试较全）。
8. **`streakDays`** 用 `SELECT DISTINCT date(...)` 后在 Dart 里倒推，未设回看窗口；
   个人库量级没问题，日志过百万时需加窗口。
9. **中文字形依赖 `fonts.gstatic.com`**（CanvasKit 按需下载 Noto Sans SC 分片）。
   内网/离线部署可用 `--dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/` 让 CanvasKit
   走本地拷贝，**字体没有等价的本地化开关**。
10. **`word_contents` 的 JSON 键名**已用真实备份核对，但备份只有 1417 个词条；
    换数据源后需重新核对。

---

## 6. 与旧版的刻意差异

见 [`FLUTTER_PARITY.md`](FLUTTER_PARITY.md)：

- §11 刻意舍弃（5 条，有明确理由，不算缺口）
- §12 已知差异（形态不同或选择不做）

---

## 7. 如何验证

```bash
cd /Users/leo/Documents/code/LexiLoop

# 门禁
dart format --set-exit-if-changed lib test
dart analyze --fatal-infos --fatal-warnings lib test
flutter test
flutter test test/architecture

# 构建
flutter build macos --debug
flutter build web --release

# 跑起来
flutter run -d macos
flutter run -d chrome          # 需要本机有 Chrome
```

Web 产物的静态托管注意：`.wasm` 必须以 `application/wasm` 提供，否则 drift 起不来；
**不强制** COOP/COEP（不带跨源隔离时 drift 自动退到 IndexedDB，持久化照常工作）。

---

## 8. 相关文档

| 文档 | 内容 |
|---|---|
| [`FLUTTER_PARITY.md`](FLUTTER_PARITY.md) | 与旧版逐条功能对照（判定基准） |
| [`FLUTTER_WEB.md`](FLUTTER_WEB.md) | Web 目标：构建、托管、CORS 实测结论、已知限制 |
| [`FLUTTER_MIGRATION_REPORT.md`](FLUTTER_MIGRATION_REPORT.md) | 迁移可行性评估（外部服务清单、各层难度、双端差异） |
| [`FLUTTER_MIGRATION_UI_AUDIT.md`](FLUTTER_MIGRATION_UI_AUDIT.md) | 旧版界面复杂度审计 |
| [`ARCHITECTURE_BASELINE.md`](ARCHITECTURE_BASELINE.md) | **旧版**分层与模块边界（迁移对照基准） |
| [`CLEAN_CODE_BASELINE.md`](CLEAN_CODE_BASELINE.md) | **旧版**整洁度整改清单（架构守卫的由来） |
