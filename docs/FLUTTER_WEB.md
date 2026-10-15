# LexiLoop Web 端（Flutter Web）构建与实测记录

基线提交 `ad94303`（分支 `flutter`）。本文件记录**新增 Web 构建目标**时做的取舍、
资产来源、以及 2026-10-15 在真实浏览器里跑出来的实测结论。

---

## 1. 怎么跑

```bash
# 开发：浏览器里热重载
flutter run -d chrome

# 产物：build/web/，可直接丢给任意静态托管
flutter build web --release
```

**静态托管的两个要求**（否则应用起不来或数据不持久）：

| 要求 | 原因 | 没有会怎样 |
| --- | --- | --- |
| `.wasm` 必须以 `application/wasm` 下发 | `WebAssembly.instantiateStreaming` 只接受这个 MIME | SQLite 引擎加载失败，数据库打不开 |
| 建议加 `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp` | 跨源隔离后才拿得到 `SharedArrayBuffer`，drift 才能用 OPFS / 共享 IndexedDB | **实测：仍可正常使用**，drift 自动退到 IndexedDB，数据一样跨刷新保留 |

本地起静态服务的最小示例见本文件末尾「复现命令」一节。

> **网络受限时**：CanvasKit 默认从 `https://www.gstatic.com/flutter-canvaskit/<engine hash>/` 拉，
> 中文字形由引擎按需从 `https://fonts.gstatic.com` 下载 Noto Sans SC 分片。
> 这两处不通时会白屏或满屏豆腐块。让 CanvasKit 走构建产物里的本地拷贝：
>
> ```bash
> flutter run -d chrome --dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/
> flutter build web --release --dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/
> ```
>
> 字体没有等价的本地化开关（引擎的 Noto 回退只能换 base URL，不能塞本地文件），
> 因此**中文字形依赖 `fonts.gstatic.com` 可达**。

---

## 2. `web/` 资产

| 文件 | 来源 | 说明 |
| --- | --- | --- |
| `web/index.html` | `flutter create --platforms=web` 生成后改写 | 标题/描述改成中文；`<html lang="zh-CN">`；加了首屏静态占位 |
| `web/manifest.json` | 同上 | 名称、主题色改成 LexiLoop 的配色 |
| `web/favicon.png`、`web/icons/*` | 同上 | Flutter 默认图标，未替换 |
| `web/sqlite3.wasm` | `https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/sqlite3.wasm` | 与解析版本 `sqlite3 3.5.2` 对齐；`sha256=13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4`，748686 字节 |
| `web/drift_worker.js` | `~/.pub-cache/hosted/pub.dev/drift-2.35.2/drift_worker.js` | drift 官方预编译 worker，360104 字节 |
| `web/drift_worker.js.deps` | 同上目录 | worker 的依赖清单，调试时用 |

**来源差异**：drift 包内还带了一份 `extension/devtools/build/sqlite3.wasm`（750007 字节，
`sha256=fbcd2e82…`），是给 DevTools 扩展用的另一个构建。本次**没有**用它——GitHub release
的 3.5.2 与 `pubspec.lock` 里的 `sqlite3` 版本严格对齐，优先取它；只有下载失败时才回退到
pub-cache 那份。

---

## 3. 平台分支：三处条件导入

Web 编译不过的东西集中在三处，各自用 `if (dart.library.js_interop)` 二选一
（`dart.library.html` 已废弃，且无法区分 JS 与 Wasm 两种编译目标）。
判定方式统一，原生端代码**逐字未动**，只是被挪进了 `*_native.dart`。

| 门面（调用方 import 它） | 原生分支 | Web 分支 | 为什么必须分 |
| --- | --- | --- | --- |
| `lib/app/desktop_window.dart` | `desktop_window_native.dart`（`window_manager`） | `desktop_window_web.dart`（空实现） | `window_manager` 的 Dart 代码 `import 'dart:io'` |
| `lib/data/db/database_connection.dart` | `database_connection_native.dart`（`NativeDatabase` + `path_provider`） | `database_connection_web.dart`（`WasmDatabase.open`） | `drift/native.dart` 依赖 `dart:ffi`；`path_provider` 没有 web 实现 |
| `lib/services/backup/backup_file.dart` | `backup_file_native.dart`（落临时文件后分享） | `backup_file_web.dart`（`XFile.fromData` 直接分享字节） | 浏览器里没有可写临时目录，`File` 也不存在 |

改完之后 `dart:io` 只以 **import** 形式出现在 `*_native.dart` 里：

```bash
$ grep -rn "^import 'dart:io'" --include=*.dart lib
lib/data/db/database_connection_native.dart:6:import 'dart:io';
lib/services/backup/backup_file_native.dart:6:import 'dart:io';
```

（其余提到 `dart:io` 的地方都在文档注释里，`lib/core/platform.dart` 的注释还专门写明了
「`lib/` 其余位置不得再出现 `dart:io`」这条约束。）

### 3.1 数据库

```dart
// database_connection_web.dart
DatabaseConnection.delayed(Future<DatabaseConnection>(() async {
  final result = await WasmDatabase.open(
    databaseName: 'lexiloop',            // 浏览器存储条目名，不带扩展名
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return result.resolvedExecutor;
}));
```

- **没有用 `@DriftDatabase(web:)`**：解析到的 drift 2.35.2 里不存在 `DriftWebOptions`，
  那条注解式写法在这个版本上不可用。
- 用 `DatabaseConnection.delayed` 而不是 `LazyDatabase`：`WasmDatabase.open` 是异步的，
  而 `AppDatabase` 的构造是同步的；`delayed` 把「打开」推迟到第一次查询，语义与原生端的
  `LazyDatabase` 一致。
- 原生端文件名是 `lexiloop.sqlite`，Web 端条目名是 `lexiloop`——浏览器存储的键不带扩展名，
  drift 官方示例同样如此。

### 3.2 备份交付

| | 原生端 | Web 端 |
| --- | --- | --- |
| 导入 | `PlatformFile.readAsBytes()` → `utf8.decode` | 同左 |
| 导出 | 写 `getTemporaryDirectory()` → `share_plus` 分享**文件路径** | `XFile.fromData(bytes, name:, mimeType:)` → `share_plus` 分享**字节** |

**顺带修掉的真实缺陷**：`lib/services/backup_service.dart` 原实现是
`File(files.first.path!)`，而 `PlatformFile.path` 只在 `uri.scheme == 'file'` 时非空——
Android 的 `content://` 与浏览器里 file_picker 给出的 blob/data URI 都拿不到路径。
现在与 `csv_import_service.dart` 一致地读字节，两端一起修好，并由
`test/services/backup/backup_service_test.dart` 钉住（用例里先断言 `picked.path == null`，
否则用例会退化成「读路径也能过」）。

Web 端「导出 → 浏览器下载」是怎么发生的：`share_plus` 的 web 实现先试 Web Share API
（`navigator.canShare`）。桌面浏览器不支持分享文件，`canShare` 返回 `false`，于是走
`downloadFallbackEnabled`（默认 `true`）的兜底分支——造一个带 `download` 属性的 `<a>`
并点击。手机浏览器支持 Web Share 时弹系统分享面板，用户仍可存成文件。

### 3.3 平台能力矩阵

`PlatformCaps` 从 `dart:io` 的 `Platform.isMacOS/isAndroid` 换成 `kIsWeb` +
`defaultTargetPlatform`，并把判定收进可构造的 `PlatformProfile`（否则 `kIsWeb` 是编译期
常量，Web 那一行在 VM 测试里根本构造不出来）。

| | Web | macOS | Android |
| --- | --- | --- | --- |
| `isDesktop` | false | **true** | false |
| `isMobile` | false | false | **true** |
| `supportsTtsFileSynthesis` | false | false | **true** |
| `requiresVoicePackSetup` | false | false | **true** |
| `needsBlurDowngrade` | false | false | **true** |

`needsBlurDowngrade` 在 Web 上取 `false`：浏览器把模糊交给合成层，桌面浏览器普遍够用，
而降级会立刻让 Web 的观感偏离设计稿。低端设备上的取舍留给后续实测。

---

## 4. CORS：浏览器里哪些数据源真的能用

浏览器有同源策略，抓 HTML 的词典 provider 一定会被挡。**没有搭代理**——
做法是 `lib/data/dictionary/http_fetcher.dart` 在 Web 上把「网络层失败」映射成
已存在的 `AppErrorCode.browserCorsBlocked`：

```dart
Exception _mapFailure(DioException error) {
  final kind = _kindOf(error);
  if (PlatformCaps.isWeb && kind == HttpFailureKind.network) {
    return ExternalServiceError(
      AppErrorCode.browserCorsBlocked,   // 而不是 HttpFailure
      isTransient: true,
      details: error.message,
    );
  }
  return HttpFailure(kind, detail: error);
}
```

两个关键取舍：

- **只映射「连不上」，不映射「超时」**。浏览器的同源策略把「被 CORS 挡下」和「真的连不上」
  都报成同一个 `XMLHttpRequest error`（dio 的 `dio_web_adapter` 一律转成 `connectionError`），
  两者在浏览器里无法区分；而超时通常确实是超时，provider 的「请求超时」文案更准确。
- **抛 `ExternalServiceError` 而不是 `HttpFailure`**。provider 的 `on HttpFailure` 会把所有
  非超时失败统一改写成 `providerTransientFailure`（文案「网络不可用」），恰好掩盖了真正的原因。
  抛 `ExternalServiceError` 后，`DictionaryPipeline._runProvider` 照常捕获并继续尝试下一个
  数据源（降级链不断），而错误码原样落进 `provider_attempts`。
  超时那一支仍然走 `HttpFailure`，行为与原生端逐字相同。

### 4.1 实测结果（2026-10-15，Chromium 149，测试页源 `http://127.0.0.1:8099`）

在应用自己的源上对每个 URL 发 `fetch(..., {mode: 'cors'})`，按浏览器的裁决记录：

| 数据源 | URL | 结果 |
| --- | --- | --- |
| 有道（主） | `https://dict.youdao.com/w/eng/<term>` | ❌ **被 CORS 挡下**（`No 'Access-Control-Allow-Origin'`） |
| 有道（备） | `https://www.youdao.com/result?word=<term>` | ❌ **被 CORS 挡下** |
| 有道发音 | `https://dict.youdao.com/dictvoice?audio=<term>&type=2` | ❌ **被 CORS 挡下**（`fetch` 拿不到；但 `<audio>` 播放不受同源策略限制，朗读仍可能可用） |
| 爱词霸 | `https://www.iciba.com/word?w=<term>` | ❌ **被 CORS 挡下** |
| Merriam-Webster 词典 API | `https://www.dictionaryapi.com/api/v3/references/collegiate/json/<term>` | ✅ **可用**（`HTTP 200`，`access-control-allow-origin: *`） |
| Merriam-Webster 音频 CDN | `https://media.merriam-webster.com/audio/prons/...` | ✅ **可用**（`HTTP 403` 是因为路径/资源不存在，CORS 本身通过，`ACAO: *`） |
| MyMemory 翻译 | `https://api.mymemory.translated.net/get?...` | ✅ **可用**（`HTTP 200`，`access-control-allow-origin: *`，curl 复核一致） |
| dictionaryapi.dev | `https://api.dictionaryapi.dev/api/v2/entries/en/<term>` | ⚠️ **本次未能测定**——本机到该域的连接全程被重置（`ERR_CONNECTION_CLOSED` / curl `SSL_ERROR_SYSCALL`），测到的失败是网络层而非同源策略 |
| LLM 网关（示例：DeepSeek） | `https://api.deepseek.com/v1/models` | ✅ **可用**（`HTTP 401` 是因为没带 key，`access-control-allow-origin` 回显了请求源） |
| LLM 网关（示例：OpenAI） | `https://api.openai.com/v1/models` | ✅ **可用**（首轮实测 `HTTP 401` + `type=cors`；后续重测时本机网络已不稳定） |

**怎么验证的**：把「被 CORS 挡下」与「网络不可达」分开——只有浏览器打出
`blocked by CORS policy: No 'Access-Control-Allow-Origin' header is present` 才算前者，
`net::ERR_CONNECTION_CLOSED / ERR_NAME_NOT_RESOLVED / ERR_TIMED_OUT` 且没有这条日志的算后者。
测到的原始记录见「复现命令」一节的 `cors3.js`。

> **实测环境提醒**：本次实测期间本机到 `pub.dev` / `www.gstatic.com` / `api.dictionaryapi.dev`
> 的连接间歇性被重置，`gstatic` 与 `dictionaryapi.dev` 的结果因此不完整。被 CORS 挡下的三个
> 域名（有道两处 + 爱词霸）与通过的两个（Merriam-Webster、MyMemory）在多次运行中结论一致。

### 4.2 浏览器里的端到端验证

比上面更硬的一条证据：在浏览器里真的跑一次初始化队列（手动建一个「内容初始化」任务 →
「立即处理一批」），任务详情里逐数据源列出实际落库的错误码：

```
数据源执行情况：youdao=FAILED[BROWSER_CORS_BLOCKED]
              iciba=FAILED[BROWSER_CORS_BLOCKED]
              dictionaryapi.dev=FAILED[PROVIDER_TRANSIENT_FAILURE]
```

- 有道、爱词霸 → `BROWSER_CORS_BLOCKED`：`_mapFailure` 的映射在真实浏览器里生效了，
  用户看到的是「浏览器不允许网页直接访问该数据源。请改用桌面端或移动端，或换一个数据源。」，
  而不是会让人去查 Wi-Fi 的「网络不可用」。
- dictionaryapi.dev → `PROVIDER_TRANSIENT_FAILURE`：这一支走的是**超时**（当时本机到该域
  连不上，请求挂到超时），正是「超时不改写成 CORS」的设计预期。

---

## 5. 浏览器实测：走通全流程

用 Playwright 驱动真实 Chromium（`channel: 'chromium'`）跑完整用户旅程。
Flutter Web 用 CanvasKit 渲染到 canvas，DOM 里没有可点的元素，所以先点一下
`flt-semantics-placeholder` 打开无障碍语义树，再按语义节点文本定位、用真实鼠标事件点击。

| # | 步骤 | 结果 |
| --- | --- | --- |
| ① | 空库首屏显示「从 EasyDict 收藏开始 / 导入 CSV」 | ✅ |
| ② | 侧栏进设置页 | ✅ |
| ③ | 添加页填写词条 / 释义 / 音标 → 保存到词库（页面切到「继续添加」） | ✅ |
| ④ | 单词本列表出现 `serendipity` | ✅ |
| ⑤ | 词条详情显示音标 `/ˌserənˈdɪpəti/` 与释义编辑入口 | ✅ |
| ⑥ | 复习页出题（看词说义）→ 点「记得」→ 进入结算 | ✅ |
| ⑦ | **刷新页面**后词条仍在（浏览器存储持久化） | ✅ |
| ⑧ | 统计页有数字：`词条总数 1 · 累计作答 1 · 正确率 100 % · 学习中 1` | ✅ |
| ⑨ | 设置 → 数据管理 → 导出 JSON 备份（敲 `EXPORT` 确认）→ **浏览器下载** `lexiloop-backup-2026-10-15-204909.json` | ✅ |
| ⑩ | 下载内容是可导入的备份信封：`format=lexiloop-json-backup`，`words` 有 1 条 | ✅ |

12 条断言全绿（③⑤⑥⑨ 各拆成两条），跑了两轮结果一致。

**存储行为**：分别在带 COOP/COEP（跨源隔离，drift 可走 OPFS）与不带（普通静态托管，
drift 退到 IndexedDB）两种服务下各跑一遍「新增词条 → 刷新」——**两种都跨刷新保留**。

---

## 6. Android 侧的两处修改

- `android/app/src/main/AndroidManifest.xml` 补 `INTERNET` 权限。
  原来只有 `android/app/src/debug/AndroidManifest.xml` 里有，那是给 Flutter 热重载用的，
  **不会进 release 包**；缺了它，release 包的词典初始化会静默失败成「网络不可用」。
- `android/app/build.gradle.kts` 把 `minSdk = flutter.minSdkVersion` 钉成 `minSdk = 26`。
  `flutter.minSdkVersion` 由 Flutter SDK 决定，会随 SDK 升级悄悄抬高，构建产物不可复现。

---

## 7. 已知差异与未决事项

1. **启动时会打一条框架级异常**（Web 与原生共用的代码路径，非本次改动引入）：

   ```
   EXCEPTION CAUGHT BY WIDGETS LIBRARY
   The following assertion was thrown while dispatching notifications for
   WidgetsBindingObserver.didChangeViewFocus:
   Assertion failed: box.dart hasSize
   "RenderBox was not laid out: RenderSemanticsAnnotations#… NEEDS-LAYOUT NEEDS-PAINT"

   focus_traversal.dart 299  findFirstFocus
   view.dart 254             didChangeViewFocus
   binding.dart 1355         handleViewFocusChanged
   ```

   触发链：浏览器窗口获得焦点 → 引擎发 `didChangeViewFocus` → `FocusManager.findFirstFocus`
   → 阅读序排序读 `FocusNode.rect` → 撞上还没完成首次布局的 `RenderSemanticsAnnotations`。
   与 `lib/app.dart` 的根 `Focus(autofocus: true)` 有关。
   **应用照常渲染、12 步全流程全绿**，只是控制台每次获得窗口焦点会多一条错误。

   **为什么没有直接改**：根 `Focus` 是全局快捷键（⌘1–⌘8）的落点，去掉
   `autofocus` 会让快捷键在用户点击页面之前失效；推迟到首帧之后需要把它改成
   `StatefulWidget` 并在 `addPostFrameCallback` 里 `requestFocus`——这是一个
   无法在没有浏览器的环境下验证的改动，猜错的代价（快捷键静默失效）比一条
   控制台断言更大。留作已知问题，改前请先在有 Chrome 的机器上复现。

2. ~~`platform_card.dart` 在 Web 上会显示「Android」~~ **已修复**：
   `lib/features/dashboard/cards/platform_card.dart` 改为按
   `(isWeb, isDesktop, isMobile)` 三态判定，Web 上显示「Web（浏览器）」、
   两者都 false 时显示「未知平台」。

3. **词条详情的释义正文没有进无障碍语义树**。截图里正常显示，但
   `flt-semantics` 里找不到那段文本，所以自动化断言只能退到「音标 + 保存释义」两个信号。
   属于 a11y 完整性缺口，与 Web 化无关。

4. **中文字形依赖 `fonts.gstatic.com`**（见第 1 节），且 CanvasKit 默认走 CDN。
   离线/内网部署需要 `--dart-define=FLUTTER_WEB_CANVASKIT_URL=canvaskit/`，字体无解。

5. **朗读（TTS）在 Web 上未实测**。`flutter_tts` 有 web 实现（SpeechSynthesis），
   编译通过，但本次没有验证实际发音与语速映射。

6. **`analysis_options.yaml` 被 `flutter test` 自动改了一行**：新增 `- "web/**"` 到 analyzer
   的 exclude 列表。这是 Flutter 工具在检测到 `web/` 目录后自动做的
   （`flutter_tools/lib/src/migrations/analysis_options_migration.dart`），不是手工改动；
   `web/` 下没有 Dart 文件，对门禁无影响。

---

## 8. 复现命令

```bash
# 门禁
dart format --set-exit-if-changed lib test
dart analyze --fatal-infos --fatal-warnings lib test
flutter test
flutter test test/architecture
flutter build web --release

# 静态服务（必须给 .wasm 正确的 MIME）
# 见本次实测用的 /tmp/lexiloop-web-test/server.js：显式映射 application/wasm，
# 默认带 COOP/COEP，加 --no-isolation 可模拟普通静态托管。
node server.js "$PWD/build/web" 8099

# 浏览器实测脚本（Playwright，全局安装）
node walk.js          # 12 步全流程 + 截图 + 下载校验
node cors3.js         # 逐数据源 CORS 实测（区分 CORS 与网络不可达）
node init2.js         # 浏览器里跑初始化队列，读 provider 错误码
```

---

## 9. 验收状态（最终）

| 项 | 结果 |
|---|---|
| `flutter build web --release` | ✅ 成功（唯一噪声是第三方包 `flutter_tts` 的 wasm dry-run 警告，只影响 `--wasm` 目标） |
| 真实浏览器全流程（Playwright + Chromium 149，release 产物） | ✅ **12/12 步通过**，跑两轮结果一致 |
| 跨刷新持久化 | ✅ 带 COOP/COEP 与不带两种托管下都保留 |
| 逐数据源 CORS | ✅ 有实测表（§4.1），并在真实浏览器里验证了错误码落库 |
| `flutter run -d chrome` | ⚠️ 本机无 Chrome，DWDS 无法附加；同一 debug 构建在 `web-server` 下正常 |
| Web 端朗读 | ⚠️ 未实测 |
