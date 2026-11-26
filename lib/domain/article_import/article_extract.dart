/// 文章正文清洗、词形提取、句子提取与分段分批。
///
/// 对应旧版 `src/modules/article-import/extract.ts`（159 行）。
///
/// 本文件必须保持纯 Dart。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/text/normalizer.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// 停用词表。
///
/// 与旧版 `extract.ts` 的 `STOPWORDS` **逐词一致**：它是「本地回退推荐」
/// 的质量下限，少一个词就会让 `the`、`of` 这类词混进待学候选。
const Set<String> articleStopwords = <String>{
  'a',
  'an',
  'the',
  'and',
  'or',
  'but',
  'if',
  'then',
  'else',
  'when',
  'while',
  'of',
  'to',
  'in',
  'on',
  'at',
  'by',
  'for',
  'with',
  'about',
  'against',
  'between',
  'into',
  'through',
  'during',
  'before',
  'after',
  'above',
  'below',
  'from',
  'up',
  'down',
  'out',
  'over',
  'under',
  'again',
  'further',
  'once',
  'i',
  'me',
  'my',
  'mine',
  'you',
  'your',
  'yours',
  'he',
  'him',
  'his',
  'she',
  'her',
  'hers',
  'it',
  'its',
  'we',
  'us',
  'our',
  'ours',
  'they',
  'them',
  'their',
  'theirs',
  'is',
  'am',
  'are',
  'was',
  'were',
  'be',
  'been',
  'being',
  'have',
  'has',
  'had',
  'do',
  'does',
  'did',
  'will',
  'would',
  'shall',
  'should',
  'may',
  'might',
  'must',
  'can',
  'could',
  'this',
  'that',
  'these',
  'those',
  'there',
  'here',
  'what',
  'which',
  'who',
  'whom',
  'why',
  'how',
  'as',
  'so',
  'than',
  'too',
  'very',
  'just',
  'also',
  'only',
  'even',
  'not',
  'no',
  'nor',
  'own',
  'same',
  'such',
};

/// 英文词形：首字符必须是字母，后续允许字母、撇号与连字符。
final RegExp _tokenPattern = RegExp("[A-Za-z][A-Za-z'-]*");

/// 句末标点（含中英文）。
final RegExp _sentencePattern = RegExp('[^.!?。！？]+[.!?。！？]+');

/// 词首 / 词尾的撇号与连字符。
final RegExp _edgeApostrophes = RegExp(r"^'+|'+$");
final RegExp _edgeHyphens = RegExp(r'^-+|-+$');

/// 空行（段落分隔）。
final RegExp _blankLinePattern = RegExp(r'\n\s*\n');

/// 单个换行。
final RegExp _newlinePattern = RegExp(r'\n');

/// 连续空格与制表符。
final RegExp _inlineWhitespace = RegExp(r'[ \t]+');

/// 一个词形的出现统计。
class ArticleTermOccurrence {
  /// 以各字段构造。
  const new({
    required this.term,
    required this.normalizedTerm,
    required this.occurrences,
  });

  /// 展示用词形（首次出现时的大小写）。
  final String term;

  /// 归一化词形。
  final String normalizedTerm;

  /// 出现次数。
  final int occurrences;
}

/// 一次词形提取的结果。
class ArticleExtraction {
  /// 以各字段构造。
  const new({
    required this.cleaned,
    required this.wordCount,
    required this.extracted,
  });

  /// 清洗后的正文。
  final String cleaned;

  /// 全文词数（**清洗后**的原始 token 数，不是去重数）。
  final int wordCount;

  /// 去重后的词形（按出现次数降序）。
  final List<ArticleTermOccurrence> extracted;
}

/// 清洗正文：NFKC 规范化、统一换行、压缩行内空白。
String cleanArticle(String raw) => unorm
    .nfkc(raw)
    .replaceAll('\r\n', '\n')
    .replaceAll(_inlineWhitespace, ' ')
    .trim();

/// 切句。
///
/// **与旧版的差异（有意）**：旧版优先用 `Intl.Segmenter` 做句边界切分，
/// 失败才退回正则。Dart 没有等价的、无需初始化 locale 数据的句切分器
/// （`package:intl` 的 `BreakIterator` 需要额外的 locale 数据装载），
/// 因此本版统一使用旧版的**正则回退分支**。语义等价于旧版在无
/// `Intl.Segmenter` 的运行环境下的行为；代价是 `Mr.`、`e.g.` 这类缩写
/// 会被切在中间——旧版的回退分支同样如此。
List<String> extractSentences(String cleaned) {
  final sentences = <String>[];
  for (final match in _sentencePattern.allMatches(cleaned)) {
    final text = match.group(0)?.trim() ?? '';
    if (text.isNotEmpty) sentences.add(text);
  }
  final rest = cleaned.replaceAll(_sentencePattern, '').trim();
  if (rest.isNotEmpty) sentences.add(rest);
  return sentences;
}

/// 提取去重词形。
///
/// 排序键与旧版一致：出现次数降序 → 词形长度降序 → 词形升序。
/// **唯一的差异**：旧版最后一级用 `localeCompare`（本地化排序），
/// 本版用 [String.compareTo]（码位序）。对英文词形两者结果相同，
/// 而 `localeCompare` 在 Dart 里需要 `intl` 的排序器与 locale 数据。
ArticleExtraction extractArticleTerms(
  String articleText, {
  String sourceLanguage = articleDefaultSourceLanguage,
  String targetLanguage = articleDefaultTargetLanguage,
}) {
  final cleaned = cleanArticle(articleText);
  final rawTokens = <String>[
    for (final match in _tokenPattern.allMatches(cleaned)) match.group(0)!,
  ];
  final counts = <String, _TermCount>{};
  for (final token in rawTokens) {
    final stripped = _stripToken(token);
    if (!_isUsableLength(stripped)) continue;
    if (articleStopwords.contains(stripped.toLowerCase())) continue;
    final normalized = normalizeTerm(stripped, sourceLanguage);
    if (!_isUsableLength(normalized)) continue;
    if (articleStopwords.contains(normalized)) continue;
    final key = identityKey(normalized, sourceLanguage, targetLanguage);
    final existing = counts[key];
    if (existing == null) {
      counts[key] = _TermCount(stripped, normalized);
    } else {
      existing.occurrences += 1;
    }
  }
  final extracted = <ArticleTermOccurrence>[
    for (final count in counts.values)
      ArticleTermOccurrence(
        term: count.term,
        normalizedTerm: count.normalizedTerm,
        occurrences: count.occurrences,
      ),
  ]..sort(_compareOccurrences);
  return ArticleExtraction(
    cleaned: cleaned,
    wordCount: rawTokens.length,
    extracted: List<ArticleTermOccurrence>.unmodifiable(extracted),
  );
}

/// 分段。
///
/// 与旧版 `segmentArticleParagraphs` 逐步对应：拆段 → 尾段合并 →
/// 超长段按句切分 → 超出上限时合并最小的相邻段。
List<ArticleSegment> segmentArticleParagraphs(
  String articleText, {
  int maxSegments = maxArticleSegments,
  int targetChars = articleSegmentTargetChars,
  int maxChars = articleSegmentMaxChars,
}) {
  final raw = unorm.nfkc(articleText).replaceAll('\r\n', '\n').trim();
  if (raw.isEmpty) return const <ArticleSegment>[];
  final paragraphs = _mergeShortTail(_splitParagraphs(raw));
  final texts = _splitOverlongParagraphs(paragraphs, targetChars, maxChars);
  return _indexSegments(_capSegments(texts, maxSegments));
}

/// 分段并分批。
///
/// 分段参数用默认值（与旧版界面一致：`segmentArticleParagraphs(text, { maxSegments })`），
/// 每批段数按 [segmentsPerBatch] 夹到 1–[maxArticleSegmentsPerBatch]。
ArticleSegmentPlan buildArticleSegmentPlan(
  String articleText, {
  int segmentsPerBatch = 1,
}) {
  final segments = segmentArticleParagraphs(articleText);
  return ArticleSegmentPlan(
    segments: segments,
    batches: batchesForSegments(segments, segmentsPerBatch),
    totalChars: articleText.length,
  );
}

/// 把分段按每批 [segmentsPerBatch] 个分批。
List<ArticleBatch> batchesForSegments(
  List<ArticleSegment> segments,
  int segmentsPerBatch,
) {
  final perBatch = segmentsPerBatch.clamp(1, maxArticleSegmentsPerBatch);
  final batches = <ArticleBatch>[];
  for (var start = 0; start < segments.length; start += perBatch) {
    final end = (start + perBatch).clamp(0, segments.length);
    final slice = segments.sublist(start, end);
    batches.add(
      ArticleBatch(
        batchIndex: batches.length,
        segmentIds: <String>[for (final segment in slice) segment.id],
        charCount: slice.fold(0, (sum, segment) => sum + segment.charCount),
      ),
    );
  }
  return batches;
}

/// 词形是否落在允许的长度区间内。
bool _isUsableLength(String value) =>
    value.length >= articleTokenMinChars &&
    value.length <= articleTokenMaxChars;

/// 去掉词首 / 词尾的撇号与连字符。
String _stripToken(String token) =>
    token.replaceAll(_edgeApostrophes, '').replaceAll(_edgeHyphens, '');

/// 排序：出现次数降序 → 长度降序 → 词形升序。
int _compareOccurrences(ArticleTermOccurrence a, ArticleTermOccurrence b) {
  if (a.occurrences != b.occurrences) {
    return b.occurrences - a.occurrences;
  }
  if (a.term.length != b.term.length) return b.term.length - a.term.length;
  return a.term.compareTo(b.term);
}

/// 拆段：优先按空行，其次按单换行（旧版 `splitIntoParagraphs`）。
List<String> _splitParagraphs(String normalized) {
  final blocks = _splitTrimmed(normalized, _blankLinePattern);
  if (blocks.length > 1) return blocks;
  final lines = _splitTrimmed(normalized, _newlinePattern);
  if (lines.length >= articleParagraphMinLines && normalized.contains('\n')) {
    return lines;
  }
  final single = normalized.trim();
  return single.isEmpty ? const <String>[] : <String>[single];
}

List<String> _splitTrimmed(String value, RegExp pattern) => <String>[
  for (final part in value.split(pattern))
    if (part.trim().isNotEmpty) part.trim(),
];

/// 尾段合并：末段短于 [articleTailMergeThreshold] 时并入前一段。
///
/// 只动末段，不动中间段落——用户按空行划分的段落意图必须被尊重。
List<String> _mergeShortTail(List<String> paragraphs) {
  final result = List<String>.of(paragraphs);
  while (result.length > 1 && result.last.length < articleTailMergeThreshold) {
    final tail = result.removeLast();
    result[result.length - 1] = '${result.last}$articleParagraphSeparator$tail';
  }
  return result;
}

List<String> _splitOverlongParagraphs(
  List<String> paragraphs,
  int targetChars,
  int maxChars,
) {
  final out = <String>[];
  for (final paragraph in paragraphs) {
    if (paragraph.length <= maxChars) {
      out.add(paragraph);
    } else {
      out.addAll(_splitLongParagraph(paragraph, targetChars, maxChars));
    }
  }
  return out;
}

/// 按句切分超长段；没有可切分的句子时退化为按目标字符数硬切。
List<String> _splitLongParagraph(
  String paragraph,
  int targetChars,
  int maxChars,
) {
  final sentences = extractSentences(paragraph);
  if (sentences.length <= 1) return _hardSlice(paragraph, targetChars);
  final out = <String>[];
  var buffer = '';
  for (final sentence in sentences) {
    final overflows = buffer.length + sentence.length + 1 > targetChars;
    if (buffer.isNotEmpty && overflows) {
      out.add(buffer.trim());
      buffer = sentence;
    } else {
      buffer = buffer.isEmpty ? sentence : '$buffer $sentence';
    }
    if (buffer.length >= maxChars) {
      out.add(buffer.trim());
      buffer = '';
    }
  }
  if (buffer.trim().isNotEmpty) out.add(buffer.trim());
  return out;
}

/// 按目标字符数硬切。
///
/// 空片段直接丢弃（旧版会把 `trim()` 后的空串也放进结果，那会变成一个
/// 没有任何内容的请求体）。
List<String> _hardSlice(String paragraph, int targetChars) {
  final out = <String>[];
  for (var start = 0; start < paragraph.length; start += targetChars) {
    final end = (start + targetChars).clamp(0, paragraph.length);
    final piece = paragraph.substring(start, end).trim();
    if (piece.isNotEmpty) out.add(piece);
  }
  return out;
}

/// 超出 [maxSegments] 时反复合并「字符数之和最小」的相邻两段。
List<String> _capSegments(List<String> texts, int maxSegments) {
  final result = List<String>.of(texts);
  while (result.length > maxSegments) {
    final index = _smallestNeighbourPair(result);
    result[index] =
        '${result[index]}$articleParagraphSeparator'
        '${result[index + 1]}';
    result.removeAt(index + 1);
  }
  return result;
}

int _smallestNeighbourPair(List<String> texts) {
  var best = 0;
  var smallest = texts.first.length + texts[1].length;
  for (var index = 1; index < texts.length - 1; index += 1) {
    final sum = texts[index].length + texts[index + 1].length;
    if (sum < smallest) {
      smallest = sum;
      best = index;
    }
  }
  return best;
}

List<ArticleSegment> _indexSegments(List<String> texts) => <ArticleSegment>[
  for (var index = 0; index < texts.length; index += 1)
    ArticleSegment(
      id: '$articleSegmentIdPrefix${index + 1}',
      index: index,
      text: texts[index],
      charCount: texts[index].length,
    ),
];

/// 可变的词形计数器。
class _TermCount {
  new(this.term, this.normalizedTerm);

  final String term;
  final String normalizedTerm;
  int occurrences = 1;
}
