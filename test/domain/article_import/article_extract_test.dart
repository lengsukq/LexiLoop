/// 文章抽取与分段的单元测试。
///
/// 钉住的性质：清洗（NFKC / 换行 / 空白）、停用词与长度过滤、词形去重计数
/// 与排序、切句、**分段边界（含尾段合并与上限合并）**、分批夹取。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/article_import/article_extract.dart';

void main() {
  group('清洗', () {
    test('NFKC 规范化、统一换行、压缩行内空白并去首尾', () {
      expect(cleanArticle('  a\t\tb\r\nc  '), 'a b\nc');
    });

    test('全角字符被规范化为半角', () {
      expect(cleanArticle('ＡＢＣ'), 'ABC');
    });
  });

  group('切句', () {
    test('按中英文句末标点切分，末尾残句也算一句', () {
      final sentences = extractSentences('One. Two! Three 没有标点');
      expect(sentences, <String>['One.', 'Two!', 'Three 没有标点']);
    });

    test('没有句末标点时整体作为一句', () {
      expect(extractSentences('no terminator here'), <String>[
        'no terminator here',
      ]);
    });
  });

  group('词形提取', () {
    test('统计词数、去重并去掉停用词', () {
      final result = extractArticleTerms(
        'The cat sat on the mat. The cat ran.',
      );
      final terms = result.extracted
          .map((item) => item.normalizedTerm)
          .toList();
      // the / on 是停用词；cat 出现 2 次排在最前。
      expect(terms.first, 'cat');
      expect(terms, containsAll(<String>['cat', 'sat', 'mat', 'ran']));
      expect(terms, isNot(contains('the')));
      expect(terms, isNot(contains('on')));
      expect(result.wordCount, 9);
      expect(
        result.extracted.firstWhere((item) => item.term == 'cat').occurrences,
        2,
      );
    });

    test('保留首次出现的大小写，但归一化词形取小写', () {
      final result = extractArticleTerms('Apple apple APPLE');
      expect(result.extracted.single.term, 'Apple');
      expect(result.extracted.single.normalizedTerm, 'apple');
      expect(result.extracted.single.occurrences, 3);
    });

    test('过滤单字符与超长词形', () {
      final long = 'a' * (articleTokenMaxChars + 1);
      final result = extractArticleTerms('I a $long valid');
      final terms = result.extracted
          .map((item) => item.normalizedTerm)
          .toList();
      expect(terms, <String>['valid']);
    });

    test('去掉词首词尾的撇号与连字符', () {
      final result = extractArticleTerms("'quoted' --dashed--");
      final terms = result.extracted
          .map((item) => item.normalizedTerm)
          .toList();
      expect(terms, containsAll(<String>['quoted', 'dashed']));
    });

    test('排序：出现次数降序 → 长度降序 → 词形升序', () {
      final result = extractArticleTerms(
        'beta beta gamma gamma alphabet alphabet',
      );
      expect(
        result.extracted.map((item) => item.normalizedTerm).toList(),
        <String>['alphabet', 'gamma', 'beta'],
      );
    });

    test('清洗后的正文一并返回', () {
      final result = extractArticleTerms('  Hello   world  ');
      expect(result.cleaned, 'Hello world');
    });
  });

  group('分段', () {
    test('按空行分段', () {
      final first = 'a' * articleTailMergeThreshold;
      final second = 'b' * articleTailMergeThreshold;
      final segments = segmentArticleParagraphs('$first\n\n$second');
      expect(segments.length, 2);
      expect(segments.first.id, 'seg-1');
      expect(segments.last.id, 'seg-2');
      expect(segments.first.text, first);
      expect(segments.last.text, second);
    });

    test('没有空行但有多个单换行时按行分段', () {
      final first = 'a' * articleTailMergeThreshold;
      final second = 'b' * articleTailMergeThreshold;
      final segments = segmentArticleParagraphs('$first\n$second');
      expect(segments.length, 2);
    });

    test('末段短于阈值时并入前一段', () {
      final head = 'a' * articleTailMergeThreshold;
      final segments = segmentArticleParagraphs('$head\n\nshort');
      expect(segments.length, 1);
      expect(segments.single.text, '$head\n\nshort');
      expect(segments.single.charCount, head.length + 2 + 'short'.length);
    });

    test('空文章返回空列表', () {
      expect(segmentArticleParagraphs('   \n  '), isEmpty);
    });

    test('超长段按句切到目标字符数附近', () {
      const sentence = 'word word word word.'; // 20 字符
      final paragraph = List<String>.filled(4, sentence).join(' ');
      final segments = segmentArticleParagraphs(
        paragraph,
        targetChars: 45,
        maxChars: 50,
      );
      expect(segments.length, greaterThan(1));
      for (final segment in segments) {
        expect(segment.charCount, lessThanOrEqualTo(paragraph.length));
        expect(segment.text, isNotEmpty);
      }
      // 所有分段的正文拼起来必须覆盖原文（只多出用于连接的空白）。
      expect(
        segments.map((s) => s.text).join(' ').replaceAll(' ', ''),
        paragraph.replaceAll(' ', ''),
      );
    });

    test('无法切句的超长段按目标字符数硬切', () {
      final paragraph = 'x' * 25;
      final segments = segmentArticleParagraphs(
        paragraph,
        targetChars: 10,
        maxChars: 20,
      );
      expect(segments.length, 3);
      expect(segments.map((s) => s.charCount).toList(), <int>[10, 10, 5]);
    });

    test('超过上限时反复合并最小的相邻段', () {
      final texts = <String>['a' * 80, 'b' * 5, 'c' * 90, 'd' * 5];
      final segments = segmentArticleParagraphs(
        texts.join('\n\n'),
        maxSegments: 2,
      );
      expect(segments.length, 2);
      // 第一轮最小相邻对是 (0,1)（80+5），第二轮是 (1,2)（90+5）。
      expect(segments[0].text, '${texts[0]}\n\n${texts[1]}');
      expect(segments[1].text, '${texts[2]}\n\n${texts[3]}');
      expect(segments.map((s) => s.index).toList(), <int>[0, 1]);
      expect(segments.map((s) => s.id).toList(), <String>['seg-1', 'seg-2']);
    });

    test('分段序号与字符数自洽', () {
      final segments = segmentArticleParagraphs(
        <String>['a' * 70, 'b' * 70].join('\n\n'),
      );
      for (final segment in segments) {
        expect(segment.index, segments.indexOf(segment));
        expect(segment.charCount, segment.text.length);
        expect(segment.id, 'seg-${segment.index + 1}');
      }
    });
  });

  group('分批', () {
    test('每批段数被夹到 1 与上限之间', () {
      final segments = segmentArticleParagraphs(
        <String>[for (var index = 0; index < 5; index += 1) 'p$index' * 30]
            .join('\n\n'),
      );
      expect(segments.length, 5);
      expect(batchesForSegments(segments, 0).length, 5);
      expect(batchesForSegments(segments, 2).length, 3);
      expect(
        batchesForSegments(segments, maxArticleSegmentsPerBatch + 5).length,
        1,
      );
    });

    test('批次带序号、分段 ID 与字符数合计', () {
      final segments = segmentArticleParagraphs(
        <String>['a' * 70, 'b' * 70, 'c' * 70].join('\n\n'),
      );
      final batches = batchesForSegments(segments, 2);
      expect(batches.length, 2);
      expect(batches.first.batchIndex, 0);
      expect(batches.first.segmentIds, <String>['seg-1', 'seg-2']);
      expect(
        batches.first.charCount,
        segments[0].charCount + segments[1].charCount,
      );
      expect(batches.last.segmentIds, <String>['seg-3']);
    });

    test('分段方案同时给出分段与分批', () {
      final plan = buildArticleSegmentPlan(
        <String>['a' * 70, 'b' * 70, 'c' * 70].join('\n\n'),
        segmentsPerBatch: 2,
      );
      expect(plan.segments.length, 3);
      expect(plan.batches.length, 2);
      expect(plan.totalChars, greaterThan(0));
    });
  });
}
