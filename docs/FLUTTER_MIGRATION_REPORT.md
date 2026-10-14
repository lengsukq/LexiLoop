# LexiLoop → 纯 Flutter 客户端 迁移难度评估

> 调查对象：`/Users/leo/Documents/code/LexiLoop`（Next.js 16 + React 19 + PostgreSQL）
> 结论先行：**外部服务层本身迁移难度不高（多为 HTTP/JSON + WebSocket），真正的迁移成本在「数据库 / 任务队列 / 后台定时」这三块服务器基础设施上。**

---

## 0. 总览：外部服务清单

| # | 外部服务 | 协议 | 需要 Key | 服务端必要性 |
|---|---------|------|---------|------------|
| 1 | LLM 网关（OpenAI 兼容 / Anthropic） | HTTPS | ✅ | 无 |
| 2 | 有道词典网页（HTML 抓取） | HTTPS | ❌ | 无 |
| 3 | 金山词霸 iciba（HTML 抓取） | HTTPS | ❌ | 无 |
| 4 | Merriam-Webster dictionaryapi.com | HTTPS | ✅ | 无 |
| 5 | dictionaryapi.dev | HTTPS | ❌ | 无 |
| 6 | MyMemory 翻译 | HTTPS | ❌ | 无 |
| 7 | 腾讯云 TMT 翻译 | HTTPS + TC3-HMAC-SHA256 签名 | ✅ | 无 |
| 8 | Edge TTS（`node-edge-tts` → Bing WebSocket） | **WSS** | ❌ | 无 |
| 9 | 有道发音 `dictvoice` | HTTPS | ❌ | 无 |
| 10 | PostgreSQL + 服务端 Worker/Cron | — | — | **需重构** |

---

## 1. LLM 调用 — 迁移难度：**中**

### 1.1 支持的 provider

只有 **两种 API 协议**（`src/modules/llm/client.ts:8`）：

```ts
apiType: "openai" | "anthropic"
```

- **OpenAI 兼容**：POST `{baseUrl}/chat/completions`，`Authorization: Bearer {key}`。默认内置 `opencode-zen`（`https://opencode.ai/zen/v1`，key 硬编码为字符串 `"public"`，见 `src/lib/config.ts:11`）——任何 OpenAI 兼容网关（DeepSeek、Kimi、Ollama/vLLM、自建）都能接。
- **Anthropic**：POST `{baseUrl}/messages`，`x-api-key` + `anthropic-version: 2023-06-01`。
- 用户可在设置页添加**任意多个** provider（`id / name / apiType / baseUrl / apiKey / models / defaultModel`），并通过 `GET {baseUrl}/models` 拉模型列表（`src/app/api/settings/models/route.ts`）。

### 1.2 API key 存在哪里

**存在数据库 settings 表，不是 env。**

- `src/modules/settings/service.ts:153` `getSettings()` → `SELECT key, value_json FROM settings`，key = `llmConfig`，value 是完整 JSON（含所有 provider 的 `apiKey` 明文）。
- **纯 JSON 明文存储，无加密**。`.env` / `.env.example` 里只有 `DATABASE_URL / LEXILOOP_PASSWORD / CRON_SECRET / APP_TIMEZONE`，**没有任何 LLM 相关 key**。
- `merriamWebsterDictionaryKey / merriamWebsterThesaurusKey / tencentTranslateSecretId / tencentTranslateSecretKey` 同样是 settings 表明文。

> **Flutter 迁移影响（重要）**：移动端必须把 key 存本地。推荐 `flutter_secure_storage`（Android Keystore / iOS Keychain 加密存储）。风险是**反编译即泄露**——若应用走 Google Play，需接受"用户自带 key（BYOK）"模式，或保留一个极薄的自建中转。

### 1.3 Prompt 里的业务逻辑（4 个独立调用点）

| 调用点 | 位置 | 次数 | Schema / 输出 | 重试与回退 |
|--------|------|------|---------------|-----------|
| **AI 词典初始化** `AiLexicalProvider` | `ai-lexical.ts` + `ai-lexical-prompt.ts` + `ai-lexical-schema.ts` | 1 次/词 | **超大 JSON Schema**（`JSON_SCHEMA`，9 个顶层字段：summary / senses / morphology / phrases / confusedWords / sentenceAnalysis / learning / tags）+ zod 校验 + 枚举归一化 | 3 档结构化降级 + 主备模型切换 |
| **文章选词** `aiSelectTerms` | `article-import/prompt.ts` + `ai-select.ts` | 1 次/段落（每段 ≤2200 字符，分段并发 3） | 手写 JSON 格式串（words/phrases/sentences）+ `AI_SELECTION_JSON_SCHEMA` + `parseJsonLoose` 容错解析 | 同上；解析失败**回退本地筛选** |
| **每日 AI 建议** `generateAiSuggestion` | `suggestions/ai.ts` | 1 次/天 | zod `aiOutputSchema`（headline/summary/strengths/risks/actions/recommended ≤10） | 同上 |
| **中文助记** `generateChineseMnemonic` | `ai-tasks/supplemental.ts` | 1 次/词（后台队列） | 纯文本，无 schema | 同上 + **业务级重写**：输出不含 ≥4 个汉字则带纠正语重发一次，仍失败抛 `AI_MNEMONIC_LANGUAGE_INVALID` |
| **翻译兜底** `requestAi` | `translations/provider.ts` | 1 次/批（≤50 条） | zod `{translations:[{index,translation}]}` strict | 腾讯优先 → AI 兜底 |

**Schema 复杂度（最难搬的一块）**：`ai-lexical-schema.ts` 定义了 `additionalProperties:false` + `$defs/related` + 大量枚举的严格 JSON Schema（OpenAI `json_schema` strict 模式用），配套 `ai-lexical-normalize.ts`（枚举大小写/别名修复，如 `"very common"`→`VERY_COMMON`）、`ai-lexical-content.ts`（`qualityScore` 0-100 打分 + `semanticIssues` 语义校验，**score<45 直接丢弃该结果**）和 `ai-lexical.ts` 的 6 个错误码（`AI_OUTPUT_TRUNCATED / AI_TERM_MISMATCH / AI_SEMANTIC_INVALID / AI_QUALITY_LOW / AI_SCHEMA_INVALID / AI_TIMEOUT`）。这套"生成 → 归一化 → 语义校验 → 质量打分 → 落库"的流水线必须逐行等价翻译到 Dart。

### 1.4 是否流式 / 超时

- **完全不流式**。全仓库 grep `stream|EventSource|text/event-stream` 在 `src/` 只命中一条注释。所有 LLM 调用都是 `await response.json()` 一次性读完，UI 靠 loading 态。
- **超时**：`AbortSignal.timeout(provider.timeoutMs)`，`timeoutMs` 默认 **180 000 ms（3 分钟）**，可在设置里调（范围 5s–300s，见 `settings/service.ts:14`）。
- 其他 provider 超时：词典类 8–10 s，Tencent 8 s，`/models` 列表 15 s，Edge TTS WebSocket 15 s。

### 1.5 重试/回退策略（`client.ts:339-446`，共 3 层）

1. **思考参数降级**：开启 thinking 时若收到 HTTP 400 且错误信息含 `thinking|reasoning|budget_tokens`，自动去掉思考参数重发一次（Anthropic 与 OpenAI 两条路径都有）。
2. **结构化输出 3 档降级**（仅 OpenAI）：`json_schema(strict)` → `json_object` → 无约束纯文本。某档返回 400 或空内容就降下一档；全空才抛 `AI_EMPTY_RESPONSE`。
3. **主备模型切换**（`callLlmWithFallback`）：仅当主模型报 `transient`（超时/网络/空返回/429/408/409/5xx）才切到 `retryModel`（可跨 provider）；鉴权/格式类错误**不**切换，避免浪费配额。若主备 endpoint+key+model 完全相同则跳过切换。

### 1.6 迁移难度评估：**中**

- **好消息**：`client.ts` 581 行是**纯逻辑**（`fetch` + 响应解析），Dart `http` / `dio` 重写约 400-500 行即可，不需要任何服务器。
- **坏消息**：3 层降级 + 大量 provider 兼容分支（Anthropic `thinking` vs OpenAI `reasoning_effort` vs `reasoning.effort`、`max_tokens` vs `max_completion_tokens`）是**长期打磨出来的兼容经验**，必须逐条复刻，否则免费网关会静默返回空内容。
- **zod → Dart**：推荐 `freezed` + `json_serializable` 生成 model，或 `json_annotation`。枚举（CEFR / frequency / register / word form type）建议用 Dart `enum` + `values.firstWhere` 归一化，复刻 `ai-lexical-normalize.ts` 的别名表。

---

## 2. 词典 API — 迁移难度：**中**（解析器本身难，调用本身易）

| Provider | 文件 | 请求 URL | 需要 Key | 超时 | 返回结构 | 解析器 |
|----------|------|-----------|---------|------|---------|--------|
| **youdao** | `providers/youdao.ts` | `https://dict.youdao.com/w/eng/{term}`<br>`https://www.youdao.com/result?word=&lang=en` | ❌ | 8s(WORD) / 10s | **HTML** | ✅ `youdao-parser.ts` + `youdao-fields.ts`（**362 行**） |
| **iciba** | `providers/iciba.ts` | `https://www.iciba.com/word?w={term}` | ❌ | 10s | **HTML**（内嵌 `<script id="__NEXT_DATA__">` 的 Next.js RSC payload，取 `props.pageProps.initialReduxState.word.wordInfo`） | ✅ `iciba-parser.ts` + `iciba-fields.ts`（**342 行**） |
| **merriam-webster** | `providers/merriam-webster.ts` | `https://www.dictionaryapi.com/api/v3/references/{collegiate\|thesaurus}/json/{term}?key=` | ✅ 2 个 key | 10s | JSON（`fl` 词性 / `shortdef` / `hwi.prs.mw` 音标 / `def[].sseq` 里 `vis` 例句 / `meta.syns` / `meta.ants`） | 内联正则清洗 `{d¦|word}` 标记 + 递归遍历 sseq |
| **dictionaryapi.dev** | `providers/dictionary-api.ts` | `https://api.dictionaryapi.dev/api/v2/entries/en/{term}` | ❌ | 10s | JSON（`phonetics[].text/audio`、`meanings[].definitions[]`） | 内联映射 |
| **mymemory** | `providers/mymemory.ts` | `https://api.mymemory.translated.net/get?q=&langpair=src|tgt` | ❌ | 8s | JSON（`responseData.translatedText` + `matches[].translation`，取 `match ≥ 0.85` 的前 4 条） | 内联映射 |
| **tencent-translate** | `providers/tencent-translate.ts` | `https://tmt.tencentcloudapi.com`（`X-TC-Action: TextTranslate`） | ✅ SecretId + SecretKey + ProjectId | 8s | JSON `Response.TargetText` | 走 `lib/tencent-translate-client.ts`（TC3 签名） |

### 2.1 各 provider 的差异化逻辑（迁移时最容易漏的部分）

- **youdao**（最复杂）：**双端点并发** `Promise.all` 拉两个页面 → 各自带 **jitter 重试一次**（120-400ms 随机延迟，仅超时/网络错才重试）→ `scoreContent` 打分择优 → `mergeDictionaryContent` 合并 → 判断 `requestedFields` 是否满足（`satisfiesRequestedFields`）。
- **iciba**：单端点直抓，靠 `__NEXT_DATA__` JSON；抓不到就返回 `UNPARSABLE_RESPONSE`。
- **merriam-webster**：用 `Promise.allSettled` 同时打 collegiate + thesaurus 两路，一路失败不影响另一路。
- 词典流水线（`dictionary/pipeline.ts`）：`PRIORITY_FALLBACK` 顺序执行、累积合并、达标即停；并行模式则全打后合并。**释义全失败时依次回退腾讯翻译 → AI**（`pipeline.ts:183`）。

### 2.2 移动端直接调用的具体问题

| 问题 | 说明 |
|------|------|
| **CORS 不适用** | ✅ 移动端是原生 HTTP，不受浏览器同源策略约束——**这条对 Flutter 反而是优势**，无需自建代理。 |
| **Key 泄露（最严重）** | Merriam-Webster、腾讯云 SecretKey 直接打进 APK → `apktool` 一解即得。腾讯云签名还需要客户端持有 `crypto` 做 HMAC-SHA256（Dart `crypto` 包可做，但密钥在客户端本身就是自欺欺人）。**建议：Merriam-Webster key 改 BYOK（用户自己填，存 flutter_secure_storage）；腾讯翻译建议直接砍掉，交给 AI 翻译。** |
| **HTML 抓取的脆弱性** | 有道/iciba 是**爬 HTML**，无官方 API、无稳定性承诺。页面改版 → 解析器全废。`youdao-fields.ts` 362 行 + `iciba-fields.ts` 342 行就是这么堆出来的。移动端没有代理服务器做灰度，只能靠本地兜底解析。 |
| **频率限制** | dictionaryapi.dev 与 MyMemory 匿名额度很低（代码里已显式处理 `429 → RATE_LIMITED`）。iciba/youdao 是网页，反爬会封 IP。**移动端必须做本地磁盘缓存 + 指数退避**（当前服务端只有内存 LRU，见 §3）。 |
| **超时与并发** | 建议 `dio` + `CancelToken`，并限制并发（服务端有 `ARTICLE_SEGMENT_CONCURRENCY = 3` 之类先例）。 |
| **User-Agent 伪装** | 代码里 UA 写死 `Mozilla/5.0 LexiLoop`。Flutter `HttpClient` 默认 UA 会被更多站点拒绝，需显式覆写 headers。 |

**迁移难度：中。** dictionaryapi.dev / mymemory 是「易」（纯 JSON 映射，几十行）。youdao/iciba 的 **704 行字段解析器**是「中」（逻辑可直译，但要重写 HTML→文本的正则链 + 实体解码）。merriam-webster 是「易-中」。

**Flutter 等价物**：
- HTTP：`dio`（拦截器/重试/超时）或 `http`
- HTML 解析：`html` 包（DOM 查询，比正则可靠）或保留现有正则直译
- 本地缓存：`sqflite` / `drift`（TTS 音频见 §3）

---

## 3. TTS — 迁移难度：**难**（唯一需要重写协议的）

### 3.1 是否 node-edge-tts？

**是。** `src/modules/tts/service.ts:4-7`：

```ts
import { generateSecMsGecToken, TRUSTED_CLIENT_TOKEN, CHROMIUM_FULL_VERSION } from "node-edge-tts/dist/drm.js";
import { WebSocket } from "ws";
```

注意：**它只用了 node-edge-tts 的 3 个 DRM 常量/函数**（`generateSecMsGecToken` 计算 `Sec-MS-GEC` 令牌、`TRUSTED_CLIENT_TOKEN`、`CHROMIUM_FULL_VERSION`），WebSocket 协议本身是**手写的**（`synthesize()`，`service.ts:80-158`）：

1. 连 `wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=...&Sec-MS-GEC=...&Sec-MS-GEC-Version=1-{chromium}&ConnectionId={uuid}`
2. 伪装 `Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold` + Chrome UA
3. 先发 `Path:speech.config`（JSON，输出格式 `audio-24khz-48kbitrate-mono-mp3`）
4. 再发 `Path:ssml` 的 SSML（`<speak><voice name="en-US-JennyNeural"><prosody>…`）
5. 收二进制帧，`indexOf("Path:audio\r\n")` 切出 MP3 分片拼接
6. 文本帧含 `Path:turn.end` 表示结束
7. **15 秒硬超时**

音色：`US → en-US-JennyNeural`，`UK → en-GB-SoniaNeural`。

### 3.2 第二条 TTS 通道：有道真人发音

`fetchYoudaoAudio()`（`service.ts:189`）：`https://dict.youdao.com/dictvoice?audio={word}&type={1=UK, 2=US}` — 无 key 的 mp3 直链，10s 超时。客户端优先用它，失败回退 Edge TTS（`tts-client.ts:256` `playEntryTtsPreferYoudao`）。

### 3.3 音频缓存策略（两级）

| 层 | 位置 | 存储 | 容量 |
|----|------|------|------|
| **服务端内存 LRU** | `tts/cache.ts` | `Map<string, ArrayBuffer>` | **200 条**（key = `${accent}:${word.toLowerCase()}`） |
| **客户端 IndexedDB** | `tts-client.ts:1-160` | IndexedDB `lexiloop-client-cache` / store `tts-audio`，存 `{key, blob, cachedAt}` | 无上限，key = `v1:{accent}:{nfkc-lowercase}` |

服务端两个 route（`api/tts/route.ts`、`api/tts/youdao/route.ts`）都是 `maxDuration = 60`（避开 Vercel Hobby 10s 限制），返回 `audio/mpeg` + `Cache-Control: public, max-age=86400`。客户端还有 `preloadTtsBatch(items, maxConcurrent=2)` 预热与并发去重（`pendingAudio` Map）。

### 3.4 移动端替代方案

**方案 A（推荐，中等难度）**：Dart 直接实现 Edge TTS WebSocket
- `web_socket_channel` 连接同一 URL，但 **`generateSecMsGecToken` 的算法必须从 node-edge-tts 的 JS 源码移植到 Dart**（它基于 Chromium 的 SHA-256 时间戳 + 固定魔数，逻辑不长但要逐行对）。
- 风险：`TrustedClientToken` / `Sec-MS-GEC` / Chromium 版本号是**未公开的私有协议**，微软随时可能变更。已有的开源 Dart 实现（如 `edge_tts` 类项目）活跃度普遍不高。

**方案 B（推荐，最省事）**：**直接换成系统 TTS**
- Android：`flutter_tts`（底层 Android `TextToSpeech`）——完全离线、免费、音色足够（`en-us-x-sfg-local` 等）。
- iOS：`flutter_tts`（AVSpeechSynthesizer）。
- 优点：**离线可用、零协议风险、延迟极低**，对背单词场景（单词/短语/句子，都是短文本）完全够用。
- 缺点：音色与 Edge Neural 不同，需要调整用户预期。

**方案 C（保真但需要代理）**：保留 Edge TTS，但**保留一个极薄的自建 TTS 代理**（几十行 Node/Python），密钥与 DRM 逻辑留在服务端。此时应用不再是"纯客户端"。

**缓存**：Dart 侧直接落盘即可，`<Flutter 项目>/tts_cache/{accent}/{hash}.mp3` 或用 `path_provider` + `drift`/sqflite 存 blob；播放用 `just_audio` / `audioplayers`（支持 `setSpeed`，正好对应 `wordSpeed/phraseSpeed/sentenceSpeed` 三个独立倍速设置）。

**迁移难度：难。** 这是所有外部依赖里唯一涉及二进制流 + 私有协议 + 逆向签名算法的地方。

---

## 4. 翻译 — 迁移难度：**易**

### 4.1 架构

`translations/provider.ts` 的 `translateItems()` 只有 **2 层**：

```
1. 腾讯云 TMT（若 tencentTranslateEnabled + SecretId + SecretKey 已配置）
   └─ 429 限流 → 直接抛出，不降级
   └─ 其他错误 → 静默吞掉，继续走 AI
2. AI 翻译（callLlmWithFallback）
   └─ zod strict 校验 {translations:[{index,translation}]}
   └─ 过滤掉越界的 index
   └─ 抛错：AI_DISABLED / AI_CONFIG_INCOMPLETE / AI_EMPTY_RESPONSE / AI_RESPONSE_INVALID
```

`translations/service.ts` 是纯 DB 写入（3 个函数：`translateMissingDefinitions` 每次取 ≤20 条、`translateMissingExamples`、`translateMissingSummary`，全部走 read-modify-write + `content_version + 1`）。

### 4.2 腾讯云客户端（`lib/tencent-translate-client.ts`，177 行）

手写 **TC3-HMAC-SHA256** 签名：canonicalRequest → stringToSign → 4 级派生签名密钥 → `Authorization` 头。语言码映射表 15 种。

- 批量：**不支持真批量**，`tencentTranslateBatch` 是**串行 for 循环**逐条调用（注释里明说了）。
- Flutter 侧：`crypto` 包（`Hmac(sha256)`、`sha256.convert`）可以完整复刻签名逻辑，约 80 行。
- **但建议直接删掉**：密钥放客户端 = 泄露；且已有 AI 翻译兜底，功能重叠。

**迁移难度：易。** 若保留腾讯 → 需要 `crypto` 包 + 手写签名（机械翻译）；若删除 → 直接用 AI，功能不受损。

---

## 5. 第三方 npm 依赖的移动端可替代性

| 包 | 用途 | Flutter/Dart 等价物 | 成熟度 | 迁移难度 |
|----|------|-------------------|--------|---------|
| **ts-fsrs** ^5.2.0 | FSRS-5 间隔重复调度（`reviews/fsrs.ts`，配置 `request_retention 0.7-0.99 / maximum_interval 3650 / enable_fuzz`） | **`fsrs` Dart 包**（作者 `open-spaced-repetition` 官方移植，含 fsrs-rs Dart binding） | ★★★★☆ 官方移植，与 ts-fsrs 同源（都跑 fsrs-rs） | **易** |
| **papaparse** ^5.5.3 | EasyDict CSV 解析（`imports/parser.ts`，`header:true / skipEmptyLines:"greedy" / transformHeader`） | **`csv` Dart 包**（~4k pub.likes）；或 `file_picker` + 手写解析 | ★★★★★ 完全够用 | **易** |
| **recharts** ^3.5.1 | 统计页 `AreaChart`（`statistics/page.tsx`，含 `ResponsiveContainer/Tooltip/CartesianGrid/XAxis/YAxis`） | **`fl_chart`**（★★★★★，30k+ pub.likes，API 几乎照抄 recharts）；或 `syncfusion_flutter_charts`（商用） | ★★★★★ | **易** |
| **framer-motion** ^12.42.2 | 页面过渡 / `AnimatePresence` / `motion.div`（用于 `ui.tsx`、`toast.tsx`、`app-shell.tsx`、`study-client.tsx` 等 6 处） | **`animations` 包**（官方，含 `SlideTransition/FadeTransition/ScaleTransition` + `AnimationController`）；复杂手势用 **`flutter_animate`**（★★★★★，声明式 DSL，`animate().fadeIn()`） | ★★★★★ | **易** |
| **lucide-react** ^0.468.0 | 图标（**60+ 文件**引用，约 150+ 个图标） | **`lucide_icons_flutter`** / **`lucide_icons`**（Flutter 官方社区移植，同一套 SVG 源）；或 `font_awesome_flutter`、`material_symbols_icons` | ★★★★☆ 图标名一一对应，迁移几乎是机械替换 | **易** |
| **date-fns** ^4.1.0 | **⚠️ 全仓库 0 处 import**（只在 package.json:24 里躺着） | 不需要 | — | **易（删掉即可）** |
| **zod** ^4.1.12 | 校验：`settings/service.ts`、`ai-lexical-schema.ts`、`suggestions/ai.ts`、`translations/provider.ts`、`imports/parser.ts`、各 API route | **`freezed` + `json_serializable`**（生成式、编译期安全）；运行时校验可用 **`validatable`** 或手写 `freezed` 构造器；或 `json_annotation` + 手写 `fromJson` | ★★★★☆ 生态成熟，但**没有 1:1 的 zod 替代品**，手写 `fromJson` 需要覆盖 enum 归一化 | **中** |
| **pg** ^8.22.0 | PostgreSQL 连接池 + `db/executor.ts` 的 SQLite 兼容 facade + 226 行 SQL | **`drift`**（★★★★★，Dart 原生 ORM，**与 PostgreSQL 无关，只支持 SQLite/D1**）；**`postgres` Dart 包**（若仍要连 PG）；纯客户端推荐 **`sqflite` + drift** | ★★★★☆ drift 是 Flutter 事实标准 | **难**（见下） |
| **clsx** ^2.1.1 | className 拼接（仅 `lib/cn.ts` 一处） | 不需要（Dart 无 className 概念） | — | **易（删掉）** |

---

## 6. 真正的迁移难点（超出"外部服务"范围但必须提）

这几项**比上面所有外部服务加起来都更难**，建议优先决策：

| 模块 | 现状 | 移动端问题 | 难度 |
|------|------|-----------|------|
| **数据库** | `db/client.ts` = PostgreSQL（`DATABASE_URL` 必填），`db/executor.ts` 226 行把 pg Pool 伪装成 SQLite 风格 API | **架构级重构**：要么改成设备本地 SQLite（drift + sqflite），要么保留自建 PG 后端（那就不是"纯客户端"了）。本地 SQLite 方案下，`FOR UPDATE SKIP LOCKED` 锁、`RETURNING`、`json_typeof/json_array_elements` 等 PG 专有 SQL 需要全部重写 | **难** |
| **初始化任务队列 + Worker** | `initialization/worker.ts`：DB 队列（`initialization_jobs` 表）+ `FOR UPDATE SKIP LOCKED` 抢占 + 指数退避（5s/30s/2min/10min/30min）+ 心跳 + 僵尸锁恢复（`recoverStaleJobs`） | 纯客户端无常驻进程。可行替代：**WorkManager / flutter_background_fetch + 本地队列表**；或用 drift 的事务 + 单 App 内串行队列（放弃跨设备并发） | **难** |
| **后台定时任务** | `background/tick.ts` + `docker-tick.ts` + `/api/background/tick` + Vercel Cron + 浏览器 KeepAlive。跑：维护任务（10min：过期预览清理 / 错词衰减 / 重试 job / 过期 session）、每日 00:05 生成 AI 建议 | 纯客户端只能靠"App 打开时补跑" + 本地定时。跨设备/关机状态下的定时能力 Android 有限（需 `workmanager` + `exact alarm` 权限，Android 12+ 受限） | **中-难** |
| **登录鉴权** | `LEXILOOP_PASSWORD` + httpOnly cookie（`lib/security.ts`，`/api/auth/login`） | 单设备应用通常**直接删除**；若要保留多端同步则必须留后端 | **易**（删）/ **难**（保留） |
| **备份/恢复** | `/api/backups/json`（JSON 导出/导入） | 纯客户端反而更简单：直接读写应用沙盒目录 | **易** |

---

## 7. 分阶段迁移建议（按难度从低到高）

### 阶段一：零风险直搬（1-2 周）
`date-fns`（删）、`clsx`（删）、`lucide-react`→`lucide_icons_flutter`、`recharts`→`fl_chart`、`framer-motion`→`flutter_animate`、`papaparse`→`csv`、`ts-fsrs`→`fsrs`。

### 阶段二：外部服务客户端化（2-3 周）
- LLM：`client.ts` 581 行 → Dio 版 `llm_client.dart`（含 3 层降级 + Anthropic/OpenAI 双协议），key 存 `flutter_secure_storage`
- zod schema → `freezed` + `fromJson`（重点复刻 `ai-lexical-normalize.ts` 的枚举别名表 + `qualityScore` 质量门）
- 词典：`dictionaryapi.dev` + `mymemory` + `merriam-webster` 先搬（纯 JSON），再搬 youdao / iciba 的 **704 行解析器**
- 翻译：只保留 AI，删掉腾讯（省掉密钥泄露面）

### 阶段三：决策点（需产品判断）
- **TTS**：推荐**方案 B（`flutter_tts` 系统 TTS）+ 有道真人发音兜底**，放弃 Edge TTS 私有协议 → 从"难"降到"易"。
- **数据库**：本地 SQLite（drift）vs 保留自建 PG 后端。这一项决定"纯客户端"是否成立。
- **Worker/定时**：本地队列 + App 打开补跑，接受"关机时不做初始化"的体验折衷。

### 阶段四：离线优先
把词典/TTS 缓存从内存 LRU 改为磁盘持久化（当前 TTS 服务端只有 200 条内存缓存，移动端必须改），并给所有外部 API 加指数退避（现在只有 youdao 有 jitter 重试一次）。

---

## 8. 一句话结论

**外部服务集成层迁移难度整体为「中」**：8 个外部服务中 6 个是纯 HTTP/JSON（易），有道/iciba 需要重写 704 行 HTML 解析器（中），Edge TTS 是唯一的"难"（私有 WebSocket 协议 + 逆向签名）——而它可以被 `flutter_tts` 直接替代。npm 依赖 8 个里 6 个有成熟 Dart 等价物（易）。**真正的成本不在外部服务，而在把 PostgreSQL + 服务端 Worker 队列 + Cron 定时改造成设备本地架构。**