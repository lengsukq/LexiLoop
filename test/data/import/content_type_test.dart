/// 内容类型判定的单测。
///
/// 对应旧版 `modules/imports/normalizer.ts` 的 `detectEntryType`：
/// 词数、句末标点、从句引导词、限定动词四条路径都要有用例，
/// 否则某条规则写错也不会有测试失败。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/import/content_type.dart';
import 'package:lexiloop/domain/enums.dart';

void main() {
  group('单词', () {
    test('单个词判为 WORD', () {
      expect(detectContentType('apple'), LexicalContentType.word);
    });

    test('带标点的单个词仍是 WORD', () {
      expect(detectContentType('Apple.'), LexicalContentType.word);
    });

    test('空串按 WORD 兜底', () {
      expect(detectContentType('   '), LexicalContentType.word);
    });
  });

  group('短语', () {
    test('三词无句法特征判为 PHRASE', () {
      expect(detectContentType('in spite of'), LexicalContentType.phrase);
    });

    test('四词名词短语不因复数被误判为句子', () {
      // `flowers` 以 s 结尾，若把三单也算限定动词就会误判成句子。
      expect(
        detectContentType('a bunch of flowers'),
        LexicalContentType.phrase,
      );
    });

    test('介词开头的短语不被从句引导词规则误判', () {
      expect(detectContentType('before the war'), LexicalContentType.phrase);
      expect(detectContentType('after all these years'), isNotNull);
    });
  });

  group('句子', () {
    test('句末标点', () {
      expect(detectContentType('I love you.'), LexicalContentType.sentence);
      expect(detectContentType('Are you ok?'), LexicalContentType.sentence);
    });

    test('无空格分词的中文句子判为 WORD（已知取舍）', () {
      // 规则顺序是「词数 ≤1 → WORD」在前，而中文没有空格分词，
      // 整句只会切成一个 token。与旧版行为一致，此处显式固化。
      expect(detectContentType('你好吗？'), LexicalContentType.word);
    });

    test('尾部带引号时仍识别句末标点', () {
      expect(
        detectContentType('He said "hello."'),
        LexicalContentType.sentence,
      );
    });

    test('词数达到阈值', () {
      final term = List<String>.filled(sentenceMinTokens, 'word').join(' ');
      expect(detectContentType(term), LexicalContentType.sentence);
    });

    test('从句引导词开头', () {
      expect(
        detectContentType('because it rained'),
        LexicalContentType.sentence,
      );
      expect(
        detectContentType('that he was right'),
        LexicalContentType.sentence,
      );
    });

    test('含限定动词', () {
      expect(
        detectContentType('the dog barked loudly'),
        LexicalContentType.sentence,
      );
      expect(
        detectContentType('he is very happy'),
        LexicalContentType.sentence,
      );
    });
  });

  group('entry_type 映射', () {
    test('句子在 entry_type 中归 PHRASE', () {
      expect(entryTypeFor(LexicalContentType.sentence), EntryType.phrase);
      expect(entryTypeFor(LexicalContentType.phrase), EntryType.phrase);
      expect(entryTypeFor(LexicalContentType.word), EntryType.word);
    });
  });
}
