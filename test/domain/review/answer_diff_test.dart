/// 答案差异的纯函数单测。
///
/// 对应旧版 `src/components/answer-diff.tsx`。这里钉的是**分段边界**：
/// 红字/绿字具体落在哪几个字符上，差一个字符用户就会以为自己错在别处。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/review/answer_diff.dart';

/// 把分段压成 `(文本, 是否差异)`，便于逐段断言。
List<(String, bool)> _segments(List<DiffSegment> segments) => <(String, bool)>[
  for (final segment in segments) (segment.text, segment.isDiff),
];

void main() {
  group('字符级 diff', () {
    test('用户输入为空时不渲染', () {
      expect(termDiff(expected: 'apple', actual: ''), isNull);
      expect(termDiff(expected: 'apple', actual: '   '), isNull);
    });

    test('忽略大小写后相等时不渲染', () {
      expect(termDiff(expected: 'Apple', actual: 'aPPLE'), isNull);
    });

    test('两侧先 trim 再比较', () {
      expect(termDiff(expected: ' apple ', actual: ' apple '), isNull);
    });

    test('漏一个字符：差异只落在漏掉的那一个字符上', () {
      final diff = termDiff(expected: 'apple', actual: 'aple')!;

      expect(_segments(diff.expected), <(String, bool)>[
        ('ap', false),
        ('p', true),
        ('le', false),
      ]);
      expect(_segments(diff.actual), <(String, bool)>[('aple', false)]);
    });

    test('替换一个字符：两侧各有一段差异', () {
      final diff = termDiff(expected: 'apple', actual: 'apply')!;

      expect(_segments(diff.expected), <(String, bool)>[
        ('appl', false),
        ('e', true),
      ]);
      expect(_segments(diff.actual), <(String, bool)>[
        ('appl', false),
        ('y', true),
      ]);
    });

    test('多写一个字符：只有用户输入一侧有差异段', () {
      final diff = termDiff(expected: 'cat', actual: 'cats')!;

      expect(_segments(diff.expected), <(String, bool)>[('cat', false)]);
      expect(_segments(diff.actual), <(String, bool)>[
        ('cat', false),
        ('s', true),
      ]);
    });

    test('完全无关的输入：两侧各成一段差异', () {
      final diff = termDiff(expected: 'cat', actual: 'dog')!;

      expect(_segments(diff.expected), <(String, bool)>[('cat', true)]);
      expect(_segments(diff.actual), <(String, bool)>[('dog', true)]);
    });
  });

  group('词级 diff', () {
    test('用户输入为空时不渲染', () {
      expect(sentenceDiff(expected: 'I ate an apple', actual: '  '), isNull);
    });

    test('归一化后相等时不渲染（大小写与句末标点）', () {
      expect(
        sentenceDiff(expected: 'I ate an apple.', actual: 'i ATE an apple'),
        isNull,
      );
    });

    test('缩写展开后相等时不渲染', () {
      expect(sentenceDiff(expected: 'I am here', actual: "I'm here"), isNull);
    });

    test('漏词归类为 missing，并给出编辑距离与参考原文', () {
      final diff = sentenceDiff(
        expected: 'I ate an apple',
        actual: 'I ate apple',
      )!;

      expect(diff.words.map((word) => word.word).toList(), <String>[
        'i',
        'ate',
        'an',
        'apple',
      ]);
      expect(diff.words[2].kind, SentenceDiffKind.missing);
      expect(
        diff.words.where((word) => word.kind == SentenceDiffKind.equal),
        hasLength(3),
      );
      expect(diff.editDistance, 3);
      expect(diff.expectedText, 'I ate an apple');
    });

    test('多写的词归类为 extra', () {
      final diff = sentenceDiff(
        expected: 'I ate apple',
        actual: 'I ate an apple',
      )!;

      expect(diff.words[2].word, 'an');
      expect(diff.words[2].kind, SentenceDiffKind.extra);
    });
  });
}
