# LexiLoop 词环

纯本地的词汇复习应用。**不依赖任何自建服务端**：数据库、间隔重复引擎、
任务队列、词典抓取与 AI 调用全部跑在客户端，数据只存在本机。

- 双端目标：**macOS**（桌面）与 **Android**（移动）；另有 **Web** 构建用于在
  浏览器里自测（见下文「Web 构建的已知限制」）。
- 迁移来源：本项目由一套 Next.js + PostgreSQL 的实现迁移而来。旧版在
  `main` 分支（`src/`），新版在 `flutter` 分支（`lib/`），两者不共存。
  功能对照见 [`docs/FLUTTER_PARITY.md`](docs/FLUTTER_PARITY.md)。

## 跑起来

```bash
flutter pub get

# macOS
flutter run -d macos

# Android（需要先接受许可：flutter doctor --android-licenses）
flutter run -d <device-id>

# 浏览器（自测用）
flutter run -d chrome
```

## 门禁（提交前必须全绿）

```bash
dart format --set-exit-if-changed lib test
dart analyze --fatal-infos --fatal-warnings lib test
flutter test
flutter test test/architecture
flutter build macos --debug
```

`test/architecture/architecture_test.dart` 是一组**结构守卫**（不是行为测试）：
分层边界、函数与 `build()` 的行数上限、构造参数个数、空 `catch`、字符串判错、
`lib/domain` 与 `lib/services` 的裸数字、`dart:io` 只允许出现在 `*_native.dart`。
它们把 [`docs/CLEAN_CODE_BASELINE.md`](docs/CLEAN_CODE_BASELINE.md) 记录过的
旧版问题类型变成了自动化约束，而不是靠人工评审。

## 分层

| 目录 | 职责 | 约束 |
|---|---|---|
| `lib/core` | 常量唯一出处、错误类型、平台能力、日期工具 | 不依赖业务层 |
| `lib/domain` | 纯逻辑：判题、FSRS 适配、熟练度、抽题、题型、分段、diff | **纯 Dart**，不得引入 Flutter / drift / dio / `dart:io` |
| `lib/data` | Drift 表与 DAO、词典 provider、导入解析 | 只有这里能碰数据库与网络 |
| `lib/services` | 编排：会话、作答流水线、初始化 worker、导入、备份、朗读 | 不出现裸数字字面量 |
| `lib/features` | 界面（按页面分目录，页面内按职责拆组件） | `build()` ≤ 80 行 |
| `lib/ui` | 液态玻璃视觉系统、自适应外壳、导航目的地 | — |

**平台差异只允许经由条件导入**：`lib/core/platform.dart`（能力矩阵）、
`lib/data/db/database_connection.dart`、`lib/app/desktop_window.dart`、
`lib/services/backup/backup_file.dart`。调用方 import 不带后缀的那个文件，
由它 `export ... if (dart.library.js_interop) ...` 选中实现。

## 数据

- **Drift（SQLite）15 张表**，与旧版 PostgreSQL 逐列对齐
  （`test/data/db/column_names_test.dart` 强制）。原生端落在应用支持目录，
  Web 端落在浏览器存储（IndexedDB / OPFS）。
- 备份导入/导出是 JSON，12 张表按父子序导入。
- **恢复备份后必须失效缓存**：新增任何会读库的顶层 provider，都要登记到
  `lib/features/settings/data_invalidation.dart` 的 `dataBackedProviders`，
  否则恢复后该页面会显示导入前的快照。

## Web 构建的已知限制

Web 端只用于**自测与验收**，不是主要交付形态：

1. **同源策略**：抓 HTML 的词典数据源（有道 / 爱词霸 / Merriam-Webster）在
   浏览器里会被 CORS 挡下。代码会抛 `AppErrorCode.browserCorsBlocked`
   （文案提示改用桌面/移动端），而不是伪装成「网络不可用」。
   `dictionaryapi.dev` 与 MyMemory 带 CORS 头，Web 端可用；LLM 网关取决于
   它自己是否发 CORS 头。
2. `window_manager` 在 Web 上不存在，桌面窗口配置走条件导入跳过。
3. 导出备份在 Web 上走浏览器下载（`share_plus` 的 web 实现）。

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/FLUTTER_MIGRATION_STATUS.md`](docs/FLUTTER_MIGRATION_STATUS.md) | 迁移进度清单（已完成 / 进行中 / 待办） |
| [`docs/FLUTTER_PARITY.md`](docs/FLUTTER_PARITY.md) | 与旧版逐条功能对照：已对齐 / 刻意舍弃 / 已知差异 |
| [`docs/FLUTTER_MIGRATION_REPORT.md`](docs/FLUTTER_MIGRATION_REPORT.md) | 迁移可行性评估：外部服务清单、各层难度、双端差异 |
| [`docs/FLUTTER_MIGRATION_UI_AUDIT.md`](docs/FLUTTER_MIGRATION_UI_AUDIT.md) | 旧版界面复杂度审计 |
| [`docs/ARCHITECTURE_BASELINE.md`](docs/ARCHITECTURE_BASELINE.md) | **旧版**分层与模块边界（迁移对照基准） |
| [`docs/CLEAN_CODE_BASELINE.md`](docs/CLEAN_CODE_BASELINE.md) | **旧版**整洁度整改清单（架构守卫的由来） |
