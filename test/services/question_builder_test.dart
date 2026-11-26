/// [QuestionBuilder] 的测试。
///
/// 用假的 [DistractorSource] 记录「按什么顺序、查了几次」，
/// 这样「易混词能凑满时不许再查数据库」这类**性能语义**也能被断言，
/// 而不只是断言最终选项集合。全程不碰数据库。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/review/distractors.dart';
import 'package:lexiloop/services/question_builder.dart';

/// 正确项的释义：`apple` → `苹果`。
const List<DefinitionValue> _appleDefinitions = <DefinitionValue>[
  DefinitionValue(language: 'zh', text: '苹果'),
];

void main() {
  group('meaningChoices', () {
    test('正确项恰好出现一次，选项数不超过 meaningChoiceCount', () async {
      final builder = QuestionBuilder(
        _FakeDistractorSource(
          confusedRows: <DistractorRow>[
            _row(2, 'banana', '香蕉'),
            _row(3, 'cherry', '樱桃'),
            _row(4, 'date', '枣'),
            _row(5, 'elder', '接骨木'),
          ],
        ),
      );

      final choices = await builder.meaningChoices(
        wordId: 1,
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>['banana', 'cherry'],
      );

      expect(choices, hasLength(meaningChoiceCount));
      expect(choices.where((choice) => choice == '苹果'), hasLength(1));
      expect(choices.toSet(), hasLength(choices.length));
    });

    test('易混词凑满时不再查活跃错词与全局池', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[
          _row(2, 'banana', '香蕉'),
          _row(3, 'cherry', '樱桃'),
          _row(4, 'date', '枣'),
        ],
        wrongRows: <DistractorRow>[_row(9, 'wrong', '错词释义')],
        poolRows: <DistractorRow>[_row(8, 'pool', '池释义')],
      );

      final choices = await QuestionBuilder(source).meaningChoices(
        wordId: 1,
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>['banana'],
      );

      expect(choices, hasLength(meaningChoiceCount));
      expect(source.calls, <String>['byTerms']);
      expect(choices, isNot(contains('错词释义')));
      expect(choices, isNot(contains('池释义')));
    });

    test('易混词不足时回退到活跃错词，再不足时回退到全局池', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[_row(2, 'banana', '香蕉')],
        wrongRows: <DistractorRow>[_row(9, 'wrong', '错词释义')],
        poolRows: <DistractorRow>[_row(8, 'pool', '池释义')],
      );

      final choices = await QuestionBuilder(source).meaningChoices(
        wordId: 1,
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>['banana'],
      );

      expect(source.calls, <String>[
        'byTerms',
        'activeWrongWords',
        'randomPool',
      ]);
      expect(choices, hasLength(meaningChoiceCount));
      expect(source.lastPoolCount, distractorTakeSize);
      expect(source.lastExcludedIds, <int>{1});
    });

    test('活跃错词凑满时不再查全局池', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[_row(2, 'banana', '香蕉')],
        wrongRows: <DistractorRow>[
          _row(9, 'wrong', '错词释义'),
          _row(10, 'wrong2', '错词释义二'),
        ],
        poolRows: <DistractorRow>[_row(8, 'pool', '池释义')],
      );

      final choices = await QuestionBuilder(source).meaningChoices(
        wordId: 1,
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>['banana'],
      );

      expect(source.calls, <String>['byTerms', 'activeWrongWords']);
      expect(choices, hasLength(meaningChoiceCount));
    });

    test('易混词为空时不查易混词表', () async {
      final source = _FakeDistractorSource(
        wrongRows: <DistractorRow>[
          _row(9, 'wrong', '错词释义'),
          _row(10, 'wrong2', '错词释义二'),
          _row(11, 'wrong3', '错词释义三'),
        ],
      );

      final choices = await QuestionBuilder(source).meaningChoices(
        wordId: 1,
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>[],
      );

      expect(source.calls, <String>['activeWrongWords']);
      expect(choices, hasLength(meaningChoiceCount));
    });

    test('与正确项重复的干扰项被剔除，大小写与空白不同也算重复', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[
          _row(2, 'dup', 'Apple Fruit'),
          _row(3, 'dup2', '  apple fruit  '),
          _row(4, 'banana', '香蕉'),
          _row(5, 'cherry', '樱桃'),
          _row(6, 'date', '枣'),
        ],
      );

      final choices = await QuestionBuilder(source).meaningChoices(
        wordId: 1,
        targetLanguage: 'zh',
        definitions: const <DefinitionValue>[
          DefinitionValue(language: 'zh', text: 'apple fruit'),
        ],
        confusedTerms: const <String>['dup'],
      );

      expect(choices, hasLength(meaningChoiceCount));
      expect(
        choices.where((choice) => choice.toLowerCase() == 'apple fruit'),
        hasLength(1),
      );
      expect(choices, contains('香蕉'));
    });

    test('候选不足时返回已凑到的选项，而不是空列表', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[_row(2, 'banana', '香蕉')],
      );

      final choices = await QuestionBuilder(source).meaningChoices(
        wordId: 1,
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>['banana'],
      );

      expect(choices, unorderedEquals(<String>['苹果', '香蕉']));
    });

    test('正确项释义全空时返回空列表，且不查任何候选来源', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[_row(2, 'banana', '香蕉')],
      );

      final choices = await QuestionBuilder(source).meaningChoices(
        wordId: 1,
        targetLanguage: 'zh',
        definitions: const <DefinitionValue>[
          DefinitionValue(language: 'zh', text: '   '),
        ],
        confusedTerms: const <String>['banana'],
      );

      expect(choices, isEmpty);
      expect(source.calls, isEmpty);
    });
  });

  group('wordChoices', () {
    test('每个选项都有释义，正确项映射到目标语言释义', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[
          _row(2, 'banana', '香蕉'),
          _row(3, 'cherry', '樱桃'),
        ],
      );

      final result = await QuestionBuilder(source).wordChoices(
        wordId: 1,
        term: ' apple ',
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>['banana'],
      );

      expect(result.choices, hasLength(3));
      expect(result.choiceDefinitions.keys.toSet(), result.choices.toSet());
      expect(result.choiceDefinitions['apple'], '苹果');
      expect(result.choiceDefinitions['banana'], '香蕉');
      expect(result.choiceDefinitions['cherry'], '樱桃');
    });

    test('不含空白词条与无释义词条，正确项恰好出现一次', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[
          _row(2, '   ', '空白词条'),
          _row(3, 'Apple', '重复的正确项'),
          _row(4, '', '空词条'),
          _row(5, 'banana', '   '),
          _row(6, 'cherry', '樱桃'),
        ],
      );

      final result = await QuestionBuilder(source).wordChoices(
        wordId: 1,
        term: 'apple',
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>['banana'],
      );

      expect(result.choices, unorderedEquals(<String>['apple', 'cherry']));
      expect(result.choiceDefinitions.keys.toSet(), result.choices.toSet());
      expect(result.choiceDefinitions, isNot(contains('Apple')));
    });

    test('逐级回退：易混词不足时依次查活跃错词与全局池', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[_row(2, 'banana', '香蕉')],
        wrongRows: <DistractorRow>[_row(3, 'wrong', '错词释义')],
        poolRows: <DistractorRow>[_row(4, 'pool', '池释义')],
      );

      final result = await QuestionBuilder(source).wordChoices(
        wordId: 1,
        term: 'apple',
        targetLanguage: 'zh',
        definitions: _appleDefinitions,
        confusedTerms: const <String>['banana'],
      );

      expect(source.calls, <String>[
        'byTerms',
        'activeWrongWords',
        'randomPool',
      ]);
      expect(result.choices, hasLength(meaningChoiceCount));
      expect(result.choiceDefinitions.keys.toSet(), result.choices.toSet());
    });

    test('释义全空时返回空选项与空映射，且不查任何候选来源', () async {
      final source = _FakeDistractorSource(
        confusedRows: <DistractorRow>[_row(2, 'banana', '香蕉')],
      );

      final result = await QuestionBuilder(source).wordChoices(
        wordId: 1,
        term: 'apple',
        targetLanguage: 'zh',
        definitions: const <DefinitionValue>[
          DefinitionValue(language: 'zh', text: ''),
        ],
        confusedTerms: const <String>['banana'],
      );

      expect(result.choices, isEmpty);
      expect(result.choiceDefinitions, isEmpty);
      expect(source.calls, isEmpty);
    });
  });
}

/// 记录调用顺序的假干扰项来源。
class _FakeDistractorSource implements DistractorSource {
  new({
    this.confusedRows = const <DistractorRow>[],
    this.wrongRows = const <DistractorRow>[],
    this.poolRows = const <DistractorRow>[],
  });

  /// 易混词查询返回的行。
  final List<DistractorRow> confusedRows;

  /// 活跃错词查询返回的行。
  final List<DistractorRow> wrongRows;

  /// 全局池查询返回的行。
  final List<DistractorRow> poolRows;

  /// 按发生顺序记录的方法名，用于断言调用顺序与次数。
  final List<String> calls = <String>[];

  /// 最后一次 `randomPool` 收到的期望条数。
  int? lastPoolCount;

  /// 最后一次 `randomPool` 收到的排除集合。
  Set<int>? lastExcludedIds;

  @override
  Future<List<DistractorRow>> byTerms(
    List<String> terms,
    int excludedWordId,
  ) async {
    calls.add('byTerms');
    return confusedRows;
  }

  @override
  Future<List<DistractorRow>> activeWrongWords(int excludedWordId) async {
    calls.add('activeWrongWords');
    return wrongRows;
  }

  @override
  Future<List<DistractorRow>> randomPool(
    Set<int> excludedWordIds,
    int count,
  ) async {
    calls.add('randomPool');
    lastExcludedIds = excludedWordIds;
    lastPoolCount = count;
    return poolRows;
  }
}

/// 造一行带目标语言释义的干扰项候选。
DistractorRow _row(int wordId, String term, String definition) => DistractorRow(
  wordId: wordId,
  term: term,
  definitionsJson: jsonEncode(<Map<String, String>>[
    <String, String>{'language': 'zh', 'text': definition},
  ]),
);
