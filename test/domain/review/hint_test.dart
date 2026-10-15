/// 拼写题提示的纯函数单测。
///
/// 对应旧版 `study-client.tsx` 的 `getHintPattern` / `getProgressiveHint`。
/// 钉的是「露几个字母、留几个空、用不用空格分隔」——提示多露一个字母就等于
/// 少了一次回忆机会，长词的格式错了会让提示行折行到看不见。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/review/hint.dart';

/// 与界面层一致的提示边界值（`features/study/study_hint_bar.dart`）。
const int _edgeLetterCount = 2;

/// 与界面层一致的「长词」阈值。
const int _longTermLength = 12;

/// 基础提示模式。
String? _pattern(String term) => getHintPattern(
  term,
  edgeLetterCount: _edgeLetterCount,
  longTermLength: _longTermLength,
);

/// 渐进式提示。
String? _progressive(String term, int level) => getProgressiveHint(
  term,
  level,
  edgeLetterCount: _edgeLetterCount,
  longTermLength: _longTermLength,
);

/// 提示是否用尽。
bool _exhausted(String term, int level) =>
    isHintExhausted(term, level, edgeLetterCount: _edgeLetterCount);

void main() {
  group('基础提示模式', () {
    test('长度不超过 2 时不给提示', () {
      expect(_pattern('a'), isNull);
      expect(_pattern('ab'), isNull);
      expect(_pattern(''), isNull);
    });

    test('含空格的词条不给提示（短语与句子）', () {
      expect(_pattern('ice cream'), isNull);
      expect(_pattern('a b'), isNull);
    });

    test('长度不超过 12 时逐字符留空', () {
      expect(_pattern('apple'), 'a _ _ _ e');
      expect(_pattern('international'), 'i ___________ l');
    });

    test('长度正好 12 仍走逐字符留空', () {
      expect(_pattern('abcdefghijkl'), 'a _ _ _ _ _ _ _ _ _ _ l');
    });
  });

  group('渐进式提示', () {
    test('level 为 0 时与基础模式相同', () {
      expect(_progressive('apple', 0), _pattern('apple'));
    });

    test('每升一级多露一个字母', () {
      expect(_progressive('apple', 1), 'a p p _ e');
      expect(_progressive('apple', 2), 'a p p l e');
    });

    test('露出数量夹取到「长度 - 2」', () {
      expect(_progressive('apple', 3), 'a p p l e');
      expect(_progressive('apple', 99), 'a p p l e');
    });

    test('短词剩余的空位逐字符留空（不是连成一片）', () {
      expect(_progressive('beautiful', 1), 'b e a _ _ _ _ _ l');
    });

    test('长词用连续下划线且不插空格', () {
      expect(_progressive('international', 1), 'i nt_________ l');
      expect(_progressive('international', 11), 'i nternationa l');
    });

    test('不满足条件的词条同样返回 null', () {
      expect(_progressive('ab', 1), isNull);
      expect(_progressive('ice cream', 1), isNull);
    });
  });

  group('提示是否用尽', () {
    test('用尽阈值是「长度 - 2」', () {
      expect(_exhausted('apple', 2), isFalse);
      expect(_exhausted('apple', 3), isTrue);
      expect(_exhausted('international', 10), isFalse);
      expect(_exhausted('international', 11), isTrue);
    });
  });
}
