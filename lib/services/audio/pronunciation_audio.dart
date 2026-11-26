/// 真人录音地址的选择策略。
///
/// **这一层存在的意义**：旧版详情页判断「是否优先播放有道真人发音」写的是
/// `pronunciations.some(p => p.source === "youdao")`（见
/// `src/app/(main)/words/[id]/use-word-detail.ts`），而 URL 里的口音参数
/// 又散落在词典 provider 内部。把这两件事收敛成纯函数之后，
/// 「哪个口音该放哪一个地址」可以被单测直接钉住，界面层不再重复这套判断。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 口音到有道 `type` 参数值的映射。
///
/// 与旧版 `YOUDAO_ACCENT_TYPE` 逐条对应：**英音为 1、美音为 2**，
/// 与有道自己的口径一致（`1` 是英式发音），写反了会得到另一种口音。
/// 存成字符串是因为它只作为查询参数出现，中间不必经过数值类型。
///
/// 放在这里而不是 `lib/core/constants.dart`：它以领域枚举 [Accent] 为键，
/// 而 `lib/core` 不依赖业务层（见 `docs/ARCHITECTURE_BASELINE.md` 的分层约定）。
const Map<Accent, String> youdaoAccentParam = <Accent, String>{
  Accent.uk: '1',
  Accent.us: '2',
};

/// 取出该口音下应当播放的真人录音地址；没有可用地址时返回 `null`。
///
/// 决策顺序与旧版一致，但每一步都写明理由：
/// 1. 词典直接给了该口音的音频地址——它已由 provider 按口音拼好
///    （有道写入的就是 `type=1|2`），直接用；
/// 2. 否则若该口音的发音来自有道而地址缺失，用词条文本补出有道地址；
/// 3. 其余情况（缺音标、非真人来源、词条为空）返回 `null`，交给系统朗读。
///
/// 第 2 步不推广到其他数据源：Merriam-Webster 的音频在自己的 CDN 上，
/// 地址无法由词条推出，硬套有道地址只会放错人的录音。
Uri? resolveHumanAudioUrl({
  required String term,
  required Accent accent,
  required List<PronunciationView> pronunciations,
}) {
  for (final pronunciation in pronunciations) {
    if (pronunciation.accent != accent) continue;
    final stored = pronunciation.audioUrl?.trim();
    if (stored != null && stored.isNotEmpty) return Uri.tryParse(stored);
  }
  final fromYoudao = pronunciations.any(
    (pronunciation) =>
        pronunciation.accent == accent &&
        pronunciation.source == youdaoAudioSource,
  );
  if (fromYoudao) return youdaoAudioUri(term, accent);
  return null;
}

/// 有道真人发音的地址；词条为空时返回 `null`。
///
/// `type` 参数决定口音（英音 `1`、美音 `2`），这是同一个词在两种口音下
/// 拿到不同 URL 的唯一来源。
Uri? youdaoAudioUri(String term, Accent accent) {
  final trimmed = term.trim();
  final type = youdaoAccentParam[accent];
  if (trimmed.isEmpty || type == null) return null;
  final encoded = Uri.encodeComponent(trimmed);
  return Uri.parse(
    '$youdaoAudioEndpoint?$youdaoAudioQueryKey=$encoded'
    '&$youdaoAudioTypeQueryKey=$type',
  );
}
