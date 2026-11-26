/// 通用词表解析与自定义 CSV 列映射单元测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/import/csv_columns.dart';
import 'package:lexiloop/data/import/wordlist_parser.dart';
import 'package:lexiloop/domain/enums.dart';

void main() {
  group('parseWordlistText', () {
    test('支持编号纯文本、竖线释义、注释行与去重', () {
      const txt = '''
# 雅思高频词
1. resilient | 有弹性的；适应力强的
2) ubiquitous
3、pragmatic
resilient | 重复项
''';
      final parsed = parseWordlistText(
        txt,
        sourceLanguage: 'en',
        targetLanguage: 'zh-CN',
        extraTags: const <String>['IELTS'],
      );
      expect(parsed.rows, hasLength(4));
      expect(parsed.rows[0].term, 'resilient');
      expect(parsed.rows[0].definitionText, '有弹性的；适应力强的');
      expect(parsed.rows[0].tags, <String>['IELTS']);
      expect(parsed.rows[1].term, 'ubiquitous');
      expect(parsed.rows[1].definitionText, isNull);
      expect(parsed.rows[2].term, 'pragmatic');
      expect(parsed.rows[3].status, ImportRowStatus.duplicate);
    });

    test('支持两列与三列 TSV（Anki / 欧路风格）', () {
      const twoCol = 'meticulous\t一丝不苟的\nserendipity\t意外发现\n';
      final parsedTwo = parseWordlistText(
        twoCol,
        sourceLanguage: 'en',
        targetLanguage: 'zh-CN',
      );
      expect(parsedTwo.rows, hasLength(2));
      expect(parsedTwo.rows.first.term, 'meticulous');
      expect(parsedTwo.rows.first.definitionText, '一丝不苟的');

      const threeCol = 'ephemeral\t/ɪˈfemərəl/\t短暂的\n';
      final parsedThree = parseWordlistText(
        threeCol,
        sourceLanguage: 'en',
        targetLanguage: 'zh-CN',
      );
      expect(parsedThree.rows.single.term, 'ephemeral');
      expect(parsedThree.rows.single.phonetic, '/ɪˈfemərəl/');
      expect(parsedThree.rows.single.definitionText, '短暂的');
    });

    test('带标准表头的 TSV 自动识别各列', () {
      const tsv = 'word\tmeaning\ttags\nubiquitous\t无处不在的\tCET6,高频\n';
      final parsed = parseWordlistText(
        tsv,
        sourceLanguage: 'en',
        targetLanguage: 'zh-CN',
        extraTags: const <String>['2026'],
      );
      expect(parsed.rows, hasLength(1));
      expect(parsed.rows.single.term, 'ubiquitous');
      expect(parsed.rows.single.definitionText, '无处不在的');
      expect(parsed.rows.single.tags, <String>['CET6', '高频', '2026']);
    });
  });

  group('自定义 CSV 列映射', () {
    test('inspectCsvForColumnMapping 提取表头与样本行，再按映射解析', () {
      const csv = 'ColA,ColB,ColC\nabandon,放弃,CET4\nresilient,有韧性的,IELTS\n';
      final draft = inspectCsvForColumnMapping(csv, filename: 'custom.csv');
      expect(draft, isNotNull);
      expect(draft!.headers, <String>['ColA', 'ColB', 'ColC']);
      expect(draft.sampleRows, hasLength(3));

      final parsed = parseDelimitedWithColumnMap(
        csv,
        sourceLanguage: 'en',
        targetLanguage: 'zh-CN',
        columns: const <CsvField, int>{
          CsvField.term: 0,
          CsvField.definition: 1,
          CsvField.tags: 2,
        },
        extraTags: const <String>['自建词表'],
      );
      expect(parsed.rows, hasLength(2));
      expect(parsed.rows[0].term, 'abandon');
      expect(parsed.rows[0].definitionText, '放弃');
      expect(parsed.rows[0].tags, <String>['CET4', '自建词表']);
      expect(parsed.rows[1].term, 'resilient');
    });
  });

  test('appendExtraTags 合并标签且去重', () {
    final base = parseWordlistText(
      'word\ttags\nalpha\tCET4\n',
      sourceLanguage: 'en',
      targetLanguage: 'zh-CN',
    );
    final merged = appendExtraTags(base, const <String>['CET4', ' 冲刺 ']);
    expect(merged.rows.single.tags, <String>['CET4', '冲刺']);
  });
}
