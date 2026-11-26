/// 词条发音解析与口音选取的测试。
///
/// 这三段逻辑在旧版里被内联在 `selection.ts` 中，`GENERAL` 口音兼容、
/// 斜杠补全、非法 JSON 兜底都只靠人工评审；拆出来后可以逐条断言。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/phonetics/pronunciation.dart';

void main() {
  group('parsePronunciationsJson', () {
    test('解析 US / UK 两种口音', () {
      final items = parsePronunciationsJson(
        '[{"accent":"US","phonetic":"ʃiːp"},'
        '{"accent":"UK","phonetic":"ʃiːp"}]',
      );
      expect(items.length, 2);
      expect(items.first.accent, Accent.us);
      expect(items.last.accent, Accent.uk);
    });

    test('历史数据里的 GENERAL 归入美音', () {
      final items = parsePronunciationsJson(
        '[{"accent":"GENERAL","phonetic":"kæt"}]',
      );
      expect(items.single.accent, Accent.us);
    });

    test('非法 JSON、非数组、缺字段都被过滤', () {
      expect(parsePronunciationsJson('不是 JSON'), isEmpty);
      expect(parsePronunciationsJson('{"accent":"US"}'), isEmpty);
      expect(parsePronunciationsJson('[{"accent":"US"}]'), isEmpty);
      expect(
        parsePronunciationsJson('[{"accent":"US","phonetic":"  "}]'),
        isEmpty,
      );
      expect(parsePronunciationsJson('[]'), isEmpty);
      expect(parsePronunciationsJson(null), isEmpty);
    });
  });

  group('selectPronunciation', () {
    final items = parsePronunciationsJson(
      '[{"accent":"US","phonetic":"kɑr"},{"accent":"UK","phonetic":"kɑː"}]',
    );

    test('按口音精确选取并补斜杠', () {
      expect(selectPronunciation(items, Accent.us), '/kɑr/');
      expect(selectPronunciation(items, Accent.uk), '/kɑː/');
    });

    test('缺少该口音时返回 null，不回退到另一口音', () {
      final onlyUs = parsePronunciationsJson(
        '[{"accent":"US","phonetic":"kɑr"}]',
      );
      expect(selectPronunciation(onlyUs, Accent.uk), isNull);
    });
  });

  group('displayPhonetic', () {
    test('已有斜杠或方括号的原样保留', () {
      expect(displayPhonetic('/kæt/'), '/kæt/');
      expect(displayPhonetic('[kæt]'), '[kæt]');
    });

    test('补全斜杠并压缩空白', () {
      expect(displayPhonetic('  kæt  '), '/kæt/');
      expect(displayPhonetic('ˈæp  əl'), '/ˈæp əl/');
    });

    test('空串返回空串', () {
      expect(displayPhonetic('   '), '');
    });
  });
}
