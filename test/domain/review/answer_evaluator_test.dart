/// 客观判题的单元测试。
///
/// 判题是「用户的努力是否被承认」的唯一裁决点，因此这里把
/// 每一个题型分支、每一个容错路径、以及「主观自评 vs 客观判定」
/// 的优先级都单独钉住。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/review/answer_evaluator.dart';

/// 构造一个词条；只覆盖被测字段。
ReviewWord _word({
  int id = 1,
  String term = 'apple',
  String normalizedTerm = 'apple',
  String sourceLanguage = 'en',
  String targetLanguage = 'zh',
  LexicalContentType contentType = LexicalContentType.word,
  InitializationStatus status = InitializationStatus.ready,
  bool isSuspended = false,
  String? definitionsJson,
}) => ReviewWord(
  id: id,
  term: term,
  normalizedTerm: normalizedTerm,
  sourceLanguage: sourceLanguage,
  targetLanguage: targetLanguage,
  contentType: contentType,
  initializationStatus: status,
  isSuspended: isSuspended,
  definitionsJson: definitionsJson,
);

AnswerInput _answer({
  ReviewRating rating = ReviewRating.good,
  QuestionType questionType = QuestionType.zhToEnSpelling,
  String? userAnswer,
}) => AnswerInput(
  clientAnswerId: 'c1',
  wordId: 1,
  rating: rating,
  questionType: questionType,
  userAnswer: userAnswer,
);

/// 一条中文释义的 `definitions_json`。
const String _zhDefinitions = '[{"language":"zh","text":"苹果"}]';

void main() {
  group('题型分类', () {
    test('文本作答类题型可客观判分', () {
      for (final type in <QuestionType>[
        QuestionType.zhToEnSpelling,
        QuestionType.listeningSpelling,
        QuestionType.clozeSentence,
        QuestionType.letterBank,
      ]) {
        expect(isObjectivelyScored(type), isTrue, reason: type.wire);
      }
    });

    test('选择题型可客观判分', () {
      for (final type in <QuestionType>[
        QuestionType.enToZhChoice,
        QuestionType.zhToEnChoice,
        QuestionType.listeningChoice,
      ]) {
        expect(isObjectivelyScored(type), isTrue, reason: type.wire);
      }
    });

    test('自由作答的看英选中不可客观判分', () {
      expect(isObjectivelyScored(QuestionType.enToZh), isFalse);
    });
  });

  group('拼写判分', () {
    test('完全一致判对', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'apple'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isTrue);
      expect(result.effectiveRating, ReviewRating.good);
    });

    test('大小写不敏感', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'APPLE'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isTrue);
    });

    test('首尾空白被忽略', () {
      final result = evaluateAnswer(
        _answer(userAnswer: '  apple  '),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isTrue);
    });

    test('英式拼写判对', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'colour'),
        _word(
          term: 'color',
          normalizedTerm: 'color',
          definitionsJson: _zhDefinitions,
        ),
      );
      expect(result.isCorrect, isTrue);
    });

    test('长词单字母手误判对', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'definately'),
        _word(
          term: 'definitely',
          normalizedTerm: 'definitely',
          definitionsJson: _zhDefinitions,
        ),
      );
      expect(result.isCorrect, isTrue);
    });

    test('短词单字母错误判错', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'cut'),
        _word(
          term: 'cat',
          normalizedTerm: 'cat',
          definitionsJson: _zhDefinitions,
        ),
      );
      expect(result.isCorrect, isFalse);
    });

    test('完全不同的词判错', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'banana'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isFalse);
    });

    test('未作答判错', () {
      final result = evaluateAnswer(
        _answer(),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isFalse);
    });
  });

  group('句子判分', () {
    ReviewWord sentence(String term) => _word(
      term: term,
      normalizedTerm: term.toLowerCase(),
      contentType: LexicalContentType.sentence,
      definitionsJson: _zhDefinitions,
    );

    test('标点与大小写差异不影响判定', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'the quick brown fox jumps!'),
        sentence('The quick brown fox jumps.'),
      );
      expect(result.isCorrect, isTrue);
    });

    test('缩写与全写等价', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'i do not know'),
        sentence("I don't know."),
      );
      expect(result.isCorrect, isTrue);
    });

    test('长句允许少量字符误差', () {
      final result = evaluateAnswer(
        _answer(
          userAnswer:
              'the quick brown fox jumps over the lazy dogg near the river',
        ),
        sentence('The quick brown fox jumps over the lazy dog near the river.'),
      );
      expect(result.isCorrect, isTrue);
    });

    test('短句不容忍误差', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'i know'),
        sentence('I do not know.'),
      );
      expect(result.isCorrect, isFalse);
    });

    test('语义完全不同的长句判错', () {
      final result = evaluateAnswer(
        _answer(
          userAnswer: 'something entirely different written here for testing',
        ),
        sentence('The quick brown fox jumps over the lazy dog near the river.'),
      );
      expect(result.isCorrect, isFalse);
    });
  });

  group('选择题判分', () {
    test('看英选中：命中合并后的释义串', () {
      final result = evaluateAnswer(
        _answer(questionType: QuestionType.enToZhChoice, userAnswer: '苹果'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isTrue);
    });

    test('看英选中：命中单条释义', () {
      final word = _word(
        definitionsJson:
            '[{"language":"zh","text":"苹果"},{"language":"zh","text":"苹果树"}]',
      );
      final result = evaluateAnswer(
        _answer(questionType: QuestionType.enToZhChoice, userAnswer: '苹果树'),
        word,
      );
      expect(result.isCorrect, isTrue);
    });

    test('看英选中：未命中判错', () {
      final result = evaluateAnswer(
        _answer(questionType: QuestionType.enToZhChoice, userAnswer: '香蕉'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isFalse);
    });

    test('看英选中：没有释义时退回自评', () {
      expect(
        evaluateAnswer(
          _answer(questionType: QuestionType.enToZhChoice),
          _word(definitionsJson: '[]'),
        ).isCorrect,
        isTrue,
      );
      expect(
        evaluateAnswer(
          _answer(
            questionType: QuestionType.enToZhChoice,
            rating: ReviewRating.again,
          ),
          _word(definitionsJson: '[]'),
        ).isCorrect,
        isFalse,
      );
    });

    test('看汉选英：命中词条判对', () {
      final result = evaluateAnswer(
        _answer(questionType: QuestionType.zhToEnChoice, userAnswer: 'apple'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isTrue);
    });

    test('听力选择：与看汉选英同规则', () {
      final result = evaluateAnswer(
        _answer(
          questionType: QuestionType.listeningChoice,
          userAnswer: 'Apple',
        ),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isTrue);
    });
  });

  group('生效等级的推导', () {
    test('客观题答错且自评「记得」时降级为 AGAIN', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'banana'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.isCorrect, isFalse);
      expect(result.effectiveRating, ReviewRating.again);
    });

    test('客观题答错但自评「简单」时保留 EASY', () {
      final result = evaluateAnswer(
        _answer(rating: ReviewRating.easy, userAnswer: 'banana'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.effectiveRating, ReviewRating.easy);
    });

    test('客观题答错但自评「模糊」时保留 HARD', () {
      final result = evaluateAnswer(
        _answer(rating: ReviewRating.hard, userAnswer: 'banana'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.effectiveRating, ReviewRating.hard);
    });

    test('客观题答对时完全采信自评', () {
      for (final rating in ReviewRating.values) {
        final result = evaluateAnswer(
          _answer(rating: rating, userAnswer: 'apple'),
          _word(definitionsJson: _zhDefinitions),
        );
        expect(result.effectiveRating, rating, reason: rating.wire);
      }
    });

    test('主观题不参与客观判定，完全采信自评', () {
      for (final rating in ReviewRating.values) {
        final result = evaluateAnswer(
          _answer(questionType: QuestionType.enToZh, rating: rating),
          _word(definitionsJson: _zhDefinitions),
        );
        expect(result.isCorrect, rating != ReviewRating.again);
        expect(result.effectiveRating, rating, reason: rating.wire);
      }
    });

    test('填空题与字母拼图走拼写规则', () {
      for (final type in <QuestionType>[
        QuestionType.clozeSentence,
        QuestionType.letterBank,
      ]) {
        expect(
          evaluateAnswer(
            _answer(questionType: type, userAnswer: 'apple'),
            _word(definitionsJson: _zhDefinitions),
          ).isCorrect,
          isTrue,
          reason: type.wire,
        );
        expect(
          evaluateAnswer(
            _answer(questionType: type, userAnswer: 'banana'),
            _word(definitionsJson: _zhDefinitions),
          ).isCorrect,
          isFalse,
          reason: type.wire,
        );
      }
    });
  });

  group('复盘展示字段', () {
    test('看英选中：题干是词条，期望答案是释义', () {
      final result = evaluateAnswer(
        _answer(questionType: QuestionType.enToZhChoice, userAnswer: '苹果'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.presentedPrompt, 'apple');
      expect(result.expectedAnswer, '苹果');
    });

    test('看汉选英：题干是释义，期望答案是词条', () {
      final result = evaluateAnswer(
        _answer(questionType: QuestionType.zhToEnChoice, userAnswer: 'apple'),
        _word(definitionsJson: _zhDefinitions),
      );
      expect(result.presentedPrompt, '苹果');
      expect(result.expectedAnswer, 'apple');
    });

    test('拼写题：期望答案是词条原文（保留大小写）', () {
      final result = evaluateAnswer(
        _answer(userAnswer: 'apple'),
        _word(term: 'Apple', definitionsJson: _zhDefinitions),
      );
      expect(result.expectedAnswer, 'Apple');
    });

    test('多条释义用中文分号连接', () {
      final result = evaluateAnswer(
        _answer(questionType: QuestionType.enToZhChoice, userAnswer: '苹果'),
        _word(
          definitionsJson:
              '[{"language":"zh","text":"苹果"},{"language":"zh","text":"苹果树"}]',
        ),
      );
      expect(result.expectedAnswer, '苹果；苹果树');
    });
  });

  group('释义解析的健壮性', () {
    test('非法 JSON 与「没有释义」等价，退回自评', () {
      final word = _word(definitionsJson: 'not json');
      expect(
        evaluateAnswer(
          _answer(questionType: QuestionType.enToZhChoice, userAnswer: '苹果'),
          word,
        ).isCorrect,
        isTrue,
      );
      expect(
        evaluateAnswer(
          _answer(
            questionType: QuestionType.enToZhChoice,
            rating: ReviewRating.again,
            userAnswer: '苹果',
          ),
          word,
        ).isCorrect,
        isFalse,
      );
    });

    test('空文本释义被过滤后同样退回自评', () {
      final word = _word(definitionsJson: '[{"language":"zh","text":"   "}]');
      final result = evaluateAnswer(
        _answer(
          questionType: QuestionType.enToZhChoice,
          rating: ReviewRating.again,
          userAnswer: '   ',
        ),
        word,
      );
      expect(result.isCorrect, isFalse);
      expect(result.expectedAnswer, '');
    });

    test('结构不是数组时视为无释义', () {
      final result = evaluateAnswer(
        _answer(
          questionType: QuestionType.enToZhChoice,
          rating: ReviewRating.again,
          userAnswer: '苹果',
        ),
        _word(definitionsJson: '{"text":"苹果"}'),
      );
      expect(result.isCorrect, isFalse);
    });

    test('目标语言释义优先，缺失时回退全部', () {
      final word = _word(
        definitionsJson:
            '[{"language":"en","text":"a fruit"}, '
            '{"language":"zh","text":"苹果"}]',
      );
      final result = evaluateAnswer(
        _answer(questionType: QuestionType.enToZhChoice, userAnswer: '苹果'),
        word,
      );
      expect(result.isCorrect, isTrue);
      expect(result.expectedAnswer, '苹果');
    });
  });
}
