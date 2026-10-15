/// 音标出题规则的单元测试。
///
/// 重点验证两件事：**干扰项必须来自同类或易混音标**（这是目录这套教学资产
/// 真正参与出题的地方），以及**候选不足时抛 `notEnoughPhoneticWords`**
/// 而不是悄悄出一组只有两个选项的题。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/phonetics/catalog.dart';
import 'package:lexiloop/domain/phonetics/quiz.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/phonetics/selection.dart';

import '../games/random_source.dart';

/// 造一个候选词条。
PhoneticSource source({
  required int itemId,
  required String term,
  required String phonetic,
  String definition = '释义',
}) {
  return PhoneticSource(
    itemId: itemId,
    wordId: itemId,
    word: GameWord(term: term, definition: definition),
    phonetic: phonetic,
    priority: GamePriority.normal,
  );
}

/// 一组同类（前元音）候选 + 一个异类候选。
List<PhoneticSource> mixedSources() => <PhoneticSource>[
  source(itemId: 1, term: 'sheep', phonetic: '/ʃiːp/'),
  source(itemId: 2, term: 'ship', phonetic: '/ʃɪp/'),
  source(itemId: 3, term: 'bed', phonetic: '/bed/'),
  source(itemId: 4, term: 'bad', phonetic: '/bæd/'),
  source(itemId: 5, term: 'food', phonetic: '/fuːd/'),
];

void main() {
  group('matchPhoneme', () {
    test('取最长符号，长度相同时元音优先', () {
      expect(matchPhoneme('/kæt/')?.symbol, 'æ');
      expect(matchPhoneme('/ʃiːp/')?.symbol, 'iː');
      expect(matchPhoneme('/sɪt/')?.symbol, 'ɪ');
      expect(matchPhoneme('/tʃeɪn/')?.symbol, 'eɪ');
    });

    test('忽略斜杠、方括号与空白', () {
      expect(matchPhoneme(' [ biːt ] ')?.symbol, 'iː');
    });

    test('无法匹配时返回 null', () {
      expect(matchPhoneme(''), isNull);
      expect(matchPhoneme('/ʘʘ/'), isNull);
    });
  });

  group('buildPhoneticQuestions', () {
    test('候选不足 4 个时抛 notEnoughPhoneticWords', () {
      expect(
        () => buildPhoneticQuestions(
          sources: mixedSources().take(3).toList(),
          count: phoneticItemCount,
          random: constantRandom(),
        ),
        throwsA(
          isA<ConflictError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.notEnoughPhoneticWords,
          ),
        ),
      );
    });

    test('音标归不到目录条目时同样抛错（不能出没有解析的题）', () {
      final sources = <PhoneticSource>[
        ...mixedSources().take(3),
        source(itemId: 9, term: 'weird', phonetic: '/ʘ/'),
      ];
      expect(
        () => buildPhoneticQuestions(
          sources: sources,
          count: phoneticItemCount,
          random: constantRandom(),
        ),
        throwsA(isA<ConflictError>()),
      );
    });

    test('三种题型按顺序循环', () {
      final questions = buildPhoneticQuestions(
        sources: mixedSources(),
        count: phoneticItemCount,
        random: constantRandom(),
      );
      expect(questions.length, 5);
      expect(
        questions.map((item) => item.challenge).toList(),
        <PhoneticChallengeType>[
          PhoneticChallengeType.soundToPhonetic,
          PhoneticChallengeType.phoneticToWord,
          PhoneticChallengeType.wordToPhonetic,
          PhoneticChallengeType.soundToPhonetic,
          PhoneticChallengeType.phoneticToWord,
        ],
      );
    });

    test('选项数量固定、互不重复且包含正确项', () {
      final questions = buildPhoneticQuestions(
        sources: mixedSources(),
        count: phoneticItemCount,
        random: constantRandom(),
      );
      for (final question in questions) {
        final options = question.base.choices.options;
        expect(options.length, phoneticChoiceCount);
        expect(options.toSet().length, options.length);
        expect(options, contains(question.answer));
      }
    });

    test('同类候选够用时，音标类干扰项全部同类或易混', () {
      final questions = buildPhoneticQuestions(
        sources: mixedSources(),
        count: phoneticItemCount,
        random: constantRandom(),
      );
      var checked = 0;
      for (final question in questions) {
        if (!question.challenge.hasPhoneticChoices) continue;
        final siblings = <String>{
          for (final other in mixedSources())
            if (other.phonetic != question.answer &&
                isSimilarEntry(question.entry, matchPhoneme(other.phonetic)))
              other.phonetic,
        };
        // 同类候选不足 3 个时无法要求「全部同类」，由下一个用例覆盖。
        if (siblings.length < phoneticChoiceCount - 1) continue;
        checked += 1;
        for (final option in question.base.choices.options) {
          if (option == question.answer) continue;
          expect(
            isSimilarEntry(question.entry, matchPhoneme(option)),
            isTrue,
            reason: '$option 与 ${question.entry.symbol} 既不同类也不易混',
          );
        }
      }
      expect(checked, greaterThan(0), reason: '至少要有一道题满足同类候选充足');
    });

    test('同类不足时退到同大类，绝不混入另一大类', () {
      final questions = buildPhoneticQuestions(
        sources: mixedSources(),
        count: phoneticItemCount,
        random: constantRandom(),
      );
      for (final question in questions) {
        if (!question.challenge.hasPhoneticChoices) continue;
        for (final option in question.base.choices.options) {
          if (option == question.answer) continue;
          final entry = matchPhoneme(option);
          expect(entry, isNotNull);
          expect(
            entry!.kind,
            question.entry.kind,
            reason: '元音题不该出现辅音选项（$option）',
          );
        }
      }
    });

    test('看音标选例词的选项是单词而不是音标', () {
      final questions = buildPhoneticQuestions(
        sources: mixedSources(),
        count: phoneticItemCount,
        random: constantRandom(),
      );
      final wordQuestion = questions.firstWhere(
        (item) => item.challenge == PhoneticChallengeType.phoneticToWord,
      );
      expect(wordQuestion.answer, isNot(startsWith('/')));
      expect(
        wordQuestion.base.choices.options.every(
          (item) => !item.startsWith('/'),
        ),
        isTrue,
      );
    });

    test('选项里带上词义，便于「看音标选例词」时展示', () {
      final questions = buildPhoneticQuestions(
        sources: mixedSources(),
        count: phoneticItemCount,
        random: constantRandom(),
      );
      expect(questions.first.base.choices.definitions, isNotEmpty);
    });

    test('同类候选不足时才用异类补齐', () {
      final sources = <PhoneticSource>[
        source(itemId: 1, term: 'sheep', phonetic: '/ʃiːp/'),
        source(itemId: 2, term: 'ship', phonetic: '/ʃɪp/'),
        source(itemId: 3, term: 'food', phonetic: '/fuːd/'),
        source(itemId: 4, term: 'bird', phonetic: '/bɜːd/'),
      ];
      final questions = buildPhoneticQuestions(
        sources: sources,
        count: phoneticItemCount,
        random: constantRandom(),
      );
      // 前元音只有 2 个候选，凑不出 3 个同类干扰项，因此必须允许异类补齐。
      for (final question in questions) {
        expect(question.base.choices.options.length, phoneticChoiceCount);
      }
    });
  });

  group('音标训练状态机', () {
    PhoneticQuizState start() {
      final questions = buildPhoneticQuestions(
        sources: mixedSources(),
        count: phoneticItemCount,
        random: constantRandom(),
      );
      final quiz = startPhoneticQuiz(
        plan: gamePlanFor(
          GameMode.phonetics,
          itemCount: questions.length,
          durationSeconds: phoneticDurationSeconds,
        ),
        questions: questions,
      );
      return phoneticQuizNext(quiz, const StartPhoneticQuiz());
    }

    test('初始 ready，开始后 playing', () {
      final questions = buildPhoneticQuestions(
        sources: mixedSources(),
        count: phoneticItemCount,
        random: constantRandom(),
      );
      final ready = startPhoneticQuiz(
        plan: gamePlanFor(GameMode.phonetics, itemCount: questions.length),
        questions: questions,
      );
      expect(ready.core.progress.phase, GamePhase.ready);
      expect(
        phoneticQuizNext(ready, const StartPhoneticQuiz()).core.isPlaying,
        isTrue,
      );
    });

    test('答错记失误、清零连击，并停留在本题', () {
      final quiz = start();
      final question = quiz.current!;
      final wrong = question.base.choices.options.firstWhere(
        (option) => option != question.answer,
      );
      final next = phoneticQuizNext(quiz, ChoosePhonetic(wrong));
      expect(next.core.tally.mistakeCount, 1);
      expect(next.core.tally.combo, 0);
      expect(next.hasWrongSelection, isTrue);
      expect(next.revealed, isFalse);
      expect(next.current!.base.itemId, question.base.itemId);
      // 答错后必须先清掉标记才能再选。
      final blocked = phoneticQuizNext(next, ChoosePhonetic(question.answer));
      expect(blocked.revealed, isFalse);
      final cleared = phoneticQuizNext(blocked, const ContinuePhonetic());
      expect(cleared.hasWrongSelection, isFalse);
      final solved = phoneticQuizNext(cleared, ChoosePhonetic(question.answer));
      expect(solved.revealed, isTrue);
      expect(solved.core.tally.combo, 1);
      expect(
        solved.core.outcomeFor(question.base.itemId),
        GameOutcome.recovered,
      );
    });

    test('答对后继续进入下一题', () {
      var quiz = start();
      final question = quiz.current!;
      quiz = phoneticQuizNext(quiz, ChoosePhonetic(question.answer));
      expect(quiz.revealed, isTrue);
      quiz = phoneticQuizNext(quiz, const ContinuePhonetic());
      expect(quiz.revealed, isFalse);
      expect(quiz.selected, isNull);
      expect(quiz.current!.base.itemId, isNot(question.base.itemId));
    });

    test('跳过先展示解析，继续后才推进，并记为未完成', () {
      var quiz = start();
      final question = quiz.current!;
      quiz = phoneticQuizNext(quiz, const SkipPhonetic());
      expect(quiz.revealed, isTrue);
      expect(quiz.core.outcomeFor(question.base.itemId), GameOutcome.missed);
      expect(quiz.current!.base.itemId, question.base.itemId);
      quiz = phoneticQuizNext(quiz, const ContinuePhonetic());
      expect(quiz.current!.base.itemId, isNot(question.base.itemId));
    });

    test('揭示答案期间不计时（含整体倒计时）', () {
      var quiz = start();
      quiz = phoneticQuizNext(quiz, const SkipPhonetic());
      final frozen = quiz.itemElapsedMs;
      final remaining = quiz.core.remainingMs;
      quiz = phoneticQuizNext(
        quiz,
        const TickPhoneticQuiz(phoneticDurationSeconds * 1000),
      );
      expect(quiz.itemElapsedMs, frozen);
      expect(quiz.core.remainingMs, remaining);
      expect(quiz.core.isFinished, isFalse);
    });

    test('时间耗尽结束本局，结束态不可再推进', () {
      var quiz = start();
      quiz = phoneticQuizNext(
        quiz,
        const TickPhoneticQuiz(phoneticDurationSeconds * 1000),
      );
      expect(quiz.core.isFinished, isTrue);
      expect(quiz.current, isNull);
      final after = phoneticQuizNext(quiz, const TickPhoneticQuiz(1000));
      expect(after.core.tally.score, quiz.core.tally.score);
    });

    test('逐题作答记录与题目数量一致', () {
      final quiz = start();
      final records = phoneticAnswerRecords(quiz);
      expect(records.length, quiz.questions.length);
      expect(records.map((item) => item.itemId).toSet().length, records.length);
    });
  });
}
