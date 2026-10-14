/// 拼写判分的文本处理。
///
/// 对应旧版 `modules/reviews/answer-evaluation.ts` 中的归一化部分。
/// 拆成独立文件是因为这些函数同时被判题、导入去重与搜索复用。
library;

import 'package:lexiloop/core/constants.dart';

/// 缩写展开表。
///
/// 用户写 `don't`、标准答案是 `do not` 时应判对——这是「拼写」题而非
/// 「标点」题，纠结缩写形式会制造大量假错。
const Map<String, String> contractionMap = <String, String>{
  "i'm": 'i am',
  "you're": 'you are',
  "he's": 'he is',
  "she's": 'she is',
  "it's": 'it is',
  "we're": 'we are',
  "they're": 'they are',
  "i've": 'i have',
  "you've": 'you have',
  "we've": 'we have',
  "they've": 'they have',
  "i'd": 'i would',
  "you'd": 'you would',
  "he'd": 'he would',
  "she'd": 'she would',
  "we'd": 'we would',
  "they'd": 'they would',
  "i'll": 'i will',
  "you'll": 'you will',
  "he'll": 'he will',
  "she'll": 'she will',
  "we'll": 'we will',
  "they'll": 'they will',
  "isn't": 'is not',
  "aren't": 'are not',
  "wasn't": 'was not',
  "weren't": 'were not',
  "haven't": 'have not',
  "hasn't": 'has not',
  "hadn't": 'had not',
  "won't": 'will not',
  "wouldn't": 'would not',
  "don't": 'do not',
  "doesn't": 'does not',
  "didn't": 'did not',
  "can't": 'cannot',
  "couldn't": 'could not',
  "shouldn't": 'should not',
  "mightn't": 'might not',
  "mustn't": 'must not',
  "that's": 'that is',
  "what's": 'what is',
  "where's": 'where is',
  "there's": 'there is',
  "here's": 'here is',
  "who's": 'who is',
  "how's": 'how is',
  "let's": 'let us',
};

/// 英式拼写归一为美式。
///
/// 词库里两种拼写都可能出现，用户写另一种不该算错。
const Map<String, String> usUkMap = <String, String>{
  'colour': 'color',
  'flavour': 'flavor',
  'honour': 'honor',
  'humour': 'humor',
  'labour': 'labor',
  'neighbour': 'neighbor',
  'rumour': 'rumor',
  'centre': 'center',
  'theatre': 'theater',
  'metre': 'meter',
  'litre': 'liter',
  'fibre': 'fiber',
  'analyse': 'analyze',
  'paralyse': 'paralyze',
  'organise': 'organize',
  'recognise': 'recognize',
  'realise': 'realize',
  'apologise': 'apologize',
  'criticise': 'criticize',
  'defence': 'defense',
  'licence': 'license',
  'offence': 'offense',
  'practise': 'practice',
  'travelling': 'traveling',
  'cancelled': 'canceled',
  'fulfil': 'fulfill',
};

/// 把英式拼写归一为美式；无映射时原样返回。
String canonicalTerm(String term) => usUkMap[term] ?? term;

/// Levenshtein 编辑距离（滚动数组，空间 O(min(a, b))）。
int levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (index) => index);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i += 1) {
    current[0] = i;
    for (var j = 1; j <= b.length; j += 1) {
      final substitution = a[i - 1] == b[j - 1]
          ? previous[j - 1]
          : _min3(previous[j - 1], previous[j], current[j - 1]) + 1;
      current[j] = substitution;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

int _min3(int a, int b, int c) {
  final smallest = a < b ? a : b;
  return smallest < c ? smallest : c;
}

/// 句子答案归一化：小写、统一撇号、展开缩写、去除全部标点与多余空白。
String normalizeSentenceAnswer(String value) {
  final words = value
      .replaceAll('’', "'")
      .replaceAll('‘', "'")
      .toLowerCase()
      .split(RegExp(r'\s+'));

  final expanded = <String>[];
  for (final raw in words) {
    var word = raw.replaceAll(_edgePunctuation, '');
    word = contractionMap[word] ?? word;
    word = usUkMap[word] ?? word;
    if (word.isNotEmpty) expanded.add(word);
  }

  return expanded
      .join(' ')
      .replaceAll(_punctuationOrSymbol, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// 句子长度超过 [sentenceFuzzyMinLength] 时允许的编辑距离。
int sentenceFuzzyTolerance(int expectedLength) {
  final scaled = (expectedLength * sentenceFuzzyRatio).floor();
  return scaled < sentenceFuzzyMinDistance ? sentenceFuzzyMinDistance : scaled;
}

/// 长词的「单字母手误」容错。
///
/// 仅对长度 ≥ [spellingFuzzyMinLength] 的词生效：短词放宽会误判（cat/cut）。
bool isSingleTypoOf(String userTerm, String targetTerm) =>
    targetTerm.length >= spellingFuzzyMinLength &&
    levenshteinDistance(userTerm, targetTerm) <= spellingFuzzyMaxDistance;

final RegExp _edgePunctuation = RegExp(
  r'^[\p{P}\p{S}]+|[\p{P}\p{S}]+$',
  unicode: true,
);
final RegExp _punctuationOrSymbol = RegExp(r'[\p{P}\p{S}]+', unicode: true);
