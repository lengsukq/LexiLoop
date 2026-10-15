/// 拼写判分的单元测试。
///
/// 这一层的每个函数都直接决定「用户答对了还是答错了」，
/// 判错会打击信心、判对会放过漏洞，因此逐条断言边界。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/review/spelling.dart';

void main() {
  group('levenshteinDistance', () {
    test('相同字符串距离为 0', () {
      expect(levenshteinDistance('apple', 'apple'), 0);
      expect(levenshteinDistance('', ''), 0);
    });

    test('空串与非空串的距离等于长度', () {
      expect(levenshteinDistance('', 'abc'), 3);
      expect(levenshteinDistance('abc', ''), 3);
    });

    test('经典用例 kitten → sitting 为 3', () {
      expect(levenshteinDistance('kitten', 'sitting'), 3);
    });

    test('单字符替换为 1', () {
      expect(levenshteinDistance('definately', 'definitely'), 1);
    });

    test('换位需要 2 步（Levenshtein 不支持换位为一）', () {
      expect(levenshteinDistance('beleive', 'believe'), 2);
    });

    test('结果与参数顺序无关', () {
      expect(
        levenshteinDistance('recieve', 'receive'),
        levenshteinDistance('receive', 'recieve'),
      );
    });
  });

  group('canonicalTerm', () {
    test('英式拼写归一为美式', () {
      expect(canonicalTerm('colour'), 'color');
      expect(canonicalTerm('centre'), 'center');
      expect(canonicalTerm('organise'), 'organize');
    });

    test('无映射时原样返回', () {
      expect(canonicalTerm('apple'), 'apple');
      expect(canonicalTerm(''), '');
    });
  });

  group('normalizeSentenceAnswer', () {
    test('展开缩写', () {
      expect(normalizeSentenceAnswer("I don't like it."), 'i do not like it');
      expect(normalizeSentenceAnswer("It's fine"), 'it is fine');
    });

    test('归一英式拼写', () {
      expect(normalizeSentenceAnswer('Colour, centre!'), 'color center');
    });

    test('统一弯引号为直引号后再展开', () {
      expect(normalizeSentenceAnswer('I don’t know'), 'i do not know');
    });

    test('去除全部标点与多余空白', () {
      expect(normalizeSentenceAnswer('  Hello,   world!!  '), 'hello world');
    });

    test('大小写不敏感', () {
      expect(
        normalizeSentenceAnswer('The QUICK brown fox'),
        normalizeSentenceAnswer('the quick Brown FOX'),
      );
    });

    test('纯标点输入得到空串', () {
      expect(normalizeSentenceAnswer('!!! ...'), '');
    });
  });

  group('sentenceFuzzyTolerance', () {
    test('短句至少容忍 1 个字符', () {
      expect(sentenceFuzzyTolerance(10), 1);
      expect(sentenceFuzzyTolerance(20), 1);
    });

    test('长句按比例放大', () {
      expect(sentenceFuzzyTolerance(100), 8);
      expect(sentenceFuzzyTolerance(200), 16);
    });
  });

  group('isSingleTypoOf', () {
    test('长词允许 1 个字母的手误', () {
      expect(isSingleTypoOf('definately', 'definitely'), isTrue);
    });

    test('短词不放宽（否则 cat/cut 会误判）', () {
      expect(isSingleTypoOf('colur', 'color'), isFalse);
      expect(isSingleTypoOf('cut', 'cat'), isFalse);
    });

    test('长词但距离超过 1 时不算手误', () {
      expect(isSingleTypoOf('recieve', 'receive'), isFalse);
    });

    test('完全不同的长词不算手误', () {
      expect(isSingleTypoOf('elephant', 'definitely'), isFalse);
    });
  });
}
