/// 词条归一化与作答时长的单元测试。
///
/// 归一化是「导入」与「判题」共用的基准，两侧必须一致；
/// 时长上界则决定统计页的数字是否可信。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/review/duration.dart';
import 'package:lexiloop/domain/text/normalizer.dart';

void main() {
  group('normalizeTerm', () {
    test('小写语言族取小写', () {
      expect(normalizeTerm('Apple', 'en'), 'apple');
      expect(normalizeTerm('Straße', 'de'), 'straße');
    });

    test('非小写语言族保留大小写', () {
      expect(normalizeTerm('中文', 'zh'), '中文');
      expect(normalizeTerm('ÄÖÜ', 'tr'), 'ÄÖÜ');
    });

    test('压缩空白并去首尾', () {
      expect(normalizeTerm('  hello   world  ', 'en'), 'hello world');
      expect(normalizeTerm('a\t\nb', 'en'), 'a b');
    });

    test('全角字符做 NFKC 归一', () {
      expect(normalizeTerm('ＡＰＰＬＥ', 'en'), 'apple');
      expect(normalizeTerm('ｈｅｌｌｏ', 'en'), 'hello');
    });

    test('表意空格与不换行空格视为普通空白', () {
      expect(normalizeTerm('hello\u3000world', 'en'), 'hello world');
      expect(normalizeTerm('hello\u00a0world', 'en'), 'hello world');
    });

    test('空字符串与纯空白得到空串', () {
      expect(normalizeTerm('', 'en'), '');
      expect(normalizeTerm('   ', 'en'), '');
    });

    test('结果幂等', () {
      final once = normalizeTerm('  ＡppLE  ', 'en');
      expect(normalizeTerm(once, 'en'), once);
    });
  });

  group('displayTerm', () {
    test('单词按语言规则取小写', () {
      expect(displayTerm('Apple', 'en', LexicalContentType.word), 'apple');
    });

    test('短语与句子保留原始大小写', () {
      expect(
        displayTerm('New York', 'en', LexicalContentType.phrase),
        'New York',
      );
      expect(
        displayTerm('I am fine.', 'en', LexicalContentType.sentence),
        'I am fine.',
      );
    });

    test('非小写语言族的单词也保留大小写', () {
      expect(displayTerm('ÄÖÜ', 'tr', LexicalContentType.word), 'ÄÖÜ');
    });
  });

  group('identityKey', () {
    test('同文本不同语言得到不同键', () {
      expect(
        identityKey('apple', 'en', 'zh'),
        isNot(identityKey('apple', 'en', 'ja')),
      );
    });

    test('同文本同语言得到相同键', () {
      expect(
        identityKey('apple', 'en', 'zh'),
        identityKey('apple', 'en', 'zh'),
      );
    });

    test('用不可见分隔符避免文本含分隔符时碰撞', () {
      // 若用 '-' 作分隔符，('a-b','c') 与 ('a','b-c') 会撞成同一个键。
      expect(identityKey('a-b', 'c', 'd'), isNot(identityKey('a', 'b-c', 'd')));
    });
  });

  group('boundedActiveDurationMs', () {
    test('未测量时返回 null', () {
      expect(boundedActiveDurationMs(null), isNull);
    });

    test('负值夹到 0', () {
      expect(boundedActiveDurationMs(-1), 0);
      expect(boundedActiveDurationMs(-100000), 0);
    });

    test('正常值原样返回', () {
      expect(boundedActiveDurationMs(3000), 3000);
    });

    test('超长值夹到上限', () {
      expect(
        boundedActiveDurationMs(maxActiveAnswerDurationMs * 5),
        maxActiveAnswerDurationMs,
      );
      expect(
        boundedActiveDurationMs(maxActiveAnswerDurationMs),
        maxActiveAnswerDurationMs,
      );
    });
  });

  group('sumActiveDurations', () {
    test('跳过未测量与零值', () {
      expect(sumActiveDurations(<int?>[1000, null, 0, 2000]), 3000);
    });

    test('每项先夹到上限再累加', () {
      expect(
        sumActiveDurations(<int?>[maxActiveAnswerDurationMs, 5000]),
        maxActiveAnswerDurationMs + 5000,
      );
    });

    test('空集合为 0', () {
      expect(sumActiveDurations(const <int?>[]), 0);
    });
  });
}
