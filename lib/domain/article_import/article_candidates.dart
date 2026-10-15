/// 文章候选的合并、推荐与预览合并。
///
/// 对应旧版 `src/modules/article-import/candidates.ts`（126 行）。
///
/// 本文件必须保持纯 Dart。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// 预览内部比较用的归一化键：NFKC + 小写。
///
/// **与 `normalizeTerm` 的区别**：这里不做空白压缩。旧版
/// `candidates.ts` / `service.ts` 在比对 AI 返回的词形与候选词形时用的就是
/// 这个更弱的归一化（`term.normalize("NFKC").toLowerCase()`），保持逐字符
/// 等价才不会出现「AI 明明选了却被判为未选」。
String articleNormalizedLookupKey(String term) =>
    unorm.nfkc(term).toLowerCase();

/// 候选的复合键：`内容类型\u0000归一化词形（小写）`。
///
/// **为什么带类型**：同一个词形可能既是单词候选又是短语候选（`take off`），
/// 只用词形做键会让两类候选互相覆盖。分隔符用 `\u0000` 而不是常见字符，
/// 避免词形本身含分隔符时产生碰撞（与旧版一致）。
String articleCandidateKey(
  LexicalContentType entryType,
  String normalizedTerm,
) => '${entryType.wire}\u0000${articleNormalizedLookupKey(normalizedTerm)}';

/// 候选在勾选集合里使用的键（小写）。
String articleSelectionKey(ArticleCandidate candidate) =>
    articleCandidateKey(candidate.entryType, candidate.normalizedTerm);

/// 按复合键合并候选。
///
/// 合并规则逐条对应旧版 `mergeArticleCandidates`：
/// 出现次数相加；难度更大的一方提供难度 / CEFR / 词频；
/// 理由、出处句、AI 卡片只在原值为空时被填充；任一方为 KNOWN 则结果 KNOWN。
List<ArticleCandidate> mergeArticleCandidates(
  List<ArticleCandidate> candidates,
) {
  final merged = <String, ArticleCandidate>{};
  for (final candidate in candidates) {
    final key = articleSelectionKey(candidate);
    final existing = merged[key];
    merged[key] = existing == null
        ? candidate
        : _mergeCandidate(existing, candidate);
  }
  return List<ArticleCandidate>.unmodifiable(merged.values);
}

/// 本地回退的推荐词缀。
///
/// 有 `aiReason` 的候选优先（那说明 AI 确实挑过它）；否则取前
/// [articleDefaultRecommendedLimit] 个待学单词。**只取单词**：短语与句子
/// 的推荐由 [recommendedCandidateKeys] 单独处理（它们默认全选）。
List<String> fallbackRecommendedTerms(
  List<ArticleCandidate> merged, {
  int limit = articleDefaultRecommendedLimit,
}) {
  final aiPicked = <String>[
    for (final candidate in merged)
      if (candidate.isCandidate &&
          candidate.entryType == LexicalContentType.word &&
          (candidate.aiReason?.isNotEmpty ?? false))
        candidate.normalizedTerm.toLowerCase(),
  ];
  if (aiPicked.isNotEmpty) return aiPicked;
  final fallback = <String>[];
  for (final candidate in merged) {
    if (!candidate.isCandidate) continue;
    if (candidate.entryType != LexicalContentType.word) continue;
    fallback.add(candidate.normalizedTerm.toLowerCase());
    if (fallback.length >= limit) break;
  }
  return fallback;
}

/// 推荐选中的候选键：单词只选推荐词缀，短语 / 句子默认全选。
List<String> recommendedCandidateKeys(
  List<ArticleCandidate> merged,
  List<String> recommendedTerms,
) {
  final recommended = <String>{
    for (final term in recommendedTerms) term.toLowerCase(),
  };
  final keys = <String>[];
  for (final candidate in merged) {
    if (!candidate.isCandidate) continue;
    if (candidate.entryType == LexicalContentType.word &&
        !recommended.contains(candidate.normalizedTerm.toLowerCase())) {
      continue;
    }
    keys.add(articleSelectionKey(candidate));
  }
  return keys;
}

/// 初次勾选：优先用服务端给出的 `recommendedKeys`，否则按推荐词缀现算。
Set<String> initialSelectionKeys(ArticleImportPreview preview) {
  final keys = preview.recommendedKeys.isNotEmpty
      ? preview.recommendedKeys
      : recommendedCandidateKeys(
          preview.candidates,
          preview.recommendedTerms.isNotEmpty
              ? preview.recommendedTerms
              : fallbackRecommendedTerms(preview.candidates),
        );
  return <String>{for (final key in keys) key.toLowerCase()};
}

/// 拼接多个预览的 `aiError`。
///
/// 同一个预览令牌只算一次（同批的多个段共享同一个预览对象），
/// 不同批次的相同文案合并计数——否则一次 10 批的分段分析会把
/// 「AI 未启用」这句话原样重复 10 遍。
String? mergeAiErrors(Iterable<ArticleImportPreview> previews) {
  final seen = <String>{};
  final messages = <String>[];
  for (final preview in previews) {
    final message = preview.aiError?.trim() ?? '';
    if (message.isEmpty) continue;
    if (!seen.add('${preview.previewToken} $message')) continue;
    messages.add(message);
  }
  if (messages.isEmpty) return null;
  final counted = <String, int>{};
  for (final message in messages) {
    counted[message] = (counted[message] ?? 0) + 1;
  }
  return counted.entries
      .map(
        (entry) =>
            entry.value > 1 ? '${entry.key}（${entry.value} 批）' : entry.key,
      )
      .join('；');
}

/// 客户端合并多个预览（分段增量展示与重试后重合并共用）。
///
/// 与旧版 `mergeArticlePreviews` 对应：先按预览令牌去重（同批的多个段共享
/// 同一个预览对象，不去重会让统计按段数重复累加），再合并候选与统计。
ArticleImportPreview? mergeArticlePreviews(
  List<ArticleImportPreview> previews,
) {
  if (previews.isEmpty) return null;
  if (previews.length == 1) return previews.first;
  final deduped = _dedupeByToken(previews);
  final merged = mergeArticleCandidates(<ArticleCandidate>[
    for (final preview in deduped) ...preview.candidates,
  ]);
  final first = deduped.first;
  final recommended = fallbackRecommendedTerms(merged);
  return ArticleImportPreview(
    previewToken: first.previewToken,
    filename: first.filename,
    sourceLanguage: first.sourceLanguage,
    targetLanguage: first.targetLanguage,
    articleStats: _mergedStats(merged, deduped),
    candidates: merged,
    recommendedTerms: recommended,
    recommendedKeys: recommendedCandidateKeys(merged, recommended),
    aiApplied:
        deduped.any((preview) => preview.aiApplied) ||
        merged.any(
          (candidate) => candidate.aiReason != null || candidate.aiCard != null,
        ),
    aiError: mergeAiErrors(deduped),
    totalCandidates: merged.length,
    knownCount: merged.where((candidate) => candidate.isKnown).length,
    expiresAt: first.expiresAt,
  );
}

/// 合并后的统计。
///
/// 词数 / 字符数取各批之和（每批的 `articleStats` 是那一批的真实统计）；
/// 去重词数取合并后的单词数，为空时退回候选总数——与旧版一致。
ArticleStats _mergedStats(
  List<ArticleCandidate> merged,
  List<ArticleImportPreview> deduped,
) {
  final wordCount = deduped.fold(
    0,
    (sum, preview) => sum + preview.articleStats.wordCount,
  );
  final charCount = deduped.fold(
    0,
    (sum, preview) => sum + preview.articleStats.charCount,
  );
  final wordCandidates = merged
      .where((candidate) => candidate.entryType == LexicalContentType.word)
      .length;
  final uniqueCount = wordCandidates > 0 ? wordCandidates : merged.length;
  return ArticleStats(
    charCount: charCount,
    wordCount: wordCount > 0
        ? wordCount
        : uniqueCount * articleWordCountEstimateFactor,
    uniqueCount: uniqueCount,
    knownCount: merged.where((candidate) => candidate.isKnown).length,
    unknownCount: merged.where((candidate) => candidate.isCandidate).length,
    phraseCount: merged
        .where((candidate) => candidate.entryType == LexicalContentType.phrase)
        .length,
    sentenceCount: merged
        .where(
          (candidate) => candidate.entryType == LexicalContentType.sentence,
        )
        .length,
  );
}

List<ArticleImportPreview> _dedupeByToken(List<ArticleImportPreview> previews) {
  final byToken = <String, ArticleImportPreview>{};
  for (final preview in previews) {
    byToken.putIfAbsent(preview.previewToken, () => preview);
  }
  return byToken.values.toList(growable: false);
}

ArticleCandidate _mergeCandidate(ArticleCandidate a, ArticleCandidate b) {
  final stronger = (b.difficulty ?? 0) > (a.difficulty ?? 0);
  return ArticleCandidate(
    term: a.term,
    normalizedTerm: a.normalizedTerm,
    occurrences: a.occurrences + b.occurrences,
    status: b.isKnown ? ArticleCandidateStatus.known : a.status,
    entryType: a.entryType,
    sourceSentence: _firstNonEmpty(a.sourceSentence, b.sourceSentence),
    aiReason: _firstNonEmpty(a.aiReason, b.aiReason),
    difficulty: stronger ? b.difficulty : a.difficulty,
    cefrLevel: stronger ? (b.cefrLevel ?? a.cefrLevel) : a.cefrLevel,
    frequency: stronger ? (b.frequency ?? a.frequency) : a.frequency,
    aiCard: a.aiCard ?? b.aiCard,
  );
}

String? _firstNonEmpty(String? current, String? candidate) {
  if (current != null && current.isNotEmpty) return current;
  return candidate;
}
