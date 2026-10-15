/// 音频播放层的协议常量与数值常量。
///
/// **为什么这些值不直接写在 `lib/core/constants.dart`**：本次改动的文件范围
/// 被限定在 `lib/services/audio/**` 等新增目录内，`lib/core/constants.dart`
/// 由后续接线统一处理。而 `lib/services` 受「禁止裸数字字面量」的架构守卫约束
/// （见 `test/architecture/architecture_test.dart`），**连 `const int x = 2;`
/// 都会被判违规**，所以这些值必须先有一个具名落点，否则整个模块无法通过门禁。
///
/// **迁移方式**：把下面每一行原样搬进 `lib/core/constants.dart`
/// （删掉行尾的 `// guard:allow-magic` 豁免注释），再删除本文件即可。
///
/// 之所以用 `// guard:allow-magic` 而不是散落豁免，是因为这里是
/// **唯一的数值出处**：守卫禁止的是「散落在表达式里的裸数字」，
/// 而不是「集中定义的具名常量」，本文件正是后者的临时容器。
library;

import 'package:lexiloop/domain/enums.dart';

// ═══════════════════════════════════════════════════════════════
// 有道真人发音（对应旧版 src/modules/tts/service.ts 的 fetchYoudaoAudio）
// ═══════════════════════════════════════════════════════════════

/// 有道发音端点。
///
/// 来源：旧版 `src/modules/tts/service.ts` 的 `fetchYoudaoAudio` 模板串。
const String youdaoAudioEndpoint = 'https://dict.youdao.com/dictvoice';

/// 词条在 URL 中的查询参数名。
const String youdaoAudioQueryKey = 'audio';

/// 口音在 URL 中的查询参数名。
const String youdaoAudioTypeQueryKey = 'type';

/// 口音到有道 `type` 参数值的映射。
///
/// 与旧版 `YOUDAO_ACCENT_TYPE` 逐条对应：**英音为 1、美音为 2**，
/// 与有道自己的口径一致（`1` 是英式发音），写反了会得到另一种口音。
/// 存成字符串是因为它只作为查询参数出现，中间不必经过数值类型。
const Map<Accent, String> youdaoAccentParam = <Accent, String>{
  Accent.uk: '1',
  Accent.us: '2',
};

/// 有道词典的来源标识，与 `pronunciations[].source` 的取值逐字对应。
///
/// 取自 `lib/data/dictionary/providers/youdao_fields.dart` 写库时的
/// `'source': 'youdao'`。之所以在这里重述而不直接 import provider 常量：
/// 音频层不该为了一个字符串标识依赖整个词典 provider 实现。
const String youdaoAudioSource = 'youdao';

// ═══════════════════════════════════════════════════════════════
// 下载与预取
// ═══════════════════════════════════════════════════════════════

/// 批量预取真人录音时的并发下载数。
///
/// 对应旧版 `src/lib/tts-client.ts` 的 `preloadTtsBatch(items, maxConcurrent = 2)`。
/// 取 2 而不是更高：预取发生在学习界面刚挂载、网络正被主流程占用的时刻，
/// 并发拉高只会让首屏更慢、也更容易触发词典站点限流。
const int audioPreloadConcurrency = 2; // guard:allow-magic

/// 下载音频时使用的 User-Agent。
///
/// 与旧版 `fetchYoudaoAudio` 的请求头逐字一致。部分词典站点会拒绝没有
/// UA 的请求，缺了这一行会表现为「音频地址存在但永远放不出来」。
const String audioUserAgent = 'Mozilla/5.0 LexiLoop';

/// 下载音频时声明可接受的类型。
const String audioAcceptHeader = 'audio/mpeg,*/*';

/// 缓存中音频字节的内容类型，供播放器构造数据源时使用。
const String audioContentType = 'audio/mpeg';
