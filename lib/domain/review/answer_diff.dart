/// 答案差异（字符级与词级）。
///
/// 对应旧版 `src/components/answer-diff.tsx` 的 `TermDiff` / `SentenceDiff`。
/// **刻意放在 `lib/domain/`**：LCS 是纯函数，界面层只负责上色；旧版把算法与
/// JSX 写在同一个组件里，想单独验证「分段边界」就必须渲染整棵 React 树。
library;

import 'dart:math' as math;

import 'package:lexiloop/domain/review/spelling.dart';

/// 一段 diff 文本。
class DiffSegment {
  /// 以片段文本与「是否为差异段」构造。
  const new({required this.text, required this.isDiff});

  /// 片段文本。
  final String text;

  /// 是否为差异片段（界面上标红/标绿并加下划线）。
  final bool isDiff;
}

/// 词级 diff 中一个词的角色。
enum SentenceDiffKind {
  /// 两侧都有且相同。
  equal,

  /// 只在正确答案里出现——用户**漏**掉的词。
  missing,

  /// 只在用户输入里出现——用户**多写**的词。
  extra,
}

/// 词级 diff 中的一个词。
class SentenceDiffWord {
  /// 以词与角色构造。
  const new({required this.word, required this.kind});

  /// 词文本（已归一化）。
  final String word;

  /// 该词的角色。
  final SentenceDiffKind kind;
}

/// 字符级 diff；不需要展示时返回 `null`。
///
/// 两条与旧版 `TermDiff` 一致的「不渲染」规则：
/// - 两侧 `trim()` 后用户输入为空（没作答就没有可对比的东西）；
/// - 忽略大小写后相等（`Apple` 对 `apple` 不算错，标出来只会让人以为自己错了）。
///
/// 返回的两侧分段分别对应用户输入与正确答案，差异段由 LCS 决定。
({List<DiffSegment> expected, List<DiffSegment> actual})? termDiff({
  required String expected,
  required String actual,
}) {
  final trimmedExpected = expected.trim();
  final trimmedActual = actual.trim();
  if (trimmedActual.isEmpty) return null;
  if (trimmedExpected.toLowerCase() == trimmedActual.toLowerCase()) return null;
  return _diffChars(expected: trimmedExpected, actual: trimmedActual);
}

/// 词级 diff；不需要展示时返回 `null`。
///
/// 与旧版 `SentenceDiff` 等价：先用 [normalizeSentenceAnswer] 归一化（缩写展开、
/// 英美拼写归一、去标点），**编辑距离为 0 就不渲染**——只差标点或大小写说明
/// 用户其实答对了，展示差异只会制造「我明明对了」的困惑。
///
/// 返回的 `editDistance` 与 `expectedText` 供界面底部拼出
/// 「编辑距离 N · 参考：…」，与旧版同一行文案。
({List<SentenceDiffWord> words, int editDistance, String expectedText})?
sentenceDiff({required String expected, required String actual}) {
  final normalizedExpected = normalizeSentenceAnswer(expected);
  final normalizedActual = normalizeSentenceAnswer(actual);
  if (normalizedActual.isEmpty) return null;
  final distance = levenshteinDistance(normalizedExpected, normalizedActual);
  if (distance == 0) return null;
  return (
    words: _diffWords(
      expected: _normalizedWords(normalizedExpected),
      actual: _normalizedWords(normalizedActual),
    ),
    editDistance: distance,
    expectedText: expected,
  );
}

/// 归一化文本按空格切词。
///
/// [normalizeSentenceAnswer] 已把连续空白压成单个空格，因此这里不会切出空词；
/// 空串必须显式返回空列表——JS 的 `''.split(' ')` 会给出一个空字符串元素，
/// 那会在界面上渲染出一个没有内容的标签。
List<String> _normalizedWords(String normalized) =>
    normalized.isEmpty ? const <String>[] : normalized.split(' ');

({List<DiffSegment> expected, List<DiffSegment> actual}) _diffChars({
  required String expected,
  required String actual,
}) {
  if (expected.isEmpty || actual.isEmpty) {
    final isDiff = expected != actual;
    return (
      expected: <DiffSegment>[DiffSegment(text: expected, isDiff: isDiff)],
      actual: <DiffSegment>[DiffSegment(text: actual, isDiff: isDiff)],
    );
  }
  final table = _lcsTable(expected.split(''), actual.split(''));
  final expectedChars = <(String, bool)>[];
  final actualChars = <(String, bool)>[];
  var i = 0;
  var j = 0;
  while (i < expected.length || j < actual.length) {
    if (i < expected.length && j < actual.length && expected[i] == actual[j]) {
      expectedChars.add((expected[i], false));
      actualChars.add((actual[j], false));
      i += 1;
      j += 1;
    } else if (j >= actual.length ||
        (i < expected.length &&
            j < actual.length &&
            table[i + 1][j] >= table[i][j + 1])) {
      expectedChars.add((expected[i], true));
      i += 1;
    } else {
      actualChars.add((actual[j], true));
      j += 1;
    }
  }
  return (
    expected: _groupChars(expectedChars),
    actual: _groupChars(actualChars),
  );
}

/// 词级 LCS 走位。
///
/// 输出的是**一条合并后的词流**（与旧版一致）：相等的词、漏掉的词、多写的词
/// 按走位顺序混排，界面因此可以像读句子一样逐词对照，而不是看两份互不相关的
/// 词表。
List<SentenceDiffWord> _diffWords({
  required List<String> expected,
  required List<String> actual,
}) {
  final table = _lcsTable(expected, actual);
  final words = <SentenceDiffWord>[];
  var i = 0;
  var j = 0;
  while (i < expected.length || j < actual.length) {
    if (i < expected.length && j < actual.length && expected[i] == actual[j]) {
      words.add(
        SentenceDiffWord(word: actual[j], kind: SentenceDiffKind.equal),
      );
      i += 1;
      j += 1;
    } else if (j >= actual.length ||
        (i < expected.length &&
            j < actual.length &&
            table[i + 1][j] >= table[i][j + 1])) {
      words.add(
        SentenceDiffWord(word: expected[i], kind: SentenceDiffKind.missing),
      );
      i += 1;
    } else {
      words.add(
        SentenceDiffWord(word: actual[j], kind: SentenceDiffKind.extra),
      );
      j += 1;
    }
  }
  return words;
}

/// 最长公共子序列长度表。
///
/// 与旧版同构：`table[i][j]` 是 `expected[i..]` 与 `actual[j..]` 的 LCS 长度。
/// 走位时用 `table[i + 1][j] >= table[i][j + 1]` 做**固定**取舍——这个 `>=`
/// 决定了「期望侧优先消耗」，两侧分段边界因此完全确定，可被测试钉住。
List<List<int>> _lcsTable<T>(List<T> expected, List<T> actual) {
  final rows = expected.length;
  final columns = actual.length;
  final table = List<List<int>>.generate(
    rows + 1,
    (_) => List<int>.filled(columns + 1, 0),
  );
  for (var i = rows - 1; i >= 0; i -= 1) {
    for (var j = columns - 1; j >= 0; j -= 1) {
      table[i][j] = expected[i] == actual[j]
          ? table[i + 1][j + 1] + 1
          : math.max(table[i + 1][j], table[i][j + 1]);
    }
  }
  return table;
}

/// 把逐字符的「同类型」相邻项合并成片段。
List<DiffSegment> _groupChars(List<(String, bool)> chars) {
  final segments = <DiffSegment>[];
  final buffer = StringBuffer();
  bool? currentIsDiff;
  for (final (char, isDiff) in chars) {
    if (currentIsDiff != null && currentIsDiff != isDiff) {
      segments.add(DiffSegment(text: buffer.toString(), isDiff: currentIsDiff));
      buffer.clear();
    }
    currentIsDiff = isDiff;
    buffer.write(char);
  }
  if (currentIsDiff != null && buffer.isNotEmpty) {
    segments.add(DiffSegment(text: buffer.toString(), isDiff: currentIsDiff));
  }
  return segments;
}
