/// 文章导入的领域模型。
///
/// 对应旧版 `src/lib/types/article-import.ts` 的 `ArticleCandidate` /
/// `ArticleStats` / `ArticleImportPreview` / `ArticleAiCard`，以及
/// `modules/article-import/extract.ts` 的 `ParagraphSegment`。
///
/// **为什么全部不可变**：旧版在 `service.ts` 里就地改 `candidate.aiReason`
/// 这类字段，读代码时无法判断「此刻的候选到底是本地结果还是 AI 结果」。
/// 这里改成「每一步产出新实例」，让 `_applyAiSelection` 的输入输出一眼可见。
///
/// 本文件必须保持纯 Dart。
library;

import 'package:lexiloop/domain/enums.dart';

/// 候选相对现有词库的状态。
///
/// 字面量与旧版一致（`KNOWN` / `CANDIDATE`），因为预览表格的状态徽章与
/// 统计口径都按它分组。
enum ArticleCandidateStatus {
  /// 词库中已有同键词条（内容类型 + 归一化词形）。
  known('KNOWN'),

  /// 待学候选。
  candidate('CANDIDATE');

  new(this.wire);

  /// 存储 / 展示标识。
  final String wire;
}

/// 文章分词的难度筛选模式。
enum ArticleDifficultyMode {
  /// 目标级别及以上（排除更低级基础词，保留目标级与更难词汇）。
  atOrAbove('AT_OR_ABOVE'),

  /// 精准匹配所选级别的核心词段（排除明显过简与超纲生僻词）。
  exactBand('EXACT_BAND');

  new(this.wire);

  /// 存储 / 传输标识。
  final String wire;
}

/// 文章提取范围。
enum ArticleExtractScope {
  /// 仅分词提取单词（轻量快速，推荐；释义/音标/例句后续交由有道查词）。
  wordsOnly('WORDS_ONLY'),

  /// 同时提取短语搭配与难句分析。
  withPhrasesAndSentences('WITH_PHRASES_AND_SENTENCES');

  new(this.wire);

  /// 存储 / 传输标识。
  final String wire;
}

/// 预览页单词列表的排序方式。
enum ArticleCandidateSort {
  /// 按难度/推荐优先。
  difficulty,

  /// 按文章出现频次降序。
  occurrences,

  /// 按原文顺序（列表原序）。
  appearance,
}

/// AI 卡片的重点词汇。
class ArticleAiKeyVocab {
  /// 以各字段构造。
  const new({required this.term, required this.meaning, this.pos});

  /// 词形。
  final String term;

  /// 词性（可为空）。
  final String? pos;

  /// 释义。
  final String meaning;
}

/// AI 为短语 / 句子生成的讲解卡片。
///
/// 对应旧版 `lib/types/article-import.ts` 的 `ArticleAiCard`。旧版把
/// `grammar.pattern` / `grammar.notes` 拆成嵌套对象；本版摊平成两个字段，
/// 因为除了渲染之外没有任何消费方关心这层嵌套。
class ArticleAiCard {
  /// 以各字段构造。
  const new({
    required this.literalTranslation,
    required this.freeTranslation,
    this.keyVocab = const <ArticleAiKeyVocab>[],
    this.grammarPattern,
    this.grammarNotes = const <String>[],
    this.nuance,
  });

  /// 直译。
  final String literalTranslation;

  /// 意译。
  final String freeTranslation;

  /// 重点词汇。
  final List<ArticleAiKeyVocab> keyVocab;

  /// 语法句型。
  final String? grammarPattern;

  /// 语法说明。
  final List<String> grammarNotes;

  /// 辨析 / 注释。
  final String? nuance;

  /// 卡片是否没有任何可展示内容。
  bool get isEmpty =>
      literalTranslation.isEmpty &&
      freeTranslation.isEmpty &&
      keyVocab.isEmpty &&
      (grammarPattern?.isEmpty ?? true) &&
      grammarNotes.isEmpty &&
      (nuance?.isEmpty ?? true);
}

/// 文章导入的一个候选词条。
class ArticleCandidate {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.normalizedTerm,
    required this.occurrences,
    required this.status,
    required this.entryType,
    this.sourceSentence,
    this.surfaceForm,
    this.aiReason,
    this.difficulty,
    this.cefrLevel,
    this.frequency,
    this.examTags = const <String>[],
    this.aiCard,
  });

  /// 展示用词形（LLM 词形还原后的标准词典原形，或本地提取的原词）。
  final String term;

  /// 归一化词形。
  final String normalizedTerm;

  /// 在文章中出现的次数（AI 生成的短语 / 句子恒为 1）。
  final int occurrences;

  /// 相对现有词库的状态。
  final ArticleCandidateStatus status;

  /// 词条类型（单词 / 短语 / 句子）。
  final LexicalContentType entryType;

  /// 出处句（本地切句里第一条包含该词形或变形词的句子）。
  final String? sourceSentence;

  /// 文章中出现的原始变形词（例如原形 `implement` 对应原文 `implemented`）。
  final String? surfaceForm;

  /// AI 给出的语境提示 / 推荐理由。
  final String? aiReason;

  /// AI 给出的难度（1–5）。
  final int? difficulty;

  /// AI 给出的 CEFR 等级。
  final String? cefrLevel;

  /// AI 给出的词频档。
  final String? frequency;

  /// AI 给出的考试标签（如 `CET6`、`IELTS`）。
  final List<String> examTags;

  /// AI 给出的讲解卡片（短语 / 句子才有）。
  final ArticleAiCard? aiCard;

  /// 是否为待学候选。
  bool get isCandidate => status == ArticleCandidateStatus.candidate;

  /// 是否为已掌握（词库中已有）。
  bool get isKnown => status == ArticleCandidateStatus.known;

  /// 复制一份并改写状态。
  ///
  /// 合并多个预览时要按**当前**词库重新判定 KNOWN（旧版
  /// `mergeArticlePreviews` 的「Re-evaluate KNOWN against DB」），
  /// 而候选本身不可变，只能换一个新实例。
  ArticleCandidate withStatus(ArticleCandidateStatus next) => ArticleCandidate(
    term: term,
    normalizedTerm: normalizedTerm,
    occurrences: occurrences,
    status: next,
    entryType: entryType,
    sourceSentence: sourceSentence,
    surfaceForm: surfaceForm,
    aiReason: aiReason,
    difficulty: difficulty,
    cefrLevel: cefrLevel,
    frequency: frequency,
    examTags: examTags,
    aiCard: aiCard,
  );
}

/// 文章统计。
///
/// 字段与旧版 `ArticleStats` 一致：预览卡片上那五个指标全部来自这里。
class ArticleStats {
  /// 以各字段构造。
  const new({
    required this.charCount,
    required this.wordCount,
    required this.uniqueCount,
    required this.knownCount,
    required this.unknownCount,
    required this.phraseCount,
    required this.sentenceCount,
  });

  /// 字符数。
  final int charCount;

  /// 全文词数。
  final int wordCount;

  /// 去重词数。
  final int uniqueCount;

  /// 已掌握词数。
  final int knownCount;

  /// 待学候选数。
  final int unknownCount;

  /// 短语数。
  final int phraseCount;

  /// 句子数。
  final int sentenceCount;
}

/// 一次文章预览。
///
/// 对应旧版 `ArticleImportPreview`。**与旧版的差异**：旧版把预览落进
/// `import_previews` 表、把预览级 AI 状态塞进 `rows_json` 首行的 `_meta`
/// 以规避加列；本版预览是内存对象，这些字段直接挂在预览上（见
/// `ArticleImportService`）。
class ArticleImportPreview {
  /// 以各字段构造。
  const new({
    required this.previewToken,
    required this.filename,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.articleStats,
    required this.candidates,
    required this.recommendedTerms,
    required this.recommendedKeys,
    required this.aiApplied,
    required this.totalCandidates,
    required this.knownCount,
    required this.expiresAt,
    this.aiError,
  });

  /// 预览令牌（提交时按它取回预览）。
  final String previewToken;

  /// 展示名。
  final String filename;

  /// 源语言。
  final String sourceLanguage;

  /// 目标语言。
  final String targetLanguage;

  /// 统计。
  final ArticleStats articleStats;

  /// 全部候选（含已掌握）。
  final List<ArticleCandidate> candidates;

  /// 推荐词（归一化词形，小写）。
  final List<String> recommendedTerms;

  /// 推荐选中的候选键（`内容类型\u0000归一化词形`，小写）。
  final List<String> recommendedKeys;

  /// AI 是否真的筛选过（false 表示走的是本地回退）。
  final bool aiApplied;

  /// AI 失败原因；成功或未启用时为 `null`。
  ///
  /// **它必须被展示**：旧版 `aiError` 的语义就是「这批结果不是 AI 挑的」，
  /// 静默降级会让用户以为 AI 认为没有值得学的词。
  final String? aiError;

  /// 候选总数。
  final int totalCandidates;

  /// 已掌握数。
  final int knownCount;

  /// 过期时间（epoch 毫秒）。
  final int expiresAt;

  /// 待学候选数。
  int get candidateCount =>
      candidates.where((candidate) => candidate.isCandidate).length;

  /// 短语数。
  int get phraseCount => candidates
      .where((candidate) => candidate.entryType == LexicalContentType.phrase)
      .length;

  /// 句子数。
  int get sentenceCount => candidates
      .where((candidate) => candidate.entryType == LexicalContentType.sentence)
      .length;
}

/// 一次提交的结果。
///
/// **与旧版的差异**：旧版还回传 `batchId`（提交会写 `import_batches`），
/// 本版不写导入批次表，故没有这个字段。
class ArticleCommitResult {
  /// 以各字段构造。
  const new({
    required this.createdWords,
    required this.existingWords,
    required this.queuedInitializations,
    this.createdWordIds = const <int>[],
    this.affectedWordIds = const <int>[],
  });

  /// 新建词条数。
  final int createdWords;

  /// 已存在（重复）词条数。
  final int existingWords;

  /// 入队初始化任务数。
  final int queuedInitializations;

  /// 本次新建的词条 ID 列表。
  final List<int> createdWordIds;

  /// 本次进入有道查词补全的词条 ID 列表（含新建与触发补全的已有词条）。
  final List<int> affectedWordIds;
}

/// 一个文章分段。
///
/// 对应旧版 `extract.ts` 的 `ParagraphSegment`。
class ArticleSegment {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.index,
    required this.text,
    required this.charCount,
  });

  /// 分段 ID（`seg-1`…）。
  final String id;

  /// 分段序号（从 0 起）。
  final int index;

  /// 分段正文。
  final String text;

  /// 字符数。
  final int charCount;
}

/// 一批分段。
///
/// 对应旧版 `extract.ts` 的 `batchesForSegments` 返回值。
class ArticleBatch {
  /// 以各字段构造。
  const new({
    required this.batchIndex,
    required this.segmentIds,
    required this.charCount,
  });

  /// 批次序号（从 0 起）。
  final int batchIndex;

  /// 该批包含的分段 ID。
  final List<String> segmentIds;

  /// 该批字符数。
  final int charCount;
}

/// 分段方案：分段 + 分批。
class ArticleSegmentPlan {
  /// 以各字段构造。
  const new({
    required this.segments,
    required this.batches,
    required this.totalChars,
  });

  /// 全部分段。
  final List<ArticleSegment> segments;

  /// 分批结果。
  final List<ArticleBatch> batches;

  /// 原文字符数。
  final int totalChars;
}

/// 单个批次的预览结果（成功带预览，失败带原因）。
///
/// 分段预览按完成顺序逐个产出本对象：界面拿到一个就合并一个，
/// 已解析的批次立刻可见（旧版 `analyzeSegmented` 的增量展示）。
class ArticleSegmentOutcome {
  /// 以成功结果构造。
  const new success({
    required this.batchIndex,
    required ArticleImportPreview this.preview,
  }) : error = null;

  /// 以失败结果构造。
  const new failure({required this.batchIndex, required String this.error})
    : preview = null;

  /// 批次序号。
  final int batchIndex;

  /// 成功时的预览。
  final ArticleImportPreview? preview;

  /// 失败原因。
  final String? error;

  /// 该批是否成功。
  bool get isSuccess => preview != null;
}
