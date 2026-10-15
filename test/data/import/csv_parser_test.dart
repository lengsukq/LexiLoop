/// EasyDict CSV 解析的单测。
///
/// 覆盖列名宽松匹配、行数上限、缺表头、非法行与批次内去重——
/// 这些都是旧版「换个导出模板就整批报错」的根因。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/import/csv_parser.dart';
import 'package:lexiloop/domain/enums.dart';

void main() {
  CsvParseResult parse(String content) =>
      parseEasyDictCsv(content, sourceLanguage: 'en', targetLanguage: 'zh');

  group('正常解析', () {
    test('中英文字段全部落位', () {
      const content =
          '单词,释义,音标,例句,短语,同义词,反义词,词根,词缀,词族,易混词,标签\n'
          'apple,苹果,/ˈæpl/,"An apple a day.",in apple pie order,'
          'fruit; pome,orange,app-,re-,apple tree,apply,水果;食物\n';

      final result = parse(content);

      expect(result.skippedCount, 0);
      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.rowNumber, 1);
      expect(row.term, 'apple');
      expect(row.normalizedTerm, 'apple');
      expect(row.definitionText, '苹果');
      expect(row.phonetic, '/ˈæpl/');
      expect(row.examples, <String>['An apple a day.']);
      expect(row.phrases, <String>['in apple pie order']);
      expect(row.synonyms, <String>['fruit', 'pome']);
      expect(row.antonyms, <String>['orange']);
      expect(row.roots, <String>['app-']);
      expect(row.affixes, <String>['re-']);
      expect(row.wordFamilies, <String>['apple tree']);
      expect(row.confusedWords, <String>['apply']);
      expect(row.tags, <String>['水果', '食物']);
      expect(row.contentType, LexicalContentType.word);
      expect(row.isValid, isTrue);
      expect(row.errorMessage, isNull);
    });

    test('英文表头大小写与空格宽松匹配', () {
      const content =
          '  Word , Definition , Word Family ,Confused Words\n'
          'run,跑,runner,ran\n';

      final result = parse(content);

      final row = result.rows.single;
      expect(row.term, 'run');
      expect(row.definitionText, '跑');
      expect(row.wordFamilies, <String>['runner']);
      expect(row.confusedWords, <String>['ran']);
    });

    test('下划线与驼峰表头同样匹配', () {
      const content =
          'word,definition,word_family,confusedWords,Phonetic\n'
          'go,去,going,goes,ɡəʊ\n';

      final row = parse(content).rows.single;
      expect(row.wordFamilies, <String>['going']);
      expect(row.confusedWords, <String>['goes']);
      expect(row.phonetic, 'ɡəʊ');
    });

    test('带 BOM 的文件也能解析', () {
      const content = '\uFEFF单词,释义\nbook,书\n';
      expect(parse(content).rows.single.term, 'book');
    });

    test('未知列被忽略', () {
      const content = '序号,单词,难度,释义\n1,cat,A1,猫\n';
      final row = parse(content).rows.single;
      expect(row.term, 'cat');
      expect(row.definitionText, '猫');
    });

    test('空行计入 skippedCount 且不进入 rows', () {
      const content = '单词,释义\ncat,猫\n\n,\ndog,狗\n';
      final result = parse(content);
      expect(result.skippedCount, 2);
      expect(result.rows.map((row) => row.term), <String>['cat', 'dog']);
    });
  });

  group('错误', () {
    test('缺词条列抛 csvMissingHeaders', () {
      const content = '释义,音标\n苹果,/ˈæpl/\n';
      expect(
        () => parse(content),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.csvMissingHeaders,
          ),
        ),
      );
    });

    test('空文件抛 csvMissingHeaders', () {
      expect(
        () => parse(''),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.csvMissingHeaders,
          ),
        ),
      );
    });

    test('超过行数上限抛 csvTooManyRows', () {
      final buffer = StringBuffer('word,definition\n');
      for (var i = 0; i <= maxCsvRows; i += 1) {
        buffer.writeln('word$i,释义$i');
      }
      expect(
        () => parse(buffer.toString()),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.csvTooManyRows,
          ),
        ),
      );
    });

    test('含替换字符抛 csvEncodingInvalid', () {
      const content = '单词,释义\ncat,\uFFFD\n';
      expect(
        () => parse(content),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.csvEncodingInvalid,
          ),
        ),
      );
    });

    test('空词条标为 INVALID 且带中文提示', () {
      const content = '单词,释义\n,空词条\ndog,狗\n';
      final result = parse(content);

      final invalid = result.rows.first;
      expect(invalid.status, ImportRowStatus.invalid);
      expect(invalid.errorCode, AppErrorCode.termRequired);
      expect(invalid.errorMessage, '词条文本不能为空。');
      expect(result.rows.last.isValid, isTrue);
    });

    test('超长词条标为 INVALID', () {
      final long = List<String>.filled(termMaxLength + 1, 'a').join();
      final result = parse('单词,释义\n$long,长\n');
      expect(result.rows.single.errorCode, AppErrorCode.termTooLong);
    });
  });

  group('批次内去重', () {
    test('同键的第二行标 DUPLICATE', () {
      const content = '单词,释义\nApple,苹果\napple,苹果\nbanana,香蕉\n';
      final result = parse(content);

      expect(result.rows[0].status, ImportRowStatus.newWord);
      expect(result.rows[1].status, ImportRowStatus.duplicate);
      expect(result.rows[2].status, ImportRowStatus.newWord);
    });

    test('大小写与首尾空白不影响去重', () {
      const content = '单词,释义\n  Apple ,苹果\napple,苹果\n';
      final result = parse(content);
      expect(result.rows[0].term, 'Apple');
      expect(result.rows[0].normalizedTerm, 'apple');
      expect(result.rows[1].status, ImportRowStatus.duplicate);
    });

    test('非法行不参与去重计数', () {
      const content = '单词,释义\n,空\n,空\n';
      final result = parse(content);
      expect(
        result.rows.every((row) => row.status == ImportRowStatus.invalid),
        isTrue,
      );
    });
  });

  group('序列化', () {
    test('toJson / fromJson 往返保持内容', () {
      const content = '单词,释义,例句,标签\ncat,猫,"A cat.",动物;宠物\n';
      final row = parse(content).rows.single;
      final restored = ParsedCsvRow.fromJson(row.toJson());

      expect(restored, isNotNull);
      expect(restored!.term, 'cat');
      expect(restored.sourceLanguage, 'en');
      expect(restored.targetLanguage, 'zh');
      expect(restored.contentType, LexicalContentType.word);
      expect(restored.examples, <String>['A cat.']);
      expect(restored.tags, <String>['动物', '宠物']);
    });

    test('结构损坏时 fromJson 返回 null', () {
      expect(ParsedCsvRow.fromJson(<String, Object?>{'term': 'cat'}), isNull);
    });
  });
}
