/// 内容类型判定：单词 / 短语 / 句子。
///
/// 对应旧版 `modules/imports/normalizer.ts` 的 `detectEntryType`。
/// 判定结果写入 `words.content_type`；`words.entry_type` 只有 WORD/PHRASE
/// 两值（句子归 PHRASE），两者的映射在 `CsvImportService` 里做。
///
/// **为什么是启发式而不是词典**：EasyDict 的 CSV 没有类型列，而「短语」与
/// 「句子」的边界在无句法分析器的前提下只能靠词数、句末标点、从句引导词与
/// 限定动词这四条弱特征逼近。阈值全部取自 `core/constants.dart`，
/// 便于与旧版逐条对照调整。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';

/// 句末标点（含中英文）。
const String _sentenceTerminators = '.!?。！？';

/// 从句引导词与关系词（小写）。
///
/// **刻意排除** `after` / `before` / `since` / `until` / `as` / `so`：
/// 它们同样能作介词，会把 `before the war`、`as soon as possible`
/// 这类短语误判成句子。宁可漏判句子，也不要把短语错标成句子——
/// 后者会让复习时用句子题型考一个短语。
const Set<String> _clauseLeads = <String>{
  'that',
  'which',
  'who',
  'whom',
  'whose',
  'when',
  'where',
  'why',
  'how',
  'if',
  'unless',
  'because',
  'although',
  'though',
  'while',
  'whereas',
  'whether',
  'whenever',
  'wherever',
};

/// 限定动词的显式清单：be / have / do 的各形态与全部情态动词。
const Set<String> _finiteVerbs = <String>{
  'am',
  'is',
  'are',
  'was',
  'were',
  'be',
  'been',
  'being',
  'has',
  'have',
  'had',
  'do',
  'does',
  'did',
  'will',
  'would',
  'shall',
  'should',
  'can',
  'could',
  'may',
  'might',
  'must',
  'ought',
};

/// 判为「过去式限定动词」的最短长度（`-ed` 结尾）。
///
/// 取 4 而不是 3，避免把 `bed`、`red`、`fed` 当成动词。
const int _pastTenseMinLength = 4;

/// 空白分词。
final RegExp _whitespace = RegExp(r'\s+');

/// 词首词尾的非字母字符（引号、标点、括号）。
final RegExp _nonLetters = RegExp("[^a-z']");

/// 允许出现在句末标点**之后**的装饰字符（引号、括号）。
const List<String> _trailingDecorations = <String>[
  '"',
  "'",
  ')',
  ']',
  '】',
  '）',
];

/// 判定内容类型。
///
/// 规则按顺序短路（与旧版一致）：
/// 1. 词数 ≤1 → 单词；
/// 2. 以句末标点结尾 → 句子；
/// 3. 词数 ≥ [sentenceMinTokens] → 句子；
/// 4. 词数 ≥ [sentenceClauseMinTokens] 且以从句引导词开头 → 句子；
/// 5. 词数 ≥ [sentenceFiniteVerbMinTokens] 且含限定动词 → 句子；
/// 6. 否则 → 短语。
LexicalContentType detectContentType(String term) {
  final trimmed = term.trim();
  if (trimmed.isEmpty) return LexicalContentType.word;

  final tokens = trimmed.split(_whitespace);
  if (tokens.length <= 1) return LexicalContentType.word;
  if (_endsWithTerminator(trimmed)) return LexicalContentType.sentence;
  if (tokens.length >= sentenceMinTokens) {
    return LexicalContentType.sentence;
  }
  if (tokens.length >= sentenceClauseMinTokens &&
      _clauseLeads.contains(_normalizeToken(tokens.first))) {
    return LexicalContentType.sentence;
  }
  if (tokens.length >= sentenceFiniteVerbMinTokens && _hasFiniteVerb(tokens)) {
    return LexicalContentType.sentence;
  }
  return LexicalContentType.phrase;
}

/// 内容类型 → `words.entry_type`。
///
/// `entry_type` 只有 WORD/PHRASE 两值（旧版 CHECK 约束如此），
/// 句子在 `entry_type` 里归 PHRASE、在 `content_type` 里保持 SENTENCE。
EntryType entryTypeFor(LexicalContentType type) =>
    type == LexicalContentType.word ? EntryType.word : EntryType.phrase;

/// 是否以句末标点结尾（允许尾部成对引号或括号）。
bool _endsWithTerminator(String text) {
  var end = text.length;
  while (end > 0 && _trailingDecorations.contains(text[end - 1])) {
    end -= 1;
  }
  if (end == 0) return false;
  return _sentenceTerminators.contains(text[end - 1]);
}

/// 是否存在限定动词。
///
/// **只认 `-ed` 过去式，不认 `-s` 三单**：`flowers`、`glasses` 这类复数
/// 名词同样以 s 结尾，误判代价（短语被当成句子）高于漏判。
bool _hasFiniteVerb(List<String> tokens) {
  for (final token in tokens) {
    final word = _normalizeToken(token);
    if (word.isEmpty) continue;
    if (_finiteVerbs.contains(word)) return true;
    if (word.length >= _pastTenseMinLength && word.endsWith('ed')) return true;
  }
  return false;
}

/// 去掉引号与标点，转小写，便于与词表比对。
String _normalizeToken(String token) =>
    token.toLowerCase().replaceAll(_nonLetters, '');
